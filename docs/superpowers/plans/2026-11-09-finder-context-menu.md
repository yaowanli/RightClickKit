# Finder 右键快捷功能 App 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 复刻「超级右键」核心功能:自用原生 macOS App(主 App + Finder Sync Extension),在 Finder 右键菜单注入 12 个快捷功能。

**Architecture:** 三模块 —— CoreKit(SPM 纯逻辑,可单测)、FinderSyncExt(Finder 扩展,注入菜单+直接执行)、主 App(AppKit 入口 + SwiftUI 设置窗/操作窗,经 `rightclickkit://` URL scheme 唤起)。非沙盒,ad-hoc 自签名。

**Tech Stack:** Swift 5.9、SwiftUI、FinderSync framework、SPM、swiftc(Command Line Tools,**不用 Xcode**)、codesign ad-hoc。

**规格文档:** `docs/superpowers/specs/2026-11-09-mac-finder-context-menu-design.md`

**前置检查(每个 task 开始前若未确认过):**
```bash
xcode-select -p          # 应输出 CLT 路径,如 /Library/Developer/CommandLineTools
swift --version          # 应 ≥ 5.9
```
若无 CLT:`xcode-select --install`(用户手动装,弹出系统对话框)。

> **⚠️ 修订(2026-11-09,执行 Task 1 时发现):** 纯 CLT **不带 XCTest 模块**(`swift test` 不可用,已实证)。经用户确认,单元测试改用**轻量测试执行器**:SPM `executableTarget` + 手写断言 harness,运行 `swift run CoreKitTestRunner`。Task 1-4 的测试代码已全部按此改写;Task 1 Step 5 的 `totalSize` 同时修复了"把目录 st_size 计入总和"的 bug。原 XCTest 版本废弃。

---

## Task 1: CoreKit 包骨架 + PathUtils + FileWalker(TDD)

**Files:**
- Create: `CoreKit/Package.swift`
- Create: `CoreKit/.gitignore`
- Create: `CoreKit/Sources/CoreKit/PathUtils.swift`
- Create: `CoreKit/Sources/CoreKit/FileWalker.swift`
- Test(可执行测试 runner): `CoreKit/Sources/CoreKitTestRunner/Harness.swift` `main.swift` `PathUtilsTests.swift` `FileWalkerTests.swift`

- [ ] **Step 1: 写 SPM 包描述文件与 gitignore**

`CoreKit/Package.swift`(注:纯 CLT 无 XCTest,测试用可执行 runner,见顶部修订说明):
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CoreKit",
    targets: [
        .target(name: "CoreKit"),
        .executableTarget(
            name: "CoreKitTestRunner",
            dependencies: ["CoreKit"]
        ),
    ]
)
```

`CoreKit/.gitignore`:
```
.build/
```

- [ ] **Step 2: 写断言 harness**

`CoreKit/Sources/CoreKitTestRunner/Harness.swift`:
```swift
import Foundation

var _failures = 0
var _currentTest = ""

func test(_ name: String, _ body: () throws -> Void) {
    _currentTest = name
    do {
        try body()
        print("✅ \(name)")
    } catch {
        print("❌ \(name): 抛错 \(error)")
        _failures += 1
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                               file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ \(_currentTest)(\(file):\(line)): 期望 \(expected),实际 \(actual)")
        _failures += 1
    }
}

func expectTrue(_ cond: Bool, _ label: String,
                file: StaticString = #file, line: UInt = #line) {
    if !cond {
        print("❌ \(_currentTest)(\(file):\(line)): \(label)")
        _failures += 1
    }
}

func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

`CoreKit/Sources/CoreKitTestRunner/main.swift`(后续 Task 2-4 各自追加一行 `runXxxTests()`):
```swift
runPathUtilsTests()
runFileWalkerTests()

if _failures > 0 {
    print("FAILED:\(_failures) 个断言失败")
    exit(1)
}
print("ALL TESTS PASSED")
```

- [ ] **Step 3: 写 PathUtils 失败测试**

`CoreKit/Sources/CoreKitTestRunner/PathUtilsTests.swift`:
```swift
import Foundation
import CoreKit

func runPathUtilsTests() {
    test("PathUtils:空闲时返回 base") {
        let dir = try makeTempDir()
        expectEqual(PathUtils.uniqueName(in: dir, base: "未命名文件夹", ext: ""), "未命名文件夹")
        expectEqual(PathUtils.uniqueName(in: dir, base: "未命名文件", ext: "txt"), "未命名文件.txt")
    }
    test("PathUtils:已存在则加空格编号") {
        let dir = try makeTempDir()
        FileManager.default.createFile(atPath: dir.appendingPathComponent("新建文本文档.txt").path, contents: Data())
        expectEqual(PathUtils.uniqueName(in: dir, base: "新建文本文档", ext: "txt"), "新建文本文档 2.txt")
    }
    test("PathUtils:连续已存在时继续递增") {
        let dir = try makeTempDir()
        for i in [1, 2] {
            let name = i == 1 ? "草稿" : "草稿 2"
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
        expectEqual(PathUtils.uniqueName(in: dir, base: "草稿", ext: ""), "草稿 3")
    }
}
```

- [ ] **Step 4: 写 FileWalker 失败测试**

`CoreKit/Sources/CoreKitTestRunner/FileWalkerTests.swift`:
```swift
import Foundation
import CoreKit

func runFileWalkerTests() {
    test("FileWalker:遍历嵌套文件") {
        let (root, _) = try makeTree()
        var visited = Set<String>()
        FileWalker.walk(root) { visited.insert($0.lastPathComponent).inserted }
        expectEqual(visited, Set(["root", "a.txt", "sub", "b.txt"]))
    }
    test("FileWalker:总大小只统计文件字节(不含目录元数据)") {
        let (root, _) = try makeTree()
        expectEqual(FileWalker.totalSize(of: [root]), Int64(9)) // a.txt 5B + b.txt 4B
    }
}

/// root/  a.txt(5B)  sub/b.txt(4B)
private func makeTree() throws -> (URL, [URL]) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("walk-\(UUID().uuidString)")
    let sub = root.appendingPathComponent("sub")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let a = root.appendingPathComponent("a.txt")
    let b = sub.appendingPathComponent("b.txt")
    try Data("hello".utf8).write(to: a)
    try Data("abcd".utf8).write(to: b)
    return (root, [a, b])
}
```

- [ ] **Step 5: 跑测试确认失败**

Run: `cd CoreKit && swift run CoreKitTestRunner 2>&1 | tail -5`
Expected: 编译失败(`cannot find 'PathUtils' in scope` 等)

- [ ] **Step 6: 最小实现**

`CoreKit/Sources/CoreKit/PathUtils.swift`:
```swift
import Foundation

public enum PathUtils {
    /// 在 directory 下返回不冲突的名字:base 或 "base N"+"ext"
    public static func uniqueName(in directory: URL, base: String, ext: String) -> String {
        func candidate(_ i: Int) -> String {
            let stem = i == 1 ? base : "\(base) \(i)"
            return ext.isEmpty ? stem : "\(stem).\(ext)"
        }
        var i = 1
        while i < 10_000,
              FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate(i)).path) {
            i += 1
        }
        return candidate(i)
    }
}
```

`CoreKit/Sources/CoreKit/FileWalker.swift`:
```swift
import Foundation

public enum FileWalker {
    /// 深度优先遍历,对每个节点(含根)调用 visit;visit 返回 false 时不进入子目录
    public static func walk(_ root: URL, visit: (URL) -> Bool) {
        guard visit(root) else { return }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for child in children {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { walk(child, visit: visit) } else { _ = visit(child) }
        }
    }

    /// 递归求和;只统计文件字节,目录自身的 st_size(APFS 上 96B 级别的元数据)不计入
    public static func totalSize(of urls: [URL]) -> Int64 {
        var total: Int64 = 0
        for url in urls {
            walk(url) { f in
                let isDir = (try? f.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if !isDir, let s = try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int64 {
                    total += s
                }
                return true
            }
        }
        return total
    }
}
```

