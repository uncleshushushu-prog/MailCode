#!/bin/bash
# ===================================================
# MailCode 分发构建脚本
# 用法: ./build_dist.sh
# 不需要开发者账号，使用 Ad-hoc 签名
# 自动生成带引导界面的专业 DMG
# ===================================================
set -euo pipefail

APP_NAME="MailCode"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build/dist"
APP_BUNDLE="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$SCRIPT_DIR/$APP_NAME.dmg"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
LEGACY_FEED_URL="https://github.com/uncleshushushu-prog/MailCode/releases/latest/download/update-feed.json"
SPARKLE_APPCAST_URL="https://github.com/uncleshushushu-prog/MailCode/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_KEY="1NNkdhrg0WRV/F8d9GT05s72eVwbGxCYFYLT0b2/cTs="
MOUNT_POINT=""

detach_existing_dmg_mounts() {
    local suffix
    for suffix in "" " 1" " 2" " 3" " 4" " 5"; do
        hdiutil detach "/Volumes/$APP_NAME$suffix" -quiet 2>/dev/null || true
    done
}

cleanup_on_error() {
    local exit_code=$?
    echo "❌ 构建脚本失败：第 $1 行，命令：$2" >&2
    if [ -n "${MOUNT_POINT:-}" ]; then
        hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    fi
    detach_existing_dmg_mounts
    exit "$exit_code"
}
trap 'cleanup_on_error "$LINENO" "$BASH_COMMAND"' ERR

echo "========================================"
echo " MailCode 分发构建"
echo "========================================"

# ═══════════════════════════════════════════
# 1. Release 构建
# ═══════════════════════════════════════════
echo ""
echo "🔨 [1/3] 构建 Release 版本..."

detach_existing_dmg_mounts
rm -rf "$BUILD_DIR"
xcodebuild -project "$SCRIPT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    build

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ 构建失败: $APP_BUNDLE 不存在"
    exit 1
fi
echo "   ✅ 构建完成"

# Xcode 会把临时构建产物注册到 LaunchServices，可能导致聚焦搜索里出现多个 MailCode。
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

set_plist_value() {
    local plist_path="$1"
    local key="$2"
    local type="$3"
    local value="$4"

    "$PLIST_BUDDY" -c "Set :$key $value" "$plist_path" 2>/dev/null \
        || "$PLIST_BUDDY" -c "Add :$key $type $value" "$plist_path"
}

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
set_plist_value "$INFO_PLIST" "MailCodeUpdateFeedURL" "string" "$LEGACY_FEED_URL"
set_plist_value "$INFO_PLIST" "SUFeedURL" "string" "$SPARKLE_APPCAST_URL"
set_plist_value "$INFO_PLIST" "SUPublicEDKey" "string" "$SPARKLE_PUBLIC_KEY"
set_plist_value "$INFO_PLIST" "SUEnableInstallerLauncherService" "bool" "true"
echo "   ✅ 更新配置已写入 Info.plist"

# ═══════════════════════════════════════════
# 2. Ad-hoc 重新签名
# ═══════════════════════════════════════════
echo ""
echo "✍️  [2/3] Ad-hoc 重新签名..."

# 清除 Xcode 自动签的旧签名（开发证书只有本机有效，别人用不了）
echo "   清除旧签名..."
codesign --remove-signature "$APP_BUNDLE" 2>/dev/null || true

find "$APP_BUNDLE" -type f \( -name "*.dylib" -o -path "*/Frameworks/*" \) 2>/dev/null | while read -r f; do
    codesign --remove-signature "$f" 2>/dev/null || true
done
find "$APP_BUNDLE" -name "*.framework" -type d 2>/dev/null | while read -r fw; do
    codesign --remove-signature "$fw" 2>/dev/null || true
done

# Ad-hoc 签名（- 表示无证书签名，但仍嵌入 entitlements 和 hardened runtime）
echo "   重新签名..."
ENTITLEMENTS="$SCRIPT_DIR/$APP_NAME/$APP_NAME.entitlements"

