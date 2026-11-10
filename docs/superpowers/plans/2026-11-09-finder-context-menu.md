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
>
> **修订 2(2026-11-09,Task 1 质量评审后):** harness 改为 flag 标记失败(断言失败后该 test 显示 ❌ 而非误报 ✅),main.swift 输出 tests/assertions 计数并退出前清理临时目录;makeTree 修复(临时父目录+子目录 root,原版断言必失败)已回写至 Task 1 Step 4。
>
> **修订 3(2026-11-10,Task 2 质量评审后):** ① 候选顺序注释改为如实描述枚举序,Task 12 改为不预选候选(默认保持原样,用户逐项确认),apply 增加空名与路径分隔符防护;② 补 CP1252/MacRoman/空串用例;③ CP437(box-drawing 形)与「UTF-8 被 GBK 误读(CJK 形)」两类真实乱码刻意不支持——把 gb18030/big5 加入中间编码会击穿「健康中文名零误报」不变量,列为 v2 候选特性;④ 执行进度以会话任务清单为准,计划 checkbox 不逐一回填。
>
> **修订 4(2026-11-10,Task 3 质量评审后):** collisions 计入链式冲突(新名命中他人旧名,identity 对排除);plan() 注释固化三层职责(名字规划/批内冲突/批外磁盘冲突归 UI 预览);Task 11 补磁盘同名预览检查、空名与路径分隔符防护、序号起始非负;补 dotfile/多点/尾点/空查找/链式/identity 6 个钉子测试(累计 19→25,Task 4 23→29,Task 13 23→29);replace 的 NFC/NFD 字面匹配列为已知限制。
>
> **修订 5(2026-11-10,Task 4 质量评审后):** makeWritable 返回成功计数(Int,@discardableResult),Task 9 按成功/失败分口径通知;Task 9 openInApp 检查 NSWorkspace.open 返回值(false 时提示先运行主 App);Task 6 ActionRouter 对空 paths 不弹窗;规格传参描述同步为 URL query 机制;补 IPC 特殊字符/空数组/缺 p 与移动无冲突/无扩展名冲突 5 个钉子测试(累计 29→34,Task 13 34);URL 容量实测无 64KB 限制,不加路径数上限。
>
> **修订 6(2026-11-10,Task 5 质量评审后):** pptx slide1 改 masterClrMapping、slideMaster1 补 sldLayoutIdLst(压低第三方导入器拒绝风险);zip 前固定时间戳 + pptx 显式条目列表(可复现构建,模板 diff 可评审);GUI 打开性验证统一留待 Task 13 验收第 1 项。
>
> **修订 7(2026-11-10,Task 6/7 执行中):** 实测裁决 SwiftPM 自动产出 libCoreKit.a(无需 products 声明/libtool);主 App 增加最小应用菜单修 Cmd+Q;根 .gitignore(.build/)入库。FinderSync API 以 SDK 实名为准(基类 `FIFinderSync`/枚举 `FIMenuKind`,SDK 无 `FNSyncExtension`/`FNSyncMenuKind`/`FinderSyncExtensionMain`),appex 入口用 Foundation `_NSExtensionMain`(无 main.swift,`-Xlinker -e -Xlinker _NSExtensionMain`)。⚠️ **实测 macOS 26 pkd 拒绝注册 ad-hoc 签名的 appex**:`pluginkit -a` 静默无效果、`pluginkit -m` 恒空;对照实验(同一 WPS appex:真实证书签名在 /tmp 可注册,ad-hoc 重签同标识符更高版本仍被拒)证明拦截发生在签名身份层;本机 0 个 codesigning 身份,纯 CLT(无 Xcode)无法自产 Apple Development 证书 → 「pluginkit 发现扩展」一步 BLOCKED,待用户决策(装真实签名证书,或 Task 13 验收时在系统设置「添加扩展」手动尝试);其余链路(构建/组装/双 plist lint/ad-hoc 签名/App 启动)全部实测通过。
>
> **修订 8(2026-11-10,Task 8 执行中,含评审确认的四项顺手修复):** ① FinderSync API 实名再裁决:`FIFinderSyncController` **无** `targetURL()`,SDK 头文件实名为 `targetedURL()`(返回 Finder 当前目标 URL——文件夹背景右键时即当前文件夹;仅在 `menu(for:)` 与其菜单 action 内有效),Task 8 代码块与 Task 7 的 copyPath 均按实名回写。② **copyPath 空选择回退**(质量评审 Important):文件夹背景右键时 `selectedItemURLs` 为空,原实现静默无效,而这恰是「拷贝当前文件夹路径」最自然手势;改为空选择回退 `targetedURL()` 拷当前文件夹路径,两者皆无才 return;同函数改用 `path(percentEncoded: false)` 消除历史百分号编码歧义(仅改动范围应用,Task 9 复制此模式,不全局翻新)。③ **build.sh 自检与签名参数化**(质量评审 Important + Minor):头部 `SIGN_IDENTITY="${SIGN_IDENTITY:--}"`(默认 ad-hoc 行为不变,为真实证书预留);签名后新增自检 `codesign --verify --deep --strict`(appex 与 $APP 各一次,对应先内后外)与两个 plist 的 `plutil -lint`(set -e 保证失败即停);末尾 `codesign -dv | head` 加 `|| true` 防 SIGPIPE;Task 7 代码块同步为最终形态。④ **ActionWindow 修复**(fix(app),原排 Task 10 前):`alive` 字典按 action(以标题为键,三个调用方标题互异)去重——同 action 重复唤起复用窗口(更新内容 + `makeKeyAndOrderFront` 置前)不叠开;willClose 时移除 observer token 修复泄漏;`show` 签名不变、调用方零改动,Task 6 代码块同步。Task 8 的 Finder UI 实测与 Task 7 同因 pluginkit BLOCKED(修订 7),标「待用户验收」。
>
> **修订 9(2026-11-10,Task 9 执行中,含 Task 8 评审确认的五项顺手改进 A-E):** ① **add(to:) 复用 Feature.title**(A,消除 11 处菜单标题双写):签名去掉 title 参数、内部取 `feature.title`;Task 7/8/9 全部菜单代码块同步。执行前逐项核对 Feature.title 与原菜单字面量:**11 处完全一致,无裁决偏差**;新建文件子菜单 5 个模板项(TXT 文本等)无 Feature 对应,保持字面量。② **image(_:) 图标辅助**(B):systemSymbolName + 16pt 定尺寸收敛为私有辅助,add(to:) 与子菜单循环(父项/循环/add 三处)改用。③ **notify() 转义链补换行**(C):尾接 `.replacingOccurrences(of: "\n", with: " ")`(AppleScript 字面量不允许裸换行,error 消息可能携带);仍 fire-and-forget 不改 wait 语义。④ **runTool(executable:arguments:cwd:) 辅助**(D):compressZip/compress7z 的 Process→run→waitUntilExit→退出码检查收敛为共用私有辅助(启动失败返回 nil,调用方各自 notify;notify 不并入,保持 fire-and-forget 不阻塞主线程);baseName 辅助同时供两处压缩取输出基名。⑤ **path(percentEncoded: false) 延续**(E,Task 8 定调模式):cutFiles 剪贴板路径数组、openInApp 的 ActionPayload paths、compressZip 的 ditto 参数均改用显式解码;7z 因 cwd+相对路径模式保持 `$0.lastPathComponent` 不变。⑥ **fix(app) ActionWindow 窗口被压小**(Task 9 冒烟新发现,超出 A-E 范围单列一笔 commit):实测 macOS 26 的 NSHostingView 默认按 SwiftUI 理想尺寸驱动窗口——ActionWindow 创建 420x200 动作窗后,runloop 布局阶段窗口被压成内容固有大小 71x48(临时 stderr 埋点 + CGWindowList 双重实证,CLI 进程不可复现,须真实 App 事件循环);修复:新建 `makeHost` 辅助统一设 `sizingOptions = []`,新建与复用(重复唤起替换 contentView)两条路径都走,实测窗口稳定保持 420x200+标题栏,Task 6 代码块同步。⑦ **Step 4 冒烟实证**:`open "rightclickkit://batch-rename?p=…"` **冷启动直达**——LaunchServices 依据 App-Info.plist 的 CFBundleURLTypes 直接拉起主 App 并送达 URL,无需先手动启动注册 scheme;占位窗(标题「批量重命名」、内容「待实现」)正常弹出,新建与复用两路径均验证,测毕 pkill 清场。另录得非致命噪音:主 App 进程内 UserDefaults(suiteName:) 因 suite 等于自身 bundle id 打 warning("will not work"),FeatureStore 回退 UserDefaults.standard 后落盘同一 plist(com.yaowl.RightClickKit.plist),扩展按 suite 读同一文件,**开关仍互通**,暂不处理。cutFiles 剪贴板与全部 Finder UI 行为因 pluginkit BLOCKED(修订 7)标待用户验收。
>
> **修订 10(2026-11-10,Task 9 规格评审判「With fixes」,两处):** ① **Important·grantWrite 计数口径错位**:`FileOps.makeWritable` 经 FileWalker 遍历根节点+全部后代,返回**节点数**(文件夹含 3 文件全成功返回 4);原实现直接累加节点数与 `tried = urls.count`(顶层条目数)比较,选中文件夹授权时全成功也会误报「部分失败 4/1 项」。修法(裁决取 URL 粒度,CoreKit 保持冻结、不加节点/条目双口径元组——过度设计):`for url in urls where FileOps.makeWritable(url) > 0 { ok += 1 }`,顶层条目粒度计数,makeWritable 返回 >0 视为该条目成功;Task 9 grantWrite 代码块同步。② **Minor·compress7z 注释与实现不自洽**:原注释称相对路径「规避 7z 对含空格/特殊字符绝对路径的解析问题」,但 `out.path` 仍是绝对路径,且 Process 直传 argv 无 shell 切分问题;注释改写为如实描述(Process argv 直传说明 + 多选跨目录时相对 cwd 仅对首项目录有效的已知限制,Task 13 验收按同目录口径),Task 9 compress7z 代码块同步。
>
> **修订 11(2026-11-10,Task 9 质量评审通过,四条一行级打磨):** ① notify 换行族转义:`.components(separatedBy: .newlines).joined(separator: " ")` 替代单 `\n` 替换(补裸 CR 漏洞,覆盖 \r、\r\n、\n 及 Unicode 行分隔符);② ActionWindow.show doc 注释补「同 title 复用时忽略 width/height,尺寸以首次创建为准」(title 即去重键,Task 10-12 作者最易踩);③ locate7z 探测表补 p7zip 主二进制名 `7z`(Homebrew 与 /usr/local 各一,原表只有 7zz/7za 兼容入口);④ cutFiles 删冗余 `clearContents()`(declareTypes 自带 clear 语义;copyPath/copyName 走 setString 不带 clear,保留)。Task 6/8/9 代码块同步。
>
> **修订 12(2026-11-10,Task 10 执行中):** ① 唯一代码级打磨(计划原稿一行):`Task.detached` 内 `firstError` 在进 `MainActor.run` 前先落为 `let reported`,消除「并发执行代码中引用捕获 var」编译警告(Swift 6 模式下为错误);语义不变(逐项 removeItem,部分失败只报首个错误)。Task 10 代码块同步。② **窗口尺寸双口径实证**(临时 stderr 埋点 + CGWindowList,埋点测毕移除未入库):窗口 frame 自创建起恒为 **440x292** = 内容 440x260 + 标题栏实高 **32**(macOS 26 实测,前序「≈440x288 = 260+28」预估据此修正);contentView 精确 {440, 260},无留白/裁切(修订 9⑥ sizingOptions=[] 修复在新尺寸上复验,0.3s/1s/2s 三点采样无漂移)。CGWindowList 读得 432x286 系 **Liquid Glass 玻璃内缩的可视区口径**(水平 -8 / 垂直 -6),与 App 侧 frame 一致,非窗口被压。③ **同 title 复用路径实测**:换 payload(单文件→文件+目录两项)重复唤起,`show(created)` 仍仅 1 次、屏幕单窗、内容已换新——ActionWindow 去重键行为符合修订 9⑥/11② 定调;冷启动直达再复验(Task 9⑦ 先例)。④ ⚠️ UI 点击流(Toggle 勾选前「彻底删除」按钮禁用、勾选解禁、实测删除 a.txt)因 CLI agent 无屏幕录制/辅助功能权限不可自动化,标**待用户验收**留待 Task 13;测试文件 `/tmp/rc-test/a.txt` 已就位保留。CoreKit 零改动,`swift run CoreKitTestRunner` 34 tests 全绿。
>
> **修订 13(2026-11-10,Task 10 质量评审通过,两条一行级打磨):** ① **done 门禁**(fix(app),全 App 唯一致命操作):「彻底删除」按钮 `.disabled(!acknowledged || working)` 补 `|| done`——done 后按 Return(defaultAction 仍绑定)会二次全量删除,已删项全部报 "No such file",错误文案误导;补门禁后完成态不可再触发。Task 10 代码块同步。② **ActionWindow @State 重置契约 doc**:show doc 注释追加「复用即整体替换 contentView → 全新 view 树,@State 天然重置,调用方无需手动清状态」(Task 11/12 作者最依赖的隐含契约,接修订 11②),Task 6 代码块同步。
>
> **修订 14(2026-11-10,Task 11 执行中):** ① apply() 沿用 Task 10 先例(修订 12①):`Task.detached` 内 `err` 进 `MainActor.run` 前落为 `let reported`(`ok` 同步落 `let okCount`),消除「并发执行代码中引用捕获 var」警告;result 文案由三元 `err!` 强解包改写为 `if let e`——语义等价(逐项 moveItem,部分失败只报首个错误),与 DeleteForeverView.swift 写法一致。Task 11 代码块同步。② **冒烟实证**:`open "rightclickkit://batch-rename?…"` **冷启动直达**(Task 9⑦/修订 12③ 先例三复验),CGWindowList 读得窗口「批量重命名」frame 精确 **560x512** = 内容 560x480 + 标题栏 32(本轮读得全 frame,未复现修订 12② Task 10 的 -8/-6 玻璃内缩读数,口径差异不影响「无压窗」结论;另一 560x592 窗为设置窗);**同 title 复用路径实测**(两项 payload → 单文件 payload 重复唤起)仍仅 1 窗不叠开,符合修订 13② @State 重置契约。③ ⚠️ 预览行内容、四规则切换预览变化、两层冲突警示文案、「应用」门禁与 moveItem 点击流因 CLI agent 无屏幕录制/辅助功能权限不可自动化,标**待用户验收**留待 Task 13;`/tmp/rc-test/` 的 a.txt/b.txt 已就位保留(未被消耗)。CoreKit 零改动,`swift run CoreKitTestRunner` 34 tests 全绿。
>
> **修订 15(2026-11-10,Task 11 质量评审通过,三项打磨,前两项涉正确性/一致性):** ① **seqStart 溢出崩溃修复**(规格评审漏网的真实缺陷):起始序号输入 19 位数字时 `Int(seqStart)` 解析到 `Int.max`,plan 内部 `start + i` 溢出 trap 崩溃;修为 `min(9_999, max(0, Int(seqStart) ?? 1))`(width: 3 暗示的数量级上限)。Task 11 代码块同步。② **done 门禁**(对齐修订 13①/Task 10 先例):补 `@State private var done`,apply 收尾成功分支置 true,应用按钮 disabled 加 `|| done`——防陈旧预览上重复应用(已改名项报 "No such file",绿色「已重命名」文案误导;失败分支不置 done,保留重试路径)。③ **guard 提升**(纯清理):apply 的 `guard let dir` 提到 `Task.detached` 之前 MainActor 侧先解包(置于 `working = true` 前,dir 为 nil 时静默返回、不卡禁用态),非可选值捕获进闭包,循环内 `guard let dir else { break }` 消失。**不动的(已裁决攒到 Task 13/终审)**:失败文案绿色、ops 静默丢项警示、取消按钮/borderedProminent 一致性。
>
> **修订 16(2026-11-10,Task 12 执行中):** ① **error/done 拆分替代 `result: String?`**(授权偏离计划原稿,直接消灭修订 15「攒到终审」清单里的「失败文案绿色」计划级瑕疵):`@State private var error: String?` + `done: Bool` + `fixedCount: Int`,失败红色 `error` 行/成功绿色「已修复 N 项。」分色显示(DeleteForeverView.swift 模式);done 门禁——成功置 done 并禁用「应用」,防陈旧行重复应用(已改名项报 "No such file");失败不置 done 保留重试路径;apply 开头 `error = nil` 清残留(对齐 DeleteForeverView `working = true; error = nil`)。Task 12 代码块同步。② **Task 10/11 先例沿用**(修订 12①/14①):`Task.detached` 内 `err` 落 `let reported`、`ok` 落 `let okCount` 再进 `MainActor.run`,文案改 `if let e`,消除并发捕获 var 警告。③ **冒烟实证**:`open "rightclickkit://fix-mojibake?…"` **冷启动直达**(Task 9⑦ 先例四复验),CGWindowList **全量口径**(`.optionAll`;本轮发现无屏幕录制权限进程上 `.optionOnScreenOnly` 探针漏报在屏窗口,后续窗口实证一律用 `.optionAll`)读得窗口「修复乱码文件名」frame 精确 **600x492** = 内容 600x460 + 标题栏 32,onscreen=true;**同 title 复用路径实测**(单路径 → 三路径 payload 重复唤起)仍单窗不叠开、frame 不变,符合修订 13② @State 重置契约。④ **测试数据就位保留**:`/tmp/rc-moji/` 四个文件——「中文」乱码(E4B8AD E69687 的 Latin-1 误读字节 `ä¸\xadæ\x96\x87.txt`)、第二乱码「数据」(E695B0 E68DAE 同形)、健康名 `正常.txt` 对照(零误报不变量)、单候选件 `À\u{0080}ab.txt`(字节 `c3 80 c2 80 ab…`,gb18030 唯一命中,big5/utf8 均败)——CoreKit 编译探针实证四种数据覆盖三态:**多候选 Picker ×2**(「中文」乱码 2 候选含「中文.txt」、「数据」乱码 2 候选含「数据.txt」)、**零候选 ×1**(健康名)、**单候选 TextField ×1**(恰 1 候选「纮ab.txt」)。规格评审修正:原「三个文件覆盖三态」表述失实——前三件全为 Picker 态或零候选,无任何一件命中 `candidates.count == 1` 的 TextField 分支(第 4 件即为此补)。Task 13 用户验收用。⚠️ 候选渲染、Picker/TextField 交互与「应用」重命名点击流因 CLI agent 无屏幕录制/辅助功能权限不可自动化,标**待用户验收**留待 Task 13。CoreKit 零改动,`swift run CoreKitTestRunner` 34 tests 全绿。

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
var _assertions = 0
var _testsRun = 0
var _currentTest = ""
var _currentTestFailed = false
var _tempDirs: [URL] = []

