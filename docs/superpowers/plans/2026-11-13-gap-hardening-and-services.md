# 缺口修复与 Services 兜底 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复二轮开源审计发现的 5 个真缺口(uniqueName 符号链接覆盖 / 外接卷不注册 / URL scheme 无鉴权 / 云盘无菜单入口 / 构建签名薄弱),并顺手落地两项低成本 UX(Option 跳过确认、版本变化重启 Finder)。

**Architecture:** 三模块不变:CoreKit(纯逻辑,新增 ActionGate:PathPolicy + ActionAuth)→ FinderSyncExt(卷注册 + nonce 签发 + Option 变体菜单)→ 主 App(URL 门禁 + ServicesProvider 兜底 + FinderRestarter)。云盘缺口不走扩展(架构上收不到 menu(for:)),走主 App NSServices(右键→服务),复用现有窗口与 Zipper。

**Tech Stack:** Swift 5.9 / AppKit / FinderSync / NSServices(NSFilenamesPboardType)/ 手工 build.sh(swiftc + xcodebuild)。

**关键约束(执行前必读):**
- ext.xcodeproj 是**手工 pbxproj、固定文件列表**(绝对路径引用 CoreKit 源文件):新增 CoreKit 文件必须同步接线,本计划已合并为单文件 ActionGate.swift 只动一处。
- 扩展经 Finder 序列化重建菜单:representedObject 不存活,**一切运行时变化的语义必须编码进 selector 或标题**(本计划 Option 变体用两个 selector)。
- `swift run CoreKitTestRunner` 是唯一测试入口(自研断言 Harness,非 XCTest)。
- 主 App 源文件由 build.sh 的 `App/*.swift` glob,新增 App 文件无需接线。
- GUI 自动化验收在用户使用机器时禁止;自动验证只用「文件日志 + open 窗口(无合成键入)」,菜单出现与否留给用户手动清单。

