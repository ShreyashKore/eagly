# iOS device glossary

The iOS terms Eagly's Rust side runs into, from the USB cable up to input injection, each with
its nearest Android equivalent. For how Eagly uses them, see docs/IOS_RUST_MIGRATION.md and
docs/IOS_SCREEN_MIRROR.md.

Eagly pins `idevice` 0.1.68 (`rust/Cargo.toml`). Entries marked **0.1.68** describe APIs that
release added; Eagly used 0.1.65 before it.

## How the pieces fit

```
Eagly (Mac/Windows)
 │
 ├─ Classic path (rust/src/api/ios.rs: logs, files, installs, icons, crash reports)
 │    usbmuxd ──► lockdownd (port 62078) ──StartService──► a service port (TLS) ──► AFC, SpringBoard, …
 │
 └─ Modern path (rust/src/api/ios_mirror.rs: screen mirror, touch, keyboard)
      usbmuxd ──► lockdownd ──► CoreDeviceProxy ══ IPv6 tunnel ══► RSD (port 58783)
                                                     └─► a service port ──► RemoteXPC over HTTP/2 ──► CoreDevice service
```

The classic path needs only a paired ("trusted") phone. The modern path also needs iOS 17+,
Developer Mode and a mounted developer disk image.

---

## 1. Transport and trust

### usbmuxd (USB multiplexing daemon)

A daemon on the **computer**, not the phone.

- **The cable:** an iPhone over USB doesn't show up as a network interface. It exposes a
  vendor-specific USB interface that carries a multiplexing protocol, and usbmuxd owns it.
- **What it offers clients:**
  - **Device tracking:** a `Listen` request streams attach and detach events.
  - **`Connect(device, port)`:** gives you a byte stream to a TCP port on the phone, carried
    over USB. Every other service is reached this way.
  - **Pair records:** stores the host's pairing credentials for each device.
  - **Wi-Fi devices:** includes ones it found over Bonjour/mDNS.
- **Where it lives:**
  - macOS: built in, as the Unix socket `/var/run/usbmuxd`.
  - Windows: Apple Mobile Device Service, from iTunes or Apple Devices, on TCP 27015. That's
    why Eagly asks Windows users to install Apple Devices.
  - Linux: libimobiledevice's open-source `usbmuxd`.
- **Protocol:** a small header plus plist messages.
- **In Eagly:** `connect_usbmuxd`, `UsbmuxdProvider`, and the port forward in
  `rust/src/api/ios_network.rs`.

**Android:** the **adb server** on the host (port 5037). `Listen` ≈ `host:track-devices`,
`Connect` ≈ `host:transport:<serial>` and then a service. The port forward ≈ `adb forward`.

### lockdownd

The phone's **gatekeeper daemon**, listening on device port **62078**. Every classic interaction
starts here:

1. **Query:** `GetValue` returns device facts: ProductVersion, DeviceName, UniqueDeviceID and
   so on.
2. **Pair:** the first time, the phone shows **"Trust This Computer?"** and asks for the
   passcode. Host and phone exchange certificates, producing a **pair record**: host
   certificate and key, root certificate, HostID and an escrow bag. The host keeps it, through
   usbmuxd.
3. **StartSession:** proves the pairing, then upgrades the connection to TLS.
4. **StartService("com.apple.afc")**: lockdownd starts that service and replies with a **port
   number**, sometimes asking for TLS. You open a new usbmuxd connection to that port.

Anything started this way is called a **lockdown service**.

**Android:** **adbd plus adb's RSA authorisation.**

- The Trust dialog ≈ "Allow USB debugging?". The pair record ≈ `~/.android/adbkey` and the
  phone's list of authorised keys.
- `GetValue` ≈ `getprop`.
- One difference: adbd runs services itself, while lockdownd **launches a separate daemon and
  gives you its port**.

### UDID

The device's unique ID. Every API takes it.

**Android:** the adb serial (`ro.serialno`).

---

## 2. The modern developer stack (iOS 17+)

With iOS 17, Apple moved developer services to a new stack that originally came from
Mac/bridgeOS internals. It's what Xcode 15+, `xcrun devicectl` and Device Hub use.

### Tunnel / CoreDeviceProxy

`com.apple.internal.devicecompute.CoreDeviceProxy` is a lockdown service that turns its
connection into a **network tunnel**: raw IPv6 packets flow between the host and the phone.

