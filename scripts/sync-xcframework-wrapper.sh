#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=""
RELEASE_TAG=""
CHECKSUM=""
FRAMEWORK_NAME="NeptuneSDKiOS"
PACKAGE_FILE="Package.swift"
README_FILE="README.md"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  bash scripts/sync-xcframework-wrapper.sh [options]

Options:
  --repo-dir <path>                   wrapper 仓库目录
  --tag <name>                        release 版本号（SemVer，例如 1.2.3）
  --checksum <sha256>                 64 位十六进制 SHA256
  --framework-name <name>             framework 名称，默认 NeptuneSDKiOS
  --package-file <path>               相对 repo-dir 的 Package.swift 路径，默认 Package.swift
  --readme-file <path>                相对 repo-dir 的 README 路径，默认 README.md
  --dry-run                           仅校验并输出计划，不写文件
  --help                              显示帮助
EOF
}

die() {
  echo "[wrapper-sync] error: $*" >&2
  exit 1
}

resolve_repo_file() {
  local relative_path="$1"
  if [[ "$relative_path" == /* ]]; then
    echo "$relative_path"
  else
    echo "$REPO_DIR/$relative_path"
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --repo-dir)
      [[ "$#" -ge 2 ]] || die "--repo-dir 需要参数"
      REPO_DIR="$2"
      shift 2
      ;;
    --tag)
      [[ "$#" -ge 2 ]] || die "--tag 需要参数"
      RELEASE_TAG="$2"
      shift 2
      ;;
    --checksum)
      [[ "$#" -ge 2 ]] || die "--checksum 需要参数"
      CHECKSUM="$2"
      shift 2
      ;;
    --framework-name)
      [[ "$#" -ge 2 ]] || die "--framework-name 需要参数"
      FRAMEWORK_NAME="$2"
      shift 2
      ;;
    --package-file)
      [[ "$#" -ge 2 ]] || die "--package-file 需要参数"
      PACKAGE_FILE="$2"
      shift 2
      ;;
    --readme-file)
      [[ "$#" -ge 2 ]] || die "--readme-file 需要参数"
      README_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift 1
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      die "未知参数: $1（可用 --help 查看帮助）"
      ;;
  esac
done

[[ -n "$REPO_DIR" ]] || die "--repo-dir 为必填项"
[[ -d "$REPO_DIR" ]] || die "repo-dir 不存在: $REPO_DIR"
[[ -n "$RELEASE_TAG" ]] || die "--tag 为必填项"
[[ -n "$CHECKSUM" ]] || die "--checksum 为必填项"

if [[ ! "$RELEASE_TAG" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  die "release tag must be SemVer: X.Y.Z[-PRERELEASE][+BUILD]"
fi

if [[ ! "$CHECKSUM" =~ ^[0-9a-fA-F]{64}$ ]]; then
  die "checksum must be a 64-character hexadecimal SHA256"
fi

PACKAGE_PATH="$(resolve_repo_file "$PACKAGE_FILE")"
README_PATH="$(resolve_repo_file "$README_FILE")"

[[ -f "$PACKAGE_PATH" ]] || die "Package.swift 不存在: $PACKAGE_PATH"
[[ -f "$README_PATH" ]] || die "README 不存在: $README_PATH"

ZIP_NAME="${FRAMEWORK_NAME}-${RELEASE_TAG}.xcframework.zip"
NORMALIZED_CHECKSUM="$(printf '%s' "$CHECKSUM" | tr 'A-F' 'a-f')"

echo "[wrapper-sync] repo_dir=$REPO_DIR"
echo "[wrapper-sync] tag=$RELEASE_TAG"
echo "[wrapper-sync] checksum=$NORMALIZED_CHECKSUM"
echo "[wrapper-sync] zip_name=$ZIP_NAME"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[wrapper-sync] dry-run: skip file updates."
  exit 0
fi

perl -0pi -e 's/let releaseTag = "[^"]+"/let releaseTag = "'"$RELEASE_TAG"'"/g' "$PACKAGE_PATH"
perl -0pi -e 's/let binaryChecksum = "[^"]+"/let binaryChecksum = "'"$NORMALIZED_CHECKSUM"'"/g' "$PACKAGE_PATH"

perl -0pi -e 's/- Release tag: `[^`]+`/- Release tag: `'"$RELEASE_TAG"'`/g' "$README_PATH"
perl -0pi -e 's/- XCFramework zip: `[^`]+`/- XCFramework zip: `'"$ZIP_NAME"'`/g' "$README_PATH"
perl -0pi -e 's/- SHA256: `[^`]+`/- SHA256: `'"$NORMALIZED_CHECKSUM"'`/g' "$README_PATH"

grep -Fq "let releaseTag = \"$RELEASE_TAG\"" "$PACKAGE_PATH" || die "Package.swift 未成功写入 releaseTag"
grep -Fq "let binaryChecksum = \"$NORMALIZED_CHECKSUM\"" "$PACKAGE_PATH" || die "Package.swift 未成功写入 binaryChecksum"
grep -Fq -- "- Release tag: \`$RELEASE_TAG\`" "$README_PATH" || die "README 未成功写入 release tag"
grep -Fq -- "- XCFramework zip: \`$ZIP_NAME\`" "$README_PATH" || die "README 未成功写入 zip 名称"
grep -Fq -- "- SHA256: \`$NORMALIZED_CHECKSUM\`" "$README_PATH" || die "README 未成功写入 SHA256"

echo "[wrapper-sync] updated wrapper repo metadata"
