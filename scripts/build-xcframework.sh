#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SCHEME="NeptuneSDKiOS"
FRAMEWORK_NAME=""
CONFIGURATION="Release"
BUILD_LIBRARY_FOR_DISTRIBUTION="NO"
OUTPUT_PATH=""
ARCHIVES_DIR=""
DERIVED_DATA_PATH=""
STAGING_DIR=""
SKIP_DEPENDENCY_CHECK=0
CHECK_RUNTIME_DEPENDENCIES_ONLY_PATH=""
ALLOW_RUNTIME_DEPENDENCIES=()

usage() {
  cat <<'EOF'
Usage:
  bash scripts/build-xcframework.sh [options]

Options:
  --scheme <name>                     Xcode scheme，默认 NeptuneSDKiOS
  --framework-name <name>             framework 名称，默认与 scheme 相同
  --configuration <name>              构建配置，默认 Release
  --build-library-for-distribution <YES|NO>
                                      是否启用 BUILD_LIBRARY_FOR_DISTRIBUTION（默认 NO）
  --output <path>                     xcframework 输出路径
  --archives-dir <path>               archive 目录
  --derived-data-path <path>          DerivedData 目录
  --allow-runtime-dependency <name>   允许的运行时动态依赖（可重复）
  --skip-dependency-check             跳过 otool 依赖检查
  --check-runtime-dependencies-only <xcframework-path>
                                      仅执行运行时依赖检查并退出（用于验证/测试）
  --help                              显示帮助
EOF
}

