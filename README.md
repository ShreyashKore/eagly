# Eagly

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Desktop](https://img.shields.io/badge/Platforms-macOS%20%7C%20Windows%20%7C%20Linux-informational?logo=apple&logoColor=white)](https://flutter.dev/desktop)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A cross-platform desktop log viewer for **Android** and **iOS** devices — built for developers and testers who need a fast, reliable debugging utility to inspect device logs without any command-line setup.

---

## Screenshots

> _Screenshots coming soon._

---

## Features

- 🔍 **Discover** connected Android and iOS devices automatically
- 📱 **Android** — stream logs via `adb logcat -v threadtime`
- 🍎 **iOS** — stream logs via `idevicesyslog`, with full multi-line syslog entry support
- 🔎 **Filter & Search** — filter by log level, tag, process ID, or free-text search
- 📂 **Import / Export** — open saved log files or export captured logs
- 🌐 **Wireless Debugging** — connect to Android devices over Wi-Fi
- 🎨 **Tabbed log sessions** — view multiple devices side by side
- 🛠️ **No external tools required** — `adb` and `libimobiledevice` are bundled in the app

### Roadmap

Future releases are planned to include:

- 📲 **Screen mirroring** — mirror device screen directly in the app
- 🖱️ **Device control** — interact with the device from your desktop
- And more developer/tester productivity features…

---

## Installation

Download the latest release for your platform from the [Releases](../../releases) page.

No external dependencies need to be installed — the app ships with all required tools bundled.

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
> Download and install iTunes from [https://www.apple.com/itunes/](https://www.apple.com/itunes/) before connecting your device.

1. Install [iTunes](https://www.apple.com/itunes/).
2. Connect your iPhone or iPad via USB.
3. When prompted on the device, tap **Trust This Computer** and enter your passcode.
4. Launch Eagly — your device should appear automatically.

---

## Building from Source

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).
