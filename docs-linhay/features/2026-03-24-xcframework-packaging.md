# NeptuneSDKiOS XCFramework 打包能力

## 背景

当前 `NeptuneSDKiOS` 通过 Swift Package 分发。为支持闭源集成或内部二进制分发，需要提供可复用的 `xcframework` 打包方案，并明确“内部源码依赖是否被集成”的验证方式。

## 目标

1. 提供一键脚本生成 `NeptuneSDKiOS.xcframework`。
2. 打包后自动检查动态依赖泄漏风险（重点关注第三方运行时依赖）。
3. 在 README 中给出标准使用方式，降低接入沟通成本。
4. 在 GitHub 打 release 时，自动把 `xcframework` 资产挂载到对应 Release。
5. 源码 SPM 与对外二进制 SPM 的最低 iOS 版本声明保持一致，统一支持 `iOS 16+`。
6. 源 SDK 仓库发布后，自动同步 `neptune-sdk-xcframework` 仓库的 release 资产、`releaseTag` 与 `binaryChecksum`，让业务侧 SPM 地址始终可直接拉到最新二进制。

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

- Given 已创建符合 SemVer 的 release 版本号（如 `1.2.3` 或 `2026.3.14`）
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
- Then 脚本自动生成下一个合法 SemVer patch（例如 `YYYY.M.(D+1)`，继续重复则持续递增）

### 场景 7：最低系统版本统一为 iOS 16

- Given 业务 App 通过源码 SPM 或二进制 SPM 接入 Neptune iOS SDK
- When Xcode 解析 `Package.swift` 与 Demo 工程部署版本
- Then `neptune-sdk-ios` 与 `neptune-sdk-xcframework` 都声明 `iOS 16+`
- And `Examples/simulator-app` 的 deployment target 同步为 `16.0`

### 场景 8：发布后自动同步二进制分发仓库

- Given `neptune-sdk-ios` 的 release workflow 已生成 `NeptuneSDKiOS-<tag>.xcframework.zip` 与对应 `sha256`
- When workflow 持有可写入 `neptune-sdk-xcframework` 仓库的 token
- Then workflow 会把 zip 与 `sha256` 上传到 `neptune-sdk-xcframework` 的同名 GitHub Release
- And 自动更新该仓库 `Package.swift` 中的 `releaseTag` 与 `binaryChecksum`
- And 自动更新 README 中展示的当前发布版本信息

### 场景 9：缺少跨仓库 token 时显式失败

- Given `neptune-sdk-ios` 的 release workflow 未配置跨仓库写权限 token
- When workflow 尝试同步 `neptune-sdk-xcframework`
- Then 任务应在同步步骤明确失败
- And 错误信息要指出缺失的 secret 名称，避免产物已发出但包装仓库未更新的半成功状态

## 关联技术方案

- 见 `docs-linhay/dev/xcframework-packaging.md`
