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

echo "==> ad-hoc 签名(先内后外)"
codesign --force --sign - "$APP/Contents/PlugIns/FinderSyncExt.appex"
codesign --force --sign - "$APP"

echo "==> 注册扩展"
pluginkit -a "$APP" || echo "(pluginkit -a 非致命失败,可忽略,系统会自行发现)"

codesign -dv "$APP" 2>&1 | head -2
echo "完成:$APP"
echo "首次使用:右键 $APP → 打开;然后到 系统设置 → 登录项与扩展 → 扩展 → Finder 扩展 勾选 RightClickKit。"
