import AppKit
import CoreKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 本次启动是否由 rightclickkit:// 动作 URL 唤起：是则不弹设置窗，只显示动作窗
    private var launchedByActionURL = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // 扩展经 rightclickkit://<action>?p=... 唤起(冷启动/热启动均送达)
    func application(_ application: NSApplication, open urls: [URL]) {
        launchedByActionURL = true
        for url in urls {
            guard let payload = ActionPayload.parse(url) else { continue }
            ActionRouter.handle(payload)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 下个 runloop 再判定（文档规定 open URL 事件在 didFinishLaunching 前后送达）：
        // 右键动作唤起的启动不弹设置窗，避免动作窗后面垫着一个设置窗；
        // 普通启动（首次使用/双击）才显示设置
        DispatchQueue.main.async {
            guard !self.launchedByActionURL else { return }
            SettingsWindow.shared.show()
        }
    }
}
