package dev.eagly.inspector;

import android.app.UiAutomation;
import android.content.Context;
import android.content.ContextWrapper;
import android.os.Looper;
import android.view.accessibility.AccessibilityNodeInfo;

import org.json.JSONObject;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * The hidden-API half of the helper: building a {@link UiAutomation} outside
 * an instrumentation, as AOSP's {@code uiautomator} command does, and reading
 * the display and node ids the public API keeps to itself. Every lookup is by
 * reflection, so one jar runs on every API level that has the pieces.
 */
final class Automation {
    /** {@code UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES}: keep TalkBack running. */
    private static final int FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES = 1;

    private Automation() {}

    static UiAutomation connect(Looper looper) throws Exception {
        Class<?> connectionClass = Class.forName("android.app.UiAutomationConnection");
        Constructor<?> connectionConstructor = connectionClass.getDeclaredConstructor();
        connectionConstructor.setAccessible(true);
        Object connection = connectionConstructor.newInstance();
        Class<?> connectionInterface = Class.forName("android.app.IUiAutomationConnection");

        UiAutomation automation;
        try {
            Constructor<UiAutomation> constructor =
                    UiAutomation.class.getDeclaredConstructor(Looper.class, connectionInterface);
            constructor.setAccessible(true);
            automation = constructor.newInstance(looper, connection);
        } catch (NoSuchMethodException e) {
            // Newer platforms take a Context, which they read the looper and
            // display from.
            Constructor<UiAutomation> constructor =
                    UiAutomation.class.getDeclaredConstructor(Context.class, connectionInterface);
            constructor.setAccessible(true);
            automation = constructor.newInstance(new ShellContext(looper), connection);
        }

        try {
            Method connect = UiAutomation.class.getDeclaredMethod("connect", int.class);
            connect.setAccessible(true);
            connect.invoke(automation, FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
        } catch (NoSuchMethodException e) {
            Method connect = UiAutomation.class.getDeclaredMethod("connect");
            connect.setAccessible(true);
            connect.invoke(automation);
        }
        return automation;
    }

    static void disconnect(UiAutomation automation) {
        try {
            Method disconnect = UiAutomation.class.getDeclaredMethod("disconnect");
            disconnect.setAccessible(true);
            disconnect.invoke(automation);
        } catch (Exception ignored) {
            // The process is exiting; the system drops the connection anyway.
        }
    }

    /** The default display's logical size, in its current rotation, and that rotation. */
    static JSONObject display() throws Exception {
        JSONObject display = new JSONObject();
        Class<?> globalClass = Class.forName("android.hardware.display.DisplayManagerGlobal");
        Object global = globalClass.getDeclaredMethod("getInstance").invoke(null);
        Object info = globalClass.getDeclaredMethod("getDisplayInfo", int.class).invoke(global, 0);
        display.put("width", intField(info, "logicalWidth"));
        display.put("height", intField(info, "logicalHeight"));
        display.put("rotation", intField(info, "rotation"));
        display.put("density", intField(info, "logicalDensityDpi"));
        return display;
    }

    private static int intField(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.getInt(target);
    }

    private static Method sourceNodeIdMethod;
    private static boolean sourceNodeIdLooked;

    /** The node's hidden source id, or -1 when the platform hides it. */
    static long sourceNodeId(AccessibilityNodeInfo info) {
        if (!sourceNodeIdLooked) {
            sourceNodeIdLooked = true;
            try {
                sourceNodeIdMethod = AccessibilityNodeInfo.class.getDeclaredMethod("getSourceNodeId");
                sourceNodeIdMethod.setAccessible(true);
            } catch (Exception ignored) {
                sourceNodeIdMethod = null;
            }
        }
        if (sourceNodeIdMethod == null) return -1;
        try {
            return (long) sourceNodeIdMethod.invoke(info);
        } catch (Exception ignored) {
            return -1;
        }
    }

    /**
     * The least a shell process can offer as a Context: the looper
     * UiAutomation runs on, the default display, and the shell's package.
     */
    private static final class ShellContext extends ContextWrapper {
        private final Looper looper;

        ShellContext(Looper looper) {
            super(null);
            this.looper = looper;
        }

        @Override
        public Looper getMainLooper() {
            return looper;
        }

        // Hidden on Context, so no @Override; it still overrides at runtime.
        public int getDisplayId() {
            return 0;
        }

        @Override
        public String getPackageName() {
            return "com.android.shell";
        }

        @Override
        public String getOpPackageName() {
            return "com.android.shell";
        }
    }
}
