# NeptuneSDKiOS XCFramework 打包能力

## 背景

当前 `NeptuneSDKiOS` 通过 Swift Package 分发。为支持闭源集成或内部二进制分发，需要提供可复用的 `xcframework` 打包方案，并明确“内部源码依赖是否被集成”的验证方式。

## 目标

1. 提供一键脚本生成 `NeptuneSDKiOS.xcframework`。
2. 打包后自动检查动态依赖泄漏风险（重点关注第三方运行时依赖）。
3. 在 README 中给出标准使用方式，降低接入沟通成本。
4. 在 GitHub 打 release 时，自动把 `xcframework` 资产挂载到对应 Release。

## 非目标

1. 不在本次改动中引入 CocoaPods Spec 或其他额外分发渠道。
2. 不在本次改动中调整 SDK 对外 API。

## BDD 验收场景

### 场景 1：开发者一键打包

- Given 仓库已安装 Xcode 命令行工具
- When 执行 `bash scripts/build-xcframework.sh`
- Then 生成 `neptune-sdk-ios/.build/artifacts/NeptuneSDKiOS.xcframework`
- And 命令退出码为 0

### 场景 2：执行帮助命令

- Given 开发者不熟悉脚本参数
- When 执行 `bash scripts/build-xcframework.sh --help`
- Then 输出中包含 `Usage` 和关键参数说明（至少包含 `--scheme` 与 `--skip-dependency-check`）
- And 命令退出码为 0

### 场景 3：依赖泄漏门禁

- Given 打包完成的 `xcframework`
- When 脚本执行依赖检查
- Then 若发现非系统动态依赖则命令失败并输出依赖清单
- And 若只存在系统库与 Swift Runtime，则命令通过

### 场景 4：发布时自动挂载 xcframework

- Given 已创建符合规范的 release 版本号（如 `v1.2.3` 或 `2026.3.14`）
- When 触发 iOS SDK 的 release workflow
- Then workflow 会构建 `NeptuneSDKiOS.xcframework`
- And 自动上传 `NeptuneSDKiOS-<tag>.xcframework.zip` 与对应 `sha256` 文件到同名 GitHub Release

### 场景 5：版本号默认当天日期

- Given 本地执行发布资产脚本时未显式传 `--tag`
- When 执行 `bash scripts/build-release-assets.sh --dry-run`
- Then 脚本会默认使用当天日期版本（格式 `YYYY.M.D`）

### 场景 6：同日多版本自动递增

- Given 当天版本 `YYYY.M.D` 已存在
- When 再次执行未传 `--tag` 的发布资产脚本
- Then 脚本自动生成 `YYYY.M.D.1`（继续重复则依次递增）

## 关联技术方案

- 见 `docs-linhay/dev/xcframework-packaging.md`