- **On a Mac:** Apple's own tools get a kernel `utun` interface.
- **Third-party tools** need one of two things:
  - **Root**, to create a TUN interface. This is what pymobiledevice3's `tunneld` does.
  - A **userspace TCP stack**. idevice has one, `jktcp`, behind the `tunnel_tcp_stack`
    feature. That's why Eagly's mirror needs no admin rights.
- **Over Wi-Fi:** the same tunnel runs over QUIC after **RemotePairing**, a separate pairing
  done over the network.

**Android:** no real equivalent, since adb never gives you IP-level access to the device.
Closest is USB tethering (RNDIS), a network over the cable. Wi-Fi RemotePairing ≈ Android 11+
**Wireless debugging**: a pairing code plus mDNS discovery.

### RSD (Remote Service Discovery)

Inside the tunnel, the phone listens on port **58783**. Connect and it sends a **handshake
listing every available service and its port**, for example:

- `com.apple.coredevice.appservice`
- `com.apple.instruments.dtservicehub`
- `com.apple.mobile.lockdown.remote.trusted`

You then connect to the port you need.

RSD **replaces lockdownd's `StartService`**: services are already running and you look them
up, rather than asking for one to be started. In idevice, `RsdHandshake` does the lookup, and
the `RsdService` trait means "this client can be opened by name through RSD".

**Android:** the servicemanager's registry (`adb shell service list`), a directory from service
name to endpoint, but reachable over a network.

### XPC and RemoteXPC

- **XPC** is Apple's standard **IPC between processes**:
  - Typed messages: dictionaries, arrays, strings, integers, UUIDs, data and file descriptors.
  - Services are named (`com.apple.…`) and started on demand by launchd.
  - Nearly every iOS daemon communicates this way.
- **RemoteXPC** is **XPC carried across the cable**:
  - Messages are serialised to a binary format and sent over **HTTP/2**.
  - One stream is the "root" channel and another the "reply" channel. That's why idevice has an
    `xpc/http2` module, and `recv_root()` vs `recv_any()`.

**Android:** **Binder/AIDL**, the standard IPC. RemoteXPC is roughly "Binder calls serialised
over HTTP/2", conceptually close to **gRPC**.

### CoreDevice

Apple's **modern device-management framework**. On the Mac it's `CoreDevice.framework`, used by
Xcode, `devicectl` and Device Hub. On the phone it's a family of RemoteXPC services named
`com.apple.coredevice.*`:

| Kind | Examples |
|---|---|
| Apps | `appservice`: list, launch and kill apps |
| Files | `fileservice` (**0.1.68**) |
| Device info and diagnostics | `deviceinfo`, `diagnosticsservice` |
| Screen | `displayservice`, `screencaptureservices` |
| Input | `hid.indigo`, `universalhidservice` |
| Icons and settings | `iconservice`, `configuration` (**0.1.68**) |

- **How a call works:** messages share a common envelope: `CoreDevice.featureIdentifier`,
  `CoreDevice.action`, `CoreDevice.input`, plus a protocol version,
  `CoreDevice.coreDeviceVersion`. idevice sends 443.18 in 0.1.65 and 629.3 in 0.1.68.
- **In Eagly:** the screen mirror is built entirely on CoreDevice.

**Android:** the developer-facing system services Android Studio uses through adb.
`devicectl device process launch` ≈ `adb shell am start`, and `devicectl device info apps` ≈
`pm list packages`.

### DDI (Developer Disk Image) and Developer Mode

- **What it is:** on iOS, developer tooling **isn't part of the OS**. It ships as a separate
  signed disk image, mounted on demand through the lockdown service `mobile_image_mounter`.
- **What's inside:** `debugserver`, the Instruments services, testmanagerd and the CoreDevice
  services.
- **Personalised since iOS 17:** each mount is signed for that specific device by **Apple's TSS
  server**. That's what idevice's `tss` feature does, and it needs a network connection the
  first time.
- **Developer Mode** (Settings → Privacy & Security, iOS 16+) has to be on, and switching it on
  requires a reboot.
- **Effect:** no DDI means no CoreDevice services.

**Android:** Developer options plus the USB debugging toggle. On Android the tools are already
in the OS and the toggle just enables them. On iOS they're **mounted at runtime**.

---

## 3. Services

### AFC (Apple File Conduit)