func test(_ name: String, _ body: () throws -> Void) {
    _testsRun += 1
    _currentTest = name
    _currentTestFailed = false
    do {
        try body()
    } catch {
        print("  ❌ (\(name)) 抛错:\(error)")
        _failures += 1
        _currentTestFailed = true
    }
    print(_currentTestFailed ? "❌ \(name)" : "✅ \(name)")
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                               file: StaticString = #file, line: UInt = #line) {
    _assertions += 1
    if actual != expected {
        print("  ❌ (\(file):\(line)): 期望 \(expected),实际 \(actual)")
        _failures += 1
        _currentTestFailed = true
    }
}

func expectTrue(_ cond: Bool, _ label: String,
                file: StaticString = #file, line: UInt = #line) {
    _assertions += 1
    if !cond {
        print("  ❌ (\(file):\(line)): \(label)")
        _failures += 1
        _currentTestFailed = true
    }
}

func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    _tempDirs.append(dir)
    return dir
}

/// 退出前统一清理测试临时目录
func cleanupTempDirs() {
    for dir in _tempDirs {
        try? FileManager.default.removeItem(at: dir)
    }
}
```

`CoreKit/Sources/CoreKitTestRunner/main.swift`(后续 Task 2-4 各自追加一行 `runXxxTests()`):
```swift
import Foundation

