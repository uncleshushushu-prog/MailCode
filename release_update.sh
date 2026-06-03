#!/bin/bash
# ===================================================
# MailCode 发布流水线
#
# 用法:
#   ./release_update.sh
#   ./release_update.sh --version 1.0.2 --build 3 --notes "修复问题"
#   ./release_update.sh --upload
#
# 输出:
#   build/releases/v<version>-<build>/MailCode.dmg
#   build/releases/v<version>-<build>/update-feed.json
#   build/releases/v<version>-<build>/appcast.xml
# ===================================================
set -euo pipefail

APP_NAME="MailCode"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="$SCRIPT_DIR/$APP_NAME.xcodeproj/project.pbxproj"
DMG_PATH="$SCRIPT_DIR/$APP_NAME.dmg"
SPARKLE_PUBLIC_KEY="1NNkdhrg0WRV/F8d9GT05s72eVwbGxCYFYLT0b2/cTs="
SPARKLE_ACCOUNT="MailCode"
UPLOAD=0
VERSION=""
BUILD=""
RELEASE_NOTES="优化体验并提升稳定性。"
GITHUB_REPO="uncleshushushu-prog/MailCode"

usage() {
    sed -n '2,20p' "$0"
}

current_version() {
    awk -F'= ' '/MARKETING_VERSION = / { gsub(/;| /, "", $2); print $2; exit }' "$PROJECT_FILE"
}

current_build() {
    awk -F'= ' '/CURRENT_PROJECT_VERSION = / { gsub(/;| /, "", $2); print $2; exit }' "$PROJECT_FILE"
}

next_patch_version() {
    local version="$1"
    IFS='.' read -r major minor patch <<< "$version"
    major="${major:-1}"
    minor="${minor:-0}"
    patch="${patch:-0}"
    printf '%s.%s.%s\n' "$major" "$minor" "$((patch + 1))"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --build)
            BUILD="${2:-}"
            shift 2
            ;;
        --notes)
            RELEASE_NOTES="${2:-}"
            shift 2
            ;;
        --upload)
            UPLOAD=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知参数: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    VERSION="$(current_version)"
fi

if [ -z "$BUILD" ]; then
    BUILD="$(current_build)"
fi

if ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
    echo "❌ build 必须是整数: $BUILD" >&2
    exit 1
fi

DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/latest/download/$APP_NAME.dmg"
LEGACY_FEED_URL="https://github.com/$GITHUB_REPO/releases/latest/download/update-feed.json"
APPCAST_URL="https://github.com/$GITHUB_REPO/releases/latest/download/appcast.xml"
RELEASE_DIR="$SCRIPT_DIR/build/releases/v$VERSION-$BUILD"
FEED_PATH="$RELEASE_DIR/update-feed.json"
APPCAST_PATH="$RELEASE_DIR/appcast.xml"
RELEASE_DMG="$RELEASE_DIR/$APP_NAME.dmg"
RELEASE_NOTES_PATH="$RELEASE_DIR/$APP_NAME.md"
TAG="v$VERSION"

echo "========================================"
echo " MailCode 发布流水线"
echo "========================================"
echo "版本: $VERSION"
echo "Build: $BUILD"
echo "旧更新源: $LEGACY_FEED_URL"
echo "Sparkle 更新源: $APPCAST_URL"
echo ""

echo "🧭 [1/5] 写入版本号与更新源..."
perl -0pi -e "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $BUILD;/g" "$PROJECT_FILE"
perl -0pi -e "s/MARKETING_VERSION = [0-9]+(?:\\.[0-9]+){1,2};/MARKETING_VERSION = $VERSION;/g" "$PROJECT_FILE"

if ! grep -q 'INFOPLIST_KEY_MailCodeUpdateFeedURL' "$PROJECT_FILE"; then
    perl -0pi -e "s/(GENERATE_INFOPLIST_FILE = YES;\\n)/\\1\\t\\t\\t\\tINFOPLIST_KEY_MailCodeUpdateFeedURL = \"$LEGACY_FEED_URL\";\\n/g" "$PROJECT_FILE"
else
    perl -0pi -e "s#INFOPLIST_KEY_MailCodeUpdateFeedURL = \".*?\";#INFOPLIST_KEY_MailCodeUpdateFeedURL = \"$LEGACY_FEED_URL\";#g" "$PROJECT_FILE"
fi

if ! grep -q 'INFOPLIST_KEY_SUFeedURL' "$PROJECT_FILE"; then
    perl -0pi -e "s/(INFOPLIST_KEY_NSHumanReadableCopyright = \"\";\\n)/\\1\\t\\t\\t\\tINFOPLIST_KEY_SUEnableInstallerLauncherService = YES;\\n\\t\\t\\t\\tINFOPLIST_KEY_SUFeedURL = \"$APPCAST_URL\";\\n\\t\\t\\t\\tINFOPLIST_KEY_SUPublicEDKey = \"$SPARKLE_PUBLIC_KEY\";\\n/g" "$PROJECT_FILE"