**已确认的取舍(用户在 ExitPlanMode 前可否决):**
- 外接卷注册卷根会让 Finder 把该卷侧边栏图标换成本 App 图标(RClick #155 实测,观察卷根必换;不观察则整卷无菜单)。接受:可操作价值 > 图标;只读卷不注册(FinderRight 同款,安装镜像无操作价值)。
- 云盘里菜单入口是「右键 → 服务」二级菜单,不是一级右键项(系统限制,无解)。

---

### Task 1: PathUtils.uniqueName 修复符号链接覆盖 bug

悬空符号链接会被 `fileExists`(跟随链接)判成「不存在」,导致 `copyItem`/`createFile` 撞掉链接,内容写到链接目标。改用 lstat 语义(`attributesOfItem` 不跟随链接)。

**Files:**
- Modify: `CoreKit/Sources/CoreKit/PathUtils.swift`
- Test: `CoreKit/Sources/CoreKitTestRunner/PathUtilsTests.swift`

- [ ] **Step 1: 写失败测试**

在 `CoreKit/Sources/CoreKitTestRunner/PathUtilsTests.swift` 的 `runPathUtilsTests()` 末尾追加:

```swift
    test("PathUtils:同名悬空符号链接也算冲突") {
        let dir = try makeTempDir()
        let link = dir.appendingPathComponent("a.txt")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/nonexistent-rck-target")
        let name = PathUtils.uniqueName(in: dir, base: "a", ext: "txt")
        expectEqual(name, "a 2.txt")
    }
    test("PathUtils:目录存在也算冲突(回归)") {
        let dir = try makeTempDir()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("未命名文件夹"), withIntermediateDirectories: false)
        expectEqual(PathUtils.uniqueName(in: dir, base: "未命名文件夹", ext: ""), "未命名文件夹 2")
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd CoreKit && swift run CoreKitTestRunner 2>&1 | grep -E "悬空|FAILED|PASSED"`
Expected: `❌ PathUtils:同名悬空符号链接也算冲突`(实际返回 `a.txt`)+ `FAILED:...`

- [ ] **Step 3: 改实现**

`PathUtils.swift` 的 while 条件改为 lstat 语义:

```swift
        var i = 1
        // 不跟随符号链接(lstat 语义):同名悬空链接也算已存在,
        // 否则 copyItem/createFile 会撞掉链接,把内容写到链接目标路径
        while i < 10_000,
              (try? FileManager.default.attributesOfItem(
                  atPath: directory.appendingPathComponent(candidate(i)).path)) != nil {
            i += 1
        }
        return candidate(i)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd CoreKit && swift run CoreKitTestRunner`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add CoreKit/Sources/CoreKit/PathUtils.swift CoreKit/Sources/CoreKitTestRunner/PathUtilsTests.swift
git commit -m "fix: uniqueName 用 lstat 判重,同名悬空符号链接不再被判不存在导致覆盖"
```

---

### Task 2: CoreKit 新增 ActionGate(PathPolicy 敏感路径拒绝 + ActionAuth 一次性 nonce)

URL scheme 可被任意进程构造 open:nonce 握手挡盲调用,PathPolicy 挡「借主 App 授权搬运受保护数据」。两个 enum 同属 URL 边界校验,合并一个文件,只接线一处 pbxproj。

**Files:**
- Create: `CoreKit/Sources/CoreKit/ActionGate.swift`
- Modify: `ext.xcodeproj/project.pbxproj`(3 处)
- Test: `CoreKit/Sources/CoreKitTestRunner/ActionGateTests.swift`(新建)+ `CoreKit/Sources/CoreKitTestRunner/main.swift`(注册)

- [ ] **Step 1: 创建 ActionGate.swift**

```swift
import Foundation

// MARK: - 敏感路径准入(仅用于 rightclickkit:// 边界)
// URL 可被任意进程构造 open,主 App 可能持 FDA/辅助功能授权,不应替外部调用者
// 搬运受保护数据。扩展内的直接动作(新建/压缩/删除)来自 Finder 用户选择,不经此策略。
public enum PathPolicy {
    /// 用户主目录下的 FDA 专属目录(前缀匹配,含后代;大小写不敏感)
    private static let homeLibraryRestricted = [
        "Library/Messages", "Library/Mail", "Library/Safari", "Library/Keychains",
        "Library/Containers", "Library/Group Containers", "Library/MobileSync",
        "Library/Cookies", "Library/Metadata",
    ]
    /// 任意位置出现的路径后缀(照片/音乐/Aperture 库是受保护包)
    private static let suffixes = [".photoslibrary", ".musiclibrary", ".aplibrary", ".migratedphotolibrary"]
    /// 任意位置出现的路径分量(Time Machine 数据)
    private static let components = ["backups.backupdb", ".timemachine"]

    /// 返回被拒绝的路径;全部通过返回空数组。纯字符串判定,不做 IO
    public static func rejected(in paths: [String]) -> [String] {
        paths.filter { isRejected($0) }
    }

    static func isRejected(_ raw: String) -> Bool {
        let path = raw.lowercased()
        let home = homeDirectory().lowercased()
        for rel in homeLibraryRestricted {
            let base = "\(home)/\(rel.lowercased())"
            if path == base || path.hasPrefix("\(base)/") { return true }
        }
        for suffix in suffixes where path.hasSuffix(suffix) { return true }
        for comp in components where path.split(separator: "/").contains(Substring(comp)) { return true }
        return false
    }

    /// getpwuid 取真实 home:沙盒下 NSHomeDirectory 指容器(本策略只在主 App 用,但取法与 FeatureStore 对齐)
    private static func homeDirectory() -> String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }
}

// MARK: - 一次性 nonce 握手
// 自用工具的相称强度:UUID 单次使用 + 30 秒时效 + 0600 权限;
// 不做签名级鉴权(同用户进程本就能直接删文件,nonce 挡的是「盲构造 URL 驱动我们的授权」)。
public enum ActionAuth {
    struct Ticket: Codable { let n: String; let ts: Double }
    static let ttl: TimeInterval = 30

    /// 票据文件:与 features.json 同目录(getpwuid 真实 home,主 App 与沙盒扩展同路可达)
    public static func nonceFileURL() -> URL {
        let home: String
        if let pw = getpwuid(getuid()) { home = String(cString: pw.pointee.pw_dir) }
        else { home = NSHomeDirectory() }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/RightClickKit/action-nonce.json")
    }

