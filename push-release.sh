#!/usr/bin/env bash
# 把编译好的 APK 推到 kevin521024/Release 仓库的 baobao 分支
# 用法: ./push-release.sh <versionCode> <versionName> [desc]
# 示例: ./push-release.sh 564 5.6.4 "首个发布版本"
set -euo pipefail

OWNER="kevin521024"
REPO="Release"
BRANCH="baobao"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 必填参数
VCODE="${1:?用法: $0 <versionCode> <versionName> [desc]}"
VNAME="${2:?用法: $0 <versionCode> <versionName> [desc]}"
DESC="${3:-饱饱影音 发布版本}"

# 找到编译输出目录（README 写的是 Release/apk/，也兼容 app/build/outputs/apk/）
APK_DIR="$REPO_ROOT/Release/apk"
if [ ! -d "$APK_DIR" ]; then
    APK_DIR="$REPO_ROOT/app/build/outputs/apk"
fi
[ -d "$APK_DIR" ] || { echo "❌ 找不到 APK 输出目录: $APK_DIR"; exit 1; }

# 检查 gh 是否登录
gh auth status >/dev/null 2>&1 || { echo "❌ gh 未登录，请先 gh auth login"; exit 1; }

# 列出所有 APK
echo "🔍 扫描 APK..."
mapfile -t APK_FILES < <(find "$APK_DIR" -name "*release*.apk" -o -name "*.apk" 2>/dev/null | sort -u)
[ ${#APK_FILES[@]} -gt 0 ] || { echo "❌ 没有找到任何 .apk 文件"; exit 1; }

# 通过文件名推断 flavor-abi（leanback-arm64_v8a.apk 这种命名）
for f in "${APK_FILES[@]}"; do
    base=$(basename "$f" .apk)
    # 去掉 -release / -unsigned 等后缀
    base=$(echo "$base" | sed -E 's/-(release|unsigned|signed|v[0-9]+)//g')
    echo "  - $base"
done

echo ""
echo "📦 即将上传到 https://github.com/$OWNER/$REPO/tree/$BRANCH/apk"
echo "   版本: $VNAME (code=$VCODE)"
echo "   说明: $DESC"
echo ""
read -p "确认上传? [y/N] " ans
[ "$ans" = "y" ] || { echo "已取消"; exit 0; }

# 用临时目录 clone 仓库
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

echo "⬇️ 克隆 $REPO 仓库..."
gh repo clone "$OWNER/$REPO" "$TMP" -- --depth 1 -b "$BRANCH" 2>&1 | sed 's/^/  /'
cd "$TMP"
mkdir -p apk

# 复制 APK 并重命名（去掉 release/unsigned 等后缀，保留 leanback-arm64_v8a 这种命名）
for f in "${APK_FILES[@]}"; do
    base=$(basename "$f" .apk)
    base=$(echo "$base" | sed -E 's/-(release|unsigned|signed|v[0-9]+)//g')
    cp "$f" "apk/$base.apk"
    echo "  ✓ $base.apk"
done

# 生成/更新 json 元数据
for json_file in apk/*.json; do
    [ -f "$json_file" ] || continue
    name=$(basename "$json_file" .json)
    cat > "$json_file" <<EOF
{
  "code": $VCODE,
  "name": "$VNAME",
  "desc": "$DESC"
}
EOF
    echo "  ✓ $name.json"
done

# 提交并推送
git add apk/
git commit -m "Release $VNAME (code $VCODE)" >/dev/null
echo "⬆️ 推送中..."
git push origin "$BRANCH" 2>&1 | sed 's/^/  /'

echo ""
echo "✅ 完成"
echo "   查看更新源: https://raw.githubusercontent.com/$OWNER/$REPO/$BRANCH/apk/"
