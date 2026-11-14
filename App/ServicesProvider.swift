import AppKit
import CoreKit

/// 云盘(iCloud Drive 等 File Provider 域)里 FinderSync 扩展收不到 menu(for:),
/// Finder 右键 → 服务 是唯一兜底入口。方法名对应 App-Info.plist 各 service 的 NSMessage。
final class ServicesProvider: NSObject {
    /// 强引用防释放(servicesProvider 语义不保证持有)
    private static var sharedInstance: ServicesProvider?
    /// 本次进程内是否已有服务被调用:冷启动经服务唤起时不弹设置窗
    private(set) static var hadInvocation = false

    static func register() {
        let provider = ServicesProvider()
        NSApp.servicesProvider = provider
        sharedInstance = provider
        // 强制系统重扫本 App 的 NSServices,安装/更新后菜单项立即可见
        NSUpdateDynamicServices()
    }

    /// 服务 pasteboard 只在本次调用期间有效,必须同步读取
    private func fileURLs(from pboard: NSPasteboard) -> [URL] {
        let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = pboard.propertyList(forType: filenames) as? [String], !paths.isEmpty {
            return paths.map { URL(fileURLWithPath: $0) }
        }
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]) ?? []
    }

    private static func markInvoked() { hadInvocation = true }

    @objc func rckBatchRename(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        Self.markInvoked()
        let urls = fileURLs(from: pboard)
        guard !urls.isEmpty else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            BatchRenameView.show(urls: urls)
        }
    }

    @objc func rckFixMojibake(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        Self.markInvoked()
        let urls = fileURLs(from: pboard)
        guard !urls.isEmpty else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            MojibakeFixView.show(urls: urls)
        }
    }

    /// 压缩会 fork 子进程并等待,放后台;完成后选中产物(与扩展内行为一致)
    @objc func rckZip(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        Self.markInvoked()
        let urls = fileURLs(from: pboard)
        guard !urls.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Zipper.zip(items: urls)
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    NSApp.activate(ignoringOtherApps: true)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                case .failure(let f):
                    let alert = NSAlert()
                    alert.messageText = "压缩失败"
                    alert.informativeText = f.message
                    alert.runModal()
                }
            }
        }
    }
}