- **What it is:** a lockdown service (`com.apple.afc`) with a small **binary file protocol**:
  `ReadDir`, `GetFileInfo`, `FileOpen`, `Read`, `Write`, `MakeDir`, `RemovePath`, `Rename`, and
  in **0.1.68** `FileLock` and `SetFileSize`.
- **Scope:** limited to `/private/var/mobile/Media` (DCIM, PublicStaging, Downloads and so on).
- **Other places it appears:**
  - `afc2` gives the whole filesystem, on jailbroken devices only.
  - **crashreportcopymobile** is the same protocol rooted at the crash-log directory. That's
    why Eagly reads crash reports through AFC calls.
  - App installs upload the `.ipa` to `PublicStaging` over AFC first.
- **In Eagly:** the file browser and crash reports, `rust/src/api/ios.rs`.

**Android:** adb's **`sync:` protocol** (`adb push/pull`) limited to `/sdcard`, or **MTP**,
which shows a similar media-only view.

### house_arrest

A lockdown service that gives you an **AFC connection rooted inside one app's container**:

- `VendContainer`: the full sandbox, but only for development-signed apps.
- `VendDocuments`: only Documents, for apps that turn on file sharing.

Eagly doesn't use it. The CoreDevice **file service** (**0.1.68**) is the modern replacement:
sessions scoped to an app's data container, an app-group container, the temporary directory or
the system crash logs.

**Android:** `adb shell run-as <pkg>`, which likewise only works for debuggable apps.

### SpringBoard

The iOS **home screen and system UI shell**: home screen, app switcher, lock screen, status bar
and app launching. The lockdown service `com.apple.springboardservices` exposes:

- App icons as PNG
- Home-screen layout
- Wallpaper
- Interface orientation

Eagly uses it for app icons (`fetch_ios_app_icon`) and rotation. The CoreDevice icon service
(**0.1.68**) is an alternative that lets you choose the icon size and reports placeholders,
but it needs the tunnel.

**Android:** **Launcher3 and SystemUI combined.**

### installation_proxy

A lockdown service to install, uninstall and list apps. Apps are identified by **bundle ID**
(`com.example.app`).

**Android:** `pm` / `cmd package`. Bundle ID ≈ package name.

### syslog_relay and os_trace_relay

Two lockdown services that stream device logs:

- `syslog_relay`: older, plain text.
- `os_trace_relay`: **unified logging** in a binary format, carrying process, PID, level,
  **subsystem and category**, and in **0.1.68** thread ID and image UUIDs. Eagly's log viewer
  uses this one.

**Android:** **logcat**. Subsystem/category ≈ tag. Unified-logging levels ≈ logcat priorities.

### DVT / Instruments (`dtservicehub`)

"DeveloperTools" services behind Xcode Instruments: sysmontap (CPU and memory per process),
network activity, process control, location simulation and screenshots. idevice exposes them
under the `dvt` feature.

**Android:** Perfetto, `dumpsys meminfo` and `top`, Android Studio's profilers, and
`adb emu geo` for location.

### debugserver

Apple's remote debugging stub, from the DDI. LLDB connects to it.

**Android:** `lldb-server` for native code, or JDWP for Java and Kotlin.

### testmanagerd and XCTest

Runs UI tests on the device. idevice's `xctest` module drives it.

**Android:** instrumentation (`am instrument`) together with UiAutomator or Espresso.

### configuration (CoreDevice, 0.1.68)

`com.apple.coredevice.configuration`, behind Xcode's appearance and accessibility toggles for a
connected device:

| Setting | Android equivalent |
|---|---|
| Light/dark appearance | `cmd uimode night yes/no` |
| Dynamic Type size | `settings put system font_scale …` |
| Reduce Motion | `settings put global animator_duration_scale 0` |
| Increase Contrast | `high_text_contrast_enabled` |
| Reduce Transparency | No direct equivalent |
| Liquid Glass opacity (iOS 26) | No equivalent |
| Colour filters (e.g. Protanopia) | `accessibility_display_daltonizer_enabled` + `accessibility_display_daltonizer` |
| Show borders | Show layout bounds (`debug.layout`) |

---

## 4. Input: how a touch from Eagly reaches an app

### backboardd

The daemon that **routes every HID event**. Touches, keys and buttons come in from IOHIDFamily,
the kernel's HID layer, and backboardd delivers them to the right app. It also handles display
brightness and backlight. Eagly's mirror waits about 300 ms after a session starts because
backboardd needs that long to pick up new virtual devices (`GATE_SETTLE`, `DEVICES_SETTLE` in
`rust/src/api/ios_mirror.rs`).

