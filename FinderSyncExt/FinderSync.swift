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
            newFile.image = image("doc.badge.plus")
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
                it.image = image(symbol)
                sub.addItem(it)
            }
            newFile.submenu = sub
            menu.addItem(newFile)
        }
        add(to: menu, symbol: "folder.badge.plus", feature: .newFolder,
            action: #selector(newFolder(_:)))
        add(to: menu, symbol: "doc.badge.arrow.up", feature: .folderFromName,
            action: #selector(folderFromName(_:)))
        add(to: menu, symbol: "doc.on.doc", feature: .copyName,
            action: #selector(copyName(_:)))
        add(to: menu, symbol: "link", feature: .copyPath,
            action: #selector(copyPath(_:)))
        add(to: menu, symbol: "scissors", feature: .cut, action: #selector(cutFiles(_:)))
        add(to: menu, symbol: "doc.zipper", feature: .compressZip, action: #selector(compressZip(_:)))
        add(to: menu, symbol: "archivebox", feature: .compress7z, action: #selector(compress7z(_:)))
        add(to: menu, symbol: "lock.open", feature: .grantWrite, action: #selector(grantWrite(_:)))
        add(to: menu, symbol: "trash", feature: .deleteForever, action: #selector(deleteForever(_:)))
        add(to: menu, symbol: "character.textbox", feature: .batchRename, action: #selector(batchRename(_:)))
        add(to: menu, symbol: "wand.and.stars", feature: .fixMojibake, action: #selector(fixMojibake(_:)))
        return menu
    }

    private func add(to menu: NSMenu, symbol: String,
                     feature: Feature, action: Selector) {
        guard FeatureStore.isEnabled(feature) else { return }
        let item = NSMenuItem(title: feature.title, action: action, keyEquivalent: "")
        item.target = self
        item.image = image(symbol)
        menu.addItem(item)
    }

    /// SF Symbol 图标统一 16pt;符号名无效时返回 nil(菜单项无图,不致命)
    private func image(_ symbol: String) -> NSImage? {
        guard let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
        img.size = NSSize(width: 16, height: 16)
        return img
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

    @objc private func cutFiles(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([NSPasteboard.PasteboardType("NSFilenamesPboardType"),
                         NSPasteboard.PasteboardType("com.apple.finder.cut-for-board")], owner: nil)
        pb.setPropertyList(urls.map { $0.path(percentEncoded: false) },
                           forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        pb.setString("1", forType: NSPasteboard.PasteboardType("com.apple.finder.cut-for-board"))
        // 验证点:Finder 中 Cmd+V 应回退为「移动」。若失效,降级方案:notify("已记录,请在 App 内粘贴")
        // (pluginkit 注册 BLOCKED,Finder 实际行为待用户验收)
    }

    @objc private func compressZip(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), let first = urls.first else { return }
        let dir = first.deletingLastPathComponent()
        let out = dir.appendingPathComponent(
            PathUtils.uniqueName(in: dir, base: baseName(first), ext: "zip"))
        guard let status = runTool(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent"]
                + urls.map { $0.path(percentEncoded: false) } + [out.path]) else {
            notify("zip 压缩失败:无法启动 ditto"); return
        }
        if status != 0 { notify("zip 压缩失败(退出码 \(status))"); return }
        NSWorkspace.shared.activateFileViewerSelecting([out])
    }

    private func locate7z() -> String? {
        ["/opt/homebrew/bin/7zz", "/opt/homebrew/bin/7za",
         "/usr/local/bin/7zz", "/usr/local/bin/7za"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @objc private func compress7z(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), let first = urls.first else { return }
        guard let seven = locate7z() else {
            notify("未找到 7zz/7za,请执行:brew install p7zip"); return
        }
        let dir = first.deletingLastPathComponent()
        let out = dir.appendingPathComponent(
            PathUtils.uniqueName(in: dir, base: baseName(first), ext: "7z"))
        // cwd 设为目标目录、参数用 lastPathComponent 相对路径,规避 7z 对含空格/特殊字符绝对路径的解析问题
        guard let status = runTool(
            executable: seven,
            arguments: ["a", "-bd", out.path] + urls.map { $0.lastPathComponent },
            cwd: dir.path) else {
            notify("7z 压缩失败:无法启动 7zz/7za"); return
        }
        if status != 0 { notify("7z 压缩失败(退出码 \(status))"); return }
        NSWorkspace.shared.activateFileViewerSelecting([out])
    }

    @objc private func grantWrite(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return }
        var ok = 0
        for url in urls { ok += FileOps.makeWritable(url) }
        let tried = urls.count
        if ok == tried {
            notify("已授予写入权限(\(tried) 项)")
        } else {
            notify("已授予写入权限 \(ok)/\(tried) 项,部分失败(可能属主不是当前用户)")
        }
    }

    private func baseName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// 同步运行外部工具并返回退出码;启动失败返回 nil。notify 由调用方负责(不并入,保持 fire-and-forget)
    private func runTool(executable: String, arguments: [String], cwd: String? = nil) -> Int32? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        if let cwd { p.currentDirectoryPath = cwd }
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func openInApp(action: String) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return }
        guard let url = ActionPayload(action: action,
                                      paths: urls.map { $0.path(percentEncoded: false) }).makeURL() else {
            notify("无法构造动作 URL"); return
        }
        if !NSWorkspace.shared.open(url) {
            notify("无法唤起主 App,请先运行一次 RightClickKit")
        }
    }

    @objc private func deleteForever(_ sender: NSMenuItem) { openInApp(action: "delete-forever") }
    @objc private func batchRename(_ sender: NSMenuItem) { openInApp(action: "batch-rename") }
    @objc private func fixMojibake(_ sender: NSMenuItem) { openInApp(action: "fix-mojibake") }

    private func notify(_ message: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let escaped = message.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ") // AppleScript 字面量不允许裸换行
        p.arguments = ["-e", "display notification \"\(escaped)\" with title \"RightClickKit\""]
        try? p.run()
    }
}
