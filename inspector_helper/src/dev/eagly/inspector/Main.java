package dev.eagly.inspector;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.UiAutomation;
import android.graphics.Bitmap;
import android.graphics.Rect;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Base64;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintStream;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * Eagly's layout-inspector helper. Runs as the shell user through
 * {@code app_process}, the way {@code uiautomator} and {@code scrcpy-server}
 * do, and keeps one {@link UiAutomation} connection open so a snapshot costs
 * a tree walk instead of a JVM start.
 *
 * <p>The protocol is one JSON object per line. Requests arrive on stdin as
 * {@code {"id": 1, "method": "…", "params": {…}}}; replies go to stdout as
 * {@code {"id": 1, "result": …}} or {@code {"id": 1, "error": "…"}}, and
 * events as {@code {"event": "…"}}. The first line written is
 * {@code {"event": "hello", …}}. stdout carries nothing else: stray prints are
 * sent to stderr. stdin closing ends the process.
 */
public final class Main {
    static final int PROTOCOL = 1;

    /** Deepest tree walked; deeper nodes are cut, which no real UI reaches. */
    private static final int MAX_DEPTH = 200;

    /** Quiet time after the last UI change before {@code changed} is sent. */
    private static final long CHANGE_SETTLE_MS = 120;

    private final UiAutomation automation;
    private final Handler handler;
    private final Writer out;
    private volatile boolean watching;
    private boolean changePending;

    private Main(UiAutomation automation, Handler handler, Writer out) {
        this.automation = automation;
        this.handler = handler;
        this.out = out;
    }