    /// 扩展侧:签发一次性 nonce(覆盖旧值,后点为准)。issuedAt 仅供测试注入
    @discardableResult
    public static func issueNonce(at file: URL = nonceFileURL(), issuedAt: Date = Date()) -> String? {
        let ticket = Ticket(n: UUID().uuidString, ts: issuedAt.timeIntervalSince1970)
        guard let data = try? JSONEncoder().encode(ticket) else { return nil }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return ticket.n
        } catch { return nil }
    }

    /// 主 App 侧:校验并核销。无论成败都删票据(防陈旧票据重放)
    public static func consume(_ nonce: String, at file: URL = nonceFileURL()) -> Bool {
        defer { try? FileManager.default.removeItem(at: file) }
        guard let data = try? Data(contentsOf: file),
              let ticket = try? JSONDecoder().decode(Ticket.self, from: data),
              ticket.n == nonce else { return false }
        return Date().timeIntervalSince1970 - ticket.ts <= ttl
    }
}
```

- [ ] **Step 2: 写测试(新建 ActionGateTests.swift)**

```swift
import Foundation
import CoreKit

func runPathPolicyTests() {
    test("PathPolicy:FDA 专属目录被拒") {
        let home = NSHomeDirectory()
        expectTrue(!PathPolicy.rejected(in: ["\(home)/Library/Messages/chat.db"]).isEmpty)
        expectTrue(!PathPolicy.rejected(in: ["\(home)/library/mail/"]).isEmpty, "大小写不敏感")
        expectTrue(!PathPolicy.rejected(in: ["\(home)/Library/Containers/x/Data"]).isEmpty)
    }
    test("PathPolicy:后代目录也被拒(防打包带走)") {
        let home = NSHomeDirectory()
        expectTrue(!PathPolicy.rejected(in: ["\(home)/Library/Mail/sub/file.emlx"]).isEmpty)
    }
    test("PathPolicy:库类后缀被拒") {
        expectTrue(!PathPolicy.rejected(in: ["/Users/x/Pictures/相册.photoslibrary"]).isEmpty)
    }
    test("PathPolicy:Time Machine 组件被拒") {
        expectTrue(!PathPolicy.rejected(in: ["/Volumes/BK/backups.backupdb/Mac/Latest"]).isEmpty)
        expectTrue(!PathPolicy.rejected(in: ["/Volumes/.timemachine/xyz"]).isEmpty)
    }
    test("PathPolicy:普通路径放行") {
        expectEqual(PathPolicy.rejected(in: ["/Users/x/Desktop/a.txt", "/tmp/b", "~/work/c.md"]), [])
        expectEqual(PathPolicy.rejected(in: []), [])
    }
}

func runActionAuthTests() {
    test("ActionAuth:签发后可核销一次,重放失败") {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("action-nonce.json")
        guard let n = ActionAuth.issueNonce(at: file) else { expectTrue(false, "签发失败"); return }
        expectTrue(ActionAuth.consume(n, at: file), "首次核销应通过")
        expectTrue(!FileManager.default.fileExists(atPath: file.path), "核销后票据应删除")
        expectTrue(!ActionAuth.consume(n, at: file), "票据已删,重放应失败")
    }
    test("ActionAuth:错 nonce 失败且票据被清") {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("action-nonce.json")
        _ = ActionAuth.issueNonce(at: file)
        expectTrue(!ActionAuth.consume("wrong", at: file))
        expectTrue(!FileManager.default.fileExists(atPath: file.path), "失败也应清票据")
    }
    test("ActionAuth:过期票据失败") {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("action-nonce.json")
        _ = ActionAuth.issueNonce(at: file, issuedAt: Date().addingTimeInterval(-60))
        guard let expired = (try? JSONDecoder().decode(
            [String: String].self, from: Data())) as Any? else { } // 占位防未用警告,实际断言在下一行
        expectTrue(!ActionAuth.consume("anything", at: file))
    }
    test("ActionAuth:0600 权限") {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("action-nonce.json")
        _ = ActionAuth.issueNonce(at: file)
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        expectEqual(attrs?[.posixPermissions] as? Int, 0o600)
    }
}
```

注意:第三个测试里那行 `guard let expired ...` 是废代码,**删除它**,直接写断言(终稿应为):

```swift
    test("ActionAuth:过期票据失败") {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("action-nonce.json")
        _ = ActionAuth.issueNonce(at: file, issuedAt: Date().addingTimeInterval(-60))
        expectTrue(!ActionAuth.consume("anything", at: file))
    }
