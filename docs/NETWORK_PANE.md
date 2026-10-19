# The Network pane

The Network pane shows the HTTP requests an app makes while it runs on a connected Android phone
or iPhone: the address, the status code, the headers, the bodies and the timing. It is laid out like
the Network panel in a browser's developer tools.

This guide is for anyone using the pane, including testers who have never set up a debugging tool.
For how the pane is built, see [NETWORK_INSPECTOR.md](NETWORK_INSPECTOR.md).

- [Where the traffic comes from](#where-the-traffic-comes-from)
- [If you test apps](#if-you-test-apps)
- [If you build apps](#if-you-build-apps)
- [HAR files](#har-files)
- [Using the pane](#using-the-pane)
- [Troubleshooting](#troubleshooting)
- [Safety](#safety)

## Where the traffic comes from

Eagly can't see an app's traffic on its own. The app has to include
**[Inspektor](https://github.com/ShreyashKore/inspektor)**, a free, open-source library for
Android and iOS apps. Inspektor records every request and response the app makes, and it can show
them on the phone itself. When the app also turns on Inspektor's *remote inspection*, Eagly
connects to it over the USB cable and shows the same traffic on your computer, live.

That means:

- **No proxy, no certificates and no Wi-Fi settings.** HTTPS traffic shows up in full, because
  Inspektor reads it inside the app, before it is encrypted.
- **It needs a test build.** Inspektor goes only into debug, dev or QA builds. Builds from the App
  Store or Google Play never contain it.
- **It covers the common HTTP libraries:** OkHttp (and Retrofit, which uses it) and Ktor on
  Android, URLSession (and Alamofire, which uses it) on iOS, and React Native on iOS.

You can also open a [HAR file](#har-files) without any device at all.

## If you test apps

1. **Get a test build that includes Inspektor.** Ask the app's developers for a debug, dev or QA
   build with Inspektor's remote inspection turned on. Point them at
   [If you build apps](#if-you-build-apps).
2. **Connect the device to Eagly.**
   - Android: connect it with a USB cable and allow USB debugging when the phone asks, or pair it
     over Wi-Fi from Eagly's device list.
   - iPhone: connect it with a cable, unlock it and tap **Trust** if it asks.
3. **Open the Network pane** for that device, and leave it open. Eagly looks for apps only while
   the pane is open.
4. **Open the app and use it.** Within a couple of seconds the line at the top of the empty pane
   changes to *Connected to …*, and requests start to appear. Requests the app recorded before you
   opened the pane are listed too.

To share what you found, use **Export as HAR** in the pane's toolbar and attach the file to your
bug report. Anyone can open it in Eagly or in a browser's developer tools.

## If you build apps

The full set-up, with every option, is in
[Inspektor's README](https://github.com/ShreyashKore/inspektor#readme). The short version:

1. **Add Inspektor to your debug build only,** and its *no-op* twin to your release build. The
   no-op twin has the same API and does nothing, so your code compiles in both and users never get
   Inspektor. For an Android app that uses OkHttp:

   ```kotlin
   dependencies {
       debugImplementation("com.gyanoba.inspektor:inspektor-okhttp:<version>")
       debugImplementation("com.gyanoba.inspektor:inspektor-ui:<version>")
       releaseImplementation("com.gyanoba.inspektor:inspektor-okhttp-no-op:<version>")
       releaseImplementation("com.gyanoba.inspektor:inspektor-ui-no-op:<version>")
   }
   ```

   Use the
   [latest version](https://central.sonatype.com/artifact/com.gyanoba.inspektor/inspektor), and
   keep every Inspektor artifact on the same one.

2. **Hook it into your HTTP client.**

   | Client | Artifact | Hook |
   |---|---|---|
   | OkHttp | `inspektor-okhttp` | `OkHttpClient.Builder().installInspektor { level = LogLevel.BODY }` |
   | Ktor | `inspektor` | `HttpClient { install(Inspektor) }` |
   | URLSession, from Kotlin | `inspektor-urlsession` | `inspektorUrlSession { level = LogLevel.BODY }` |
   | Swift, React Native | `InspektorUrlSession` pod | See [From Swift or React Native](https://github.com/ShreyashKore/inspektor#from-swift-or-react-native) |

3. **Turn on remote inspection,** once, early in the app's life (`Application.onCreate` on
   Android, at launch on iOS):

   ```kotlin
   @OptIn(UnstableInspektorAPI::class)
   InspektorRemote.start()
   ```

   From Swift it is `InspektorRemote.shared.start()`. It returns at once and is safe to call more
   than once.

4. **Run the debug build on a device connected to Eagly** and open the Network pane.

The empty Network pane shows these steps too, with snippets you can copy for each client.

## HAR files

A HAR file is a saved recording of network traffic in a standard format. You can open one with
**Open HAR file**, whether or not a device is connected. Good sources:

- Inspektor's own screen on the phone (**Export as HAR**).
- Eagly itself (**Export as HAR** in the Network pane's toolbar).
- A browser's developer tools (Network tab, then *Export HAR*).
- Proxies such as Charles, Proxyman or Fiddler.

## Using the pane

- **Filter bar.** Type to search URLs, or use keys like `status:404`, `method:POST` or
  `domain:api.example.com`; the box suggests keys and values as you type. The chips narrow by
  content type: JSON, Doc, Text, Img, Media and Other.
- **Timeline overview.** The strip above the list shows when each request ran. Toggle it from the
  toolbar.
- **The list.** Click a column header to sort. Right-click a row to copy it (as a URL, as cURL,
  its headers or body) or to show only requests like it: same host, path, method or status.
- **Detail.** Click a request to open its **Headers**, **Payload**, **Response** and **Timing**.
  Bodies are formatted and searchable.
- **Clear** empties the list in Eagly. Nothing is deleted on the device.

## Troubleshooting

**The pane says "Looking for apps with Inspektor…" and nothing happens.**

- Open Eagly's **Logs** pane and search for `Inspektor: remote inspection listening`. Inspektor
  writes that line when remote inspection starts. If it never appears, the build doesn't call
  `InspektorRemote.start()`, or it is a release build with the no-op library. Ask the developers
  for a build that does.
- Make sure the app is open. On iPhone, keep it in front: iOS pauses apps in the background, and
  Eagly reconnects when the app comes back.

**The app shows up, but some requests are missing.**

- Only requests made through a client Inspektor is hooked into are recorded. Requests from a web
  view (a web page shown inside the app), from a second HTTP client the developers didn't hook up,
  or from system services aren't.
- On iOS, URLSession tasks created with a completion handler are invisible to Inspektor's
  delegate. The developers can use `InspektorUrlProtocol` instead; the README explains how.

**The pane says the device is disconnected.** Reconnect the cable (or Wi-Fi pairing). Eagly
picks the app up again by itself, and carries on with the same list.

**The app restarted.** Give it a moment. Eagly reconnects and continues the list rather than
repeating it.

## Safety

Remote inspection has no password: while it runs, other apps on the same device could read the
recorded traffic and change responses through Inspektor's overrides. It can't be reached from the
network, only from the device itself, and Eagly reaches it over USB. That is why Inspektor belongs
in test builds only, and why release builds should use the no-op artifacts. See
[Inspektor's notes on remote inspection](https://github.com/ShreyashKore/inspektor#remote-inspection-with-eagly).
