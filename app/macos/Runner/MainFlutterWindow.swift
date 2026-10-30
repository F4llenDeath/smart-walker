import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.title = "Smart Walker"
    self.setContentSize(NSSize(width: 1180, height: 820))
    self.contentMinSize = NSSize(width: 900, height: 640)
    self.center()
    self.delegate = self

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Route the close button / Command-W through Flutter's cancellable quit
    // request, keeping the engine alive until pending trial saves complete.
    NSApp.terminate(nil)
    return false
  }
}
