#!/bin/bash
# 一键构建:CoreKit(release)→ 主 App 二进制 → 扩展二进制 → 组装 bundle → 签名(默认 ad-hoc,可用 SIGN_IDENTITY 覆盖)→ 自检 → 注册
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_ID="com.yaowl.RightClickKit"
BUILD="$ROOT/.build/app"
APP="$BUILD/RightClickKit.app"
# 签名身份:自动检测 Apple Development 证书(macOS 26 的 pluginkit 拒绝注册 ad-hoc 签名的 appex);
# 检测不到时回退 ad-hoc(主 App 仍可运行,仅扩展无法注册);SIGN_IDENTITY 环境变量可强制覆盖
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"')}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="-"
fi

command -v swiftc >/dev/null || { echo "错误:未找到 swiftc,请先 xcode-select --install"; exit 1; }
# xcodebuild 必须用全路径:PATH 里 CLT 的同名 stub 会报错(仅 CLT 环境无真正 xcodebuild)
XB=""
[ -x "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" ] && \
  XB="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"

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
# appex 必须由 xcodebuild 构建并自动签名:实测 macOS 26 的 LS/pkd 只收录 xcodebuild 产物,
# swiftc+codesign 手签的同等内容(含 DER entitlements)会被静默拒绝,且原因与证书类型无关。
# xcodebuild 产物自带 Info.plist(含签名封印)与模板资源,不得再向内拷贝文件
if [ -n "$XB" ]; then
  "$XB" -project "$ROOT/ext.xcodeproj" -target FinderSyncExt -configuration Release \
    build SYMROOT="$ROOT/.build/extbuild" -quiet
  rm -rf "$APP/Contents/PlugIns/FinderSyncExt.appex"
  cp -R "$ROOT/.build/extbuild/Release/FinderSyncExt.appex" "$APP/Contents/PlugIns/"
else
  # 回退:仅 CLT 时仍可产出能运行的主 App;扩展签名合格但 LS 不收录,无法注册
  echo "警告:未找到 xcodebuild,扩展将无法注册(仅主 App 可用)" >&2
  # appex 无 main.swift,入口用 Foundation 的 _NSExtensionMain(系统经 Info.plist
  # NSExtensionPrincipalClass 实例化扩展主类,与 Xcode 的 appex 链接方式一致)
  swiftc -O -module-name FinderSyncExt \
    -I "$ROOT/CoreKit/.build/release/Modules" \
    -L "$ROOT/CoreKit/.build/release" -lCoreKit \
    "$ROOT"/FinderSyncExt/*.swift \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/MacOS/FinderSyncExt"
  cp "$ROOT/Resources/Ext-Info.plist" "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/Info.plist"
  cp "$ROOT"/Resources/Templates/template.* \
     "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/Resources/"
fi

echo "==> 写入 plist 与模板资源"
cp "$ROOT/Resources/App-Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"

echo "==> 签名(先内后外,身份:$SIGN_IDENTITY)"
if [ -n "$XB" ]; then
  # xcodebuild 产物保留其自动签名(appex 内含 app-sandbox entitlement);
  # 仅重签主 App 外壳,避免 CLI 重签覆盖扩展的合格签名
  # -o runtime:Hardened Runtime,防 DYLD_INSERT_LIBRARIES 注入继承我们的辅助功能授权
  codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
else
  # appex 必须带 app-sandbox entitlement:macOS 26 的 pluginkit 静默拒绝非沙盒 Finder Sync 扩展
  codesign --force --entitlements "$ROOT/Resources/Ext.entitlements" --sign "$SIGN_IDENTITY" \
    "$APP/Contents/PlugIns/FinderSyncExt.appex"
  # 主 App 同样启用 Hardened Runtime(两分支统一),否则下方自检会硬失败
  codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
fi

echo "==> 自检(签名与 plist,先内后外)"
codesign --verify --deep --strict "$APP/Contents/PlugIns/FinderSyncExt.appex"
codesign --verify --deep --strict "$APP"
# Hardened Runtime 必须真实存在(-o runtime 被忽略时静默缺失)
codesign -dv "$APP" 2>&1 | grep -q "runtime" || { echo "错误:主 App 未启用 Hardened Runtime"; exit 1; }
plutil -lint "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/PlugIns/FinderSyncExt.appex/Contents/Info.plist"

echo "==> 注册扩展"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
# 已注册且版本未变时跳过重注册:重复 pluginkit -a 会重启扩展并重排选举(丢角标归属);
# 版本变了或未注册时才走全量注销→强扫→注册→选举→重启 pkd
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
MARKER="$BUILD/.registered-v$VER"
if [ -f "$MARKER" ] && pluginkit -m | grep -q "$APP_ID.FinderSyncExt"; then
  echo "==> 扩展已注册且版本未变(v$VER),跳过重注册"
  pluginkit -e use -i "$APP_ID.FinderSyncExt" 2>/dev/null || true
else
  # LS/pkd 注册是异步的且对旧记录有缓存:注销→强扫→注册→置启用选举→重启 pkd 促进发现
  pluginkit -r "$APP" 2>/dev/null || true
  "$LSREG" -f "$APP" 2>/dev/null || true
  pluginkit -a "$APP" || true
  pluginkit -e use -i "$APP_ID.FinderSyncExt" 2>/dev/null || true
  killall pkd 2>/dev/null || true
  rm -f "$BUILD"/.registered-* 2>/dev/null || true
  touch "$MARKER"
  sleep 3
fi
# LS 收录 appex 的可靠触发方式是启动一次主 App;pkd 选举需要 LS 先收录
open "$APP" 2>/dev/null || true
sleep 3
if ! pluginkit -m | grep -q "$APP_ID.FinderSyncExt"; then
  echo "提示:扩展暂未出现在 pluginkit,请重跑本脚本。" >&2
fi

# 同 bundle ID 多拷贝注册会让 pluginkit 选举不稳定、菜单时有时无
DUP=$(pluginkit -m | grep -c "$APP_ID.FinderSyncExt" || true)
if [ "$DUP" -gt 1 ]; then
  echo "警告:检测到 $DUP 份扩展注册(选举不稳定,菜单可能时有时无):" >&2
  pluginkit -m | grep "$APP_ID.FinderSyncExt" >&2
  echo "请对旧路径执行:pluginkit -r <旧 .app 路径>" >&2
fi

codesign -dv "$APP" 2>&1 | head -2 || true
echo "完成:$APP"
echo "首次使用:右键 $APP → 打开;然后到 系统设置 → 登录项与扩展 → 扩展 → Finder 扩展 勾选 RightClickKit。"
