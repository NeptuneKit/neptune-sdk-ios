# NeptuneSDKiOS XCFramework 打包技术方案

关联需求：`docs-linhay/features/2026-03-24-xcframework-packaging.md`

## 方案概述

新增脚本 `scripts/build-xcframework.sh` 与 `scripts/build-release-assets.sh`，执行以下流程：

1. 分别 archive iOS 真机与 iOS Simulator 产物。
2. 优先从 archive 产物中定位 `NeptuneSDKiOS.framework`；若未产出 framework，则回退到 `.o + .swiftmodule` 自动组装静态 framework。
3. 使用 `xcodebuild -create-xcframework` 合并为单个 `NeptuneSDKiOS.xcframework`。
4. 对产物内二进制执行 `otool -L` 扫描，检查是否存在第三方动态依赖泄漏。
5. 发布场景下将 `xcframework` 打包为 zip，并生成 `sha256` 文件用于 release 附件分发。

## 关键设计

1. 默认产物输出到 `.build/artifacts/NeptuneSDKiOS.xcframework`，便于与现有脚本目录保持一致。
2. 默认启用依赖检查，支持 `--skip-dependency-check` 跳过（用于临时排障）。
3. 支持 `--allow-runtime-dependency <name>` 白名单，用于明确允许的运行时依赖。
4. 默认 `BUILD_LIBRARY_FOR_DISTRIBUTION=NO`，减少当前依赖在 archive 场景下的编译不稳定；如需开启 library evolution，可显式传 `--build-library-for-distribution YES`。
5. 当 `BUILD_LIBRARY_FOR_DISTRIBUTION=NO` 时，创建 xcframework 自动附加 `-allow-internal-distribution`，允许使用 `.swiftmodule` 进行内部二进制分发。
6. `build-release-assets.sh` 的 `--tag` 可选；当未传时默认使用当天日期版本（`YYYY.M.D`），若同日版本已存在则自动递增为 `YYYY.M.D.1`、`YYYY.M.D.2`。
7. 发布版本格式支持两种：`vX.Y.Z(-suffix)` 与 `YYYY.M.D(.N)`。
8. GitHub workflow `.github/workflows/release-xcframework.yml` 在 `release published` 事件触发后自动上传以下附件到对应 Release；`workflow_dispatch` 未传 `tag_name` 时同样默认当天日期版本。
   - `NeptuneSDKiOS-<tag>.xcframework.zip`
   - `NeptuneSDKiOS-<tag>.xcframework.zip.sha256`

## 依赖检查判定规则

允许项：

1. 系统库（`/System/Library/*`、`/usr/lib/*`、`/Developer/*`）。
2. Swift Runtime（`@rpath/libswift*` 等）。
3. 当前 framework 自身 install name。
4. 用户通过白名单显式放行的依赖。

失败项：

1. 其他非系统动态库或 framework 引用（例如 `@rpath/GRDB.framework/GRDB`）。

## 测试策略（TDD）

1. 新增脚本测试，先验证 `--help` 行为与参数说明。
2. 测试先红（脚本不存在时失败），补实现后转绿。
3. 为发布脚本新增 `--dry-run` 快速测试路径，覆盖 tag 校验与产物路径解析，避免在单测阶段执行真实 archive。
