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
        // —— 新建文件子菜单 ——
        if FeatureStore.isEnabled(.newFile) {
            let newFile = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
            if let img = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil) {
                img.size = NSSize(width: 16, height: 16); newFile.image = img
            }
            let sub = NSMenu(title: "新建文件")
            let templates: [(String, String, String)] = [
                ("TXT 文本", "txt", "doc.plaintext"),
                ("Markdown", "md", "number"),
                ("Word 文档", "docx", "doc.richtext"),
                ("Excel 表格", "xlsx", "tablecells"),
                ("PPT 演示", "pptx", "slider.horizontal.below.rectangle"),
            ]
            for (title, ext, symbol) in templates {
                let it = NSMenuItem(title: title, action: #selector(newTemplateFile(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = ext
                if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                    img.size = NSSize(width: 16, height: 16); it.image = img
                }
                sub.addItem(it)
            }
            newFile.submenu = sub
            menu.addItem(newFile)
        }
        add(to: menu, "新建文件夹", symbol: "folder.badge.plus", feature: .newFolder,
            action: #selector(newFolder(_:)))
        add(to: menu, "使用文件名新建文件夹", symbol: "doc.badge.arrow.up", feature: .folderFromName,
            action: #selector(folderFromName(_:)))
        add(to: menu, "拷贝文件(夹)名称", symbol: "doc.on.doc", feature: .copyName,
            action: #selector(copyName(_:)))
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
        // 空选择(文件夹背景右键)回退为拷贝当前文件夹路径
        let urls = controller.selectedItemURLs() ?? []
        let paths: [String]
        if urls.isEmpty {
            guard let dir = controller.targetedURL() else { return }
            paths = [dir.path(percentEncoded: false)]
        } else {
            paths = urls.map { $0.path(percentEncoded: false) }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths.joined(separator: "\n"), forType: .string)
    }

    @objc private func newTemplateFile(_ sender: NSMenuItem) {
        guard let ext = sender.representedObject as? String,
              let dir = controller.targetedURL() else { return }
        let name = PathUtils.uniqueName(in: dir, base: "未命名文件", ext: ext)
        let dst = dir.appendingPathComponent(name)
        let fm = FileManager.default
        if ["docx", "xlsx", "pptx"].contains(ext) {
            guard let src = Bundle.main.url(forResource: "template", withExtension: ext) else {
                notify("缺少模板文件:\(ext)"); return
            }
            do { try fm.copyItem(at: src, to: dst) } catch { notify("创建失败:\(error.localizedDescription)"); return }
        } else {
            guard fm.createFile(atPath: dst.path, contents: Data()) else {
                notify("创建失败:\(name)"); return
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting([dst])
    }

    @objc private func newFolder(_ sender: NSMenuItem) {
        guard let dir = controller.targetedURL() else { return }
        let name = PathUtils.uniqueName(in: dir, base: "未命名文件夹", ext: "")
        let dst = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: false)
        } catch {
            notify("创建失败:\(error.localizedDescription)"); return
        }
        NSWorkspace.shared.activateFileViewerSelecting([dst])
    }

    @objc private func folderFromName(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return }
        let fm = FileManager.default
        for url in urls {
            let stem = url.deletingPathExtension().lastPathComponent
            let dir = url.deletingLastPathComponent().appendingPathComponent(stem)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: false)
                _ = try FileOps.moveWithoutClobber(from: url, to: dir.appendingPathComponent(url.lastPathComponent))
            } catch {
                notify("失败:\(error.localizedDescription)")
            }
        }
    }

    @objc private func copyName(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urls.map { $0.lastPathComponent }.joined(separator: "\n"), forType: .string)
    }

    private func notify(_ message: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let escaped = message.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        p.arguments = ["-e", "display notification \"\(escaped)\" with title \"RightClickKit\""]
        try? p.run()
    }
}
