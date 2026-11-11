import FinderSync
import AppKit
import UserNotifications
// xcodeproj 构建时 CoreKit 源文件直接编入本 module,无需 import(build.sh 仍走 SPM 动态链接)
#if !COREKIT_IN_TARGET
import CoreKit
#endif

class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()

    override init() {
        super.init()
        // 监听全盘,Finder 所有文件夹的右键菜单都出现本扩展
        controller.directoryURLs.insert(URL(fileURLWithPath: "/"))
        // 沙盒内 osascript 发 Apple Events 被静默拒,通知走 UNUserNotificationCenter
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, err in
            NSLog("[RCK] 通知授权 granted=\(granted) err=\(String(describing: err))")
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        dbg("menu(for:) kind=\(menuKind.rawValue)")
        let menu = NSMenu(title: "RightClickKit")
        // —— 新建文件子菜单 ——
        if FeatureStore.isEnabled(.newFile) {
            let newFile = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
            newFile.image = image("doc.badge.plus")
            let sub = NSMenu(title: "新建文件")
            // 注意:FinderSync 的菜单项会经 Finder 序列化重建,representedObject 不存活;
            // 模板类型必须编码进 selector(FinderSync 下 target/action 可存活)
            let templates: [(String, String, Selector, String)] = [
                ("TXT 文本", "doc.plaintext", #selector(newTXT(_:)), "txt"),
                ("Markdown", "number", #selector(newMD(_:)), "md"),
                ("Word 文档", "doc.richtext", #selector(newDOCX(_:)), "docx"),
                ("Excel 表格", "tablecells", #selector(newXLSX(_:)), "xlsx"),
                ("PPT 演示", "slider.horizontal.below.rectangle", #selector(newPPTX(_:)), "pptx"),
            ]
            // 字段顺序说明:上表(标题, 符号, selector, 扩展名)
            for (title, symbol, action, _) in templates {
                let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
                it.target = self
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
            guard let dir = controller.targetedURL() else { notify("无法定位当前文件夹"); return }
            paths = [dir.path(percentEncoded: false)]
        } else {
            paths = urls.map { $0.path(percentEncoded: false) }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths.joined(separator: "\n"), forType: .string)
    }

    @objc private func newTXT(_ sender: NSMenuItem) { createTemplate("txt") }
    @objc private func newMD(_ sender: NSMenuItem) { createTemplate("md") }
    @objc private func newDOCX(_ sender: NSMenuItem) { createTemplate("docx") }
    @objc private func newXLSX(_ sender: NSMenuItem) { createTemplate("xlsx") }
    @objc private func newPPTX(_ sender: NSMenuItem) { createTemplate("pptx") }

    private func createTemplate(_ ext: String) {
        dbg("createTemplate ext=\(ext)")
        guard let dir = controller.targetedURL() else { dbg("targetedURL 为 nil"); notify("无法定位当前文件夹"); return }
        dbg("dir=\(dir.path) ext=\(ext)")
        let name = PathUtils.uniqueName(in: dir, base: "未命名文件", ext: ext)
        let dst = dir.appendingPathComponent(name)
        let fm = FileManager.default
        if ["docx", "xlsx", "pptx"].contains(ext) {
            guard let src = Bundle.main.url(forResource: "template", withExtension: ext) else {
                dbg("模板缺失: \(ext)"); notify("缺少模板文件:\(ext)"); return
            }
            dbg("模板 src=\(src.path)")
            do { try fm.copyItem(at: src, to: dst) } catch { dbg("copyItem 失败: \(error)"); notify("创建失败:\(error.localizedDescription)"); return }
        } else {
            let ok = fm.createFile(atPath: dst.path, contents: Data())
            dbg("createFile(\(dst.path)) = \(ok)")
            guard ok else { notify("创建失败:\(name)"); return }
        }
        NSWorkspace.shared.activateFileViewerSelecting([dst])
    }

    @objc private func newFolder(_ sender: NSMenuItem) {
        guard let dir = controller.targetedURL() else { notify("无法定位当前文件夹"); return }
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
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { notify("未选中任何项目"); return }
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
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { notify("未选中任何项目"); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urls.map { $0.lastPathComponent }.joined(separator: "\n"), forType: .string)
    }

    @objc private func cutFiles(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { notify("未选中任何项目"); return }
        let pb = NSPasteboard.general
        pb.declareTypes([NSPasteboard.PasteboardType("NSFilenamesPboardType"),
                         NSPasteboard.PasteboardType("com.apple.finder.cut-for-board")], owner: nil)
        pb.setPropertyList(urls.map { $0.path(percentEncoded: false) },
                           forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        pb.setString("1", forType: NSPasteboard.PasteboardType("com.apple.finder.cut-for-board"))
        // 验证点:Finder 中 Cmd+V 应回退为「移动」。若失效,降级方案:notify("已记录,请在 App 内粘贴")
        // (pluginkit 注册 BLOCKED,Finder 实际行为待用户验收)
    }

    @objc private func compressZip(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), let first = urls.first else { notify("未选中任何项目"); return }
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
        ["/opt/homebrew/bin/7zz", "/opt/homebrew/bin/7z", "/opt/homebrew/bin/7za",
         "/usr/local/bin/7zz", "/usr/local/bin/7z", "/usr/local/bin/7za"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @objc private func compress7z(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), let first = urls.first else { notify("未选中任何项目"); return }
        guard let seven = locate7z() else {
            notify("未找到 7zz/7za,请执行:brew install p7zip"); return
        }
        let dir = first.deletingLastPathComponent()
        let out = dir.appendingPathComponent(
            PathUtils.uniqueName(in: dir, base: baseName(first), ext: "7z"))
        // cwd 设为首项目录、参数用 lastPathComponent 相对路径(Process 直传 argv 无 shell 切分问题);
        // 已知限制:多选跨目录时相对 cwd 仅对首项目录有效,Task 13 验收按同目录口径
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
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { notify("未选中任何项目"); return }
        // 顶层条目粒度计数:makeWritable 返回的是节点数(文件夹计入全部后代),
        // 直接累加会与 urls.count 口径错位,文件夹全成功也会误报「部分失败」
        var ok = 0
        for url in urls where FileOps.makeWritable(url) > 0 { ok += 1 }
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
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { notify("未选中任何项目"); return }
        guard let url = ActionPayload(action: action,
                                      paths: urls.map { $0.path(percentEncoded: false) }).makeURL() else {
            notify("无法构造动作 URL"); return
        }
        // 沙盒扩展内 NSWorkspace.open(自定义 scheme) 会让 LS 弹「选择应用」框:
        // LS 按扩展 bundle 查 claim 查不到(claim 挂在主 App)。改为显式指定主 App 打开
        let appexPath = Bundle.main.bundlePath
        if appexPath.hasSuffix(".appex") {
            var ns = (appexPath as NSString)
            ns = (ns.deletingLastPathComponent) as NSString  // PlugIns
            ns = (ns.deletingLastPathComponent) as NSString  // Contents
            ns = (ns.deletingLastPathComponent) as NSString  // 主 App .app
            let appURL = URL(fileURLWithPath: ns as String)
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = false
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
                if let error { NSLog("[RCK] 唤起主 App 失败: \(error)") }
            }
        } else if !NSWorkspace.shared.open(url) {
            notify("无法唤起主 App,请先运行一次 RightClickKit")
        }
    }

    @objc private func deleteForever(_ sender: NSMenuItem) { openInApp(action: "delete-forever") }
    @objc private func batchRename(_ sender: NSMenuItem) { openInApp(action: "batch-rename") }
    @objc private func fixMojibake(_ sender: NSMenuItem) { openInApp(action: "fix-mojibake") }

    private func dbg(_ s: String) {
        NSLog("[RCK] %@", s)
        let path = NSTemporaryDirectory() + "rck-debug.log"
        let line = "\(Date()) \(s)\n"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile(); fh.write(line.data(using: String.Encoding.utf8)!); fh.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: String.Encoding.utf8)
        }
    }

    private func notify(_ message: String) {
        dbg("notify: \(message)")
        let content = UNMutableNotificationContent()
        content.title = "RightClickKit"
        content.body = message.components(separatedBy: .newlines).joined(separator: " ")
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { err in
            if let err { NSLog("[RCK] notify add 失败: \(err)") }
        }
    }
}
