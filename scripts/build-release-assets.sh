#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

RELEASE_TAG=""
FRAMEWORK_NAME="NeptuneSDKiOS"
CONFIGURATION="Release"
BUILD_LIBRARY_FOR_DISTRIBUTION="NO"
OUTPUT_DIR="$ROOT/.build/artifacts/release"
SKIP_DEPENDENCY_CHECK=0
DRY_RUN=0
ALLOW_RUNTIME_DEPENDENCIES=()

usage() {
  cat <<'EOF'
Usage:
  bash scripts/build-release-assets.sh [options]

Options:
  --tag <name>                        release 版本号（例如 v1.2.3 或 2026.3.14.1，默认当天日期并自动递增）
  --framework-name <name>             framework 名称，默认 NeptuneSDKiOS
  --configuration <name>              构建配置，默认 Release
  --build-library-for-distribution <YES|NO>
                                      透传到 xcframework 构建脚本（默认 NO）
  --output-dir <path>                 发布产物目录，默认 .build/artifacts/release
  --allow-runtime-dependency <name>   允许的运行时动态依赖（可重复）
  --skip-dependency-check             跳过 otool 依赖检查
  --dry-run                           仅做参数校验并输出产物路径，不执行构建
  --help                              显示帮助
EOF
}

die() {
  echo "[release-assets] error: $*" >&2
  exit 1
}

resolve_path() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    echo "$path"
  else
    echo "$ROOT/$path"
  fi
}

release_tag_exists() {
  local tag="$1"
  local asset_path="$OUTPUT_DIR/${FRAMEWORK_NAME}-${tag}.xcframework.zip"

  if [[ -f "$asset_path" ]]; then
    return 0
  fi

  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$ROOT" tag --list "$tag" | grep -Fxq "$tag"; then
      return 0
    fi
  fi

  return 1
}

next_date_release_tag() {
  local base_tag="${NEPTUNE_RELEASE_DATE_BASE:-$(date '+%Y.%-m.%-d')}"
  local candidate="$base_tag"
  local suffix=1

  while release_tag_exists "$candidate"; do
    candidate="${base_tag}.${suffix}"
    suffix=$((suffix + 1))
  done

  echo "$candidate"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ "$#" -ge 2 ]] || die "--tag 需要参数"
      RELEASE_TAG="$2"
      shift 2
      ;;
    --framework-name)
      [[ "$#" -ge 2 ]] || die "--framework-name 需要参数"
      FRAMEWORK_NAME="$2"
      shift 2
      ;;
    --configuration)
      [[ "$#" -ge 2 ]] || die "--configuration 需要参数"
      CONFIGURATION="$2"
      shift 2
      ;;
    --build-library-for-distribution)
      [[ "$#" -ge 2 ]] || die "--build-library-for-distribution 需要参数"
      case "$2" in
        YES|NO)
          BUILD_LIBRARY_FOR_DISTRIBUTION="$2"
          ;;
        *)
          die "--build-library-for-distribution 只接受 YES 或 NO"
          ;;
      esac
      shift 2
      ;;
    --output-dir)
      [[ "$#" -ge 2 ]] || die "--output-dir 需要参数"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --allow-runtime-dependency)
      [[ "$#" -ge 2 ]] || die "--allow-runtime-dependency 需要参数"
      ALLOW_RUNTIME_DEPENDENCIES+=("$2")
      shift 2
      ;;
    --skip-dependency-check)
      SKIP_DEPENDENCY_CHECK=1
      shift 1
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

if [[ -z "$RELEASE_TAG" ]]; then
  RELEASE_TAG="$(next_date_release_tag)"
fi

if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] && [[ ! "$RELEASE_TAG" =~ ^[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}(\.[0-9]+)?$ ]]; then
  die "release tag must match ^v[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$ or ^[0-9]{4}\\.[0-9]{1,2}\\.[0-9]{1,2}(\\.[0-9]+)?$"
fi

OUTPUT_DIR="$(resolve_path "$OUTPUT_DIR")"
XCFRAMEWORK_PATH="$OUTPUT_DIR/${FRAMEWORK_NAME}.xcframework"
ZIP_PATH="$OUTPUT_DIR/${FRAMEWORK_NAME}-${RELEASE_TAG}.xcframework.zip"
CHECKSUM_PATH="${ZIP_PATH}.sha256"

echo "[release-assets] release_tag=$RELEASE_TAG"
echo "[release-assets] xcframework_path=$XCFRAMEWORK_PATH"
echo "[release-assets] zip_path=$ZIP_PATH"
echo "[release-assets] checksum_path=$CHECKSUM_PATH"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[release-assets] dry-run: skip build/package."
  exit 0
fi

mkdir -p "$OUTPUT_DIR"

build_args=(
  --framework-name "$FRAMEWORK_NAME"
  --configuration "$CONFIGURATION"
  --build-library-for-distribution "$BUILD_LIBRARY_FOR_DISTRIBUTION"
  --output "$XCFRAMEWORK_PATH"
)

if [[ "$SKIP_DEPENDENCY_CHECK" -eq 1 ]]; then
  build_args+=(--skip-dependency-check)
fi

for allowed in "${ALLOW_RUNTIME_DEPENDENCIES[@]-}"; do
  [[ -z "$allowed" ]] && continue
  build_args+=(--allow-runtime-dependency "$allowed")
done

bash "$ROOT/scripts/build-xcframework.sh" "${build_args[@]}"

rm -f "$ZIP_PATH" "$CHECKSUM_PATH"
ditto -c -k --sequesterRsrc --keepParent "$XCFRAMEWORK_PATH" "$ZIP_PATH"

checksum="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$checksum" "$(basename "$ZIP_PATH")" > "$CHECKSUM_PATH"

echo "[release-assets] done"
echo "[release-assets] zip_path=$ZIP_PATH"
echo "[release-assets] checksum_path=$CHECKSUM_PATH"