else
    perl -0pi -e "s#INFOPLIST_KEY_SUFeedURL = \".*?\";#INFOPLIST_KEY_SUFeedURL = \"$APPCAST_URL\";#g" "$PROJECT_FILE"
    perl -0pi -e "s#INFOPLIST_KEY_SUPublicEDKey = \".*?\";#INFOPLIST_KEY_SUPublicEDKey = \"$SPARKLE_PUBLIC_KEY\";#g" "$PROJECT_FILE"
fi

if ! grep -q 'INFOPLIST_KEY_SUEnableInstallerLauncherService' "$PROJECT_FILE"; then
    perl -0pi -e "s/(INFOPLIST_KEY_NSHumanReadableCopyright = \"\";\\n)/\\1\\t\\t\\t\\tINFOPLIST_KEY_SUEnableInstallerLauncherService = YES;\\n/g" "$PROJECT_FILE"
fi

echo "✅ 版本配置完成"

echo ""
echo "🔨 [2/5] 构建 DMG..."
"$SCRIPT_DIR/build_dist.sh"

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ 构建失败: $DMG_PATH 不存在" >&2
    exit 1
fi

echo ""
echo "🧾 [3/5] 生成发布目录与更新清单..."
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
cp "$DMG_PATH" "$RELEASE_DMG"
printf '%s\n' "$RELEASE_NOTES" > "$RELEASE_NOTES_PATH"

python3 - "$FEED_PATH" "$VERSION" "$BUILD" "$DOWNLOAD_URL" "$RELEASE_NOTES" <<'PY'
import json
import sys

path, version, build, download_url, release_notes = sys.argv[1:]
with open(path, "w", encoding="utf-8") as f:
    json.dump(
        {
            "version": version,
            "build": int(build),
            "download_url": download_url,
            "release_notes": release_notes,
        },
        f,
        ensure_ascii=False,
        indent=2,
    )
    f.write("\n")
PY

echo "✅ 发布文件:"
echo "   $RELEASE_DMG"
echo "   $FEED_PATH"

GENERATE_APPCAST="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" -type f -print -quit)"
if [ -z "$GENERATE_APPCAST" ]; then
    echo "❌ 未找到 Sparkle generate_appcast。请先运行: xcodebuild -resolvePackageDependencies -project $APP_NAME.xcodeproj -scheme $APP_NAME" >&2
    exit 1
fi

"$GENERATE_APPCAST" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/$TAG/" \
    --embed-release-notes \
    --maximum-versions 0 \
    "$RELEASE_DIR"

if [ ! -f "$APPCAST_PATH" ]; then
    echo "❌ Sparkle appcast 生成失败: $APPCAST_PATH 不存在" >&2
    exit 1
fi

echo "   $APPCAST_PATH"

echo ""
echo "🧪 [4/5] 校验更新清单..."
python3 -m json.tool "$FEED_PATH" >/dev/null
echo "✅ JSON 有效"
python3 - "$APPCAST_PATH" <<'PY'
import sys
import xml.etree.ElementTree as ET
ET.parse(sys.argv[1])
PY
echo "✅ appcast XML 有效"

echo ""
echo "🚀 [5/5] 上传..."
if [ "$UPLOAD" -eq 0 ]; then
    echo "跳过上传。使用 --upload 可上传到 GitHub Releases。"
    echo ""
    echo "待上传文件:"
    echo "   $RELEASE_DMG"
    echo "   $FEED_PATH"
    echo "   $APPCAST_PATH"
    echo ""
    echo "上传后 App 会读取:"
    echo "   $APPCAST_URL"
else
    if ! command -v gh >/dev/null 2>&1; then
        echo "❌ 未安装 GitHub CLI: gh" >&2
        exit 1
    fi

    if ! gh auth status >/dev/null 2>&1; then
        echo "❌ GitHub CLI 未登录或 token 已失效。请先运行: gh auth login -h github.com" >&2
        exit 1
    fi

    if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
        gh release upload "$TAG" "$RELEASE_DMG" "$FEED_PATH" "$APPCAST_PATH" --repo "$GITHUB_REPO" --clobber
        gh release edit "$TAG" --repo "$GITHUB_REPO" --latest
    else
        gh release create "$TAG" "$RELEASE_DMG" "$FEED_PATH" "$APPCAST_PATH" \
            --repo "$GITHUB_REPO" \
            --title "$APP_NAME $VERSION" \
            --notes "$RELEASE_NOTES" \
            --latest
    fi

    echo "✅ 已上传到 GitHub Releases: $TAG"
fi

echo ""
echo "========================================"
echo " ✅ 发布流水线完成"
echo "========================================"
