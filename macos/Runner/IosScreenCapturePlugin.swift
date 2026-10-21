import AVFoundation
import Cocoa
import CoreImage
import CoreMediaIO
import FlutterMacOS

/// Shows a USB-connected iPhone's screen the way QuickTime Player does: once
/// screen-capture devices are allowed, macOS offers the phone as a muxed
/// `AVCaptureDevice`, and its frames are rendered into a Flutter texture.
///
///  - method `eagly/ios_screen_capture`: `start {deviceName}` -> textureId,
///    `stop {textureId}`, `snapshot {textureId}` -> PNG of the latest frame
///  - event  `eagly/ios_screen_capture/events`:
///    `{textureId, event: "size", width, height}` whenever the picture's size
///    changes, the first frame included, and `{textureId, event: "ended",
///    message}` when the capture stops by itself
///
/// Needs camera permission, so `NSCameraUsageDescription`. On an iPhone 16e
/// (iOS 26.6) it ran at about 50 fps at the phone's full resolution, and the
/// first frame took about 5.5 s. Starting a capture re-enumerates the phone on
/// USB, which drops its usbmux connections once. See
/// docs/IOS_SCREEN_MIRROR.md.
public class IosScreenCapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let textures: FlutterTextureRegistry
  private var captures: [Int64: IosScreenCapture] = [:]
  private var eventSink: FlutterEventSink?

  init(textures: FlutterTextureRegistry) {
    self.textures = textures
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    WindowTransitionGuard.shared.install()
    let instance = IosScreenCapturePlugin(textures: registrar.textures)
    let method = FlutterMethodChannel(
      name: "eagly/ios_screen_capture", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: method)
    let events = FlutterEventChannel(
      name: "eagly/ios_screen_capture/events", binaryMessenger: registrar.messenger)
    events.setStreamHandler(instance)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let textureId = (args?["textureId"] as? NSNumber)?.int64Value
    switch call.method {
    case "start":
      start(deviceName: args?["deviceName"] as? String ?? "", result: result)
    case "stop":
      if let textureId = textureId, let capture = captures.removeValue(forKey: textureId) {
        capture.stop()
        textures.unregisterTexture(textureId)
      }
      result(nil)
    case "snapshot":
      guard let textureId = textureId, let capture = captures[textureId] else {
        result(nil)
        return
      }
      result(capture.snapshotPng().map { FlutterStandardTypedData(bytes: $0) })
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(deviceName: String, result: @escaping FlutterResult) {
    AVCaptureDevice.requestAccess(for: .video) { granted in
      guard granted else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "permission_denied", message: Self.cameraDeniedMessage(), details: nil))
        }
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let opened = IosScreenCapture.open(deviceName: deviceName)
        DispatchQueue.main.async {
          switch opened {
          case .failure(let error):
            result(FlutterError(code: error.code, message: error.message, details: nil))
          case .success(let capture):
            let id = self.textures.register(capture)
            capture.attach(textureId: id, registry: self.textures) { [weak self] event in
              DispatchQueue.main.async { self?.eventSink?(event) }
            }
            self.captures[id] = capture
            capture.start()
            result(NSNumber(value: id))
          }
        }
      }
    }
  }
}

extension IosScreenCapturePlugin {
  /// Why the camera was refused. macOS asks on behalf of the app that started
  /// the process tree: launched from Finder that is Eagly, but started by
  /// `flutter run` in a terminal or IDE it is that app, and one without a
  /// camera usage description is refused without a prompt.
  static func cameraDeniedMessage() -> String {
    let lead = "macOS treats an iPhone's screen as a camera, and "
    if getppid() != 1 {
      return lead
        + "asks the app that started Eagly, such as a terminal or an IDE, for camera "
        + "access. Allow that app in System Settings → Privacy & Security → Camera, or "
        + "open Eagly from Finder."
    }
    return lead
      + "Eagly isn't allowed to use the camera. Allow it in System Settings → Privacy & "
      + "Security → Camera."
  }
}

struct IosScreenCaptureError: Error {
  let code: String
  let message: String
}