```

- [ ] **Step 3: main.swift 注册测试**

`CoreKit/Sources/CoreKitTestRunner/main.swift` 在 `runPathUtilsTests()` 后插入两行:

```swift
runPathPolicyTests()
runActionAuthTests()
```

- [ ] **Step 4: 跑测试**

Run: `cd CoreKit && swift run CoreKitTestRunner`
Expected: `ALL TESTS PASSED`(原 5 个 PathUtils/ActionPayload 测试 + 新 9 个)

- [ ] **Step 5: pbxproj 接线 ActionGate.swift**

先确认 ID 未被占用:

Run: `grep -o 'BB00000000000000000000[0-9A-F][0-9A-F]' ext.xcodeproj/project.pbxproj | sort -u`
Expected: 现有 ID 集合;`1C`/`1D` 不在其中(被占用则顺延换号)。

对 `ext.xcodeproj/project.pbxproj` 做 3 处追加:

1. PBXBuildFile 区(Zipper 行 `BB000000000000000000000B` 之后):
```
		BB000000000000000000001D /* ActionGate.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB000000000000000000001C; };
```
2. PBXFileReference 区(末尾,Zipper 行之后):
```
		BB000000000000000000001C /* ActionGate.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = ActionGate.swift; path = "/Users/yaowl/orca/projects/mac-右键快捷键/CoreKit/Sources/CoreKit/ActionGate.swift"; sourceTree = "<absolute>"; };
```
3. Sources build phase(`BB0000000000000000000007 /* PathUtils.swift in Sources */,` 同级处):
```
				BB000000000000000000001D /* ActionGate.swift in Sources */,
```

- [ ] **Step 6: 验证接线**

Run: `grep -c "ActionGate" ext.xcodeproj/project.pbxproj`
Expected: `3`

- [ ] **Step 7: Commit**

```bash
git add CoreKit/Sources/CoreKit/ActionGate.swift CoreKit/Sources/CoreKitTestRunner/ActionGateTests.swift CoreKit/Sources/CoreKitTestRunner/main.swift ext.xcodeproj/project.pbxproj
git commit -m "feat: ActionGate——URL 边界一次性 nonce 握手 + FDA 敏感路径拒绝(带测试)"
```

---

### Task 3: 扩展接线——nonce 签发 / 外接卷注册 / 观察目录日志

**Files:**
- Modify: `FinderSyncExt/FinderSync.swift`(init、selectAndRename、openInApp、新增 4 个方法)

- [ ] **Step 1: init 加卷注册与挂载监听**

`FinderSync.swift` init 改为:

```swift
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
```

- [ ] **Step 2: 新增卷注册与观察日志方法(放在 workingDirectory() 附近)**

```swift
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
```

- [ ] **Step 3: 两处唤起点签发 nonce**

`selectAndRename` 中 `guard let hint = ...` 一行改为:

```swift
        guard let nonce = ActionAuth.issueNonce(),
          let hint = ActionPayload(action: "rename-hint", paths: []).makeURL(nonce: nonce) else { return }
```

`openInApp` 的 guard 块改为:

```swift
        guard let nonce = ActionAuth.issueNonce(),
          let url = ActionPayload(action: action,
                                  paths: urls.map { $0.path(percentEncoded: false) }).makeURL(nonce: nonce) else {
            notify("无法构造动作 URL"); return
        }
```

- [ ] **Step 4: ActionPayload.makeURL 支持 nonce**

`CoreKit/Sources/CoreKit/ActionPayload.swift` 的 makeURL 改为:

```swift
    /// rightclickkit://<action>?p=<JSON 数组>&n=<一次性 nonce>
    /// nonce 由扩展签发(见 ActionAuth)、主 App 核销;缺 n 的 URL 会被主 App 拒绝
    public func makeURL(nonce: String? = nil) -> URL? {
        guard let json = try? JSONEncoder().encode(paths),
              let str = String(data: json, encoding: .utf8) else { return nil }
        var comps = URLComponents()
        comps.scheme = "rightclickkit"
        comps.host = action
        var items = [URLQueryItem(name: "p", value: str)]
        if let nonce { items.append(URLQueryItem(name: "n", value: nonce)) }
        comps.queryItems = items
        return comps.url
    }
