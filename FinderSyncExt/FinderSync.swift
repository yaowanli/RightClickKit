import FinderSync
import AppKit
import CoreKit

class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()

    override init() {
        super.init()
        // 监听全盘,Finder 所有文件夹的右键菜单都出现本扩展
        controller.directoryURLs.insert(URL(fileURLWithPath: "/"))
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "RightClickKit")
        add(to: menu, "拷贝路径", symbol: "link", feature: .copyPath,
            action: #selector(copyPath(_:)))
        return menu
    }

    private func add(to menu: NSMenu, _ title: String, symbol: String,
                     feature: Feature, action: Selector) {
        guard FeatureStore.isEnabled(feature) else { return }
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            img.size = NSSize(width: 16, height: 16)
            item.image = img
        }
        menu.addItem(item)
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urls.map { $0.path }.joined(separator: "\n"), forType: .string)
    }
}