find "$APP_BUNDLE" -name "*.framework" -type d 2>/dev/null | while read -r fw; do
    codesign --force --deep --sign - --options=runtime \
        --entitlements "$ENTITLEMENTS" "$fw"
done

codesign --force --deep --sign - --options=runtime \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"

# 验证
echo "   验证签名..."
codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1
echo ""
echo "   验证 Entitlements..."
codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null || true
echo "   ✅ 签名完成！"

# ═══════════════════════════════════════════
# 3. 制作专业 DMG（带背景引导图）
# ═══════════════════════════════════════════
echo ""
echo "📦 [3/3] 制作 DMG..."

# 3a. 生成背景图（优先使用用户的图片）
USER_BG="$SCRIPT_DIR/dmg-background.png"
if [ -f "$USER_BG" ]; then
    echo "   使用自定义背景图: $USER_BG"
    cp "$USER_BG" "$BUILD_DIR/dmg-bg.png"
else
    echo "   自动生成引导背景图..."
    echo "   💡 你可放置 600x400 PNG 到 $USER_BG 使用自己的图"
    BG_SCRIPT="$BUILD_DIR/.gen_bg.swift"
    cat > "$BG_SCRIPT" << 'SWIFTEOF'
import Cocoa
let w = 600, h = 400
let image = NSImage(size: NSSize(width: w, height: h))
image.lockFocus()
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: w, height: h).fill()
let tAttr: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.black]
NSAttributedString(string: "安装 MailCode", attributes: tAttr).draw(at: NSPoint(x: 210, y: 340))
let sAttr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.gray]
NSAttributedString(string: "将 MailCode 拖入 Applications 文件夹", attributes: sAttr).draw(at: NSPoint(x: 170, y: 50))
NSColor(red: 0.2, green: 0.48, blue: 1.0, alpha: 0.7).setStroke()
let line = NSBezierPath()
line.lineWidth = 2.5; line.lineCapStyle = .round
line.move(to: NSPoint(x: 170, y: 200)); line.line(to: NSPoint(x: 400, y: 200)); line.stroke()
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 420, y: 200)); arrow.line(to: NSPoint(x: 390, y: 180))
arrow.move(to: NSPoint(x: 420, y: 200)); arrow.line(to: NSPoint(x: 390, y: 220))
arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.stroke()
image.unlockFocus()
guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let bmp = NSBitmapImageRep(cgImage: cg) as NSBitmapImageRep?,
      CommandLine.arguments.count > 1 else { exit(1) }
try bmp.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("done")
SWIFTEOF

    MODULE_CACHE="$TMPDIR/clang-module-cache"
    mkdir -p "$MODULE_CACHE"
    xcrun swift -module-cache-path "$MODULE_CACHE" "$BG_SCRIPT" "$BUILD_DIR/dmg-bg.png" 2>&1
    rm -f "$BG_SCRIPT"
fi

# 3b. 创建并配置 DMG
DMG_SRC="$BUILD_DIR/dmg-src"
DMG_TMP="$BUILD_DIR/$APP_NAME-tmp.dmg"
rm -rf "$DMG_SRC" "$DMG_TMP" "$DMG_PATH"
mkdir -p "$DMG_SRC"

cp -R "$APP_BUNDLE" "$DMG_SRC/"

cat > "$DMG_SRC/安装说明.txt" <<EOF
MailCode 安装说明

一、安装

1. 打开这个 DMG。
2. 将 MailCode 拖入 Applications 文件夹。

二、首次打开

如果 macOS 提示“无法验证开发者”或“无法检查是否包含恶意软件”，请按下面步骤处理：

1. 先确认 MailCode 已经拖入 Applications 文件夹。
2. 打开“终端”：
   - 按 Command + Space 打开聚焦搜索。
   - 输入“终端”或“Terminal”。
   - 回车打开。
3. 在终端中输入下面这行命令，然后回车：