die() {
  echo "[xcframework] error: $*" >&2
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

write_framework_info_plist() {
  local plist_path="$1"
  cat >"$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${FRAMEWORK_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.neptunekit.${FRAMEWORK_NAME}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${FRAMEWORK_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
EOF
}

contains_allowlisted_dependency() {
  local dependency="$1"
  local dependency_basename
  dependency_basename="$(basename "$dependency")"
  local allowed
  for allowed in "${ALLOW_RUNTIME_DEPENDENCIES[@]-}"; do
    [[ -z "$allowed" ]] && continue
    if [[ "$dependency" == *"$allowed"* ]] || [[ "$dependency_basename" == "$allowed" ]]; then
      return 0
    fi
  done
  return 1
}

is_allowed_dependency() {
  local dependency="$1"
  local self_framework="$2"

  if [[ "$dependency" == "@rpath/${self_framework}.framework/${self_framework}" ]]; then
    return 0
  fi

  if [[ "$dependency" == /System/Library/* ]] || [[ "$dependency" == /usr/lib/* ]] || [[ "$dependency" == /Developer/* ]]; then
    return 0
  fi

  if [[ "$dependency" == @rpath/libswift* ]] || [[ "$dependency" == @loader_path/Frameworks/libswift* ]] || [[ "$dependency" == @executable_path/Frameworks/libswift* ]]; then
    return 0
  fi

  if contains_allowlisted_dependency "$dependency"; then
    return 0
  fi

  return 1
}

archive_for_destination() {
  local destination="$1"
  local archive_path="$2"
  local derived_data_path="$3"

  xcodebuild \
    archive \
    -scheme "$SCHEME" \
    -destination "$destination" \
    -archivePath "$archive_path" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$derived_data_path" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION="$BUILD_LIBRARY_FOR_DISTRIBUTION"
}

find_framework_path() {
  local archive_path="$1"
  local framework_path
  framework_path="$(find "$archive_path/Products" -type d -name "${FRAMEWORK_NAME}.framework" | head -n 1 || true)"
  echo "$framework_path"
}

build_static_framework_from_archive() {
  local archive_path="$1"
  local derived_data_path="$2"
  local release_folder="$3"
  local tag="$4"

  local objects_dir
  objects_dir="$(find "$archive_path/Products" -type d -name Objects | head -n 1 || true)"
  [[ -n "$objects_dir" ]] || die "未找到静态产物目录（Objects）: $archive_path"

  local build_products_path="$derived_data_path/Build/Intermediates.noindex/ArchiveIntermediates/$SCHEME/BuildProductsPath/$release_folder"
  local swiftmodule_dir="$build_products_path/${FRAMEWORK_NAME}.swiftmodule"
  [[ -d "$swiftmodule_dir" ]] || die "未找到 Swift 模块目录: $swiftmodule_dir"

  local output_framework="$STAGING_DIR/$tag/${FRAMEWORK_NAME}.framework"
  local output_binary="$output_framework/$FRAMEWORK_NAME"
  rm -rf "$output_framework"
  mkdir -p "$output_framework/Modules/${FRAMEWORK_NAME}.swiftmodule"

  local object_files=()
  while IFS= read -r object_file; do
    object_files+=("$object_file")
  done < <(find "$objects_dir" -type f -name '*.o' | sort)

  if [[ "${#object_files[@]}" -eq 0 ]]; then
    die "Objects 目录里没有 .o 文件: $objects_dir"
  fi

  xcrun libtool -static -o "$output_binary" "${object_files[@]}"
  cp "$swiftmodule_dir"/* "$output_framework/Modules/${FRAMEWORK_NAME}.swiftmodule/"
  write_framework_info_plist "$output_framework/Info.plist"
  echo "$output_framework"
}

assemble_framework_for_platform() {
  local archive_path="$1"
  local derived_data_path="$2"
  local release_folder="$3"
  local tag="$4"

  local framework_path
  framework_path="$(find_framework_path "$archive_path")"
  if [[ -n "$framework_path" ]]; then
    echo "$framework_path"
    return 0
  fi

  echo "[xcframework] archive 未直接产出 ${FRAMEWORK_NAME}.framework，改用静态产物组装..." >&2
  build_static_framework_from_archive "$archive_path" "$derived_data_path" "$release_folder" "$tag"
}

check_runtime_dependencies() {
  local xcframework_path="$1"
  local inspected_count=0
  local leaks=()
  local framework_dir
  while IFS= read -r framework_dir; do
    local binary_path="${framework_dir}/${FRAMEWORK_NAME}"
    if [[ ! -f "$binary_path" ]]; then
      continue
    fi
    inspected_count=$((inspected_count + 1))
    local dependency
    while IFS= read -r dependency; do
      [[ -z "$dependency" ]] && continue
      if [[ "$dependency" == "$binary_path"*"("*.o")" ]]; then
        continue
      fi
      # 静态产物经 otool -L 输出时会包含 "binary(member.o):" 之类条目，需跳过。
      if [[ "$dependency" != /* ]] && [[ "$dependency" != @rpath/* ]] && [[ "$dependency" != @loader_path/* ]] && [[ "$dependency" != @executable_path/* ]]; then
        continue
      fi
      if ! is_allowed_dependency "$dependency" "$FRAMEWORK_NAME"; then
        leaks+=("${binary_path} -> ${dependency}")
      fi
    done < <(otool -L "$binary_path" | tail -n +2 | awk '{print $1}')
  done < <(find "$xcframework_path" -type d -name "${FRAMEWORK_NAME}.framework")

  if [[ "$inspected_count" -eq 0 ]]; then
    die "未在 xcframework 中找到可检查的二进制: $xcframework_path"
  fi

  if [[ "${#leaks[@]}" -gt 0 ]]; then
    echo "[xcframework] 检测到非系统动态依赖（可能未被静态集成）：" >&2
    local leak
    for leak in "${leaks[@]}"; do
      echo "  - $leak" >&2
    done
    echo "[xcframework] 如确认依赖需动态分发，可通过 --allow-runtime-dependency 放行。" >&2
    exit 1
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --scheme)
      [[ "$#" -ge 2 ]] || die "--scheme 需要参数"
      SCHEME="$2"
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
    --output)
      [[ "$#" -ge 2 ]] || die "--output 需要参数"
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --archives-dir)
      [[ "$#" -ge 2 ]] || die "--archives-dir 需要参数"
      ARCHIVES_DIR="$2"
      shift 2
      ;;
    --derived-data-path)
      [[ "$#" -ge 2 ]] || die "--derived-data-path 需要参数"
      DERIVED_DATA_PATH="$2"
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
    --check-runtime-dependencies-only)
      [[ "$#" -ge 2 ]] || die "--check-runtime-dependencies-only 需要参数"
      CHECK_RUNTIME_DEPENDENCIES_ONLY_PATH="$2"
      shift 2
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

if [[ -n "$CHECK_RUNTIME_DEPENDENCIES_ONLY_PATH" ]]; then
  if ! command -v otool >/dev/null 2>&1; then
    die "未找到 otool，请先安装 Xcode Command Line Tools"
  fi
  CHECK_RUNTIME_DEPENDENCIES_ONLY_PATH="$(resolve_path "$CHECK_RUNTIME_DEPENDENCIES_ONLY_PATH")"
  check_runtime_dependencies "$CHECK_RUNTIME_DEPENDENCIES_ONLY_PATH"
  echo "[xcframework] runtime dependency check passed: $CHECK_RUNTIME_DEPENDENCIES_ONLY_PATH"
  exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  die "未找到 xcodebuild，请先安装 Xcode Command Line Tools"
fi

if [[ "$SKIP_DEPENDENCY_CHECK" -eq 0 ]] && ! command -v otool >/dev/null 2>&1; then
  die "未找到 otool，请先安装 Xcode Command Line Tools"
fi

if [[ -z "$FRAMEWORK_NAME" ]]; then
  FRAMEWORK_NAME="$SCHEME"
fi

if [[ -z "$OUTPUT_PATH" ]]; then
  OUTPUT_PATH="$ROOT/.build/artifacts/${FRAMEWORK_NAME}.xcframework"
fi
if [[ -z "$ARCHIVES_DIR" ]]; then
  ARCHIVES_DIR="$ROOT/.build/xcframework-archives"
fi
if [[ -z "$DERIVED_DATA_PATH" ]]; then
  DERIVED_DATA_PATH="$ROOT/.build/xcframework-derived-data"
fi
if [[ -z "$STAGING_DIR" ]]; then
  STAGING_DIR="$ROOT/.build/xcframework-staging"
fi

OUTPUT_PATH="$(resolve_path "$OUTPUT_PATH")"
ARCHIVES_DIR="$(resolve_path "$ARCHIVES_DIR")"
DERIVED_DATA_PATH="$(resolve_path "$DERIVED_DATA_PATH")"
STAGING_DIR="$(resolve_path "$STAGING_DIR")"

mkdir -p "$ARCHIVES_DIR" "$DERIVED_DATA_PATH" "$STAGING_DIR" "$(dirname "$OUTPUT_PATH")"

IOS_ARCHIVE_PATH="$ARCHIVES_DIR/${FRAMEWORK_NAME}-ios.xcarchive"
SIM_ARCHIVE_PATH="$ARCHIVES_DIR/${FRAMEWORK_NAME}-ios-simulator.xcarchive"
IOS_DERIVED_DATA_PATH="$DERIVED_DATA_PATH/ios"
SIM_DERIVED_DATA_PATH="$DERIVED_DATA_PATH/simulator"
IOS_RELEASE_FOLDER="${CONFIGURATION}-iphoneos"
SIM_RELEASE_FOLDER="${CONFIGURATION}-iphonesimulator"

rm -rf "$IOS_ARCHIVE_PATH" "$SIM_ARCHIVE_PATH" "$OUTPUT_PATH" "$IOS_DERIVED_DATA_PATH" "$SIM_DERIVED_DATA_PATH" "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

echo "[xcframework] archive iOS device..."
archive_for_destination "generic/platform=iOS" "$IOS_ARCHIVE_PATH" "$IOS_DERIVED_DATA_PATH"

echo "[xcframework] archive iOS simulator..."
archive_for_destination "generic/platform=iOS Simulator" "$SIM_ARCHIVE_PATH" "$SIM_DERIVED_DATA_PATH"

IOS_FRAMEWORK_PATH="$(assemble_framework_for_platform "$IOS_ARCHIVE_PATH" "$IOS_DERIVED_DATA_PATH" "$IOS_RELEASE_FOLDER" "ios")"
SIM_FRAMEWORK_PATH="$(assemble_framework_for_platform "$SIM_ARCHIVE_PATH" "$SIM_DERIVED_DATA_PATH" "$SIM_RELEASE_FOLDER" "simulator")"

echo "[xcframework] create xcframework..."
create_xcframework_args=(
  -create-xcframework
)

if [[ "$BUILD_LIBRARY_FOR_DISTRIBUTION" == "NO" ]]; then
  create_xcframework_args+=(-allow-internal-distribution)
fi

create_xcframework_args+=(
  -framework "$IOS_FRAMEWORK_PATH"
  -framework "$SIM_FRAMEWORK_PATH"
  -output "$OUTPUT_PATH"
)

xcodebuild "${create_xcframework_args[@]}"

if [[ "$SKIP_DEPENDENCY_CHECK" -eq 0 ]]; then
  echo "[xcframework] check runtime dependencies..."
  check_runtime_dependencies "$OUTPUT_PATH"
fi

echo "[xcframework] done: $OUTPUT_PATH"