- [ ] **Step 7: 跑测试确认通过**

Run: `cd CoreKit && swift run CoreKitTestRunner`
Expected: 5 个 `✅`,末尾 `ALL TESTS PASSED`,退出码 0

- [ ] **Step 8: 提交**

```bash
git add CoreKit
git commit -m "feat(core): PathUtils 唯一命名与 FileWalker 递归遍历(含轻量测试 runner)"
```

---

## Task 2: MojibakeFixer 乱码检测/修复(TDD)

**Files:**
- Create: `CoreKit/Sources/CoreKit/MojibakeFixer.swift`
- Test: `CoreKit/Sources/CoreKitTestRunner/MojibakeTests.swift`(并在 runner 的 `main.swift` 追加 `runMojibakeTests()`)

原理:磁盘乱码名 = 原始字节被按「中间编码」(Latin-1/CP1252/MacRoman)误读成字符串后又存为 UTF-8。修复 = 用中间编码还原原始字节 → 按目标编码(UTF-8/GB18030/Big5)解码 → 结果含 CJK 即候选。

- [ ] **Step 1: 写失败测试**

`CoreKit/Sources/CoreKitTestRunner/MojibakeTests.swift`:
```swift
import Foundation
import CoreKit

func runMojibakeTests() {
    // "中文" UTF-8 字节(E4 B8 AD E6 96 87)被按 Latin-1 误读后的乱码名
    let utf8Mojibake = "\u{E4}\u{B8}\u{AD}\u{E6}\u{96}\u{87}"
    // "中文" GBK 字节(D6 D0 CE C4)被按 Latin-1 误读后的乱码名
    let gbkMojibake = "\u{D6}\u{D0}\u{CE}\u{C4}"

    test("乱码修复:UTF-8 字节被 Latin-1 误读 → 还原中文") {
        expectEqual(MojibakeFixer.candidates(for: utf8Mojibake).first ?? "", "中文")
    }
    test("乱码修复:GBK 字节被 Latin-1 误读 → 候选含中文") {
        expectTrue(MojibakeFixer.candidates(for: gbkMojibake).contains("中文"), "候选应含 中文")
    }
    test("乱码修复:正常中文名无候选") {
        expectTrue(MojibakeFixer.candidates(for: "报告.txt").isEmpty, "报告.txt 不应有候选")
    }
    test("乱码修复:纯 ASCII 名无候选") {
        expectTrue(MojibakeFixer.candidates(for: "plain.txt").isEmpty, "plain.txt 不应有候选")
    }
    test("乱码修复:含 U+FFFD 判为不可修复") {
        expectTrue(MojibakeFixer.candidates(for: "re\u{FFFD}placed.txt").isEmpty, "含替换字符应返回空")
    }
}
```

同时把 `CoreKit/Sources/CoreKitTestRunner/main.swift` 的顶部调用区改为:
```swift
runPathUtilsTests()
runFileWalkerTests()
runMojibakeTests()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd CoreKit && swift run CoreKitTestRunner 2>&1 | tail -3`
Expected: 编译失败(`cannot find 'MojibakeFixer' in scope`)

- [ ] **Step 3: 实现**

`CoreKit/Sources/CoreKit/MojibakeFixer.swift`:
```swift
import Foundation

public enum MojibakeFixer {
    private static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(UInt32(CFStringEncodings.GB_18030_2000.rawValue))))
    private static let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(UInt32(CFStringEncodings.big5.rawValue))))

    private static let intermediates: [String.Encoding] = [.isoLatin1, .windowsCP1252, .macOSRoman]
    private static let targets: [String.Encoding] = [.utf8, gb18030, big5]

    /// 返回按置信度排序的去重候选;不可修复或无候选时返回 []
    public static func candidates(for name: String) -> [String] {
        guard !name.contains("\u{FFFD}") else { return [] }
        var seen: Set<String> = [name]
        var out: [String] = []
        for inter in intermediates {
            guard let raw = name.data(using: inter, allowLossyConversion: false) else { continue }
            for target in targets {
                guard let fixed = String(data: raw, encoding: target),
                      fixed != name, looksCJK(fixed), seen.insert(fixed).inserted else { continue }
                out.append(fixed)
            }
        }
        return out
    }

    public static func looksCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd CoreKit && swift run CoreKitTestRunner`
Expected: 累计 10 个 `✅`,末尾 `ALL TESTS PASSED`

- [ ] **Step 5: 提交**

```bash
git add CoreKit
git commit -m "feat(core): 乱码文件名检测与修复算法"
```

---

## Task 3: RenameRules 批量重命名(TDD)

**Files:**
- Create: `CoreKit/Sources/CoreKit/RenameRules.swift`
- Test: `CoreKit/Sources/CoreKitTestRunner/RenameRulesTests.swift`(并在 runner 的 `main.swift` 追加 `runRenameTests()`)

- [ ] **Step 1: 写失败测试**

`CoreKit/Sources/CoreKitTestRunner/RenameRulesTests.swift`:
```swift
import Foundation
import CoreKit

func runRenameTests() {
    test("重命名:前缀加在主名前,保留扩展名") {
        let r = RenamePlanner.plan(names: ["a.txt"], rule: .prefix("项目_"))
        expectEqual(r[0].new, "项目_a.txt")
    }
    test("重命名:后缀加在扩展名前") {
        let r = RenamePlanner.plan(names: ["a.txt"], rule: .suffix("_备份"))
        expectEqual(r[0].new, "a_备份.txt")
    }
    test("重命名:序号替换主名,保留扩展名") {
        let r = RenamePlanner.plan(names: ["a.txt", "b.txt"],
                                   rule: .sequence(base: "照片", start: 1, width: 3))
        expectEqual(r[0].new, "照片001.txt")
        expectEqual(r[1].new, "照片002.txt")
    }
    test("重命名:查找替换作用于全名") {
        let r = RenamePlanner.plan(names: ["IMG_1.jpg", "IMG_2.jpg"],
                                   rule: .replace(find: "IMG", replacement: "照片"))
        expectEqual(r.map { $0.new }, ["照片_1.jpg", "照片_2.jpg"])
    }
    test("重命名:无扩展名边界") {
        let r = RenamePlanner.plan(names: ["README"], rule: .prefix("v2_"))
        expectEqual(r[0].new, "v2_README")
    }
    test("冲突检测:发现重复新名") {
        let pairs: [(old: String, new: String)] = [("a", "x"), ("b", "x")]
        expectEqual(RenamePlanner.collisions(in: pairs), ["x"])
    }
}
```

同时把 runner `main.swift` 调用区追加 `runRenameTests()`。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd CoreKit && swift run CoreKitTestRunner 2>&1 | tail -3`
Expected: 编译失败(`cannot find 'RenamePlanner' in scope`)

- [ ] **Step 3: 实现**

`CoreKit/Sources/CoreKit/RenameRules.swift`:
```swift
import Foundation

public enum RenameRule {
    case prefix(String)                                  // 加在主名前
    case suffix(String)                                  // 加在扩展名前
    case sequence(base: String, start: Int, width: Int)  // base+序号,丢弃原名
    case replace(find: String, replacement: String)      // 全名查找替换
}

