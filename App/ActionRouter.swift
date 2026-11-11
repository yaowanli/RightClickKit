import Foundation
import AppKit
import CoreKit

enum ActionRouter {
    static func handle(_ payload: ActionPayload) {
        // 无窗口动作:发 Return 触发 Finder 内联重命名,不需要 paths 也不弹窗
        if payload.action == "rename-hint" {
            ReturnKeySender.sendWhenFinderFrontmost()
            return
        }
        let urls = payload.paths.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return } // 空 p=%5B%5D 不弹空窗
        DispatchQueue.main.async {
            switch payload.action {
            case "delete-forever": DeleteForeverView.show(urls: urls)
            case "batch-rename":   BatchRenameView.show(urls: urls)
            case "fix-mojibake":   MojibakeFixView.show(urls: urls)
            default: break
            }
        }
    }
}