runPathUtilsTests()
runFileWalkerTests()

cleanupTempDirs()

if _failures > 0 {
    print("FAILED:\(_failures) failures (\(_assertions) assertions run)")
    exit(1)
}
print("ALL TESTS PASSED (\(_testsRun) tests, \(_assertions) assertions)")
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
    let parent = try makeTempDir()
    let root = parent.appendingPathComponent("root")
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
    test("乱码修复:CP1252 误读形态(en-dash)→ 首候选中文.txt") {
        let raw = Data("中文.txt".utf8)
        let form = String(data: raw, encoding: .windowsCP1252)
        expectTrue(form != nil, "CP1252 应能解码中文字节")
        guard let form else { return }
        expectEqual(MojibakeFixer.candidates(for: form).first ?? "", "中文.txt")
    }
    test("乱码修复:MacRoman 误读形态 → 候选含中文.txt") {
        let raw = Data("中文.txt".utf8)
        let form = String(data: raw, encoding: .macOSRoman)
        expectTrue(form != nil, "MacRoman 应能解码任意字节")
        guard let form else { return }
        expectTrue(MojibakeFixer.candidates(for: form).contains("中文.txt"), "候选应含 中文.txt")
    }
    test("乱码修复:空串返回空") {
        expectTrue(MojibakeFixer.candidates(for: "").isEmpty, "空串不应有候选")
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

    /// 返回去重后的修复候选;顺序为枚举序(单字节中间编码在前、.utf8 目标在前),
    /// 不是严格置信度排序——首个候选不一定正确,UI 不得预选,须由用户确认。
    /// 不可修复或无候选时返回 []
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

    private static func looksCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd CoreKit && swift run CoreKitTestRunner`
Expected: 累计 13 个 `✅`,末尾 `ALL TESTS PASSED`

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
    test("冲突检测:链式改名(新名命中他人旧名)被判冲突") {
        let r = RenamePlanner.plan(names: ["1.txt", "002.txt"],
                                   rule: .sequence(base: "", start: 2, width: 3))
        expectEqual(RenamePlanner.collisions(in: r), ["002.txt"])
    }
    test("冲突检测:identity 对不参与链式误报") {
        let pairs: [(old: String, new: String)] = [("a", "a"), ("b", "x")]
        expectEqual(RenamePlanner.collisions(in: pairs), [])
    }
    test("重命名:点开头隐藏文件按无扩展名处理") {
        let r = RenamePlanner.plan(names: [".hidden"], rule: .prefix("v2_"))
        expectEqual(r[0].new, "v2_.hidden")
    }
    test("重命名:多点文件只取最后一段扩展名") {
        let r = RenamePlanner.plan(names: ["a.b.c"], rule: .prefix("x_"))
        expectEqual(r[0].new, "x_a.b.c")
    }
    test("重命名:尾点文件名保留尾点") {
        let r = RenamePlanner.plan(names: ["name."], rule: .prefix("v2_"))
        expectEqual(r[0].new, "v2_name.")
    }
    test("重命名:空查找串为 no-op") {
        let r = RenamePlanner.plan(names: ["abc"], rule: .replace(find: "", replacement: "-"))
        expectEqual(r[0].new, "abc")
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
    /// 纯名字级规划:返回与输入等长且同序的 (old, new) 列表,identity 对(old==new)包含在内,
    /// 由调用方过滤。只负责名字变换;批内重复与链式冲突用 collisions(in:) 检测,
    /// 批外磁盘同名冲突由调用方在预览层检查(需要文件系统,这里保持纯函数)。
    /// 已知限制:replace 为字面匹配,不处理 Unicode NFC/NFD 等价。
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

    /// 返回批次内不允许直接执行的新名:出现 ≥2 次的新名,以及链式冲突
    /// (某项的 new 等于另一非自身项的 old,如 1.txt→002.txt 而 002.txt 也在批次内)。
    /// identity 对(old==new)不参与链式判定。排序返回,输出确定。
    public static func collisions(in pairs: [(old: String, new: String)]) -> [String] {
        var dupNew: [String: Int] = [:]
        for p in pairs { dupNew[p.new, default: 0] += 1 }
        var out = Set(dupNew.filter { $0.value > 1 }.map { $0.key })
        let olds = Set(pairs.map { $0.old })
        for p in pairs where p.new != p.old && olds.contains(p.new) {
            out.insert(p.new)
        }
        return out.sorted()
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd CoreKit && swift run CoreKitTestRunner`
Expected: 累计 25 个 `✅`,末尾 `ALL TESTS PASSED`

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
    test("ActionPayload:往返保留 +&#%\" 特殊字符") {
        let p = ActionPayload(action: "copy-path",
                              paths: ["/tmp/a+b&c#d%e\"f.txt"])
        guard let url = p.makeURL() else {
            expectTrue(false, "makeURL 不应返回 nil"); return
        }
        expectEqual(ActionPayload.parse(url), p)
    }
    test("ActionPayload:空路径数组往返") {
        let p = ActionPayload(action: "cut", paths: [])
        guard let url = p.makeURL() else {
            expectTrue(false, "makeURL 不应返回 nil"); return
        }
        expectEqual(ActionPayload.parse(url), p)
    }
    test("ActionPayload:缺 p 参数判 nil") {
        expectTrue(ActionPayload.parse(URL(string: "rightclickkit://a")!) == nil,
                   "缺 p 不应被解析")
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
        // 源与目标必须是不同路径(同路径会变成"移到自己"的退化场景)
        let srcDir = try makeTempDir()
        let a = srcDir.appendingPathComponent("x.txt")
        try Data("1".utf8).write(to: a)
        let dst = dir.appendingPathComponent("x.txt")
        try Data("2".utf8).write(to: dst)
        let final = try FileOps.moveWithoutClobber(from: a, to: dst)
        expectEqual(final.lastPathComponent, "x 2.txt")
        expectEqual(try String(contentsOf: final, encoding: .utf8), "1")
        expectEqual(try String(contentsOf: dst, encoding: .utf8), "2")
    }
    test("FileOps:无冲突直接移动") {
        let dir = try makeTempDir()
        let a = dir.appendingPathComponent("a.txt")
        try Data("1".utf8).write(to: a)
        let dst = dir.appendingPathComponent("x.txt")
        let final = try FileOps.moveWithoutClobber(from: a, to: dst)
        expectEqual(final, dst)
        expectEqual(try String(contentsOf: dst, encoding: .utf8), "1")
        expectEqual(FileManager.default.fileExists(atPath: a.path), false)
    }
    test("FileOps:冲突且无扩展名时移为 x 2") {
        let dir = try makeTempDir()
        let srcDir = try makeTempDir()
        let a = srcDir.appendingPathComponent("x")
        try Data("1".utf8).write(to: a)
        let dst = dir.appendingPathComponent("x")
        try Data("2".utf8).write(to: dst)
        let final = try FileOps.moveWithoutClobber(from: a, to: dst)
        expectEqual(final.lastPathComponent, "x 2")
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
        let attrs = try fm.attributesOfItem(atPath: f.path)
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
        guard url.scheme?.lowercased() == "rightclickkit",
              let host = url.host, !host.isEmpty,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let v = comps.queryItems?.first(where: { $0.name == "p" })?.value,
              let data = v.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return ActionPayload(action: host, paths: paths)
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
            let stem = "\(base) \(i)"
            candidate = dir.appendingPathComponent(ext.isEmpty ? stem : "\(stem).\(ext)")
            i += 1
        }
        try fm.moveItem(at: from, to: candidate)
        return candidate
    }

    /// 解除锁定(UF_IMMUTABLE)并给属主加写权限(递归)。
    /// 返回成功处理的节点数(目录与文件同口径:两步 setAttributes 都成功才计 1);
    /// 失败常见于属主不是当前用户,调用方按成功/失败分口径提示。
    @discardableResult
    public static func makeWritable(_ url: URL) -> Int {
        let fm = FileManager.default
        var ok = 0
        FileWalker.walk(url) { f in
            let unlockOK = (try? fm.setAttributes([.immutable: false], ofItemAtPath: f.path)) != nil
            var chmodOK = false
            if let mode = ((try? fm.attributesOfItem(atPath: f.path))?[.posixPermissions] as? NSNumber)?.int16Value {
                chmodOK = (try? fm.setAttributes([.posixPermissions: NSNumber(value: mode | 0o200)], ofItemAtPath: f.path)) != nil
            }
            if unlockOK && chmodOK { ok += 1 }
            return true
        }
        return ok
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd CoreKit && swift run CoreKitTestRunner`
Expected: 累计 34 个 `✅`,末尾 `ALL TESTS PASSED`

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
# 模板 GUI 打开性验证(Word/Pages/WPS/Keynote)统一留待 Task 13 验收第 1 项
set -euo pipefail
OUT="$(cd "$(dirname "$0")/.." && pwd)/Resources/Templates"
mkdir -p "$OUT"
rm -f "$OUT/template.docx" "$OUT/template.xlsx" "$OUT/template.pptx"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

make_docx() {
  local d="$WORK/docx"; mkdir -p "$d/_rels" "$d/word"
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
  find "$d" -exec touch -t 202601010000 {} +
  (cd "$d" && TZ=UTC zip -q -X "$OUT/template.docx" "[Content_Types].xml" "_rels/.rels" "word/document.xml")
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
  find "$d" -exec touch -t 202601010000 {} +
  (cd "$d" && TZ=UTC zip -q -X "$OUT/template.xlsx" "[Content_Types].xml" "_rels/.rels" "xl/_rels/workbook.xml.rels" "xl/workbook.xml" "xl/worksheets/sheet1.xml")
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
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>
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
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>
X
  cat > "$d/ppt/slideMasters/_rels/slideMaster1.xml.rels" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/></Relationships>
X
  cat > "$d/ppt/theme/theme1.xml" <<'X'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office"><a:themeElements><a:clrScheme name="Office"><a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="44546A"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2><a:accent1><a:srgbClr val="4472C4"/></a:accent1><a:accent2><a:srgbClr val="ED7D31"/></a:accent2><a:accent3><a:srgbClr val="A5A5A5"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4><a:accent5><a:srgbClr val="5B9BD5"/></a:accent5><a:accent6><a:srgbClr val="70AD47"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme><a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme><a:fmtScheme name="Office"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>
X
  find "$d" -exec touch -t 202601010000 {} +
  (cd "$d" && TZ=UTC zip -q -X "$OUT/template.pptx" "[Content_Types].xml" "_rels/.rels" "ppt/_rels/presentation.xml.rels" "ppt/presentation.xml" "ppt/slides/_rels/slide1.xml.rels" "ppt/slides/slide1.xml" "ppt/slideLayouts/_rels/slideLayout1.xml.rels" "ppt/slideLayouts/slideLayout1.xml" "ppt/slideMasters/_rels/slideMaster1.xml.rels" "ppt/slideMasters/slideMaster1.xml" "ppt/theme/theme1.xml")
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

`App/main.swift`(已回写为仓库现状:含最小应用菜单,修 Cmd+Q):
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// 最小应用菜单:没有它,程序菜单栏为空,Cmd+Q 退出失效
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(title: "退出 RightClickKit",
                           action: #selector(NSApplication.terminate(_:)),
                           keyEquivalent: "q"))
appMenuItem.submenu = appMenu
app.mainMenu = mainMenu

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

`App/ActionWindow.swift`(已回写为仓库现状:按 action 去重复用窗口置前不叠开,willClose 移除 observer 修复泄漏,见顶部修订 8④;makeHost 关闭 macOS 26 NSHostingView 自动定尺寸,见顶部修订 9⑥):
```swift
import AppKit
import SwiftUI

/// 操作类窗口(彻底删除/批量重命名/乱码修复)的宿主,持有引用防释放。
/// 按 action(以标题为键,三个调用方标题互异)去重:重复唤起复用窗口置前,不叠开。
enum ActionWindow {
    private static var alive: [String: (window: NSWindow, observer: NSObjectProtocol)] = [:]

    /// macOS 26:NSHostingView 默认按 SwiftUI 理想尺寸驱动窗口,会把窗口锁到内容固有大小(如 71x48);
    /// 关掉 sizingOptions 恢复由 contentRect 指定的窗口尺寸。新建与复用路径都必须走这里。
    private static func makeHost<Content: View>(_ content: Content) -> NSHostingView<Content> {
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        return host
    }

    /// 弹出操作窗;同 title 复用时忽略 width/height,尺寸以首次创建为准(title 即去重键)。
    /// 复用即整体替换 contentView → 全新 view 树,@State 天然重置,调用方无需手动清状态。
    @discardableResult
    static func show(title: String, width: CGFloat, height: CGFloat,
                     @ViewBuilder content: () -> some View) -> NSWindow {
        if let entry = alive[title] {
            entry.window.contentView = makeHost(content())
            entry.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return entry.window
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.contentView = makeHost(content())
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: w, queue: .main
        ) { [weak w, title] _ in
            guard let w, let entry = alive[title], entry.window === w else { return }
            NotificationCenter.default.removeObserver(entry.observer)
            alive.removeValue(forKey: title)
        }
        alive[title] = (w, observer)
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
        guard !urls.isEmpty else { return }  // 空 p=%5B%5D 不弹空窗
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

> 本节执行说明(2026-11-10):经实测裁决,`swift build -c release` 自动产出 `libCoreKit.a`(executableTarget 依赖触发静态归档),build.sh 的 swiftc 链接命令无需任何前置归档步骤;根 `.gitignore`(`.build/`)与主 App 最小应用菜单(Cmd+Q)随本任务一并入库。另两项实测裁决:① 本 SDK(macOS 26 纯 CLT)的 FinderSync 框架为经典 ObjC 接口,基类实名 `FIFinderSync`、菜单枚举实名 `FIMenuKind`,计划原稿的 `FNSyncExtension`/`FNSyncMenuKind`/`FinderSyncExtensionMain` 在 SDK 中不存在;appex 无 Swift 顶层入口,链接时用 Foundation 的 `_NSExtensionMain` 作入口(`-Xlinker -e -Xlinker _NSExtensionMain`),系统经 Info.plist `NSExtensionPrincipalClass` 实例化主类,**不需要也不存在** `FinderSyncExt/main.swift`。② ⚠️ ad-hoc 签名的 appex 无法进入 pluginkit 数据库(`pluginkit -a` 静默拒绝,`pluginkit -m` 恒空;对照组:同一 WPS appex 真实证书签名可注册、ad-hoc 重签后同标识符更高版本仍被拒;本机 `security find-identity` 为 0,纯 CLT 无 Xcode 无法自产 Apple Development 证书)——「pluginkit 发现扩展」一步 BLOCKED,待用户决策:装真实签名证书,或 Task 13 验收时在 系统设置 → 登录项与扩展 → 添加扩展 手动尝试。其余链路(构建/组装/签名/plutil/App 启动)全部验证通过。
>
> 执行说明补记(2026-11-10,Task 8 执行中):下方两个代码块已随修订 8 ①②③ 回写为最终形态——copyPath 空选择回退 `targetedURL()`(SDK 实名,原 `targetURL()` 不存在)+ `path(percentEncoded: false)`;build.sh `SIGN_IDENTITY` 参数化、签名/plist 自检、`codesign -dv | head` 加 `|| true`。
>
> 执行说明补记 2(2026-11-10,Task 9 执行中):FinderSync.swift 代码块再次随修订 9 A/B 回写为最终形态——add(to:) 去掉 title 参数、内部取 `feature.title`,新增 `image(_:)` 图标辅助。

**Files:**
- Create: `FinderSyncExt/FinderSync.swift`
- Create: `Resources/Ext-Info.plist`
- Create: `build.sh`

本任务只挂一个「拷贝路径」菜单项,打通「构建→签名→注册→Finder 显示」全链路;其余菜单项 Task 8-9 补齐。

- [ ] **Step 1: 扩展入口与菜单**

`FinderSyncExt/FinderSync.swift`(已回写为仓库现状,API 用 SDK 实名):
```swift
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
        add(to: menu, symbol: "link", feature: .copyPath,
            action: #selector(copyPath(_:)))
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

`build.sh`(已回写为仓库现状:SIGN_IDENTITY 参数化 + 签名/plist 自检,见顶部修订 8③):
```bash
#!/bin/bash
# 一键构建:CoreKit(release)→ 主 App 二进制 → 扩展二进制 → 组装 bundle → 签名(默认 ad-hoc,可用 SIGN_IDENTITY 覆盖)→ 自检 → 注册
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_ID="com.yaowl.RightClickKit"
BUILD="$ROOT/.build/app"
APP="$BUILD/RightClickKit.app"
# 签名身份:默认 ad-hoc("-");后续换真实证书时 SIGN_IDENTITY="Apple Development: …" ./build.sh 即可
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

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
# appex 无 main.swift,入口用 Foundation 的 _NSExtensionMain(系统经 Info.plist
# NSExtensionPrincipalClass 实例化扩展主类,与 Xcode 的 appex 链接方式一致)
swiftc -O -module-name FinderSyncExt \
  -I "$ROOT/CoreKit/.build/release/Modules" \
  -L "$ROOT/CoreKit/.build/release" -lCoreKit \
  "$ROOT"/FinderSyncExt/*.swift \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/MacOS/FinderSyncExt"

echo "==> 写入 plist 与模板资源"
cp "$ROOT/Resources/App-Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Ext-Info.plist" "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/Info.plist"
cp "$ROOT"/Resources/Templates/template.* \
   "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/Resources/"

echo "==> 签名(先内后外,身份:$SIGN_IDENTITY)"
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/PlugIns/FinderSyncExt.appex"
codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "==> 自检(签名与 plist,先内后外)"
codesign --verify --deep --strict "$APP/Contents/PlugIns/FinderSyncExt.appex"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/Info.plist"

echo "==> 注册扩展"
pluginkit -a "$APP" || echo "(pluginkit -a 非致命失败,可忽略,系统会自行发现)"

codesign -dv "$APP" 2>&1 | head -2 || true
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

> 本节执行说明(2026-11-10):四个 action 与新建文件子菜单(5 项)全部实装,菜单顺序为 新建文件(子菜单)/新建文件夹/使用文件名新建文件夹/拷贝文件(夹)名称/拷贝路径(末项为 Task 7 既有)。⚠️ 计划原稿的 `controller.targetURL()` 在 SDK 中不存在,头文件实名为 `targetedURL()`(返回 Finder 当前目标 URL,文件夹背景右键时即当前文件夹;仅 `menu(for:)` 与其菜单 action 内有效),已按实名回写下方代码块(见顶部修订 8①)。Step 4 的 Finder UI 实测因「子 agent 无法操作 Finder UI + pluginkit 注册 BLOCKED(修订 7)」标**待用户验收**,留待 Task 13;其余步骤(构建/自检/冒烟/CoreKit 34 测试)已通过。
>
> 执行说明补记(2026-11-10,Task 9 执行中):本节两个代码块已随修订 9 A/B/C 回写为最终形态——add(to:) 去掉 title 参数取 `feature.title`、`image(_:)` 图标辅助、notify() 转义链补换行。

**Files:**
- Modify: `FinderSyncExt/FinderSync.swift`

- [ ] **Step 1: menu(for:) 补齐菜单项(批次一)**

在 `menu(for:)` 中、`copyPath` 之前加入(保持 add 复用):

```swift
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
```

- [ ] **Step 2: 实现四个 action(加在 FinderSync 类内)**

```swift
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
            .components(separatedBy: .newlines).joined(separator: " ") // AppleScript 字面量不允许裸换行(覆盖 \r、\r\n、\n 及 Unicode 行分隔符)
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

> 本节执行说明(2026-11-10):7 个菜单项与 action 全部实装;下方代码块已随修订 9 A-E 回写为最终形态(add 复用 Feature.title/image 辅助/runTool 辅助/path(percentEncoded: false)/notify 换行转义)。Step 4 冒烟实测:**冷启动直达**(LaunchServices 依 CFBundleURLTypes 拉起主 App 并送达 URL,无需先手动启动注册 scheme),占位窗正常弹出;期间发现并修复 macOS 26 NSHostingView 压窗问题(修订 9⑥,fix(app) 单独一笔)。⚠️ cutFiles 剪贴板行为与全部 Finder UI 实测因 pluginkit BLOCKED(修订 7)标**待用户验收**,留待 Task 13。CoreKit 零改动,34 测试保持全绿。
>
> 执行说明补记(2026-11-10,规格评审后):grantWrite 改顶层条目粒度计数(修文件夹授权误报「部分失败」)、compress7z 注释如实化(跨目录已知限制),见顶部修订 10,代码块同步。

**Files:**
- Modify: `FinderSyncExt/FinderSync.swift`

- [ ] **Step 1: menu(for:) 补齐剩余项(按此顺序)**

```swift
        add(to: menu, symbol: "scissors", feature: .cut, action: #selector(cutFiles(_:)))
        add(to: menu, symbol: "doc.zipper", feature: .compressZip, action: #selector(compressZip(_:)))
        add(to: menu, symbol: "archivebox", feature: .compress7z, action: #selector(compress7z(_:)))
        add(to: menu, symbol: "lock.open", feature: .grantWrite, action: #selector(grantWrite(_:)))
        add(to: menu, symbol: "trash", feature: .deleteForever, action: #selector(deleteForever(_:)))
        add(to: menu, symbol: "character.textbox", feature: .batchRename, action: #selector(batchRename(_:)))
        add(to: menu, symbol: "wand.and.stars", feature: .fixMojibake, action: #selector(fixMojibake(_:)))
```

- [ ] **Step 2: 实现剪切/压缩/授权限(类内新增)**

```swift
    @objc private func cutFiles(_ sender: NSMenuItem) {
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return }
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
        ["/opt/homebrew/bin/7zz", "/opt/homebrew/bin/7z", "/opt/homebrew/bin/7za",
         "/usr/local/bin/7zz", "/usr/local/bin/7z", "/usr/local/bin/7za"]
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
        guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return }
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
```

- [ ] **Step 3: 实现唤起主 App 的三项(类内新增)**

```swift
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
```

- [ ] **Step 4: 构建 + URL 链路冒烟**

Run: `./build.sh`
Expected: 构建成功(退出码 0,签名/plist 自检全过)

Run: `open "rightclickkit://batch-rename?p=%5B%22%2Ftmp%22%5D"`
Expected: 主 App 前台弹出「批量重命名」占位窗(contentRect 420x200,内容「待实现」;host=动作名,与 CoreKit ActionPayload.makeURL() 一致)。实测(2026-11-10,修订 9⑦):冷启动直达,无需先启动 App 注册 scheme;同 action 二次唤起走复用路径不叠开。注意:曾实测窗口被压成内容固有尺寸 71x48,系 macOS 26 NSHostingView 默认行为,已在主 App 侧修复(修订 9⑥)。

测毕清场:`pkill -x RightClickKit`

- [ ] **Step 5: 提交**

```bash
git add FinderSyncExt
git commit -m "feat(ext): 剪切/压缩zip/7z/授权限/唤起主 App 三动作"
```

---

## Task 10: 主 App · 彻底删除窗(双确认)

> 本节执行说明(2026-11-10):完整实现按下方代码块落地(唯一打磨:`firstError` 落 let 再进 `MainActor.run`,见顶部修订 12①)。Step 2 冒烟:**冷启动直达**(Task 9⑦ 先例复验),窗(标题「彻底删除」)正常弹出;新建/复用两路径均实测(复用换 payload 后仍单窗、内容换新);窗口 frame 实证 440x292(内容 440x260 + 标题栏 32),CGWindowList 432x286 为 Liquid Glass 可视区内缩口径,双口径一致无压窗(修订 12②)。⚠️ 勾选确认→按钮解禁→实际删除的点击流因 CLI agent 无辅助功能权限不可自动化,标**待用户验收**(Task 13);测试文件 `/tmp/rc-test/a.txt` 已保留待验。CoreKit 零改动,34 测试全绿。
>
> 执行说明补记(2026-11-10,质量评审后):删除按钮加 done 门禁(完成态不可二次触发),见顶部修订 13①,代码块已同步。

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
                    .disabled(!acknowledged || working || done)
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
            let reported = firstError // 落为 let 再进 MainActor.run,消除并发捕获 var 警告(Swift 6 将为错误)
            await MainActor.run {
                working = false
                if let e = reported { error = e } else { done = true }
            }
        }
    }
    private func closeWindow() { NSApp.keyWindow?.close() }
}
```

- [ ] **Step 2: 构建 + 逻辑验证**

Run: `./build.sh && open "rightclickkit://delete-forever?p=%5B%22%2Ftmp%2Frc-test%2Fa.txt%22%5D"`
Expected: 窗口弹出;「彻底删除」按钮在勾选确认前禁用;创建 `mkdir -p /tmp/rc-test && echo hi > /tmp/rc-test/a.txt` 后实测删除成功
执行结果(2026-11-10):构建退出码 0;窗口弹出、标题「彻底删除」、frame 440x292(内容+标题栏 32;CGWindowList 432x286 为玻璃内缩口径,修订 12②);冷启动与同 title 复用两路径实测通过。按钮禁用/勾选确认/实际删除为 UI 点击流,无辅助功能权限不可自动化,标**待用户验收**(Task 13 清单覆盖),`/tmp/rc-test/a.txt` 保留待验。

- [ ] **Step 3: 提交**

```bash
git add App
git commit -m "feat(app): 彻底删除窗(双确认+大小统计)"
```

---

## Task 11: 主 App · 批量重命名窗

> 本节执行说明(2026-11-10):完整实现按下方代码块落地(apply() 按 Task 10 先例落 `let reported`/`let okCount`,见顶部修订 14①)。Step 2 冒烟:**冷启动直达**(Task 9⑦ 先例三复验),窗(标题「批量重命名」)正常弹出,frame 精确 560x512(内容 560x480 + 标题栏 32);同 title 复用路径实测仍单窗不叠开(修订 14②)。⚠️ 预览行/四规则切换/两层冲突警示/「应用」moveItem 点击流无辅助功能权限不可自动化,标**待用户验收**(Task 13);`/tmp/rc-test/` a.txt/b.txt 保留待验。CoreKit 零改动,34 测试全绿。
>
> 执行说明补记(2026-11-10,质量评审后):序号输入防溢出(`min(9_999, …)`)、应用按钮 done 门禁(完成态不可二次应用)、apply 的 dir 解包提升至 MainActor 侧,见顶部修订 15,代码块已同步。

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
    @State private var done = false
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
        case 2: return .sequence(base: seqBase, start: min(9_999, max(0, Int(seqStart) ?? 1)), width: 3)
        default: return .replace(find: find, replacement: replaceWith)
        }
    }

    private var planned: [(old: String, new: String)] {
        RenamePlanner.plan(names: names, rule: rule)
    }
    private var collisions: [String] { RenamePlanner.collisions(in: planned) }

    /// 批外磁盘同名冲突:新名不在本批内、但目标目录已有同名文件
    private var diskConflicts: [String] {
        guard let dir = urls.first?.deletingLastPathComponent() else { return [] }
        let olds = Set(names)
        return planned.filter { $0.old != $0.new }.map { $0.new }
            .filter { !olds.contains($0)
                && FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
    }

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
            if !diskConflicts.isEmpty {
                Label("与文件夹中已有文件重名:\(diskConflicts.joined(separator: "、"))", systemImage: "exclamationmark.triangle").foregroundColor(.orange).font(.caption)
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
                Button("应用") { apply() }.keyboardShortcut(.defaultAction).disabled(working || done || !collisions.isEmpty || !diskConflicts.isEmpty)
            }
        }
        .padding(16).frame(width: 560, height: 480)
    }

    private func apply() {
        guard let dir = urls.first?.deletingLastPathComponent() else { return }
        working = true
        let ops = planned.filter { $0.old != $0.new && !$0.new.isEmpty && !$0.new.contains("/") && !$0.new.contains(":") }
        Task.detached {
            var ok = 0
            var err: String?
            for p in ops {
                do {
                    try FileManager.default.moveItem(
                        at: dir.appendingPathComponent(p.old),
                        to: dir.appendingPathComponent(p.new))
                    ok += 1
                } catch { err = err ?? error.localizedDescription }
            }
            let reported = err // 落为 let 再进 MainActor.run,消除并发捕获 var 警告(Swift 6 将为错误)
            let okCount = ok
            await MainActor.run {
                working = false
                if let e = reported { result = "失败:\(e)" } else { result = "已重命名 \(okCount) 项"; done = true }
            }
        }
    }
}
```
注:批量重命名假定选中项同目录(Finder 多选必然同目录),与扩展传参一致。

- [ ] **Step 2: 构建 + 验证**

Run: `./build.sh && open "rightclickkit://batch-rename?p=%5B%22%2Ftmp%2Frc-test%2Fa.txt%22%2C%22%2Ftmp%2Frc-test%2Fb.txt%22%5D"`
Expected: 窗口列出两行预览;选「序号」规则预览变化;应用后 /tmp/rc-test 内文件名变为 文件001.txt 等

执行结果(2026-11-10):构建退出码 0(签名与 plist 自检全过);`swift run CoreKitTestRunner` 34 tests 全绿;`open`(a.txt+b.txt 两项)**冷启动直达**,CGWindowList 实证窗口「批量重命名」frame 560x512(= 内容 560x480 + 标题栏 32);同 title 复用(换单文件 payload)仍单窗不叠开。两行预览/规则切换预览变化/应用后文件名变化为 UI 点击流,无辅助功能权限不可自动化,标**待用户验收**(Task 13 清单覆盖),`/tmp/rc-test/` 的 a.txt/b.txt 保留未消耗。

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
    @State private var error: String?
    @State private var done = false
    @State private var fixedCount = 0

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
                        // 默认空=保持原样,用户手动填
                        TextField("新文件名", text: $row.chosen).font(.system(size: 12))
                    } else {
                        Picker("", selection: $row.chosen) {
                            Text("保持原样").tag("")
                            ForEach(row.candidates, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().font(.system(size: 12))
                    }
                }.padding(.vertical, 2)
            }
            HStack {
                if let error { Text(error).font(.caption).foregroundColor(.red) }
                if done { Text("已修复 \(fixedCount) 项。").font(.caption).foregroundColor(.green) }
                Spacer()
                Button("应用") { apply() }.keyboardShortcut(.defaultAction).disabled(working || done)
            }
        }
        .padding(16).frame(width: 600, height: 460)
        .onAppear(perform: buildRows)
    }

    private func buildRows() {
        rows = urls.map { url in
            let cands = MojibakeFixer.candidates(for: url.lastPathComponent)
            // 不预选候选:默认保持原样,须由用户逐项确认(候选顺序非置信度序)
            return Row(url: url, candidates: cands, chosen: "")
        }
    }

    private func apply() {
        working = true
        error = nil
        let ops = rows.filter {
            !$0.candidates.isEmpty && !$0.chosen.isEmpty
                && $0.chosen != $0.url.lastPathComponent
                && !$0.chosen.contains("/") && !$0.chosen.contains(":")
        }.map { ($0.url, $0.chosen) }
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
            let reported = err // 落为 let 再进 MainActor.run,消除并发捕获 var 警告(Swift 6 将为错误)
            let okCount = ok
            await MainActor.run {
                working = false
                if let e = reported {
                    error = e // 失败不置 done,保留重试路径
                } else {
                    fixedCount = okCount
                    done = true
                }
            }
        }
    }
}
```

- [ ] **Step 2: 构造乱码实测**

> 本节执行说明(2026-11-10):完整实现按上方代码块落地(唯一打磨:error/done 拆分 + `reported`/`okCount` 落 let,见顶部修订 16①②)。原稿 Step 2 的 `touch "$(…)…"` 行与 `surrogatepass` 中间变量为 shell 转义歧义下的不可靠写法,统一收敛为字节级 python 构造(下方代码块即实测可复现形态),另补第二乱码、健康名对照与单候选件共四件覆盖三态(见顶部修订 16④)。

Run:
```bash
./build.sh
rm -rf /tmp/rc-moji && mkdir -p /tmp/rc-moji
python3 - <<'PY'
import os
base = "/tmp/rc-moji"
# E4B8AD E69687("中文")的 Latin-1 误读形态字节造文件名
raw = b"\xc3\xa4\xc2\xb8\xc2\xad\xc3\xa6\xc2\x96\xc2\x87.txt"
with open(os.path.join(base.encode(), raw), "w") as f:
    f.write("")
# 第二个乱码:"数据" E695B0 E68DAE 同形;健康名对照验证零误报不变量
raw2 = b"\xc3\xa6\xc2\x95\xc2\xb0\xc3\xa6\xc2\x8d\xc2\xae.txt"
with open(os.path.join(base.encode(), raw2), "w") as f:
    f.write("")
# 第 4 件:À+U+0080+ab.txt —— gb18030 唯一命中,恰 1 候选「纮ab.txt」(单候选 TextField 态)
raw3 = b"\xc3\x80\xc2\x80ab.txt"
with open(os.path.join(base.encode(), raw3), "w") as f:
    f.write("")
with open(os.path.join(base, "正常.txt"), "w") as f:
    f.write("")
PY
ls /tmp/rc-moji
```
Expected: 目录中出现 `ä¸\xadæ\x96\x87.txt`、`æ\x95°æ\x8d®.txt`、`À\u{0080}ab.txt`(ls 显示 `Àab.txt`,U+0080 不可见)三个乱码文件与 `正常.txt`

URL 的 payload 百分号编码(python3 `urllib.parse.quote(json.dumps(paths), safe='')`,与 CoreKit `ActionPayload.makeURL()` 同构):

Run: `open "rightclickkit://fix-mojibake?p=%5B%22%2Ftmp%2Frc-moji%2F%C3%A4%C2%B8%C2%AD%C3%A6%C2%96%C2%87.txt%22%5D"`
Expected: 窗口显示原乱码名 + 候选「中文.txt」;应用后文件被重命名

执行结果(2026-11-10):构建退出码 0(签名与 plist 自检全过);`swift run CoreKitTestRunner` 34 tests 全绿;三个测试文件构造成功(`ls` 实证)。`open`(单乱码路径)**冷启动直达**(Task 9⑦/修订 12③/14② 先例四复验),CGWindowList **全量口径**(`.optionAll`;实测无屏幕录制权限进程上 `.optionOnScreenOnly` 探针漏报在屏窗口,后续窗口实证一律用 `.optionAll`)读得窗口「修复乱码文件名」frame 精确 **600x492** = 内容 600x460 + 标题栏 32、onscreen=true(另一 560x592 窗为设置窗);**同 title 复用路径实测**(三路径 payload:两乱码+一健康名对照重复唤起)仍单窗不叠开、frame 不变,符合修订 13② @State 重置契约。原乱码名渲染、候选「中文.txt」显示、Picker/TextField 交互与「应用」重命名点击流为 UI 操作,无辅助功能权限不可自动化,标**待用户验收**(Task 13 清单覆盖);`/tmp/rc-moji/` 三文件保留未被消耗(乱码名未被重命名,用户可全程实操)。

(注:算法正确性由 CoreKit 的 MojibakeFixerTests 作为依据,本步骤只验证 UI 链路弹窗与列表渲染。)

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
Expected: 34 个 `✅` ALL TESTS PASSED + 构建成功

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
10. 修复乱码 → 中文乱码被识别修复(测试数据已就位:`/tmp/rc-moji/` 四件覆盖三态——两个 Latin-1 形乱码为多候选 Picker 态、健康名 `正常.txt` 零候选应显示「无可识别候选」不误报、`À\u{0080}ab.txt` 恰 1 候选「纮ab.txt」为单候选 TextField 态;均默认「保持原样」待用户逐项确认)
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