```

- [ ] **Step 5: 跑测试(默认参数不破坏既有用例)+ 编译扩展**

Run: `cd CoreKit && swift run CoreKitTestRunner && /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project ext.xcodeproj -target FinderSyncExt -configuration Release build SYMROOT=.build/extbuild -quiet && echo EXT-OK`
Expected: `ALL TESTS PASSED` + `EXT-OK`

- [ ] **Step 6: Commit**

```bash
git add FinderSyncExt/FinderSync.swift CoreKit/Sources/CoreKit/ActionPayload.swift
git commit -m "feat: 扩展签发一次性 nonce + 逐卷注册外接卷(只并入不剔除)+ 观察目录日志"
```

---

### Task 4: 主 App 调用门禁(nonce 核销 + PathPolicy)

**Files:**
- Modify: `App/AppDelegate.swift`

- [ ] **Step 1: application(_:open:) 加门禁**

```swift
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
                let names = rejected.map { $0.lastPathComponent }.joined(separator: "、")
                NSLog("[RCK] PathPolicy 拒绝: \(names)")
                let alert = NSAlert()
                alert.messageText = "已拒绝操作受保护的路径"
                alert.informativeText = "以下路径属于系统隐私目录,RightClickKit 不处理:\n\(names)"
                alert.runModal()
                continue
            }
            ActionRouter.handle(payload)
        }
    }
