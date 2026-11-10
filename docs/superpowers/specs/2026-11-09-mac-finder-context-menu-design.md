# Mac Finder 右键快捷功能 App 设计文档

日期:2026-11-09
状态:已确认(用户逐节确认)

## 1. 背景与目标

复刻「超级右键」(iRightMouse)的核心功能,做一个**自用**的原生 macOS App,把常用文件操作注入 Finder 右键菜单顶层。

- 形式:原生 App(主 App + Finder Sync Extension),菜单项直接出现在右键菜单顶层
- 用途:仅自用,不分发 → **ad-hoc 自签名,无需付费开发者账号**
- 工具链:**不装完整 Xcode**,只用 Command Line Tools(`swiftc` + 手工组装 bundle)
- 系统要求:macOS 15+ (Darwin 25)

## 2. MVP 功能范围

用户选定三类:

1. **路径/基础操作类**:拷贝路径、拷贝文件名、剪切、新建文件夹、彻底删除
2. **新建文件类**:新建 TXT/Markdown/Word/Excel/PPT
3. **高级工具类**:压缩 7z/zip、修复乱码文件名、批量重命名、授予写入权限

未入选(后续版本):复制到/移动到、发送快捷方式到桌面、隐藏/取消隐藏文件、文件图标、文件信息。

## 3. 总体架构

```
RightClickKit.app
└── Contents/
    ├── MacOS/RightClickKit              ← 主 App:SwiftUI 设置窗口 + 操作弹窗
    ├── Library/FinderSyncExt.appex/
    │   └── MacOS/FinderSyncExt          ← Finder 扩展:注入右键菜单
    └── Resources/                       ← 文件模板(.docx/.xlsx/.pptx)、图标
```

| 模块 | 职责 | 依赖 |
|------|------|------|
| **CoreKit**(SPM 纯 Swift 包) | 无 UI 逻辑:乱码检测/修复算法、重命名规则、路径工具 | 无,`swift test` 可独立跑 |
| **FinderSyncExt**(扩展进程) | `menu(for:)` 提供菜单项;无需 UI 的操作直接执行 | CoreKit |
| **主 App**(SwiftUI) | 设置窗口;需要 UI 的操作弹窗 | CoreKit |

关键机制:

- **进程分工**:拷贝路径、剪切、新建文件/文件夹、压缩、授权限在扩展进程内直接完成;需要 UI 的操作(彻底删除确认、乱码修复预览、批量重命名)经 URL scheme `rightclickkit://action=...` 唤起主 App。
- **非沙盒**:扩展继承主 App 非沙盒状态,直接访问文件系统。
- **启用方式**:首次运行引导用户到 系统设置 → 登录项与扩展 → Finder 扩展 开启(一次性)。
- **传参**:扩展通过 `NSWorkspace.open(_:configuration:)` 唤起主 App,URL 带 action 类型(`rightclickkit://action=batch-rename`),`OpenConfiguration.arguments` 带选中的文件路径列表,不落盘。

## 4. 菜单项功能明细

| 菜单项 | 行为 | 执行位置 |
|--------|------|---------|
| 新建文件 ▸ | 子菜单:TXT / Markdown / Word / Excel / PPT;在当前文件夹创建模板文件,创建后 Finder 选中并进入重命名 | 扩展进程 |
| 新建文件夹 | 创建「未命名文件夹」并进入重命名 | 扩展进程 |
| 使用文件名新建文件夹 | 选中 `a.txt` → 创建 `a/` 并把文件移入 | 扩展进程 |
| 拷贝路径 | POSIX 路径到剪贴板 | 扩展进程 |
| 拷贝文件(夹)名称 | 文件名(含扩展名)到剪贴板 | 扩展进程 |
| 剪切 | 写入 Finder 剪贴板格式 `com.apple.finder.cut-for-board`,Cmd+V 即移动;实施时验证,失效则降级为「扩展内暂存 + 提示」 | 扩展进程 |
| 彻底删除 | 唤起主 App → 红色警告双确认 → `rm -rf`(不进废纸篓) | 主 App |
| 授予写入权限 | 批量 `chmod u+w` + 解除锁定标志 | 扩展进程 |
| 修复乱码文件名 | 唤起主 App → 识别 GBK/Big5 误解码 → 预览原/新名 → 确认批量重命名 | 主 App |
| 批量重命名 | 主 App 窗口:前缀/后缀/序号/查找替换,实时预览,应用 | 主 App |
| 压缩为 zip | `ditto -c -k --sequesterRsrc --keepParent` | 扩展进程 |
| 压缩为 7z | 检测 `7zz`/`7za`(brew),无则通知提示安装命令 | 扩展进程 |

### 乱码修复算法(CoreKit,单测覆盖)

对文件名字节流按单字节误读编码(Latin-1/CP1252/MacRoman)还原,再按 UTF-8/GB18030/Big5 解码,结合乱码特征(replacement char、典型乱码字符集)给最高置信度候选;所有候选展示,用户可逐行修改。CP437 与 CJK 形误读通路列为后续候选(v2)。

### 新建文件模板

内嵌最小合法模板(.docx/.xlsx/.pptx 各约 10KB)到 Resources;TXT/Markdown 直接创建空文件。

## 5. 构建系统

```
├── CoreKit/               ← SPM 包
├── App/                   ← 主 App 源码
├── FinderSyncExt/         ← 扩展源码
├── Resources/             ← 模板、图标、Info.plist 模板
└── build.sh
```

`build.sh`:

1. `swift build` 编译 CoreKit
2. `swiftc` 编译主 App 与扩展(SwiftUI 用 CLT 自带 macOS SDK 直接编译)
3. 组装 `RightClickKit.app` 目录树,生成 `Info.plist`(含 `NSExtension` 声明、`CFBundleURLTypes` URL scheme)
4. `codesign --sign - --deep` ad-hoc 自签名
5. `pluginkit -a` 注册扩展,输出启用引导提示

首次运行:右键 → 打开 绕过 Gatekeeper;之后去系统设置启用扩展。

## 6. 设置窗口(SwiftUI)

- 扩展启用状态检测(读 `pluginkit -m`)+ 跳转系统设置按钮 + 引导文案
- 功能开关列表(每菜单项一个 toggle)
- 新建文件模板列表(MVP 仅展示,后续可扩展)
- 关于 + 退出

## 7. 错误处理

| 场景 | 处理 |
|------|------|
| 扩展未启用 | 主 App 首页醒目引导(最常见问题) |
| 文件操作失败(权限/占用) | 扩展进程发系统通知含原因;主 App 操作弹 NSAlert |
| 彻底删除 | 双确认弹窗,显示文件数与总大小 |
| 乱码修复无候选 | 提示未检测到可修复编码,不强制重命名 |
| 7z 未安装 | 通知附 `brew install p7zip` 提示 |

## 8. 测试策略

- **单元测试**(CoreKit,`swift test`):乱码检测/修复、重命名规则生成、路径工具
- **手动验收清单**:每个菜单项在 Finder 实测,覆盖多选、无选中、只读目录、中文/空格文件名

## 9. 明确不做(YAGNI)

- 不做 App Store 分发 / 公证
- 不做多语言(界面中文)
- 不做自动更新
- MVP 不做用户自定义模板上传
- 不做菜单图标自定义(内置固定图标)