public enum RenamePlanner {
    public static func plan(names: [String], rule: RenameRule) -> [(old: String, new: String)] {
        names.enumerated().map { i, name in
            let ext = (name as NSString).pathExtension
            let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
            let new: String
            switch rule {
            case .prefix(let p): new = p + stem + (ext.isEmpty ? "" : "." + ext)
            case .suffix(let s): new = stem + s + (ext.isEmpty ? "" : "." + ext)
            case .sequence(let base, let start, let width):
                let num = String(start + i, radix: 10)
                let padded = String(repeating: "0", count: max(0, width - num.count)) + num
                new = base + padded + (ext.isEmpty ? "" : "." + ext)
            case .replace(let find, let rep): new = name.replacingOccurrences(of: find, with: rep)
            }
            return (name, new)
        }
    }

    /// 返回批次内出现 ≥2 次的新名字
    public static func collisions(in pairs: [(old: String, new: String)]) -> [String] {
        var counts: [String: Int] = [:]
        for p in pairs { counts[p.new, default: 0] += 1 }
        return counts.filter { $0.value > 1 }.map { $0.key }.sorted()
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd CoreKit && swift run CoreKitTestRunner`
Expected: 累计 16 个 `✅`,末尾 `ALL TESTS PASSED`

- [ ] **Step 5: 提交**

```bash
git add CoreKit
git commit -m "feat(core): 批量重命名规则与冲突检测"
```

---

## Task 4: ActionPayload(URL 传参)+ FeatureStore(功能开关)+ FileOps(TDD)

**Files:**
- Create: `CoreKit/Sources/CoreKit/ActionPayload.swift`
- Create: `CoreKit/Sources/CoreKit/FeatureStore.swift`
- Create: `CoreKit/Sources/CoreKit/FileOps.swift`
- Test: `CoreKit/Sources/CoreKitTestRunner/ActionPayloadTests.swift` `FileOpsTests.swift`(并在 runner 的 `main.swift` 追加 `runActionPayloadTests()` 与 `runFileOpsTests()`)

说明:规格定的 `OpenConfiguration.arguments` 在主 App **已运行时会被忽略**,故传参改为 URL query(`rightclickkit://<action>?p=<JSON 百分号编码>`),冷启动/热启动都可靠,仍不落盘。

- [ ] **Step 1: 写失败测试**

`CoreKit/Sources/CoreKitTestRunner/ActionPayloadTests.swift`:
```swift
import Foundation
import CoreKit

func runActionPayloadTests() {
    test("ActionPayload:URL 往返保留 action 与路径") {
        let p = ActionPayload(action: "batch-rename",
                              paths: ["/tmp/中 文/a.txt", "/tmp/b(1).txt"])
        let url = p.makeURL()
        expectTrue(url != nil, "makeURL 不应返回 nil")
        guard let url else { return }
        expectEqual(url.scheme, "rightclickkit")
        let back = ActionPayload.parse(url)
        expectTrue(back != nil, "parse 不应返回 nil")
        guard let back else { return }
        expectEqual(back, p)
    }
    test("ActionPayload:拒绝外来 URL") {
        expectTrue(ActionPayload.parse(URL(string: "https://example.com/p=1")!) == nil,
                   "https URL 不应被解析")
    }
}
```

`CoreKit/Sources/CoreKitTestRunner/FileOpsTests.swift`:
```swift
import Foundation
import CoreKit

func runFileOpsTests() {
    test("FileOps:移动冲突时自动改名为 x 2.ext") {
        let dir = try makeTempDir()
        let a = dir.appendingPathComponent("x.txt")
        try Data("1".utf8).write(to: a)
        let dst = dir.appendingPathComponent("x.txt")
        try Data("2".utf8).write(to: dst)
        let final = try FileOps.moveWithoutClobber(from: a, to: dst)
        expectEqual(final.lastPathComponent, "x 2.txt")
        expectEqual(try String(contentsOf: final, encoding: .utf8), "1")
        expectEqual(try String(contentsOf: dst, encoding: .utf8), "2")
    }
    test("FileOps:授权限解除锁定并加 u+w") {
        let dir = try makeTempDir()
        let f = dir.appendingPathComponent("y.txt")
        try Data("y".utf8).write(to: f)
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o444, .immutable: true], ofItemAtPath: f.path)
        FileOps.makeWritable(f)
        let attrs = fm.attributesOfItem(atPath: f.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0
        expectEqual(perms & 0o200, Int16(0o200))
        expectEqual(attrs[.immutable] as? Bool, false)
    }
}
```

同时把 runner `main.swift` 调用区改为(累计):
```swift
runPathUtilsTests()
runFileWalkerTests()
runMojibakeTests()
runRenameTests()
runActionPayloadTests()
runFileOpsTests()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd CoreKit && swift run CoreKitTestRunner 2>&1 | tail -3`
Expected: 编译失败(`cannot find 'ActionPayload'/'FileOps' in scope`)

- [ ] **Step 3: 实现**

`CoreKit/Sources/CoreKit/ActionPayload.swift`:
```swift
import Foundation

public struct ActionPayload: Equatable {
    public let action: String
    public let paths: [String]

    public init(action: String, paths: [String]) {
        self.action = action
        self.paths = paths
    }

    /// rightclickkit://<action>?p=<JSON 数组,系统自动百分号编码>
    public func makeURL() -> URL? {
        guard let json = try? JSONEncoder().encode(paths),
              let str = String(data: json, encoding: .utf8) else { return nil }
        var comps = URLComponents()
        comps.scheme = "rightclickkit"
        comps.host = action
        comps.queryItems = [URLQueryItem(name: "p", value: str)]
        return comps.url
    }

    public static func parse(_ url: URL) -> ActionPayload? {
        guard url.scheme?.lowercased() == "rightclickkit", !url.host!.isEmpty,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let v = comps.queryItems?.first(where: { $0.name == "p" })?.value,
              let data = v.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return ActionPayload(action: url.host ?? "", paths: paths)
    }
}
```

`CoreKit/Sources/CoreKit/FeatureStore.swift`(无测试,薄封装 UserDefaults):
```swift
import Foundation

public enum Feature: String, CaseIterable {
    case newFile = "new-file"
    case newFolder = "new-folder"
    case folderFromName = "folder-from-name"
    case cut = "cut"
    case copyPath = "copy-path"
    case copyName = "copy-name"
    case compressZip = "compress-zip"
    case compress7z = "compress-7z"
    case grantWrite = "grant-write"
    case deleteForever = "delete-forever"
    case batchRename = "batch-rename"
    case fixMojibake = "fix-mojibake"

    public var title: String {
        switch self {
        case .newFile: return "新建文件"
        case .newFolder: return "新建文件夹"
        case .folderFromName: return "使用文件名新建文件夹"
        case .cut: return "剪切"
        case .copyPath: return "拷贝路径"
        case .copyName: return "拷贝文件(夹)名称"
        case .compressZip: return "压缩为 zip"
        case .compress7z: return "压缩为 7z"
        case .grantWrite: return "授予写入权限"
        case .deleteForever: return "彻底删除"
        case .batchRename: return "批量重命名"
        case .fixMojibake: return "修复乱码文件名"
        }
    }
}

public enum FeatureStore {
    static let defaults = UserDefaults(suiteName: "com.yaowl.RightClickKit")
        ?? UserDefaults.standard

    public static func isEnabled(_ f: Feature) -> Bool {
        defaults.object(forKey: f.rawValue) as? Bool ?? true
    }
    public static func setEnabled(_ f: Feature, _ on: Bool) {
        defaults.set(on, forKey: f.rawValue)
    }
}
```

`CoreKit/Sources/CoreKit/FileOps.swift`:
```swift
import Foundation

public enum FileOps {
    /// 移动;目标已存在时自动命名 "x 2.ext"、"x 3.ext"…
    @discardableResult
    public static func moveWithoutClobber(from: URL, to: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: to.path) else {
            try fm.moveItem(at: from, to: to)
            return to
        }
        let dir = to.deletingLastPathComponent()
        let ext = to.pathExtension
        let base = ext.isEmpty ? to.lastPathComponent : String(to.lastPathComponent.dropLast(ext.count + 1))
        var i = 2
        var candidate = to
        while fm.fileExists(atPath: candidate.path) {
            let stem = i == 1 ? base : "\(base) \(i)"
            candidate = dir.appendingPathComponent(ext.isEmpty ? stem : "\(stem).\(ext)")
            i += 1
        }
        try fm.moveItem(at: from, to: candidate)
        return candidate
    }

    /// 解除锁定(UF_IMMUTABLE)并给属主加写权限(递归)
    public static func makeWritable(_ url: URL) {
        let fm = FileManager.default
        FileWalker.walk(url) { f in
            try? fm.setAttributes([.immutable: false], ofItemAtPath: f.path)
            if let mode = (fm.attributesOfItem(atPath: f.path)[.posixPermissions] as? NSNumber)?.int16Value {
                try? fm.setAttributes([.posixPermissions: NSNumber(value: mode | 0o200)], ofItemAtPath: f.path)
            }
            return true
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd CoreKit && swift run CoreKitTestRunner`
Expected: 累计 20 个 `✅`,末尾 `ALL TESTS PASSED`

- [ ] **Step 5: 提交**

```bash
git add CoreKit
git commit -m "feat(core): URL 传参、功能开关、安全移动与授权限"
```

---

## Task 5: Office 模板生成脚本(make_templates.sh)

**Files:**
- Create: `scripts/make_templates.sh`
- Create(脚本产物,进 git): `Resources/Templates/template.docx` `template.xlsx` `template.pptx`

- [ ] **Step 1: 写生成脚本**

`scripts/make_templates.sh`:
```bash
#!/bin/bash
# 生成最小合法的 docx/xlsx/pptx 空模板(纯 XML + zip,无需 Xcode)
set -euo pipefail
OUT="$(cd "$(dirname "$0")/.." && pwd)/Resources/Templates"
mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

make_docx() {
  local d="$WORK/docx"; mkdir -p "$d/_rels" "$d/word/_rels"
  cat > "$d/[Content_Types].xml" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
X
  cat > "$d/_rels/.rels" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
X
  cat > "$d/word/document.xml" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p/></w:body></w:document>
X
  (cd "$d" && zip -q -X "$OUT/template.docx" "[Content_Types].xml" "_rels/.rels" "word/document.xml")
}

make_xlsx() {
  local d="$WORK/xlsx"; mkdir -p "$d/_rels" "$d/xl/_rels" "$d/xl/worksheets"
  cat > "$d/[Content_Types].xml" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
X
  cat > "$d/_rels/.rels" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
X
  cat > "$d/xl/_rels/workbook.xml.rels" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
X
  cat > "$d/xl/workbook.xml" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<x:workbook xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><x:sheets><x:sheet name="Sheet1" sheetId="1" r:id="rId1"/></x:sheets></x:workbook>
X
  cat > "$d/xl/worksheets/sheet1.xml" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><x:sheetData/></x:worksheet>
X
  (cd "$d" && zip -q -X "$OUT/template.xlsx" "[Content_Types].xml" "_rels/.rels" "xl/_rels/workbook.xml.rels" "xl/workbook.xml" "xl/worksheets/sheet1.xml")
}

make_pptx() {
  local d="$WORK/pptx"
  mkdir -p "$d/_rels" "$d/ppt/_rels" "$d/ppt/slides/_rels" "$d/ppt/slideLayouts/_rels" "$d/ppt/slideMasters/_rels" "$d/ppt/theme"
  cat > "$d/[Content_Types].xml" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/></Types>
X
  cat > "$d/_rels/.rels" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>
X
  cat > "$d/ppt/_rels/presentation.xml.rels" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/></Relationships>
X
  cat > "$d/ppt/presentation.xml" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst><p:sldId id="256" r:id="rId2"/></p:sldIdLst><p:sldSz cx="9144000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>
X
  cat > "$d/ppt/slides/slide1.xml" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld><p:clrMapOvr><a:overrideClrMapping bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/></p:clrMapOvr></p:sld>
X
  cat > "$d/ppt/slides/_rels/slide1.xml.rels" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>
X
  cat > "$d/ppt/slideLayouts/slideLayout1.xml" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank"><p:cSld name="空白"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>
X
  cat > "$d/ppt/slideLayouts/_rels/slideLayout1.xml.rels" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>
X
  cat > "$d/ppt/slideMasters/slideMaster1.xml" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/></p:sldMaster>
X
  cat > "$d/ppt/slideMasters/_rels/slideMaster1.xml.rels" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/></Relationships>
X
  cat > "$d/ppt/theme/theme1.xml" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office"><a:themeElements><a:clrScheme name="Office"><a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="44546A"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2><a:accent1><a:srgbClr val="4472C4"/></a:accent1><a:accent2><a:srgbClr val="ED7D31"/></a:accent2><a:accent3><a:srgbClr val="A5A5A5"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4><a:accent5><a:srgbClr val="5B9BD5"/></a:accent5><a:accent6><a:srgbClr val="70AD47"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme><a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme><a:fmtScheme name="Office"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>
X
  (cd "$d" && zip -q -r -X "$OUT/template.pptx" .)
}

make_docx
make_xlsx
make_pptx
ls -la "$OUT"
```

- [ ] **Step 2: 运行并验证产物**

Run: `chmod +x scripts/make_templates.sh && ./scripts/make_templates.sh && zipinfo Resources/Templates/template.docx | head -5 && zipinfo Resources/Templates/template.pptx | head -12`
Expected: 三个文件生成;docx 含 `[Content_Types].xml`、`word/document.xml`;pptx 含 presentation/slides/theme 各部件

- [ ] **Step 3: 人工可打开性验证(有 Office 则验,无则跳过并在提交信息注明)**

双击 `Resources/Templates/template.docx`(Pages/Word/WPS 任一可打开即通过)。

- [ ] **Step 4: 提交**

```bash
git add scripts Resources
git commit -m "feat(templates): 最小合法 docx/xlsx/pptx 空模板生成脚本"
```

---

## Task 6: 主 App 骨架(AppKit 入口 + 设置窗 + URL 分发)

**Files:**
- Create: `App/main.swift`
- Create: `App/AppDelegate.swift`
- Create: `App/SettingsWindow.swift`
- Create: `App/SettingsView.swift`
- Create: `App/ActionWindow.swift`
- Create: `App/ActionRouter.swift`
- Create: `App/ExtStatus.swift`
- Create: `Resources/App-Info.plist`

- [ ] **Step 1: 程序入口(纯 AppKit,不用 storyboard/@main,便于 swiftc)**

`App/main.swift`:
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
```

`App/AppDelegate.swift`:
```swift
import AppKit
import CoreKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        SettingsWindow.shared.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // 扩展经 rightclickkit://<action>?p=... 唤起(冷启动/热启动均送达)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let payload = ActionPayload.parse(url) else { continue }
            ActionRouter.handle(payload)
        }
    }
}
```

- [ ] **Step 2: 设置窗容器 + 操作窗容器**

`App/SettingsWindow.swift`:
```swift
import AppKit
import SwiftUI

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "RightClickKit"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