    public static void main(String[] args) throws Exception {
        Writer out = new OutputStreamWriter(
                new FileOutputStream(FileDescriptor.out), StandardCharsets.UTF_8);
        System.setOut(new PrintStream(new FileOutputStream(FileDescriptor.err), true));

        // Android 16's accessibility client posts to the main looper, which a
        // bare app_process doesn't have: without one it crashes on connect.
        // The main thread runs that looper; stdin is read on its own thread.
        Looper.prepareMainLooper();

        HandlerThread thread = new HandlerThread("eagly-inspector");
        thread.start();
        Handler handler = new Handler(thread.getLooper());
        final UiAutomation automation;
        try {
            automation = Automation.connect(thread.getLooper());
        } catch (Throwable error) {
            fail(out, error);
            return;
        }
        final Main main = new Main(automation, handler, out);
        main.configure();
        main.awaitWindows();

        JSONObject hello = new JSONObject();
        hello.put("event", "hello");
        hello.put("protocol", PROTOCOL);
        hello.put("sdk", Build.VERSION.SDK_INT);
        main.write(hello);

        Thread reader = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    BufferedReader in = new BufferedReader(
                            new InputStreamReader(System.in, StandardCharsets.UTF_8));
                    String line;
                    while ((line = in.readLine()) != null) {
                        if (line.trim().isEmpty()) continue;
                        main.handle(line);
                    }
                } catch (Exception ignored) {
                    // stdin broke: the host is gone, same as it closing.
                } finally {
                    Automation.disconnect(automation);
                    System.exit(0);
                }
            }
        }, "eagly-inspector-stdin");
        reader.start();
        Looper.loop();
    }

    /**
     * Reports a failed connect as `{"event": "error", "code": …}` and exits.
     * Left uncaught, the runtime logs it to logcat, not stderr, and kills the
     * process, so all the host would see is "Killed". The usual cause is
     * `busy`: Android allows one UiAutomation at a time, and a UI test,
     * Appium, Maestro or `uiautomator` already holds it.
     */
    private static void fail(Writer out, Throwable error) {
        Throwable cause = error;
        while (cause instanceof java.lang.reflect.InvocationTargetException
                && cause.getCause() != null) {
            cause = cause.getCause();
        }
        String message = String.valueOf(cause);
        try {
            JSONObject event = new JSONObject();
            event.put("event", "error");
            event.put("code", message.contains("already registered") ? "busy" : "connect");
            event.put("message", message);
            out.write(event.toString());
            out.write('\n');
            out.flush();
        } catch (Exception ignored) {
            // Nothing left to tell the host with.
        }
        System.exit(1);
    }

    private void configure() {
        AccessibilityServiceInfo info = automation.getServiceInfo();
        if (info == null) info = new AccessibilityServiceInfo();
        info.flags |= AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
                | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        info.eventTypes = AccessibilityEvent.TYPES_ALL_MASK;
        automation.setServiceInfo(info);
        automation.setOnAccessibilityEventListener(new UiAutomation.OnAccessibilityEventListener() {
            @Override
            public void onAccessibilityEvent(AccessibilityEvent event) {
                onEvent(event);
            }
        });
    }

    /** How long a fresh connection may take to see the screen's windows. */
    private static final long WINDOWS_TIMEOUT_MS = 2000;

    /** How long a snapshot waits for a window list that is momentarily empty. */
    private static final long WINDOWS_RETRY_MS = 500;

    /**
     * Waits for the first window list. A connection that has just set its
     * service flags sees no windows for a moment, and a snapshot taken then
     * comes back empty, so `hello` waits until there is something to walk.
     */
    private void awaitWindows() {
        long deadline = SystemClock.uptimeMillis() + WINDOWS_TIMEOUT_MS;
        while (SystemClock.uptimeMillis() < deadline) {
            if (!automation.getWindows().isEmpty()) return;
            SystemClock.sleep(20);
        }
    }

    // ── Requests ────────────────────────────────────────────────────────

    private void handle(String line) {
        Object id = null;
        try {
            JSONObject request = new JSONObject(line);
            id = request.opt("id");
            String method = request.getString("method");
            JSONObject params = request.optJSONObject("params");
            if (params == null) params = new JSONObject();
            Object result;
            switch (method) {
                case "snapshot":
                    result = snapshot(params);
                    break;
                case "watch":
                    watching = params.optBoolean("enabled", true);
                    result = new JSONObject();
                    break;
                case "ping":
                    result = new JSONObject();
                    break;
                default:
                    throw new IllegalArgumentException("unknown method " + method);
            }
            JSONObject reply = new JSONObject();
            reply.put("id", id);
            reply.put("result", result);
            write(reply);
        } catch (Throwable error) {
            try {
                JSONObject reply = new JSONObject();
                reply.put("id", id == null ? JSONObject.NULL : id);
                reply.put("error", String.valueOf(error));
                write(reply);
            } catch (Exception ignored) {
                // Nothing left to tell the host with.
            }
        }
    }

    /**
     * The UI as it stands: every window with its node tree, the display, and
     * optionally a JPEG screenshot taken straight after the walk.
     *
     * <p>Params: {@code idleMs} (default 0) waits for the UI to settle first,
     * as {@code uiautomator dump} does for a whole second; {@code screenshot}
     * (default true); {@code scale} (default 1) shrinks the screenshot;
     * {@code quality} (default 80) is its JPEG quality.
     */
    private JSONObject snapshot(JSONObject params) throws Exception {
        long started = SystemClock.uptimeMillis();
        long idleMs = params.optLong("idleMs", 0);
        if (idleMs > 0) {
            try {
                automation.waitForIdle(idleMs, idleMs * 4);
            } catch (Exception ignored) {
                // A UI that never settles still gets inspected.
            }
        }

        JSONObject result = new JSONObject();
        result.put("display", Automation.display());

        JSONArray windows = new JSONArray();
        // The list is briefly empty while an activity starts; wait it out.
        long windowsDeadline = SystemClock.uptimeMillis() + WINDOWS_RETRY_MS;
        List<AccessibilityWindowInfo> infos = automation.getWindows();
        while (infos.isEmpty() && SystemClock.uptimeMillis() < windowsDeadline) {
            SystemClock.sleep(20);
            infos = automation.getWindows();
        }
        for (AccessibilityWindowInfo window : infos) {
            windows.put(window(window));
        }
        if (windows.length() == 0) {
            // Still no window list: fall back to the active window alone, as
            // uiautomator does.
            AccessibilityNodeInfo root = automation.getRootInActiveWindow();
            if (root != null) {
                JSONObject window = new JSONObject();
                window.put("id", -1);
                window.put("type", "application");
                window.put("active", true);
                window.put("root", node(root, 0));
                windows.put(window);
            }
        }
        result.put("windows", windows);
        result.put("treeMs", SystemClock.uptimeMillis() - started);

        if (params.optBoolean("screenshot", true)) {
            Bitmap bitmap = automation.takeScreenshot();
            if (bitmap != null) {
                double scale = params.optDouble("scale", 1);
                if (scale > 0 && scale < 1) {
                    Bitmap scaled = Bitmap.createScaledBitmap(bitmap,
                            Math.max(1, (int) (bitmap.getWidth() * scale)),
                            Math.max(1, (int) (bitmap.getHeight() * scale)), true);
                    bitmap.recycle();
                    bitmap = scaled;
                }
                ByteArrayOutputStream jpeg = new ByteArrayOutputStream();
                bitmap.compress(Bitmap.CompressFormat.JPEG,
                        params.optInt("quality", 80), jpeg);
                bitmap.recycle();
                result.put("screenshot", Base64.encodeToString(jpeg.toByteArray(), Base64.NO_WRAP));
            }
        }
        result.put("elapsedMs", SystemClock.uptimeMillis() - started);
        return result;
    }

    private JSONObject window(AccessibilityWindowInfo info) throws Exception {
        JSONObject window = new JSONObject();
        window.put("id", info.getId());
        window.put("type", windowType(info.getType()));
        window.put("layer", info.getLayer());
        window.put("active", info.isActive());
        window.put("focused", info.isFocused());
        if (Build.VERSION.SDK_INT >= 24 && info.getTitle() != null) {
            window.put("title", info.getTitle().toString());
        }
        Rect bounds = new Rect();
        info.getBoundsInScreen(bounds);
        window.put("bounds", rect(bounds));
        AccessibilityNodeInfo root = info.getRoot();
        if (root != null) window.put("root", node(root, 0));
        return window;
    }

    private static String windowType(int type) {
        switch (type) {
            case AccessibilityWindowInfo.TYPE_APPLICATION: return "application";
            case AccessibilityWindowInfo.TYPE_INPUT_METHOD: return "inputMethod";
            case AccessibilityWindowInfo.TYPE_SYSTEM: return "system";
            case AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY: return "accessibilityOverlay";
            case 5: return "splitScreenDivider";
            case 6: return "magnificationOverlay";
            default: return "unknown";
        }
    }

    private JSONObject node(AccessibilityNodeInfo info, int depth) throws Exception {
        JSONObject node = new JSONObject();
        putText(node, "class", info.getClassName());
        putText(node, "package", info.getPackageName());
        putText(node, "resourceId", info.getViewIdResourceName());
        putText(node, "text", info.getText());
        putText(node, "contentDesc", info.getContentDescription());
        if (Build.VERSION.SDK_INT >= 26) putText(node, "hint", info.getHintText());
        if (Build.VERSION.SDK_INT >= 30) putText(node, "stateDesc", info.getStateDescription());
        if (Build.VERSION.SDK_INT >= 28) putText(node, "paneTitle", info.getPaneTitle());
        if (Build.VERSION.SDK_INT >= 33) putText(node, "uniqueId", info.getUniqueId());
        Rect bounds = new Rect();
        info.getBoundsInScreen(bounds);
        node.put("bounds", rect(bounds));
        long sourceId = Automation.sourceNodeId(info);
        if (sourceId != -1) {
            // The low half is the View's accessibility id, the `aid=` that
            // `dumpsys activity top` prints; the high half a virtual child's.
            node.put("viewId", (int) sourceId);
            int virtual = (int) (sourceId >>> 32);
            if (virtual != -1) node.put("virtualId", virtual);
        }
        if (Build.VERSION.SDK_INT >= 24) node.put("drawingOrder", info.getDrawingOrder());

        JSONArray flags = new JSONArray();
        if (info.isCheckable()) flags.put("checkable");
        if (info.isChecked()) flags.put("checked");
        if (info.isClickable()) flags.put("clickable");
        if (info.isLongClickable()) flags.put("longClickable");
        if (info.isEnabled()) flags.put("enabled");
        if (info.isFocusable()) flags.put("focusable");
        if (info.isFocused()) flags.put("focused");
        if (info.isScrollable()) flags.put("scrollable");
        if (info.isPassword()) flags.put("password");
        if (info.isSelected()) flags.put("selected");
        if (info.isEditable()) flags.put("editable");
        if (info.isVisibleToUser()) flags.put("visible");
        if (info.isAccessibilityFocused()) flags.put("accessibilityFocused");
        if (Build.VERSION.SDK_INT >= 26 && info.isImportantForAccessibility()) {
            flags.put("important");
        }
        node.put("flags", flags);

        int count = info.getChildCount();
        if (count > 0 && depth < MAX_DEPTH) {
            JSONArray children = new JSONArray();
            for (int i = 0; i < count; i++) {
                AccessibilityNodeInfo child = info.getChild(i);
                if (child == null) continue;
                children.put(node(child, depth + 1));
            }
            node.put("children", children);
        }
        return node;
    }

    private static void putText(JSONObject node, String key, CharSequence value) throws Exception {
        if (value != null && value.length() > 0) node.put(key, value.toString());
    }

    private static JSONArray rect(Rect rect) {
        JSONArray array = new JSONArray();
        array.put(rect.left);
        array.put(rect.top);
        array.put(rect.right);
        array.put(rect.bottom);
        return array;
    }

    // ── Change events ───────────────────────────────────────────────────

    private void onEvent(AccessibilityEvent event) {
        if (!watching) return;
        switch (event.getEventType()) {
            case AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED:
            case AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED:
            case AccessibilityEvent.TYPE_WINDOWS_CHANGED:
            case AccessibilityEvent.TYPE_VIEW_SCROLLED:
            case AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED:
            case AccessibilityEvent.TYPE_VIEW_SELECTED:
            case AccessibilityEvent.TYPE_VIEW_FOCUSED:
                break;
            default:
                return;
        }
        // Coalesce a burst into one `changed`, sent once the UI goes quiet.
        handler.removeCallbacks(sendChanged);
        changePending = true;
        handler.postDelayed(sendChanged, CHANGE_SETTLE_MS);
    }

    private final Runnable sendChanged = new Runnable() {
        @Override
        public void run() {
            if (!changePending || !watching) return;
            changePending = false;
            try {
                JSONObject event = new JSONObject();
                event.put("event", "changed");
                write(event);
            } catch (Exception ignored) {
                // The host is gone; stdin closing ends the process.
            }
        }
    };

    private synchronized void write(JSONObject message) throws Exception {
        out.write(message.toString());
        out.write('\n');
        out.flush();
    }
}