xattr -dr com.apple.quarantine /Applications/MailCode.app

4. 命令执行完成后，打开 Applications 文件夹，双击 MailCode。

这一步的作用是移除 macOS 给下载 App 添加的隔离标记。它不会修改你的邮箱数据，也不会授予 MailCode 额外权限。
EOF

# 不要事先创建 Applications 链接（符号链接 Finder 无法定位）

# 先卸载可能残留的旧挂载
hdiutil detach "/Volumes/$APP_NAME" -quiet 2>/dev/null || true
detach_existing_dmg_mounts
sleep 1

# 创建 HFS+ 读写镜像（HFS+ 比 APFS 更稳定可靠）
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_SRC" \
    -ov -format UDRW -fs HFS+ -size 100m "$DMG_TMP"

# 挂载并获取实际挂载路径
ATTACH_OUTPUT=$(hdiutil attach "$DMG_TMP" -noverify -noautofsck)
printf '%s\n' "$ATTACH_OUTPUT"
MOUNT_POINT=$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/\/Volumes\// { print substr($0, index($0, "/Volumes/")); exit }')
if [ -z "$MOUNT_POINT" ]; then
    echo "❌ 无法获取 DMG 挂载点"
    exit 1
fi
echo "   挂载点: $MOUNT_POINT"

# 复制背景图并隐藏
cp "$BUILD_DIR/dmg-bg.png" "$MOUNT_POINT/.background.png"
SetFile -a V "$MOUNT_POINT/.background.png" 2>/dev/null || true

# 创建 Applications 别名（Finder 只能定位 alias，不能定位符号链接）
osascript <<EOSA
tell application "Finder"
    set aliasFile to make alias file to POSIX file "/Applications" at POSIX file "$MOUNT_POINT"
    set name of aliasFile to "Applications"
    return
end tell
EOSA

sleep 1

# 用 AppleScript 配置 Finder 窗口
osascript <<EOSC
tell application "Finder"
    set diskAlias to POSIX file "$MOUNT_POINT" as alias
    set backgroundAlias to POSIX file "$MOUNT_POINT/.background.png" as alias

    -- 打开卷并等待 Finder 刷新
    open diskAlias
    delay 2

    -- 通过卷名找到窗口
    set theWindow to container window of diskAlias
    delay 0.5

    -- 设置窗口属性
    set current view of theWindow to icon view
    try
        set toolbar visible of theWindow to false
    end try
    try
        set statusbar visible of theWindow to false
    end try
    try
        set bounds of theWindow to {200, 150, 800, 550}
    end try

    -- 设置图标位置
    try
        set position of item "$APP_NAME" of theWindow to {130, 330}
    end try
    try
        set position of item "Applications" of theWindow to {300, 330}
    end try
    try
        set position of item "安装说明.txt" of theWindow to {470, 330}
    end try

    -- 设置图标选项
    try
        set icon size of icon view options of theWindow to 64
        set text size of icon view options of theWindow to 12
        set background picture of icon view options of theWindow to backgroundAlias
    end try
end tell
EOSC

sleep 2
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
sleep 1

# 转成最终只读压缩格式
hdiutil convert "$DMG_TMP" -format UDZO -o "$DMG_PATH"

# 清理中间文件
rm -rf "$DMG_SRC" "$DMG_TMP" "$BUILD_DIR/dmg-bg.png"
rm -rf "$APP_BUNDLE" "$BUILD_DIR/Build/Products/Release/$APP_NAME.app.dSYM"

echo ""
echo "========================================"
echo " ✅ 全部完成！"
echo "========================================"
echo ""
echo "   分发文件: $DMG_PATH"
echo "   大小: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "📋 发给别人时，告知收件人："
echo "   1. 双击打开 DMG"
echo "   2. 将 MailCode 拖入 Applications 文件夹"
echo "   3. 如提示无法验证开发者，按安装说明执行 xattr 命令"
echo "   4. 打开 Applications 文件夹，双击 MailCode"
echo ""