`App/ActionWindow.swift`:
```swift
import AppKit
import SwiftUI

/// 操作类窗口(彻底删除/批量重命名/乱码修复)的宿主,持有引用防释放
enum ActionWindow {
    private static var alive: [ObjectIdentifier: NSWindow] = [:]

    static func show(title: String, width: CGFloat, height: CGFloat,
                     @ViewBuilder content: () -> some View) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: content())
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        alive[ObjectIdentifier(w)] = w
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: w, queue: .main
        ) { [weak w] _ in
            if let w { alive.removeValue(forKey: ObjectIdentifier(w)) }
        }
        return w
    }
}
```

`App/ActionRouter.swift`:
```swift
import Foundation
import CoreKit

enum ActionRouter {
    static func handle(_ payload: ActionPayload) {
        let urls = payload.paths.map { URL(fileURLWithPath: $0) }
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
```
注:`DeleteForeverView/BatchRenameView/MojibakeFixView` 在 Task 8-10 实现;本任务先建占位文件(见 Step 4)使代码可编译。

- [ ] **Step 3: 扩展启用状态检测**

`App/ExtStatus.swift`:
```swift
import Foundation

enum ExtStatus: Equatable {
    case enabled        // pluginkit 输出 "+" 前缀
    case disabled       // "-" 前缀
    case notRegistered  // 无输出(未安装/未注册)

    static func detect(bundleID: String = "com.yaowl.RightClickKit.FinderSyncExt") -> ExtStatus {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        p.arguments = ["-m", "-i", bundleID]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in out.split(separator: "\n") {
            if line.hasPrefix("+") { return .enabled }
            if line.hasPrefix("-") { return .disabled }
            if line.hasPrefix("!") { return .disabled }
        }
        return .notRegistered
    }
}
```

