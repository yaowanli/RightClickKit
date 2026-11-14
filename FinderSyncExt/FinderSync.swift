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
        // 外接卷必须逐卷注册:FinderSync 观察边界按卷计算,不跨挂载点继承
        // (RClick DMG 实测 / FinderRight 2026-10-02 实测一致);云盘是 File Provider 域,
        // 注册也收不到回调,兜底走主 App Services(见 App/ServicesProvider.swift)
        mergeMountedVolumes()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(volumeDidMount(_:)),
            name: NSWorkspace.didMountNotification, object: nil)
        // 沙盒内 osascript 发 Apple Events 被静默拒,通知走 UNUserNotificationCenter
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, err in
            NSLog("[RCK] 通知授权 granted=\(granted) err=\(String(describing: err))")
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        dbg("menu(for:) kind=\(menuKind.rawValue)")
        let menu = NSMenu(title: "RightClickKit")
        // 一次读文件取全部开关快照:isEnabled 逐项读会变成每次右键 12 次文件 IO
        let flags = FeatureStore.flags()
        // —— 新建文件子菜单 ——
        if flags[.newFile] ?? true {
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
        add(to: menu, flags: flags, feature: .newFolder, action: #selector(newFolder(_:)))
        add(to: menu, flags: flags, feature: .folderFromName, action: #selector(folderFromName(_:)))
        add(to: menu, flags: flags, feature: .openTerminal, action: #selector(openTerminal(_:)))
        add(to: menu, flags: flags, feature: .copyName, action: #selector(copyName(_:)))
        add(to: menu, flags: flags, feature: .copyPath, action: #selector(copyPath(_:)))
        add(to: menu, flags: flags, feature: .cut, action: #selector(cutFiles(_:)))
        // 剪切队列非空时提供「粘贴」与「取消剪切」;放在剪切正下方,语义相邻
        let cutQueue = UserDefaults.standard.stringArray(forKey: Self.cutQueueKey) ?? []
        if !cutQueue.isEmpty {
            let paste = NSMenuItem(title: "粘贴(移动 \(cutQueue.count) 项到此处)",
                                   action: #selector(pasteMove(_:)), keyEquivalent: "")
            paste.target = self
            paste.image = image("doc.on.clipboard")
            menu.addItem(paste)
            let cancel = NSMenuItem(title: "取消剪切", action: #selector(cancelCut(_:)), keyEquivalent: "")
            cancel.target = self
            cancel.image = image("xmark.circle")
            menu.addItem(cancel)
        }
        add(to: menu, flags: flags, feature: .compressZip, action: #selector(compressZip(_:)))
        add(to: menu, flags: flags, feature: .compress7z, action: #selector(compress7z(_:)))
        add(to: menu, flags: flags, feature: .grantWrite, action: #selector(grantWrite(_:)))
        // Option 在菜单构建时读一次:跳过确认变体的标题与 selector 由同一状态决定,
        // 防标题与行为分叉(菜单进 Finder 后扩展无法再改)
        if flags[.deleteForever] ?? true {
            let skip = Self.optionKeyDown
            let item = NSMenuItem(title: skip ? "彻底删除(跳过确认)" : Feature.deleteForever.title,
                                  action: skip ? #selector(deleteForeverSkip(_:)) : #selector(deleteForever(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.image = image(Feature.deleteForever.icon)
            menu.addItem(item)
        }
        add(to: menu, flags: flags, feature: .batchRename, action: #selector(batchRename(_:)))
        add(to: menu, flags: flags, feature: .fixMojibake, action: #selector(fixMojibake(_:)))
        return menu
    }

    private func add(to menu: NSMenu, flags: [Feature: Bool], feature: Feature, action: Selector) {
        guard flags[feature] ?? true else { return }
        let item = NSMenuItem(title: feature.title, action: action, keyEquivalent: "")
        item.target = self
        item.image = image(feature.icon)
        menu.addItem(item)
    }

    /// SF Symbol 图标统一 16pt;按符号名缓存(menu(for:) 每次右键都会重建菜单,
    /// NSImage(systemSymbolName:) 非零成本,RClick 同款做法)。符号名无效时返回 nil(菜单项无图,不致命)
    private static let iconCache = NSCache<NSString, NSImage>()

    private func image(_ symbol: String) -> NSImage? {
        if let hit = Self.iconCache.object(forKey: symbol as NSString) { return hit }
        guard let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
        img.size = NSSize(width: 16, height: 16)
        Self.iconCache.setObject(img, forKey: symbol as NSString)
        return img
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        guard let dir = workingDirectory() else { notify("无法定位当前文件夹"); return }
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            notify("未找到终端应用(Terminal.app)"); return
        }
        // 把文件夹当文档传给终端 App(RClick 同款):Terminal 收到目录即开新窗口并 cd 过去
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([dir], withApplicationAt: terminal, configuration: config) { [weak self] _, error in
            guard let error else { return }
            NSLog("[RCK] 打开终端失败: \(error)")
            DispatchQueue.main.async { self?.notify("打开终端失败:\(error.localizedDescription)") }
        }
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

    /// 新建目标目录:仅当选中的单个文件夹时进其内部,否则 Finder 当前目录(FinderRight/RClick 同款语义)
    private func workingDirectory() -> URL? {
        let sel = controller.selectedItemURLs() ?? []
        if sel.count == 1 {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: sel[0].path, isDirectory: &isDir), isDir.boolValue {
                return sel[0]
            }
        }
        return controller.targetedURL()
    }

    /// 新卷挂载:只并入不剔除。卸载卷的残留路径无害;重设集合=重新注册,
    /// 会让本扩展在重叠扩展中重新排队(RClick/FinderRight 同款取舍)
    @objc private func volumeDidMount(_ n: Notification) { mergeMountedVolumes() }

    private func mergeMountedVolumes() {
        guard let vols = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsReadOnlyKey], options: [.skipHiddenVolumes]) else { return }
        var add: Set<URL> = []
        for v in vols {
            let ro = (try? v.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? true
            let p = v.path
            // 只读卷不注册:观察卷根会让 Finder 把该卷侧边栏图标换成本 App 图标(RClick #155 实测);
            // 只读的安装镜像没有可操作价值,不值得付图标代价(FinderRight 同款取舍)
            if !ro, p != "/", !p.hasPrefix("/System"), !p.hasPrefix("/private") { add.insert(v) }
        }
        guard !add.isEmpty else { return }
        let current = controller.directoryURLs ?? []
        let merged = current.union(add)
        guard merged != current else { return } // 集合未变化不重设
        controller.directoryURLs = merged
        dbg("directoryURLs 并入 \(merged.count - current.count) 个卷,共 \(merged.count) 项")
    }

    /// 观察目录起止日志:排查「某目录菜单不出现」的第一现场(配合 touch rck-debug.log)
    override func beginObservingDirectory(at url: URL) { dbg("beginObserving \(url.path)") }
    override func endObservingDirectory(at url: URL) { dbg("endObserving \(url.path)") }

    private func createTemplate(_ ext: String) {
        dbg("createTemplate ext=\(ext)")
        guard let dir = workingDirectory() else { dbg("targetedURL 为 nil"); notify("无法定位当前文件夹"); return }
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
        selectAndRename(dst)
    }

    @objc private func newFolder(_ sender: NSMenuItem) {
        guard let dir = workingDirectory() else { notify("无法定位当前文件夹"); return }
        let name = PathUtils.uniqueName(in: dir, base: "未命名文件夹", ext: "")
        let dst = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: false)
        } catch {
            notify("创建失败:\(error.localizedDescription)"); return
        }
        selectAndRename(dst)
    }

    /// 选中新建产物并尝试自动重命名:主 App 在运行时唤起它(不激活、无窗口)发 Return 键,
    /// Finder 前台且选中新项时即进入内联重命名(RClick 同款体验);
    /// 主 App 未运行/无辅助功能权限时静默跳过,只保持选中
    private func selectAndRename(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        guard let mainID = hostAppURL().flatMap({ Bundle(url: $0)?.bundleIdentifier }), !mainID.isEmpty,
          !NSRunningApplication.runningApplications(withBundleIdentifier: mainID).isEmpty else { return }
        guard let nonce = ActionAuth.issueNonce(),
          let hint = ActionPayload(action: "rename-hint", paths: []).makeURL(nonce: nonce) else {
            dbg("nonce 签发或 URL 构造失败,跳过自动重命名"); return
        }
        openURLWithHostApp(hint, activates: false)
    }

    /// 主 App 的 .app URL:从扩展 bundle 路径上溯三级。唤起主 App 与主 App bundle ID 探测共用这一个机制
    private func hostAppURL() -> URL? {
        let appexPath = Bundle.main.bundlePath
        guard appexPath.hasSuffix(".appex") else { return Bundle.main.bundleURL }
        var ns = (appexPath as NSString)
        ns = (ns.deletingLastPathComponent) as NSString  // PlugIns
        ns = (ns.deletingLastPathComponent) as NSString  // Contents
        ns = (ns.deletingLastPathComponent) as NSString  // 主 App .app
        return URL(fileURLWithPath: ns as String)
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

    // MARK: - 剪切/粘贴(移动)
    // macOS 26 实测:沙盒扩展写 NSFilenamesPboardType 会被系统剥离;即使无沙盒进程按
    // legacy 写法写 fileURL+cut-for-board,Cmd+V 也只拷贝不移动 —— 剪贴板 trick 已死。
    // 故走降级方案(计划文档预留):剪切入队列,目标文件夹右键「粘贴(移动到此处)」由扩展直接移动。

    private static let cutQueueKey = "cutQueuePaths"

    @objc private func cutFiles(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { notify("未选中任何项目"); return }
        let paths = urls.map { $0.path(percentEncoded: false) }
        let fm = FileManager.default
        // Finder 同款累加语义:去重合并进现有队列,顺带剔除外部已删除的项
        var queue = (UserDefaults.standard.stringArray(forKey: Self.cutQueueKey) ?? []).filter { fm.fileExists(atPath: $0) }
        let added = paths.filter { !queue.contains($0) }
        guard !added.isEmpty else { notify("所选项目已在剪切队列中"); return }
        queue.append(contentsOf: added)
        UserDefaults.standard.set(queue, forKey: Self.cutQueueKey)
        notify("已剪切 \(added.count) 项(队列共 \(queue.count) 项),在目标文件夹右键选择「粘贴(移动到此处)」")
    }

    @objc private func cancelCut(_ sender: NSMenuItem) {
        UserDefaults.standard.removeObject(forKey: Self.cutQueueKey)
        notify("已取消剪切")
    }

    @objc private func pasteMove(_ sender: NSMenuItem) {
        guard let dir = controller.targetedURL() else { notify("无法定位当前文件夹"); return }
        guard let paths = UserDefaults.standard.stringArray(forKey: Self.cutQueueKey), !paths.isEmpty else {
            notify("剪切队列为空"); return
        }
        // 跨卷移动会退化为逐字节拷贝,同步等待会卡住扩展主线程 → 后台执行,完成后回主线程选中/通知
        DispatchQueue.global(qos: .userInitiated).async {
            self.pasteMoveInBackground(paths: paths, dir: dir)
        }
    }

    private func pasteMoveInBackground(paths: [String], dir: URL) {
        let fm = FileManager.default
        let dirPath = dir.path(percentEncoded: false)
        var moved: [URL] = []
        var failed = 0
        var skipped = 0
        for p in paths {
            let src = URL(fileURLWithPath: p)
            guard fm.fileExists(atPath: src.path) else { failed += 1; continue }
            // 同目录粘贴 = 无操作(Finder 语义):moveWithoutClobber 会把 a.txt 改名成 a 2.txt,必须跳过
            if src.deletingLastPathComponent().path == dirPath { skipped += 1; continue }
            do {
                moved.append(try FileOps.moveWithoutClobber(from: src, to: dir.appendingPathComponent(src.lastPathComponent)))
            } catch {
                failed += 1
                dbg("pasteMove 失败 \(p): \(error)")
            }
        }
        // 队列只留仍存在、且不在本目录的项;父目录用相等比较(hasPrefix 会把子目录路径误判成本目录项)
        let remain = paths.filter {
            fm.fileExists(atPath: $0) && URL(fileURLWithPath: $0).deletingLastPathComponent().path != dirPath
        }
        if remain.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.cutQueueKey)
        } else {
            UserDefaults.standard.set(remain, forKey: Self.cutQueueKey)
        }
        DispatchQueue.main.async {
            if !moved.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(moved) }
            if failed > 0 {
                self.notify("移动完成 \(moved.count) 项,失败 \(failed) 项")
            } else if moved.isEmpty, skipped > 0 {
                self.notify("所选项目就在当前文件夹,无需移动")
            } else if moved.isEmpty {
                self.notify("没有可移动的项目(源文件可能已被删除)")
            } else {
                self.notify("已移动 \(moved.count) 项")
            }
        }
    }

    @objc private func compressZip(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { notify("未选中任何项目"); return }
        runCompression { Zipper.zip(items: urls) }
    }

    @objc private func compress7z(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { notify("未选中任何项目"); return }
        guard let tool = Zipper.locate7z() else {
            notify("未找到 7zz/7za,请执行:brew install p7zip"); return
        }
        runCompression { Zipper.sevenZip(items: urls, toolPath: tool) }
    }

    /// 压缩耗时不可控(大文件),同步等待会卡住扩展主线程 → 后台执行,完成后回主线程通知/选中
    private func runCompression(_ op: @escaping () -> Result<URL, Zipper.Failure>) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = op()
            DispatchQueue.main.async {
                switch result {
                case .success(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
                case .failure(let f): self.notify(f.message)
                }
            }
        }
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

    private func openInApp(action: String) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { notify("未选中任何项目"); return }
        guard let nonce = ActionAuth.issueNonce(),
          let url = ActionPayload(action: action,
                                  paths: urls.map { $0.path(percentEncoded: false) }).makeURL(nonce: nonce) else {
            notify("无法签发动作凭据,请重试"); return
        }
        openURLWithHostApp(url, activates: true)
    }

    /// 沙盒扩展内 NSWorkspace.open(自定义 scheme) 会让 LS 弹「选择应用」框:
    /// LS 按扩展 bundle 查 claim 查不到(claim 挂在主 App)。改为显式指定主 App 打开
    private func openURLWithHostApp(_ url: URL, activates: Bool) {
        if let appURL = hostAppURL(), appURL.pathExtension == "app" {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = activates
            config.createsNewApplicationInstance = false
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
                if let error { NSLog("[RCK] 唤起主 App 失败: \(error)") }
            }
        } else if !NSWorkspace.shared.open(url) {
            notify("无法唤起主 App,请先运行一次 RightClickKit")
        }
    }

    @objc private func deleteForever(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { notify("未选中任何项目"); return }
        // 确认浮层由扩展直接弹出并执行删除,不唤起主 App(轻确认场景下沉到扩展)
        DeleteConfirmPanel.present(urls: urls)
    }

    /// 菜单构建时刻的 Option 键状态(双路兜底:class 属性优先,再取当前事件)
    private static var optionKeyDown: Bool {
        NSEvent.modifierFlags.contains(.option)
            || NSApp.currentEvent?.modifierFlags.contains(.option) == true
    }

    /// Option+右键 = 跳过确认直接删除(标题已明示);删除在后台执行,完成发通知
    @objc private func deleteForeverSkip(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { notify("未选中任何项目"); return }
        DispatchQueue.global(qos: .userInitiated).async {
            var firstError: String?
            for t in urls {
                do { try FileManager.default.removeItem(at: t) }
                catch { if firstError == nil { firstError = error.localizedDescription } }
            }
            DispatchQueue.main.async {
                if let e = firstError {
                    self.notify("删除失败:\(e)")
                } else {
                    self.notify("已彻底删除 \(urls.count) 项")
                }
            }
        }
    }
    @objc private func batchRename(_ sender: NSMenuItem) { openInApp(action: "batch-rename") }
    @objc private func fixMojibake(_ sender: NSMenuItem) { openInApp(action: "fix-mojibake") }

    private func dbg(_ s: String) {
        NSLog("[RCK] %@", s)
        // 文件日志仅在文件已存在时追加:正式环境不会无中生有留下日志;
        // 需要排查时手动创建一次该文件即可开启(touch $TMPDIR/rck-debug.log)
        let path = NSTemporaryDirectory() + "rck-debug.log"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let line = "\(Date()) \(s)\n"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile(); fh.write(line.data(using: String.Encoding.utf8)!); fh.closeFile()
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
