import AppKit
import ApplicationServices

/// 新建后自动重命名:扩展选中新产物后唤起本 App,这里等 Finder 到前台再发一次 Return,
/// 触发 Finder 内联重命名(RClick 同款体验)。需要辅助功能权限,未授权时静默跳过。
enum ReturnKeySender {
    static func sendWhenFinderFrontmost() {
        guard AXIsProcessTrusted() else {
            NSLog("[RCK] rename-hint: 无辅助功能权限,跳过自动重命名")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var activated = false
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" {
                    usleep(100_000) // 激活与选中非同时完成,留稳定窗口再触发
                    postReturn()
                    return
                }
                // 只激活一次,之后纯轮询,避免反复抢焦点
                if !activated {
                    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
                    activated = true
                }
                usleep(50_000)
            }
            NSLog("[RCK] rename-hint: Finder 2 秒内未到前台,跳过自动重命名")
        }
    }

    private static func postReturn() {
        let returnKeyCode: CGKeyCode = 36
        let down = CGEvent(keyboardEventSource: nil, virtualKey: returnKeyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: returnKeyCode, keyDown: false)
        down?.post(tap: .cghidEventTap)
        usleep(25_000)
        up?.post(tap: .cghidEventTap)
    }
}
