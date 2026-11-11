# RightClickKit

自用 macOS Finder 右键增强工具:主 App + Finder Sync 扩展,在 Finder 右键菜单注入 13 个快捷功能。原生 Swift 实现,无第三方依赖,macOS 26 实测通过。

## 功能

| 功能 | 说明 |
|------|------|
| 新建文件 | 在当前位置新建 TXT / Markdown / Word / Excel / PPT 文档,支持自动进入重命名 |
| 新建文件夹 | 在当前位置新建文件夹 |
| 使用文件名新建文件夹 | 选中文件,以其文件名建文件夹并移入 |
| 打开终端 | 在当前文件夹打开终端;选中文件夹时打开该文件夹 |
| 剪切 | 剪切入队列,在目标文件夹右键「粘贴(移动到此处)」完成移动 |
| 拷贝路径 / 拷贝名称 | 复制选中项目的完整路径或名称;文件夹背景右键时拷当前文件夹路径 |
| 压缩为 zip | 多选支持,布局与 Finder「压缩」一致 |
| 压缩为 7z | 需先 `brew install p7zip` |
| 授予写入权限 | 递归解除锁定并给属主添加写权限 |
| 彻底删除 | 不进废纸篓直接删除,需勾选确认,不可恢复 |
| 批量重命名 | 前缀 / 后缀 / 序号 / 查找替换四种规则,实时预览与冲突警示 |
| 修复乱码文件名 | 检测 GBK↔UTF-8 乱码文件名并逐项改名 |

功能开关在主 App「设置 → 功能」中逐项启停,即时生效(无需重启 Finder)。

## 构建与安装

```bash
./build.sh
```

前置要求:

- **Command Line Tools**(`xcode-select --install`)—— 编译主 App 与 CoreKit
- **Xcode**(完整版)—— 扩展必须经 `xcodebuild` 构建并签名;实测 macOS 26 只收录 xcodebuild 产物,swiftc + codesign 手签的同等 appex 会被系统静默拒绝注册
- **Apple Development 证书**(免费 Apple ID 在 Xcode 登录即得)—— pluginkit 拒绝注册 ad-hoc 签名的沙盒扩展;检测不到证书时构建回退 ad-hoc,主 App 仍可运行,仅扩展无法注册
- 可用 `SIGN_IDENTITY="证书名"` 环境变量覆盖自动检测

构建完成后扩展自动注册。若右键菜单未出现,到「系统设置 → 扩展 → Finder 扩展」手动勾选 RightClickKit。

## 权限

- **Finder 扩展**:右键菜单入口,系统设置中启用
- **辅助功能(可选)**:授权后新建文件自动进入重命名;未授权不影响其余功能
- **主 App 非沙盒**:彻底删除、授予写权限等操作不受限
- **扩展沙盒**:macOS 26 强制(pluginkit 静默拒绝非沙盒 appex)

## 配置存储

功能开关存于 `~/Library/Application Support/RightClickKit/features.json`。不用 UserDefaults:主 App 与沙盒扩展的 suite 域相互隔离,JSON 文件是唯一跨进程共享通道。

## 已知限制

- 7z 压缩需自行 `brew install p7zip`,未安装时菜单项点击会提示
- ditto 打的 zip 不设 UTF-8 文件名标志:Mac 端解压无损,发 Windows 解压中文名会乱码
- 乱码修复覆盖 GBK↔UTF-8 误读(Latin-1/CP1252 形);CP437(□□□ 形)与大文件名场景不支持
- 修复乱码基于字节探测,极少数健康中文名可能出现在候选列表(确认前不改动)

## 项目结构

```
App/                 主 App(AppKit 入口 + SwiftUI 设置窗/操作窗)
FinderSyncExt/       Finder Sync 扩展(注入菜单 + 直接执行压缩/剪切等)
CoreKit/             SPM 纯逻辑包(PathUtils/FileWalker/RenameRules/MojibakeFixer/Zipper/FeatureStore)
  Sources/CoreKitTestRunner/   轻量测试执行器(CLT 无 XCTest,手写断言 harness)
ext.xcodeproj        扩展 target(CoreKit 源码经 COREKIT_IN_TARGET 直接编入同一 module)
Resources/           appex plist / entitlements / Office 模板
scripts/             模板与图标生成脚本(make_icon.swift 渲染 AppIcon.icns)
docs/                设计规格与实施计划(含 18 轮执行修订记录)
```

主 App 与扩展经 `rightclickkit://` URL scheme 通信(批量重命名/修复乱码唤起主 App 窗口,自动重命名发 Return 键)。

## 测试

```bash
cd CoreKit && swift run CoreKitTestRunner
```

39 个测试覆盖路径工具、文件遍历、重命名规则、乱码检测、zip 压缩(含中文文件名往返与多选重名)。

## 致谢

实现过程中参考了同类开源项目 FinderRight 与 RClick 的设计(zip 压缩策略、IPC 传参、设置页布局),在此致谢。