```

- [ ] **Step 2: 编译主 App**

Run: `swiftc -O -I CoreKit/.build/release/Modules -L CoreKit/.build/release -lCoreKit App/*.swift -o /tmp/rck-main-check && echo MAIN-OK`
Expected: `MAIN-OK`

- [ ] **Step 3: Commit**

```bash
git add App/AppDelegate.swift
git commit -m "feat: 主 App 对 rightclickkit:// 调用加 nonce 核销与敏感路径门禁"
```

---

### Task 5: Option+右键跳过确认彻底删除

菜单交给 Finder 后扩展拿不到点击事件,Option 状态必须在**构建时**读一次,且标题与 selector 由同一状态决定(语义一致性,RClick 同款约束)。

**Files:**
- Modify: `FinderSyncExt/FinderSync.swift`

- [ ] **Step 1: menu(for:) 中 deleteForever 项改为变体**

把 `add(to: menu, flags: flags, feature: .deleteForever, action: #selector(deleteForever(_:)))` 一行替换为:

```swift
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
```

- [ ] **Step 2: 新增 optionKeyDown 与 deleteForeverSkip(放 deleteForever 旁)**

```swift
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
```

- [ ] **Step 3: 编译扩展**

Run: `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project ext.xcodeproj -target FinderSyncExt -configuration Release build SYMROOT=.build/extbuild -quiet && echo EXT-OK`
Expected: `EXT-OK`

- [ ] **Step 4: Commit**

```bash
git add FinderSyncExt/FinderSync.swift
git commit -m "feat: Option+右键「彻底删除(跳过确认)」,标题与 selector 由构建时同源状态决定"
```

---

### Task 6: 主 App ServicesProvider + NSServices 声明(云盘兜底)

云盘(iCloud Drive 等 File Provider 域)按「一目录一扩展」路由,我们的扩展永远收不到 menu(for:);Finder 右键 → 服务 是唯一兜底。三个服务复用现有窗口与 Zipper。

**Files:**
- Create: `App/ServicesProvider.swift`
- Modify: `Resources/App-Info.plist`(追加 NSServices)
- Modify: `App/AppDelegate.swift`(didFinishLaunching 注册)

- [ ] **Step 1: 创建 ServicesProvider.swift**

```swift
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
```

- [ ] **Step 2: App-Info.plist 追加 NSServices**

在 `Resources/App-Info.plist` 的 `</dict>`(顶层,CFBundleURLTypes 之后)前插入:

```xml
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>RightClickKit:批量重命名</string></dict>
            <key>NSMessage</key><string>rckBatchRename</string>
            <key>NSPortName</key><string>RightClickKit</string>
            <key>NSRequiredContext</key><dict><key>NSTextContent</key><string>FilePath</string></dict>
            <key>NSSendTypes</key><array><string>NSFilenamesPboardType</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>RightClickKit:修复乱码文件名</string></dict>
            <key>NSMessage</key><string>rckFixMojibake</string>
            <key>NSPortName</key><string>RightClickKit</string>
            <key>NSRequiredContext</key><dict><key>NSTextContent</key><string>FilePath</string></dict>
            <key>NSSendTypes</key><array><string>NSFilenamesPboardType</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>RightClickKit:压缩为 ZIP</string></dict>
            <key>NSMessage</key><string>rckZip</string>
            <key>NSPortName</key><string>RightClickKit</string>
            <key>NSRequiredContext</key><dict><key>NSTextContent</key><string>FilePath</string></dict>
            <key>NSSendTypes</key><array><string>NSFilenamesPboardType</string></array>
        </dict>
    </array>
```

- [ ] **Step 3: AppDelegate 接线注册 + 服务冷启动不弹设置窗**

didFinishLaunching 的延迟设置窗块改为(插入 ServicesProvider.register 与 hadInvocation 判断):

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        ServicesProvider.register()
        // 下个 runloop 再判定（文档规定 open URL 事件在 didFinishLaunching 前后送达）：
        // 右键动作/服务唤起的启动不弹设置窗，避免动作窗后面垫着一个设置窗；
        // 普通启动（首次使用/双击）才显示设置
        DispatchQueue.main.async {
            guard !self.launchedByActionURL, !ServicesProvider.hadInvocation else { return }
            SettingsWindow.shared.show()
        }
        FinderRestarter.restartFinderIfNeeded()  // Task 7 实现,本任务先注释掉此行亦可
    }
```

注:若按任务顺序执行(FinderRestarter 在 Task 7),本步先不加最后一行。

- [ ] **Step 4: lint plist + 编译主 App**

Run: `plutil -lint Resources/App-Info.plist && swiftc -O -I CoreKit/.build/release/Modules -L CoreKit/.build/release -lCoreKit App/*.swift -o /tmp/rck-main-check && echo MAIN-OK`
Expected: `OK` + `MAIN-OK`

- [ ] **Step 5: Commit**

```bash
git add App/ServicesProvider.swift Resources/App-Info.plist App/AppDelegate.swift
git commit -m "feat: NSServices 兜底——云盘等扩展收不到菜单的目录经「右键→服务」提供重命名/乱码修复/压缩"
```

---

### Task 7: 版本变化自动重启 Finder 一次

升级后 Finder 持旧扩展引用导致菜单陈旧,是该品类经典投诉;版本号变化且本会话未做过时 killall Finder 一次。

**Files:**
- Create: `App/FinderRestarter.swift`
- Modify: `App/AppDelegate.swift`(didFinishLaunching 调用)

- [ ] **Step 1: 创建 FinderRestarter.swift**

```swift
import AppKit

/// 版本号变化时重启 Finder 一次:升级后 Finder 可能持旧扩展引用导致菜单/角标陈旧。
/// 以 CFBundleVersion 为准——日常 rebuild 不改版本号就不会触发,避免开发期反复重启 Finder
enum FinderRestarter {
    private static let key = "lastLaunchedBuildVersion"

    static func restartFinderIfNeeded() {
        let cur = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
        guard !cur.isEmpty else { return }
        let prev = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(cur, forKey: key)
        guard let prev, prev != cur else { return } // 首次运行只记录,不重启
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Finder"]
        try? p.run()
        NSLog("[RCK] 版本 \(prev)→\(cur),已重启 Finder 刷新扩展注册")
    }
}
```

- [ ] **Step 2: didFinishLaunching 末尾调用**

在 `App/AppDelegate.swift` 的 `applicationDidFinishLaunching` 末尾加:

```swift
        FinderRestarter.restartFinderIfNeeded()
```

- [ ] **Step 3: 编译主 App**

Run: `swiftc -O -I CoreKit/.build/release/Modules -L CoreKit/.build/release -lCoreKit App/*.swift -o /tmp/rck-main-check && echo MAIN-OK`
Expected: `MAIN-OK`

- [ ] **Step 4: Commit**

```bash
git add App/FinderRestarter.swift App/AppDelegate.swift
git commit -m "feat: 版本号变化时自动重启 Finder 一次,刷新升级后的扩展菜单"
```

---

### Task 8: build.sh 加固

四个点:主 App 加 Hardened Runtime 并硬校验(防 DYLD 注入继承辅助功能/FDA 授权);版本未变跳过重注册(重复 pluginkit -a 会重启扩展、重排选举);注册后查重复拷贝(同 bundle 多份导致选举不稳定);注册成功的版本标记。

**Files:**
- Modify: `build.sh`(签名段、自检段、注册段)

- [ ] **Step 1: 签名段加 -o runtime**

`echo "==> 签名..."` 段中 xcodebuild 分支(67-70 行)的最后一行改为:

```bash
  # -o runtime:Hardened Runtime,防 DYLD_INSERT_LIBRARIES 注入继承我们的辅助功能授权
  codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
```

- [ ] **Step 2: 自检段追加 runtime 硬校验**

`codesign --verify --deep --strict "$APP"` 之后追加:

```bash
# Hardened Runtime 必须真实存在(-o runtime 被忽略时静默缺失)
codesign -dv "$APP" 2>&1 | grep -q "runtime" || { echo "错误:主 App 未启用 Hardened Runtime"; exit 1; }
```

- [ ] **Step 3: 注册段改为「版本未变则跳过」**

`echo "==> 注册扩展"` 起到 `open "$APP"` 之前,整段替换为:

```bash
echo "==> 注册扩展"
# 已注册且版本未变时跳过重注册:重复 pluginkit -a 会重启扩展并重排选举(丢角标归属);
# 版本变了或未注册时才走全量注销→强扫→注册→选举→重启 pkd
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
MARKER="$BUILD/.registered-v$VER"
if [ -f "$MARKER" ] && pluginkit -m | grep -q "$APP_ID.FinderSyncExt"; then
  echo "==> 扩展已注册且版本未变(v$VER),跳过重注册"
  pluginkit -e use -i "$APP_ID.FinderSyncExt" 2>/dev/null || true
else
  LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  pluginkit -r "$APP" 2>/dev/null || true
  "$LSREG" -f "$APP" 2>/dev/null || true
  pluginkit -a "$APP" || true
  pluginkit -e use -i "$APP_ID.FinderSyncExt" 2>/dev/null || true
  killall pkd 2>/dev/null || true
  rm -f "$BUILD"/.registered-* 2>/dev/null || true
  touch "$MARKER"
  sleep 3
fi
# LS 收录 appex 的可靠触发方式是启动一次主 App(幂等:已运行则仅激活)
open "$APP" 2>/dev/null || true
sleep 3
```

- [ ] **Step 4: 末尾追加重复注册检查**

`if ! pluginkit -m | grep -q ...` 提示块之后、`codesign -dv` 之前追加:

```bash
# 同 bundle ID 多拷贝注册会让 pluginkit 选举不稳定、菜单时有时无
DUP=$(pluginkit -m | grep -c "$APP_ID.FinderSyncExt" || true)
if [ "$DUP" -gt 1 ]; then
  echo "警告:检测到 $DUP 份扩展注册(选举不稳定,菜单可能时有时无):" >&2
  pluginkit -m | grep "$APP_ID.FinderSyncExt" >&2
  echo "请对旧路径执行:pluginkit -r <旧 .app 路径>" >&2
fi
```

- [ ] **Step 5: bash 语法自检**

Run: `bash -n build.sh && echo SYNTAX-OK`
Expected: `SYNTAX-OK`

- [ ] **Step 6: Commit**

```bash
git add build.sh
git commit -m "feat: build.sh 加固——Hardened Runtime 硬校验/版本未变跳过重注册/多拷贝注册检查"
```

---

### Task 9: 全量构建 + 测试 + 注册验证

- [ ] **Step 1: 全量构建**

Run: `./build.sh`
Expected: `完成:.build/app/RightClickKit.app`;无「错误」「警告:检测到 N 份」;签名行显示 Apple Development 证书

- [ ] **Step 2: 验证注册与签名**

Run: `pluginkit -m | grep -c "com.yaowl.RightClickKit.FinderSyncExt"; codesign -dv .build/app/RightClickKit.app 2>&1 | grep -o "runtime"; ls .build/app/.registered-* 2>/dev/null`
Expected: `1`;`runtime`;`.build/app/.registered-v1`

- [ ] **Step 3: 二次构建验证跳过逻辑**

Run: `./build.sh 2>&1 | grep -E "跳过重注册|注册扩展"`
Expected: `==> 扩展已注册且版本未变(v1),跳过重注册`

- [ ] **Step 4: 无 nonce 调用被拒(安全回归)**

Run: `touch ~/Library/Containers/com.yaowl.RightClickKit.FinderSyncExt/Data/tmp/rck-debug.log; open 'rightclickkit://batch-rename?p=%5B%5D'; sleep 2; log show --last 1m --predicate 'process == "RightClickKit"' 2>/dev/null | grep "拒绝" || echo "无拒绝日志(看下一步)"`
Expected: 主 App **不弹任何窗口**;若 log show 不可用,用 `tail -f /tmp/rck-*.log` 或人工确认无窗口。窗口弹出 = 失败。

- [ ] **Step 5: 若需修复则修复并重跑,无需则跳过 commit**

---

### Task 10: DMG 卷实测(外接卷注册生效)

「open 文件夹窗口」仅触发 Finder 观察回调,无合成键入,对用户零干扰;菜单出现与否留给手动清单。

- [ ] **Step 1: 确保调试日志文件存在**

Run: `touch ~/Library/Containers/com.yaowl.RightClickKit.FinderSyncExt/Data/tmp/rck-debug.log`

- [ ] **Step 2: 建挂测试 DMG 并挂载**

Run: `hdiutil create -size 5m -fs APFS -volname rckvol /tmp/rckvol.dmg -ov -quiet && hdiutil attach /tmp/rckvol.dmg -nobrowse -quiet && echo MOUNTED`
Expected: `MOUNTED`(不弹 Finder 窗口)

- [ ] **Step 3: 打开卷内窗口触发观察**

Run: `sleep 2 && open /Volumes/rckvol && sleep 2 && grep -c "beginObserving /Volumes/rckvol" ~/Library/Containers/com.yaowl.RightClickKit.FinderSyncExt/Data/tmp/rck-debug.log`
Expected: 计数 `≥ 1`(=0 则卷注册未生效,回 Task 3 排查)

- [ ] **Step 4: 清理**

Run: `osascript -e 'tell application "Finder" to close (every window whose name is "rckvol")'; hdiutil detach /Volumes/rckvol -quiet; rm /tmp/rckvol.dmg && echo CLEANED`
Expected: `CLEANED`

---

### Task 11: 手动验收清单 + 文档回写

- [ ] **Step 1: 发给用户手动验收清单(逐条执行,只读为主)**

```markdown
# RightClickKit 本轮修复验收清单

1. **外接卷菜单**:挂载一个 U 盘/DMG,进入卷内文件夹右键 → 应出现 RightClickKit 菜单组。
   (注意:该卷在侧边栏的图标会变成 RightClickKit 图标——系统限制的已知代价)
2. **云盘/普通目录 Services**:在 iCloud Drive(或任意文件夹)选中文件右键 → 服务 →
   应有「RightClickKit:批量重命名 / 修复乱码文件名 / 压缩为 ZIP」三项且可用。
3. **Option 跳过确认**:按住 Option 右键 → 菜单项显示「彻底删除(跳过确认)」→ 点击直接删除并发通知;
   不按 Option → 正常弹确认浮层。
4. **nonce 回归**:正常右键 → 批量重命名/修复乱码仍能唤起主 App 窗口(验签发-核销链路)。
5. **版本重启(可选)**:改 App-Info.plist 的 CFBundleVersion → build.sh → Finder 自动重启一次。
```

- [ ] **Step 2: 文档回写**

`README.md` 更新:功能表补「Services 兜底入口」「Option 跳过确认」;已知限制补「云盘目录无一级右键菜单(系统限制,走服务二级菜单)」「观察的外接卷侧边栏图标会变为 App 图标」。

`docs/superpowers/plans/2026-11-09-finder-context-menu.md` 追加修订记录(编号顺延):本轮缺口修复五项 + UX 两项,注明出处(FinderRight ServicesProvider/ExclusiveRename、RClick external-volumes-observation.md)。

- [ ] **Step 3: Commit**

```bash
git add README.md docs/superpowers/plans/2026-11-09-finder-context-menu.md
git commit -m "docs: 记录缺口修复批次(Services 兜底/卷注册/nonce 门禁/签名加固)与已知限制"
```

- [ ] **Step 4: (用户验收通过后)push + 合并 master**

```bash
https_proxy=http://127.0.0.1:7897 git push -u origin feature/finder-context-menu
# ff 合并判据:https_proxy=... git fetch origin master && git merge-base --is-ancestor origin/master HEAD
```

---

## Self-Review 结论

- **覆盖检查**:5 缺口 → uniqueName(T1)/ 外接卷(T3+T10)/ URL 鉴权(T2+T3+T4,含 FDA 路径拒绝)/ 云盘 Services(T6)/ 签名加固(T8);UX 两项 → Option 跳过确认(T5)/ 版本重启 Finder(T7)。审计中「单向子菜单折叠」(无单项子菜单,不适用)与「菜单图标动态颜色」(无彩色主题,不适用)明确排除;「移动/复制到常用目录、打开路径、复制哈希」属新功能候选,不在本批。
- **占位符扫描**:Task 2 Step 2 的过期测试在正文给了终稿;无 TBD/TODO。
- **类型一致性**:`makeURL(nonce:)`、`ActionAuth.issueNonce(at:issuedAt:)`/`consume(_:at:)`、`PathPolicy.rejected(in:)`、`FinderRestarter.restartFinderIfNeeded()`、`ServicesProvider.register()/hadInvocation` 各任务间签名一致;pbxproj ID 1C/1D 先验证再使用。