**Android:** **InputFlinger** (InputReader and InputDispatcher) in system_server.

### Indigo

Apple's internal name for its **event-injection protocol**. It was first used by the **iOS
Simulator**: Simulator.app sends Indigo messages to the simulated device. CoreDevice now offers
it on real hardware as `com.apple.coredevice.hid.indigo`. It sends **semantic events**:

- `IndigoButtonEvent`: Home, Power, Volume. Eagly sends hardware buttons this way.
- `IndigoKeyboardButtonEvent`: one key going down or up. Eagly types this way today.
- `IndigoDigitizerEvent`: touches, including edge-swipe system gestures.
- `IndigoScrollEvent`: the digital crown on Apple Watch, or a dial.
- Vendor-defined events.

**Android:** **`InputManager.injectInputEvent`**, the API behind
`adb shell input tap / keyevent / swipe`. You describe an event and the system acts on it,
without a real input device.

### Universal HID service and dtuhidd

- **Universal HID service** (`com.apple.coredevice.feature.remote.universalhidservice`) works
  with **raw HID reports** sent to **virtual HID devices** registered on the phone. The devices
  it reports are called "surfaces" (the touchscreen, keyboard and buttons). You can list them
  and send raw reports to them, and in **0.1.68** create one: the `mainKeyboard` API registers
  a virtual USB keyboard, which (per upstream PR #132) keeps iOS from showing its on-screen
  keyboard and autocorrecting what's typed.
- **dtuhidd** is the developer-tools HID daemon. It creates a virtual touchscreen, keyboard and
  buttons **for each session**. Eagly sends multi-touch-format touchscreen reports to that
  touchscreen.

**Android:**

- Raw reports to virtual devices ≈ **`/dev/uhid`**, as used by Android's `hid` tool in CTS.
- dtuhidd ≈ whatever creates the uhid devices.
- The difference from Indigo is the same as uhid vs `input`: one is a real input device going
  through the HID pipeline, the other is synthetic event injection.

### Device Hub

Apple's own Mac app for viewing and controlling connected devices. The display stream, Indigo
and Universal HID services that Eagly's mirror uses are the ones it uses. Its screen-sharing
indicator appears on the phone when iOS 27 requires an open media stream before it accepts
input.

**Android:** closest is **scrcpy**, or Android Studio's Running Devices / device mirroring.

---

## Cheat sheet

| iOS | What it is | Android equivalent |
|---|---|---|
| usbmuxd | Host daemon that multiplexes streams over USB | adb server |
| lockdownd | Device gatekeeper: pairing, info, starting services | adbd + RSA authorisation |
| Pair record / "Trust" | Host credentials stored after pairing | `adbkey` / "Allow USB debugging?" |
| UDID | Device ID | adb serial |
| CoreDeviceProxy tunnel | IPv6 network over the cable | No real equivalent (closest: USB tethering) |
| RemotePairing | Wi-Fi pairing and tunnel | Wireless debugging (pairing code + mDNS) |
| RSD | List of services in the tunnel | `service list` (servicemanager) |
| XPC / RemoteXPC | IPC / IPC over HTTP/2 | Binder / ~gRPC |
| CoreDevice | Modern developer service framework | `am` / `pm` / `cmd` via adb |
| DDI + Developer Mode | Developer tools mounted on demand | Developer options + USB debugging |
| AFC | Media-only file protocol | `adb sync` / MTP |
| house_arrest | File access inside an app's container | `run-as` |
| SpringBoard | Home screen and system UI | Launcher3 + SystemUI |
| installation_proxy | Install, uninstall, list apps | `pm` / `cmd package` |
| os_trace_relay | Unified-log stream | logcat |
| DVT / Instruments | Profiling and process tooling | Perfetto / Studio profilers |
| debugserver | Debugger stub | lldb-server / JDWP |
| testmanagerd / XCTest | UI test runner | `am instrument` / UiAutomator |
| backboardd | HID event routing | InputFlinger |
| Indigo | Semantic event injection | `injectInputEvent` / `input` |
| Universal HID / dtuhidd | Virtual HID devices with raw reports | `/dev/uhid` / `hid` tool |
| Device Hub | Apple's mirror and control app | scrcpy / Studio device mirroring |
