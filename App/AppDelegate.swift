import AppKit
import CoreKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 本次启动是否由 rightclickkit:// 动作 URL 唤起：是则不弹设置窗，只显示动作窗
    private var launchedByActionURL = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // 无窗常驻时的 Dock 点击兜底:垃圾 URL/被拒调用可能让本次启动零窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindow.shared.show() }
        return true
    }

    // 扩展经 rightclickkit://<action>?p=...&n=... 唤起(冷启动/热启动均送达)。
    // scheme 可被任意进程 open:nonce 由扩展签发、此处单次核销,缺失/过期一律丢弃;
    // 路径再过 PathPolicy,不替外部调用者搬运 FDA 敏感目录
    func application(_ application: NSApplication, open urls: [URL]) {
        launchedByActionURL = true
        for url in urls {
            guard let payload = ActionPayload.parse(url) else { continue }
            let nonce = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "n" })?.value
            guard let nonce, ActionAuth.consume(nonce) else {
                NSLog("[RCK] 拒绝无 nonce 或 nonce 无效的调用: \(url.host ?? "-")")
                continue
            }
            let rejected = PathPolicy.rejected(in: payload.paths)
            if !rejected.isEmpty {
                let names = rejected.map { ($0 as NSString).lastPathComponent }.joined(separator: "、")
                NSLog("[RCK] PathPolicy 拒绝: \(names)")
                let alert = NSAlert()
                alert.messageText = "已拒绝操作受保护的路径"
                alert.informativeText = "以下路径属于受保护的系统目录(隐私/媒体库/时间机器),RightClickKit 不处理:\n\(names)"
                alert.runModal()
                continue
            }
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