- [ ] **Step 4: 设置窗 UI(三个 tab)+ 操作窗占位**

`App/SettingsView.swift`:
```swift
import SwiftUI
import CoreKit

struct SettingsView: View {
    var body: some View {
        TabView {
            ExtensionTab()
                .tabItem { Label("扩展", systemImage: "puzzlepiece.extension") }
            FeaturesTab()
                .tabItem { Label("功能", systemImage: "switch.2") }
            TemplatesTab()
                .tabItem { Label("模板", systemImage: "doc") }
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }.padding(12).frame(width: 560, height: 540)
    }
}

struct ExtensionTab: View {
    @State private var status: ExtStatus = ExtStatus.detect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(statusText, systemImage: statusIcon)
                .font(.title3).foregroundColor(statusColor)
            Text("首次使用:在 系统设置 → 登录项与扩展 → 扩展 → Finder 扩展 中勾选 RightClickKit。")
                .foregroundColor(.secondary)
            HStack {
                Button("刷新状态") { status = ExtStatus.detect() }
                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Spacer()
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        switch status {
        case .enabled: return "扩展已启用"
        case .disabled: return "扩展已安装但未启用"
        case .notRegistered: return "扩展未注册,请先运行构建脚本"
        }
    }
    private var statusIcon: String {
        switch status {
        case .enabled: return "checkmark.circle.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }
    private var statusColor: Color {
        status == .enabled ? .green : .orange
    }
}

struct FeaturesTab: View {
    @State private var flags: [Feature: Bool] = Dictionary(
        uniqueKeysWithValues: Feature.allCases.map { ($0, FeatureStore.isEnabled($0)) })

    var body: some View {
        List(Feature.allCases, id: \.rawValue) { f in
            Toggle(f.title, isOn: Binding(
                get: { flags[f] ?? true },
                set: { flags[f] = $0; FeatureStore.setEnabled(f, $0) }))
        }.padding(8)
    }
}

struct TemplatesTab: View {
    private let templates: [(String, String)] = [
        ("TXT 文本", "txt"), ("Markdown", "md"), ("Word 文档", "docx"),
        ("Excel 表格", "xlsx"), ("PPT 演示", "pptx"),
    ]
    var body: some View {
        List(templates, id: \.1) { t in
            HStack { Image(systemName: "doc"); Text(t.0); Spacer(); Text(".\(t.1)").foregroundColor(.secondary) }
        }.padding(8)
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("RightClickKit").font(.title2)
            Text("版本 0.1.0 · 自用 Finder 右键增强").foregroundColor(.secondary)
            Button("退出") { NSApp.terminate(nil) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

操作窗占位(本任务编译所需,Task 8-10 各自替换实现):
`App/DeleteForeverView.swift`:
```swift
import SwiftUI
import AppKit

struct DeleteForeverView {
    static func show(urls: [URL]) {
        ActionWindow.show(title: "彻底删除", width: 420, height: 200) {
            Text("待实现").padding()
        }
    }
}
```
`App/BatchRenameView.swift`:
```swift
import SwiftUI
import AppKit

struct BatchRenameView {
    static func show(urls: [URL]) {
        ActionWindow.show(title: "批量重命名", width: 420, height: 200) {
            Text("待实现").padding()
        }
    }
}
```
`App/MojibakeFixView.swift`:
```swift
import SwiftUI
import AppKit

struct MojibakeFixView {
    static func show(urls: [URL]) {
        ActionWindow.show(title: "修复乱码文件名", width: 420, height: 200) {
            Text("待实现").padding()
        }
    }
}
```

`Resources/App-Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>RightClickKit</string>
    <key>CFBundleDisplayName</key><string>RightClickKit</string>
    <key>CFBundleIdentifier</key><string>com.yaowl.RightClickKit</string>
    <key>CFBundleExecutable</key><string>RightClickKit</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.yaowl.RightClickKit.url</string>
            <key>CFBundleURLSchemes</key>
            <array><string>rightclickkit</string></array>
        </dict>
    </array>
