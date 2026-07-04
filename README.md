# Eagly — Universal Logcat & Console for Android and iOS

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Desktop](https://img.shields.io/badge/Platforms-macOS%20%7C%20Windows%20%7C%20Linux-informational?logo=apple&logoColor=white)](https://flutter.dev/desktop)
[![Size](https://img.shields.io/badge/Download-under%2050%20MB-brightgreen)](#download)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Eagly** is a lightweight, cross-platform **desktop log viewer** for **Android** and
**iOS** devices. View **logcat** and **iOS device logs & crash reports** on **Windows,
macOS, and Linux** — no Android Studio, no Xcode, and no command-line setup required.
It works as a **universal ADB** and **universal logcat** console: stream live logs,
mirror and control the screen, browse files, read iOS crashes, and install apps. `adb`
and `libimobiledevice` come bundled, the whole app is **under 50 MB**, and it stays
light on memory.

**Jump to:** [Why Eagly?](#why-eagly) · [Features](#features) · [Screenshots](#screenshots) · [Download](#download) · [Usage](#usage) · [Build from Source](#building-from-source)

---

## Why Eagly?

- 📱 **View iOS logs and crash reports on Windows** — inspect iPhone & iPad device logs
  and crashes without owning a Mac.
- 🔁 **One universal logcat / ADB console** — the same log viewer and workflow on
  **Windows, Ubuntu / Linux, and macOS**.
- 🚫 **View logs without Android Studio or Xcode** — read live device logs and crashes
  without installing heavyweight IDEs or SDKs.
- 🪶 **Small & efficient** — **under 50 MB** to download and a low memory footprint, so
  it launches instantly and stays out of the way while you debug.

---

## Features

| | |
|---|---|
| 📲 **Screen mirror & control** | Mirror an Android device's screen in-app and drive it with mouse & keyboard. |
| 🔍 **Live logs** | Stream Android (`adb logcat`) and iOS (`idevicesyslog`) logs with full multi-line support. |
| 🔎 **Filter & search** | Filter by log level, tag, process, or free-text — plus regex search. |
| 🐞 **iOS crash reports** | Browse and inspect crash logs pulled straight from connected iPhones & iPads. |
| 📂 **File manager** | Browse, upload, download and delete files on Android (single-level browsing on iOS). |
| 📦 **Install apps** | Drag & drop an `.apk` (Android) or `.ipa` (iOS) onto the window to install. |
| 🌐 **Wireless debugging** | Connect to Android devices over Wi-Fi — no cable needed. |
| 🗂️ **Import / export** | Open saved log files in dedicated tabs or export captured logs. |
| 🎨 **Tabbed sessions & themes** | View multiple devices side by side, with light and dark themes. |
| 🛠️ **No external tools** | `adb` and `libimobiledevice` are bundled — nothing to install separately. |

---

## Screenshots

### 📲 Screen mirroring & control — *Android*
Mirror the device screen right next to your logs and control it with your mouse and keyboard.

![Screen mirroring](docs/screenshots/screen-mirroring.png)

### 🔍 Live logs
Fast, colour-coded streaming with timestamps, package, PID/TID, level and tag columns.

![Logs screen](docs/screenshots/logs_screen.png)

### 🔎 Filtering & regex search
Narrow down noisy logs by level, tag or process, and find anything with regex search.

| Filtering | Regex search |
|---|---|
| <video src="https://github.com/user-attachments/assets/a93d115b-8899-4c03-895c-3aa0f33dec17" width="400"></video> | <video src="https://github.com/user-attachments/assets/10971f7b-a0a0-418b-a0b7-c70c43b9b77b" width="400"></video> |

### 🐞 iOS crash reports
Pull and read crash logs from connected iPhones and iPads.

![iOS crash reports list](docs/screenshots/ios-crashlogs-list.png)
![iOS crash report details](docs/screenshots/ios-crashlogs-details.png)

### 📂 File manager — *Android*
Browse the device filesystem; upload, download and delete files.

![File manager](docs/screenshots/file-manager.png)

### 🌐 Wireless debugging
Pair and connect to Android devices over Wi-Fi.

![Wireless debugging](docs/screenshots/wireless-debugging.png)

### 🗂️ Import logs
Open previously saved log files in their own workspace tab.

![Import logs](docs/screenshots/import-logs.png)

### 🎨 Getting started & themes
A friendly landing screen and full light / dark theme support.

![Getting started](docs/screenshots/getting_started_screen.png)
![Settings & themes](docs/screenshots/settings_screen.png)

---

## Download

Grab the latest release for your platform:

| Platform | Download |
|-----------|-----------|
| 🪟 Windows | [.exe installer](https://github.com/ShreyashKore/eagly/releases/latest/download/eagly-windows-setup.exe) · [.msix](https://github.com/ShreyashKore/eagly/releases/latest/download/eagly-windows.msix) |
| 🐧 Linux | [.deb package](https://github.com/ShreyashKore/eagly/releases/latest/download/eagly-linux.deb) |
| 🍎 macOS | [.dmg](https://github.com/ShreyashKore/eagly/releases/latest/download/eagly-macos.dmg) |

For all versions and changelogs, see the [Releases](https://github.com/ShreyashKore/eagly/releases) page.

Every build is **under 50 MB** and runs with a low memory footprint. Eagly bundles all
required Android and iOS communication tools, including `adb` and `libimobiledevice`, so
there's nothing else to install. **On Windows, iTunes must be installed for iOS device
support.**

---

## Usage

### Android

1. Enable **Developer Options** on your Android device.
2. Turn on **USB Debugging** (Settings → Developer Options → USB debugging).
3. Connect your device via USB (or use wireless debugging).
4. Launch Eagly — your device should appear automatically.

### iOS — macOS / Linux

1. Connect your iPhone or iPad via USB.
2. When prompted on the device, tap **Trust This Computer** and enter your passcode.
3. Launch Eagly — your device should appear automatically.

### iOS — Windows

> **iTunes is required** for iOS device communication on Windows.
> Download and install iTunes from [https://www.apple.com/itunes/](https://www.apple.com/itunes/) or [Apple Devices](https://apps.microsoft.com/detail/9np83lwlpz9k) before connecting your device.

1. Install [iTunes](https://www.apple.com/itunes/) or [Apple Devices](https://apps.microsoft.com/detail/9np83lwlpz9k).
2. Connect your iPhone or iPad via USB.
3. When prompted on the device, tap **Trust This Computer** and enter your passcode.
4. Launch Eagly — your device should appear automatically.

---

## Building from Source

First-time setup is scripted — run [`scripts/setup.sh`](scripts/setup.sh)
(on Windows, from Git Bash: `bash scripts/setup.sh`). See
[docs/SETUP.md](docs/SETUP.md) for prerequisites and details, and
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for the packaging flow.


## Contributions

<a href="https://github.com/ShreyashKore/eagly/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=ShreyashKore/eagly" />
</a>