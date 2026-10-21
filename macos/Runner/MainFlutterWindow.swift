import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Forward launch arguments to Dart's `main(args)`, as the Windows and
    // Linux runners already do (e.g. `--record-mode`).
    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(CommandLine.arguments.dropFirst())
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    ScrcpyVideoPlugin.register(
      with: flutterViewController.registrar(forPlugin: "ScrcpyVideoPlugin"))
    IosScreenCapturePlugin.register(
      with: flutterViewController.registrar(forPlugin: "IosScreenCapturePlugin"))

    super.awakeFromNib()
  }
}
