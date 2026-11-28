import Cocoa
import FlutterMacOS
import macos_window_utils

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Forward launch arguments to Dart's `main(args)`, as the Windows and
    // Linux runners already do (e.g. `--record-mode`).
    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(CommandLine.arguments.dropFirst())
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    // Hosts the Flutter view over an NSVisualEffectView, so the window can
    // take the system's sidebar material (flutter_acrylic, see
    // `lib/presentation/theme/platform_look.dart`).
    let windowUtilsViewController = MacOSWindowUtilsViewController(
      flutterViewController: flutterViewController)
    self.contentViewController = windowUtilsViewController
    self.setFrame(windowFrame, display: true)
    MainFlutterWindowManipulator.start(mainFlutterWindow: self)

    RegisterGeneratedPlugins(registry: flutterViewController)

    ScrcpyVideoPlugin.register(
      with: flutterViewController.registrar(forPlugin: "ScrcpyVideoPlugin"))
    IosScreenCapturePlugin.register(
      with: flutterViewController.registrar(forPlugin: "IosScreenCapturePlugin"))

    super.awakeFromNib()
  }
}
