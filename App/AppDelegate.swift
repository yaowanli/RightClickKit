import AppKit
import CoreKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        SettingsWindow.shared.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // 扩展经 rightclickkit://<action>?p=... 唤起(冷启动/热启动均送达)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let payload = ActionPayload.parse(url) else { continue }
            ActionRouter.handle(payload)
        }
    }
}