/// One iPhone's screen, captured and surfaced as a Flutter texture.
final class IosScreenCapture: NSObject, FlutterTexture,
  AVCaptureVideoDataOutputSampleBufferDelegate
{
  private let device: AVCaptureDevice
  private let session = AVCaptureSession()
  /// `startRunning` / `stopRunning` block, and must not run on the queue the
  /// frames arrive on.
  private let sessionQueue = DispatchQueue(label: "eagly.ios-screen-capture.session")
  private let frameQueue = DispatchQueue(label: "eagly.ios-screen-capture.frames")

  private let lock = NSLock()
  private var latest: CVPixelBuffer?
  private var size = CGSize.zero
  private var textureId: Int64 = 0
  private weak var registry: FlutterTextureRegistry?
  private var emit: (([String: Any]) -> Void)?
  private var observers: [NSObjectProtocol] = []
  private var ended = false

  private init(device: AVCaptureDevice) {
    self.device = device
  }

  /// Finds the phone called [deviceName] and prepares a session for it.
  /// Blocks for up to 10 s while macOS brings the phone's screen up.
  static func open(deviceName: String) -> Result<IosScreenCapture, IosScreenCaptureError> {
    allowScreenCaptureDevices()
    let deadline = Date().addingTimeInterval(10)
    var phones: [AVCaptureDevice] = []
    repeat {
      phones = connectedPhones()
      let named = phones.filter { $0.localizedName == deviceName }
      if named.count > 1 {
        return .failure(
          IosScreenCaptureError(
            code: "ambiguous",
            message: "More than one connected iPhone is called “\(deviceName)”. "
              + "Rename one in its Settings → General → About to tell them apart."))
      }
      // The device's name is the phone's own; with one phone plugged in,
      // any name will do.
      if let phone = named.first ?? (phones.count == 1 ? phones[0] : nil) {
        return open(phone)
      }
      Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return .failure(
      IosScreenCaptureError(
        code: phones.isEmpty ? "no_device" : "ambiguous",
        message: phones.isEmpty
          ? "macOS didn't offer the iPhone's screen. Unplug it and plug it back in."
          : "None of the connected iPhones is called “\(deviceName)”."))
  }

  private static func open(_ device: AVCaptureDevice) -> Result<IosScreenCapture, IosScreenCaptureError>
  {
    let capture = IosScreenCapture(device: device)
    do {
      try capture.configure()
      return .success(capture)
    } catch let error as IosScreenCaptureError {
      return .failure(error)
    } catch {
      return .failure(IosScreenCaptureError(code: "failed", message: error.localizedDescription))
    }
  }

  /// Screen-capture devices are hidden until a process opts in; QuickTime
  /// Player does the same.
  private static func allowScreenCaptureDevices() {
    var address = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var allow: UInt32 = 1
    CMIOObjectSetPropertyData(
      CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
      UInt32(MemoryLayout<UInt32>.size), &allow)
  }

  /// The phones macOS offers as capture devices. Their unique ID is not the
  /// UDID, so they are told apart by name.
  private static func connectedPhones() -> [AVCaptureDevice] {
    let types: [AVCaptureDevice.DeviceType]
    if #available(macOS 14.0, *) {
      types = [.external]
    } else {
      types = [.externalUnknown]
    }
    return AVCaptureDevice.DiscoverySession(
      deviceTypes: types, mediaType: .muxed, position: .unspecified
    ).devices.filter { $0.modelID == "iOS Device" }
  }

  private func configure() throws {
    let input = try AVCaptureDeviceInput(device: device)
    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: frameQueue)
    guard session.canAddInput(input), session.canAddOutput(output) else {
      throw IosScreenCaptureError(
        code: "failed", message: "macOS couldn't capture the iPhone's screen.")
    }
    session.addInput(input)
    session.addOutput(output)
  }

  func attach(
    textureId: Int64, registry: FlutterTextureRegistry,
    emit: @escaping ([String: Any]) -> Void
  ) {
    lock.lock()
    self.textureId = textureId
    self.registry = registry
    self.emit = emit
    lock.unlock()
  }

  func start() {
    let center = NotificationCenter.default
    observers = [
      center.addObserver(
        forName: .AVCaptureDeviceWasDisconnected, object: device, queue: nil
      ) { [weak self] _ in
        self?.end("The iPhone was disconnected.")
      },
      center.addObserver(
        forName: .AVCaptureSessionRuntimeError, object: session, queue: nil
      ) { [weak self] note in
        let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
        self?.end(
          "The iPhone's screen capture stopped: \(error?.localizedDescription ?? "unknown error").")
      },
    ]
    sessionQueue.async { self.session.startRunning() }
  }

  func stop() {
    lock.lock()
    ended = true
    emit = nil
    lock.unlock()
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    sessionQueue.async {
      self.session.stopRunning()
      self.lock.lock()
      self.latest = nil
      self.lock.unlock()
    }
  }

  /// The latest frame as a PNG. Its status bar is the clean "9:41" one iOS
  /// draws while its screen is being captured.
  func snapshotPng() -> Data? {
    lock.lock()
    let pixels = latest
    lock.unlock()
    guard let pixels = pixels else { return nil }
    return CIContext().pngRepresentation(
      of: CIImage(cvPixelBuffer: pixels), format: .RGBA8,
      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
  }

  private func end(_ message: String) {
    lock.lock()
    let emit = ended ? nil : self.emit
    ended = true
    let id = textureId
    lock.unlock()
    emit?(["textureId": id, "event": "ended", "message": message])
  }

  // MARK: FlutterTexture

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard let latest = latest else { return nil }
    return Unmanaged.passRetained(latest)
  }

  // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let frameSize = CGSize(
      width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))
    lock.lock()
    if ended {
      lock.unlock()
      return
    }
    latest = pixels
    let resized = frameSize != size
    size = frameSize
    let id = textureId
    let registry = self.registry
    let emit = self.emit
    lock.unlock()
    if resized {
      emit?([
        "textureId": id, "event": "size", "width": Int(frameSize.width),
        "height": Int(frameSize.height),
      ])
    }
    // The frame is kept either way; a redraw for any other reason shows it.
    if !WindowTransitionGuard.shared.isSettling {
      registry?.textureFrameAvailable(id)
    }
  }
}

