import Foundation
import AppKit
import CoreKit

enum ActionRouter {
    static func handle(_ payload: ActionPayload) {
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