</dict>
</plist>
```

- [ ] **Step 5: 编译验证(主 App 二进制)**

Run:
```bash
cd CoreKit && swift build -c release && cd ..
mkdir -p .build/app
swiftc -O -I CoreKit/.build/release/Modules -L CoreKit/.build/release -lCoreKit \
  App/*.swift -o .build/app/RightClickKit
```
Expected: 无报错,生成二进制

- [ ] **Step 6: 提交**

```bash
git add App Resources
git commit -m "feat(app): 主 App 骨架、设置窗与 URL 动作分发"
```

---

## Task 7: Finder 扩展骨架 + build.sh(首个可安装集成里程碑)

**Files:**
- Create: `FinderSyncExt/main.swift`
- Create: `FinderSyncExt/FinderSync.swift`
- Create: `Resources/Ext-Info.plist`
- Create: `build.sh`

本任务只挂一个「拷贝路径」菜单项,打通「构建→签名→注册→Finder 显示」全链路;其余菜单项 Task 8-9 补齐。

- [ ] **Step 1: 扩展入口与菜单**

`FinderSyncExt/main.swift`(appex 程序入口,顶层代码):
```swift
import FinderSync

FinderSyncExtensionMain.principalClass = FinderSync.self
```

`FinderSyncExt/FinderSync.swift`:
```swift
import FinderSync
import AppKit
import CoreKit

class FinderSync: FNSyncExtension {
    private let controller = FIFinderSyncController.default()

    override init() {
        super.init()
        // 监听全盘,Finder 所有文件夹的右键菜单都出现本扩展
        controller.directoryURLs.insert(URL(fileURLWithPath: "/"))
    }

    override func menu(for menuKind: FNSyncMenuKind) -> NSMenu {
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
```

`Resources/Ext-Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FinderSyncExt</string>
    <key>CFBundleDisplayName</key><string>RightClickKit Finder 扩展</string>
    <key>CFBundleIdentifier</key><string>com.yaowl.RightClickKit.FinderSyncExt</string>
    <key>CFBundleExecutable</key><string>FinderSyncExt</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.FinderSync</string>
        <key>NSExtensionPrincipalClass</key>
        <string>FinderSyncExt.FinderSync</string>
    </dict>
</dict>
</plist>
```

- [ ] **Step 2: build.sh**

`build.sh`:
```bash
#!/bin/bash
# 一键构建:CoreKit(release)→ 主 App 二进制 → 扩展二进制 → 组装 bundle → ad-hoc 签名 → 注册
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_ID="com.yaowl.RightClickKit"
BUILD="$ROOT/.build/app"
APP="$BUILD/RightClickKit.app"

command -v swiftc >/dev/null || { echo "错误:未找到 swiftc,请先 xcode-select --install"; exit 1; }

echo "==> 编译 CoreKit"
(cd "$ROOT/CoreKit" && swift build -c release)

echo "==> 组装 bundle 目录"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/MacOS"
mkdir -p "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/Resources"

echo "==> 编译主 App"
swiftc -O \
  -I "$ROOT/CoreKit/.build/release/Modules" \
  -L "$ROOT/CoreKit/.build/release" -lCoreKit \
  "$ROOT"/App/*.swift \
  -o "$APP/Contents/MacOS/RightClickKit"

echo "==> 编译 Finder 扩展"
swiftc -O -module-name FinderSyncExt \
  -I "$ROOT/CoreKit/.build/release/Modules" \
  -L "$ROOT/CoreKit/.build/release" -lCoreKit \
  "$ROOT"/FinderSyncExt/*.swift \
  -o "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/MacOS/FinderSyncExt"

echo "==> 写入 plist 与模板资源"
cp "$ROOT/Resources/App-Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Ext-Info.plist" "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/Info.plist"
cp "$ROOT"/Resources/Templates/template.* \
   "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/Resources/"

echo "==> ad-hoc 签名(先内后外)"
codesign --force --sign - "$APP/Contents/PlugIns/FinderSyncExt.appex"
codesign --force --sign - "$APP"

echo "==> 注册扩展"
pluginkit -a "$APP" || echo "(pluginkit -a 非致命失败,可忽略,系统会自行发现)"

codesign -dv "$APP" 2>&1 | head -2
echo "完成:$APP"
echo "首次使用:右键 $APP → 打开;然后到 系统设置 → 登录项与扩展 → 扩展 → Finder 扩展 勾选 RightClickKit。"
```

- [ ] **Step 3: 构建并自检**

Run: `chmod +x build.sh && ./build.sh`
Expected: 末尾输出 `完成:…/RightClickKit.app` 且 `Identifier=com.yaowl.RightClickKit`

Run: `pluginkit -m -i com.yaowl.RightClickKit.FinderSyncExt`
Expected: 输出一行(前缀 `-` 或 `+`),证明扩展已被系统发现

Run: `open .build/app/RightClickKit.app`
Expected: 设置窗口弹出(需先右键 → 打开绕 Gatekeeper,或在弹窗中选「打开」)

- [ ] **Step 4: 提交**

```bash
git add FinderSyncExt Resources build.sh
git commit -m "feat(ext): Finder 扩展骨架与一键构建脚本(ad-hoc 签名)"
```

> 提示:从此刻起扩展已可见但只有「拷贝路径」;若用户在系统设置启用了扩展,可立即在 Finder 实测。

---

## Task 8: 扩展功能批次一(新建文件/新建文件夹/拷贝名称)

**Files:**
- Modify: `FinderSyncExt/FinderSync.swift`

- [ ] **Step 1: menu(for:) 补齐菜单项(批次一)**

在 `menu(for:)` 中、`copyPath` 之前加入(保持 add 复用):

```swift
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
```

- [ ] **Step 2: 实现三个 action(加在 FinderSync 类内)**

```swift
    @objc private func newTemplateFile(_ sender: NSMenuItem) {
        guard let ext = sender.representedObject as? String,
              let dir = controller.targetURL() else { return }
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
        guard let dir = controller.targetURL() else { return }
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
```

- [ ] **Step 3: 构建**

Run: `./build.sh`
Expected: 构建成功无报错

- [ ] **Step 4: 手动验证(需扩展已启用)**

在 Finder 任一文件夹右键:菜单出现 4 项;新建文件子菜单 5 项逐一创建成功;使用文件名新建文件夹行为正确。
(子 agent 无法操作 Finder UI 时:标记此项为「待用户验收」,继续后续任务。)

- [ ] **Step 5: 提交**

```bash
git add FinderSyncExt
git commit -m "feat(ext): 新建文件/新建文件夹/使用文件名新建文件夹/拷贝名称"
```

---

## Task 9: 扩展功能批次二(剪切/压缩/授权限/唤起主 App 三项)

**Files:**
- Modify: `FinderSyncExt/FinderSync.swift`

- [ ] **Step 1: menu(for:) 补齐剩余项(按此顺序)**

```swift
        add(to: menu, "剪切", symbol: "scissors", feature: .cut, action: #selector(cutFiles(_:)))
        add(to: menu, "压缩为 zip", symbol: "doc.zipper", feature: .compressZip, action: #selector(compressZip(_:)))
        add(to: menu, "压缩为 7z", symbol: "archivebox", feature: .compress7z, action: #selector(compress7z(_:)))
        add(to: menu, "授予写入权限", symbol: "lock.open", feature: .grantWrite, action: #selector(grantWrite(_:)))
        add(to: menu, "彻底删除", symbol: "trash", feature: .deleteForever, action: #selector(deleteForever(_:)))
        add(to: menu, "批量重命名", symbol: "character.textbox", feature: .batchRename, action: #selector(batchRename(_:)))
        add(to: menu, "修复乱码文件名", symbol: "wand.and.stars", feature: .fixMojibake, action: #selector(fixMojibake(_:)))
```

- [ ] **Step 2: 实现剪切/压缩/授权限(类内新增)**

```swift
    @objc private func cutFiles(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([NSPasteboard.PasteboardType("NSFilenamesPboardType"),
                         NSPasteboard.PasteboardType("com.apple.finder.cut-for-board")], owner: nil)
        pb.setPropertyList(urls.map { $0.path },
                           forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        pb.setString("1", forType: NSPasteboard.PasteboardType("com.apple.finder.cut-for-board"))
        // 验证点:Finder 中 Cmd+V 应回退为「移动」。若失效,降级方案:notify("已记录,请在 App 内粘贴") — 先按此实现验证
    }

    @objc private func compressZip(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), let first = urls.first else { return }
        let dir = first.deletingLastPathComponent()
        let base = first.deletingPathExtension().lastPathComponent
        let out = dir.appendingPathComponent(PathUtils.uniqueName(in: dir, base: base, ext: "zip"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent"] + urls.map { $0.path } + [out.path]
        do {
            try p.run(); p.waitUntilExit()
            if p.terminationStatus != 0 { notify("zip 压缩失败(退出码 \(p.terminationStatus))"); return }
        } catch { notify("zip 压缩失败:\(error.localizedDescription)"); return }
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
        let out = dir.appendingPathComponent(PathUtils.uniqueName(in: dir, base: baseName(first), ext: "7z"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: seven)
        p.arguments = ["a", "-bd", out.path] + urls.map { $0.lastPathComponent }
        p.currentDirectoryPath = dir.path
        do {
            try p.run(); p.waitUntilExit()
            if p.terminationStatus != 0 { notify("7z 压缩失败(退出码 \(p.terminationStatus))"); return }
        } catch { notify("7z 压缩失败:\(error.localizedDescription)"); return }
        NSWorkspace.shared.activateFileViewerSelecting([out])
    }

    @objc private func grantWrite(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return }
        for url in urls { FileOps.makeWritable(url) }
        notify("已授予写入权限(\(urls.count) 项)")
    }

    private func baseName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
```

- [ ] **Step 3: 实现唤起主 App 的三项(类内新增)**

```swift
    private func openInApp(action: String) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return }
        guard let url = ActionPayload(action: action, paths: urls.map { $0.path }).makeURL() else {
            notify("无法构造动作 URL"); return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func deleteForever(_ sender: NSMenuItem) { openInApp(action: "delete-forever") }
    @objc private func batchRename(_ sender: NSMenuItem) { openInApp(action: "batch-rename") }
    @objc private func fixMojibake(_ sender: NSMenuItem) { openInApp(action: "fix-mojibake") }
```

- [ ] **Step 4: 构建 + URL 链路冒烟**

Run: `./build.sh`
Expected: 构建成功

Run: `open "rightclickkit://action/batch-rename?p=%5B%22%2Ftmp%22%5D"`
Expected: 主 App 前台弹出「批量重命名(待实现)」占位窗(URL host 是 `action`、path 第一段是动作名 —— 若 parse 不匹配,以 CoreKit 测试为准修正构造端)

注意:上一步构造的 URL host=`action`,而 Task 4 的 `makeURL()` host=动作名(`rightclickkit://batch-rename?p=...`)。冒烟命令相应改为:
Run: `open "rightclickkit://batch-rename?p=%5B%22%2Ftmp%22%5D"`

Expected: 占位窗弹出。

- [ ] **Step 5: 提交**

```bash
git add FinderSyncExt
git commit -m "feat(ext): 剪切/压缩zip/7z/授权限/唤起主 App 三动作"
```

---

## Task 10: 主 App · 彻底删除窗(双确认)

**Files:**
- Modify: `App/DeleteForeverView.swift`(替换占位)

- [ ] **Step 1: 完整实现**

`App/DeleteForeverView.swift`:
```swift
import SwiftUI
import AppKit
import CoreKit

struct DeleteForeverView: View {
    let urls: [URL]
    @State private var totalSize: Int64?
    @State private var acknowledged = false
    @State private var working = false
    @State private var error: String?
    @State private var done = false

    static func show(urls: [URL]) {
        ActionWindow.show(title: "彻底删除", width: 440, height: 260) {
            DeleteForeverView(urls: urls)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("彻底删除 \(urls.count) 个项目", systemImage: "trash.fill")
                .font(.headline).foregroundColor(.red)
            Text("路径:\(pathsSummary)")
                .font(.caption).foregroundColor(.secondary).lineLimit(3)
            Text(sizeText).foregroundColor(.secondary)
            Toggle("我了解:此操作不进废纸篓,不可恢复", isOn: $acknowledged)
                .disabled(working)
            if let error { Text(error).foregroundColor(.red).font(.caption) }
            if done { Text("已删除。").foregroundColor(.green) }
            HStack {
                Spacer()
                Button("取消") { closeWindow() }.keyboardShortcut(.cancelAction).disabled(working)
                Button(working ? "删除中…" : "彻底删除") { delete() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!acknowledged || working)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 440, height: 260)
        .task { totalSize = await Task.detached { FileWalker.totalSize(of: urls) }.value }
    }

    private var pathsSummary: String {
        urls.prefix(3).map { $0.lastPathComponent }.joined(separator: "、")
            + (urls.count > 3 ? " 等" : "")
    }
    private var sizeText: String {
        guard let s = totalSize else { return "正在计算大小…" }
        return ByteCountFormatter.string(fromByteCount: s, countStyle: .file)
    }

    private func delete() {
        working = true; error = nil
        let targets = urls
        Task.detached {
            var firstError: String?
            for t in targets {
                do { try FileManager.default.removeItem(at: t) }
                catch { firstError = firstError ?? error.localizedDescription }
            }
            await MainActor.run {
                working = false
                if let e = firstError { error = e } else { done = true }
            }
        }
    }
    private func closeWindow() { NSApp.keyWindow?.close() }
}
```

- [ ] **Step 2: 构建 + 逻辑验证**

Run: `./build.sh && open "rightclickkit://delete-forever?p=%5B%22%2Ftmp%2Frc-test%2Fa.txt%22%5D"`
Expected: 窗口弹出;「彻底删除」按钮在勾选确认前禁用;创建 `mkdir -p /tmp/rc-test && echo hi > /tmp/rc-test/a.txt` 后实测删除成功

- [ ] **Step 3: 提交**

```bash
git add App
git commit -m "feat(app): 彻底删除窗(双确认+大小统计)"
```

---

## Task 11: 主 App · 批量重命名窗

**Files:**
- Modify: `App/BatchRenameView.swift`(替换占位)

- [ ] **Step 1: 完整实现**

`App/BatchRenameView.swift`:
```swift
import SwiftUI
import AppKit
import CoreKit

struct BatchRenameView: View {
    let urls: [URL]
    @State private var ruleIndex = 0
    @State private var prefix = ""
    @State private var suffix = ""
    @State private var seqBase = "文件"
    @State private var seqStart = "1"
    @State private var find = ""
    @State private var replaceWith = ""
    @State private var working = false
    @State private var result: String?

    static func show(urls: [URL]) {
        ActionWindow.show(title: "批量重命名", width: 560, height: 480) {
            BatchRenameView(urls: urls)
        }
    }

    private var names: [String] { urls.map { $0.lastPathComponent } }

    private var rule: RenameRule {
        switch ruleIndex {
        case 0: return .prefix(prefix)
        case 1: return .suffix(suffix)
        case 2: return .sequence(base: seqBase, start: Int(seqStart) ?? 1, width: 3)
        default: return .replace(find: find, replacement: replaceWith)
        }
    }

    private var planned: [(old: String, new: String)] {
        RenamePlanner.plan(names: names, rule: rule)
    }
    private var collisions: [String] { RenamePlanner.collisions(in: planned) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("规则", selection: $ruleIndex) {
                Text("加前缀").tag(0); Text("加后缀").tag(1)
                Text("序号").tag(2); Text("查找替换").tag(3)
            }.pickerStyle(.segmented)

            switch ruleIndex {
            case 0: TextField("前缀", text: $prefix)
            case 1: TextField("后缀", text: $suffix)
            case 2: HStack { TextField("基础名", text: $seqBase)
                            TextField("起始序号", text: $seqStart).frame(width: 80) }
            default: HStack { TextField("查找", text: $find)
                             TextField("替换为", text: $replaceWith) }
            }

            if !collisions.isEmpty {
                Label("重名冲突:\(collisions.joined(separator: "、"))", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange).font(.caption)
            }

            List(planned, id: \.old) { p in
                HStack {
                    Text(p.old).lineLimit(1)
                    Image(systemName: "arrow.right").foregroundColor(.secondary)
                    Text(p.new).lineLimit(1).foregroundColor(.blue)
                }.font(.system(size: 12))
            }

            HStack {
                Text(result ?? "").font(.caption).foregroundColor(.green)
                Spacer()
                Button("应用") { apply() }.keyboardShortcut(.defaultAction).disabled(working || !collisions.isEmpty)
            }
        }
        .padding(16).frame(width: 560, height: 480)
    }

    private func apply() {
        working = true
        let ops = planned.filter { $0.old != $0.new }
        let dir = urls.first?.deletingLastPathComponent()
        Task.detached {
            var ok = 0
            var err: String?
            for p in ops {
                guard let dir else { break }
                do {
                    try FileManager.default.moveItem(
                        at: dir.appendingPathComponent(p.old),
                        to: dir.appendingPathComponent(p.new))
                    ok += 1
                } catch { err = err ?? error.localizedDescription }
            }
            await MainActor.run {
                working = false
                result = err != nil ? "失败:\(err!)" : "已重命名 \(ok) 项"
            }
        }
    }
}
```
注:批量重命名假定选中项同目录(Finder 多选必然同目录),与扩展传参一致。

- [ ] **Step 2: 构建 + 验证**

Run: `./build.sh && open "rightclickkit://batch-rename?p=%5B%22%2Ftmp%2Frc-test%2Fa.txt%22%2C%22%2Ftmp%2Frc-test%2Fb.txt%22%5D"`
Expected: 窗口列出两行预览;选「序号」规则预览变化;应用后 /tmp/rc-test 内文件名变为 文件001.txt 等

- [ ] **Step 3: 提交**

```bash
git add App
git commit -m "feat(app): 批量重命名窗(四规则+实时预览+冲突检测)"
```

---

## Task 12: 主 App · 修复乱码文件名窗

**Files:**
- Modify: `App/MojibakeFixView.swift`(替换占位)

- [ ] **Step 1: 完整实现**

`App/MojibakeFixView.swift`:
```swift
import SwiftUI
import AppKit
import CoreKit

struct MojibakeFixView: View {
    struct Row: Identifiable {
        let id = UUID()
        let url: URL
        let candidates: [String]
        var chosen: String
    }

    let urls: [URL]
    @State private var rows: [Row] = []
    @State private var working = false
    @State private var result: String?

    static func show(urls: [URL]) {
        ActionWindow.show(title: "修复乱码文件名", width: 600, height: 460) {
            MojibakeFixView(urls: urls)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if rows.isEmpty && !working {
                Text("未检测到可修复的编码。").foregroundColor(.secondary)
            }
            List($rows) { $row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.url.lastPathComponent).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    if row.candidates.isEmpty {
                        Text("无可识别候选").font(.system(size: 12)).foregroundColor(.orange)
                    } else if row.candidates.count == 1 {
                        TextField("新文件名", text: $row.chosen).font(.system(size: 12))
                    } else {
                        Picker("", selection: $row.chosen) {
                            ForEach(row.candidates, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().font(.system(size: 12))
                    }
                }.padding(.vertical, 2)
            }
            HStack {
                Text(result ?? "").font(.caption).foregroundColor(.green)
                Spacer()
                Button("应用") { apply() }.keyboardShortcut(.defaultAction).disabled(working)
            }
        }
        .padding(16).frame(width: 600, height: 460)
        .onAppear(perform: buildRows)
    }

    private func buildRows() {
        rows = urls.map { url in
            let cands = MojibakeFixer.candidates(for: url.lastPathComponent)
            return Row(url: url, candidates: cands, chosen: cands.first ?? "")
        }
    }

    private func apply() {
        working = true
        let ops = rows.filter { !$0.candidates.isEmpty && $0.chosen != $0.url.lastPathComponent }
            .map { ($0.url, $0.chosen) }
        Task.detached {
            var ok = 0
            var err: String?
            for (url, newName) in ops {
                do {
                    try FileManager.default.moveItem(
                        at: url,
                        to: url.deletingLastPathComponent().appendingPathComponent(newName))
                    ok += 1
                } catch { err = err ?? error.localizedDescription }
            }
            await MainActor.run {
                working = false
                result = err != nil ? "失败:\(err!)" : "已修复 \(ok) 项"
            }
        }
    }
}
```

- [ ] **Step 2: 构造乱码实测**

Run:
```bash
./build.sh
mkdir -p /tmp/rc-moji
touch "/tmp/rc-moji/$("\u{E4}\u{B8}\u{AD}\u{E6}\u{96}\u{87}".ps1)" 2>/dev/null || true
python3 - <<'PY'
import os
base = "/tmp/rc-moji"
name = "ä¸­æ\udc96æ\udc87.txt".encode("utf-8", "surrogatepass").decode("utf-8", "replace")
# 直接用字节造文件名:E4B8AD E69687 的 Latin-1 误读形态
raw = b"\xc3\xa4\xc2\xb8\xc2\xad\xc3\xa6\xc2\x96\xc2\x87.txt"
with open(os.path.join(base.encode(), raw), "w") as f:
    f.write("")
PY
ls /tmp/rc-moji
```
Expected: 目录中出现形如 `ä¸­æ–‡.txt` 的乱码文件

Run: `open "rightclickkit://fix-mojibake?p=<上面乱码文件路径的 JSON 百分号编码>"`
Expected: 窗口显示原乱码名 + 候选「中文.txt」;应用后文件被重命名

(注:若构造乱码文件名步骤在 shell 中过于繁琐,可用 Swift 单测的 MojibakeFixerTests 作为算法正确性依据,本步骤只验证 UI 链路弹窗与列表渲染。)

- [ ] **Step 3: 提交**

```bash
git add App
git commit -m "feat(app): 乱码修复窗(候选预览+逐项可改)"
```

---

## Task 13: 全量构建 + 手动验收清单(需用户参与)

**Files:**
- Create: `README.md`

- [ ] **Step 1: 全量跑一遍测试与构建**

Run: `cd CoreKit && swift run CoreKitTestRunner && cd .. && ./build.sh`
Expected: 20 个 `✅` ALL TESTS PASSED + 构建成功

- [ ] **Step 2: 写 README(使用说明)**

`README.md`:
```markdown
# RightClickKit

自用 macOS Finder 右键增强工具(复刻超级右键核心功能)。无需 Xcode,Command Line Tools 即可构建。

## 构建

    ./build.sh

产物:`.build/app/RightClickKit.app`

## 启用(仅首次)

1. 右键 `.build/app/RightClickKit.app` →「打开」(绕过 Gatekeeper)
2. App 内「扩展」页 →「打开系统设置」→ 登录项与扩展 → 扩展 → Finder 扩展 → 勾选 RightClickKit
3. 在 Finder 任意文件夹右键,菜单即出现功能项

## 功能

新建文件(TXT/MD/Word/Excel/PPT)、新建文件夹、使用文件名新建文件夹、剪切、
拷贝路径、拷贝文件(夹)名称、压缩为 zip/7z、授予写入权限、彻底删除、批量重命名、修复乱码文件名。

## 测试

    cd CoreKit && swift run CoreKitTestRunner
```

- [ ] **Step 3: 请用户手动验收**

逐项清单(用户在 Finder 中验证,子 agent 将结果记录到对话):
1. 新建文件 5 种类型各建一个,能正常打开
2. 新建文件夹 → Finder 选中新建项
3. 使用文件名新建文件夹(选中 a.txt)→ a/a.txt
4. 剪切 + Cmd+V → 文件被移动(**重点验证**;失效则改降级方案)
5. 拷贝路径/名称 → 粘贴板内容正确(多选用换行分隔)
6. 压缩 zip → 解压内容完整;压缩 7z → 未装 7z 时出现 brew 提示通知
7. 授予写入权限 → 锁定的文件解锁可写
8. 彻底删除 → 双确认后文件消失且不在废纸篓
9. 批量重命名 → 四种规则均生效
10. 修复乱码 → 中文乱码被识别修复
11. 设置窗口:功能开关生效(关掉某项后菜单消失)、扩展状态显示正确

- [ ] **Step 4: 按验收结果修复问题并提交**

```bash
git add README.md
git commit -m "docs: README 使用说明"
```

---

## 计划自审记录

1. **规格覆盖**:规格第 4 节 12 个菜单项 ↔ Task 8(4 项)/ Task 9(7 项)/ Task 7(拷贝路径 1 项);设置窗 ↔ Task 6;构建 ↔ Task 7;模板 ↔ Task 5;彻底删除/批量重命名/乱码修复 ↔ Task 10-12;测试策略 ↔ Task 1-4(轻量测试 runner)+ Task 13(手动清单)。无遗漏。
2. **占位符扫描**:Task 6 的三个操作窗占位是刻意的中间态(该任务只求骨架可编译),Task 8-12 完整替换,不属计划缺陷。
3. **类型一致性**:`ActionPayload(action:paths:)`、`FeatureStore.isEnabled(_:)`、`RenamePlanner.plan(names:rule:)`、`FileOps.moveWithoutClobber/makeWritable`、`PathUtils.uniqueName(in:base:ext:)`、`FileWalker.walk/totalSize` 在各任务间签名一致;action 名 `delete-forever`/`batch-rename`/`fix-mojibake` 扩展端与路由端一致。
4. **对规格的一处修正(已说明)**:传参从 `OpenConfiguration.arguments` 改为 URL query(热启动可靠),见 Task 4 说明。