/// Holds the capture's redraws back while the window or screen is changing.
///
/// Each captured frame makes Flutter redraw the window, about 50 times a
/// second, and redrawing while the window's size is in flux hits a Flutter
/// engine bug on macOS: the back-buffer cache can return a surface of the
/// wrong size, and Impeller dereferences a null texture in
/// `Canvas::SetupRenderPass` (flutter/flutter#192522, unfixed in 3.47.7).
/// Window drags, resizes, full screen, Space and display changes and coming
/// to the front are the known triggers, and a video texture on screen makes
/// them reliable. This only lowers the odds; turning Impeller off is the
/// engine-wide workaround.
final class WindowTransitionGuard {
  static let shared = WindowTransitionGuard()

  /// How long the window is given to settle after a change.
  private static let settleTime: TimeInterval = 0.5

  /// A ceiling on waiting for an end that never comes (a drag whose
  /// did-move is never posted, say), so the picture cannot stay frozen.
  private static let longestWait: TimeInterval = 30

  private let lock = NSLock()
  /// Until a change with an end (a resize, a move, full screen) ends.
  private var heldUntil = Date.distantPast
  /// Until the window has had a moment after the latest change.
  private var settledAt = Date.distantPast
  private var observers: [NSObjectProtocol] = []

  var isSettling: Bool {
    lock.lock()
    defer { lock.unlock() }
    return Date() < max(heldUntil, settledAt)
  }

  func install() {
    guard observers.isEmpty else { return }
    let windows = NotificationCenter.default
    let workspace = NSWorkspace.shared.notificationCenter
    let observe: (NotificationCenter, Notification.Name, @escaping () -> Void) -> Void = {
      [weak self] center, name, action in
      self?.observers.append(
        center.addObserver(forName: name, object: nil, queue: nil) { _ in action() })
    }
    for name in [
      NSWindow.willStartLiveResizeNotification, NSWindow.willMoveNotification,
      NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification,
    ] {
      observe(windows, name) { [weak self] in self?.hold() }
    }
    for name in [
      NSWindow.didEndLiveResizeNotification, NSWindow.didMoveNotification,
      NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
    ] {
      observe(windows, name) { [weak self] in self?.settle(endingHold: true) }
    }
    for name in [
      NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification,
      NSWindow.didChangeBackingPropertiesNotification, NSWindow.didDeminiaturizeNotification,
      NSWindow.didChangeOcclusionStateNotification,
      NSApplication.didBecomeActiveNotification,
      NSApplication.didChangeScreenParametersNotification,
    ] {
      observe(windows, name) { [weak self] in self?.settle(endingHold: false) }
    }
    for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
      observe(workspace, name) { [weak self] in self?.settle(endingHold: false) }
    }
  }

  private func hold() {
    lock.lock()
    heldUntil = Date().addingTimeInterval(Self.longestWait)
    lock.unlock()
  }

  /// Frames resume once the window has had a moment: after the change in
  /// flight ends, if [endingHold], and after this one.
  private func settle(endingHold: Bool) {
    lock.lock()
    if endingHold { heldUntil = .distantPast }
    settledAt = Date().addingTimeInterval(Self.settleTime)
    lock.unlock()
  }
}
