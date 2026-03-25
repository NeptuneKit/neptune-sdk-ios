# NeptuneSDKiOS

iOS 端 Neptune v2 SDK 最小骨架，当前已支持内存队列与可选 SQLite 持久化队列。

## 目前能力
- 统一日志模型：`NeptuneIngestLogRecord`
- 日志队列：默认内存模式，支持可选 SQLite 持久化模式
- 队列能力：
  - 入队
  - `cursor` / `limit` 分页查询
  - 容量上限裁剪
  - overflow 计数
- 导出服务：`health()`、`metrics()`、`logs(cursor:limit:)`
- 网关发现：`NeptuneGatewayDiscoveryClient`
- 本地 HTTP 导出服务：`NeptuneExportHTTPServer`
  - `GET /v2/export/health`
  - `GET /v2/export/metrics`
  - `GET /v2/export/logs?cursor&limit`
  - `POST /v2/client/command`
  - `POST /v1/client/command`
- 网关主动回调注册：`NeptuneGatewayRegistrationClient`
  - 启动后立即向 `POST /v2/clients:register` 注册
  - 默认每 `30s` 续约一次
  - `sessionId` 只用于展示，主键按 `platform + appId + deviceId` 组织

## 依赖
- Swift 6
- [Vapor](https://github.com/vapor/vapor) 用于本地 HTTP 导出服务
- [GRDB](https://github.com/groue/GRDB.swift) 用于 SQLite 持久化队列

## 初始化方式

### 1. 默认内存模式

不传存储参数时，行为与旧版本一致：数据只保存在内存，进程退出后丢失。

```swift
import NeptuneSDKiOS

let service = NeptuneSDKiOS.makeExportService()
```

也可以显式指定内存模式：

```swift
let service = try NeptuneSDKiOS.makeExportService(storage: .memory)
```

### 2. SQLite 持久化模式

```swift
import NeptuneSDKiOS

let databasePath = NSTemporaryDirectory() + "/neptune-export.sqlite"
let service = try NeptuneSDKiOS.makeExportService(
    storage: .sqlite(path: databasePath),
    capacity: 2000
)
```

说明：
- 首次初始化时会创建 SQLite 数据库和表结构。
- `capacity` 会在首次初始化时写入数据库状态表。
- 后续使用同一数据库路径重建服务时，会复用已持久化的日志、overflow 计数和容量配置。

## 运行示例

```swift
import NeptuneSDKiOS

let databasePath = NSTemporaryDirectory() + "/neptune-export.sqlite"
let service = try NeptuneSDKiOS.makeExportService(
    storage: .sqlite(path: databasePath)
)

_ = await service.ingest(
    NeptuneIngestLogRecord(
        timestamp: "2026-03-23T12:34:56Z",
        level: .info,
        message: "hello neptune",
        platform: "ios",
        appId: "demo.app",
        sessionId: "session-1",
        deviceId: "device-1",
        category: "demo"
    )
)

let server = NeptuneSDKiOS.makeExportHTTPServer(service: service)
try await server.start(port: 8080)

// http://127.0.0.1:8080/v2/export/health
// http://127.0.0.1:8080/v2/export/metrics
// http://127.0.0.1:8080/v2/export/logs?cursor=0&limit=50
// http://127.0.0.1:8080/v2/client/command
```

停止服务：

```swift
await server.stop()
```

## 网关发现

SDK 会先尝试通过 mDNS 找到候选网关，再回退到手动 DSN。每个候选都会请求 `GET /v2/gateway/discovery`，最终返回稳定的 `endpoint`、`source`、`host`、`port` 和 `version`。

```swift
import NeptuneSDKiOS

let discovery = NeptuneSDKiOS.makeGatewayDiscoveryClient(
    configuration: .init(
        manualDSN: URL(string: "http://127.0.0.1:18765")
    )
)

let result = try await discovery.discover()
print(result.endpoint)
print(result.source)
print(result.host)
print(result.port)
print(result.version)
```

可按需注入测试替身：

```swift
let discovery = NeptuneGatewayDiscoveryClient(
    configuration: .init(manualDSN: URL(string: "http://127.0.0.1:18765")),
    browser: myMockBrowser,
    transport: myMockTransport
)
```

## 主动回调注册

SDK 还提供一个基于 `URLSession` 的注册/续约客户端入口。它会：

- 启动后立即调用 discovery
- 向 `POST /v2/clients:register` 发送客户端身份和本地 `commandUrl`
- 默认每 `30s` 续约一次
- 停止后不再续约，由网关 TTL 自动下线

本地命令回调由 `NeptuneExportHTTPServer` 提供：

- `POST /v2/client/command`
- `POST /v1/client/command` 仅保留 `ping` 兼容

```swift
import NeptuneSDKiOS

let client = NeptuneSDKiOS.makeGatewayRegistrationClient(
    discovery: NeptuneSDKiOS.makeGatewayDiscoveryClient(
        configuration: .init(manualDSN: URL(string: "http://127.0.0.1:18765"))
    ),
    configuration: .init(
        appId: "demo.app",
        sessionId: "session-1",
        deviceId: "device-1",
        commandUrl: URL(string: "http://127.0.0.1:8080/v2/client/command")!,
        sdkName: "neptune-sdk-ios",
        sdkVersion: NeptuneExportService.version
    )
)

await client.start()

// 前台恢复时如果需要立即刷新，可手动调用：
// await client.registerNow()
```

## Smoke Demo

仓库提供一个可直接执行的冒烟链路，用来验证 SDK 的接入、日志入队、HTTP 导出和 SQLite 重建能力。

运行方式：

```bash
swift run NeptuneSDKiOSSmokeDemo
```

或者使用脚本包装：

```bash
./scripts/smoke-demo.sh
```

默认 demo 会：
- 创建临时 SQLite 数据库
- 通过 `NeptuneSDKiOS` 生成服务并写入一组日志
- 启动本地 HTTP 导出服务并请求 `/v2/export/health`、`/v2/export/metrics`、`/v2/export/logs`
- 重新打开同一 SQLite 数据库，验证日志和 metrics 仍可恢复
- 输出一份摘要，包含记录数、overflow 计数、日志 ID 和 HTTP 状态

## XCFramework 打包

仓库提供一键打包脚本：

```bash
bash scripts/build-xcframework.sh
```

默认输出：

- `.build/artifacts/NeptuneSDKiOS.xcframework`

脚本默认会在打包后执行运行时依赖检查（`otool -L`）：

- 仅允许系统库、Swift Runtime 和 SDK 自身 framework
- 如果发现第三方动态依赖，会失败并打印依赖清单，避免“以为已集成、实际需额外分发”的风险
- 脚本默认使用 `BUILD_LIBRARY_FOR_DISTRIBUTION=NO`（兼容当前依赖编译），如需产出 `.swiftinterface` 可显式传 `--build-library-for-distribution YES`
- 当 `BUILD_LIBRARY_FOR_DISTRIBUTION=NO` 时，脚本会自动使用 `-allow-internal-distribution` 生成 `xcframework`（适合内部团队分发）

常用参数：

```bash
bash scripts/build-xcframework.sh --help
bash scripts/build-xcframework.sh --skip-dependency-check
bash scripts/build-xcframework.sh --allow-runtime-dependency GRDB
bash scripts/build-xcframework.sh --build-library-for-distribution YES
```

### Release 自动挂载 XCFramework

仓库内置发布资产脚本（用于 workflow 或本地手动预演）：

```bash
bash scripts/build-release-assets.sh --dry-run
bash scripts/build-release-assets.sh --tag v1.2.3 --dry-run
```

说明：

- `--tag` 可选，不传时默认使用当天日期版本，并在同日多次发布时自动递增（`YYYY.M.D`、`YYYY.M.D.1`、`YYYY.M.D.2`）
- 支持两种版本格式：`vX.Y.Z` 或 `YYYY.M.D(.N)`

正式执行时会：

1. 调用 `build-xcframework.sh` 生成 `NeptuneSDKiOS.xcframework`
2. 打包为 `NeptuneSDKiOS-<tag>.xcframework.zip`
3. 生成 `NeptuneSDKiOS-<tag>.xcframework.zip.sha256`

GitHub Actions 工作流：`.github/workflows/release-xcframework.yml`

- 触发方式：`release published`（发布 release 后自动执行）或 `workflow_dispatch`
- `workflow_dispatch` 未传 `tag_name` 时，会以当天日期作为版本号并基于当前提交构建
- 执行结果：自动把 zip 与 sha256 挂载到对应 tag 的 GitHub Release

## Simulator App Demo（真实 iOS Demo 工程）

仓库提供可在 iOS 模拟器安装运行的真实 Demo App：

- 工程目录：`Examples/simulator-app`
- 入口脚本：`scripts/simulator-demo.sh`
- App Bundle ID：`com.neptunekit.demo.ios`

执行：

```bash
bash scripts/simulator-demo.sh
```

脚本会自动完成：

1. `tuist generate` 生成 `SimulatorApp.xcodeproj`
2. 使用当前 Booted iOS Simulator 执行 `xcodebuild` 编译
3. `simctl install` 安装 App
4. `simctl launch` 拉起 App

App 内提供四个操作按钮：

- `Ingest 1 Log`
- `Show Metrics`
- `Start Export Server`
- `Discover Gateway`

App 启动后会自动触发一次 gateway discovery + `POST /v2/clients:register`，并在日志区输出 `gateway registration started`、`gateway registration discovery success/failure`、`gateway registration success/failure`。

`Discover Gateway` 会先尝试 mDNS，再回退到 `http://127.0.0.1:18765`，并把 `source`、`host`、`port`、`version` 和 `endpoint` 直接打印到页面日志区。

当 `Discover Gateway` 成功后，Demo 会自动向 CLI 网关发送一条 `POST /v2/logs:ingest` 请求，正文使用 `application/json`，并在页面日志区输出 `gateway ingest success` 或 `gateway ingest failure`。

导出服务默认监听 `127.0.0.1:18765`，可在模拟器内继续验证：

- `/v2/export/health`
- `/v2/export/metrics`
- `/v2/export/logs`

## 接口兼容性
- 导出路由保持不变：`/v2/export/health`、`/v2/export/metrics`、`/v2/export/logs?cursor&limit`
- `cursor` 解析失败时按 `nil` 处理
- `limit` 缺省时默认为 `100`
- `limit` 为负数时钳制为 `0`

## 开发说明
- 运行测试：`xcrun swift test`
- 运行冒烟 demo：`swift run NeptuneSDKiOSSmokeDemo`
- 测试框架：Swift Testing
- 当前测试覆盖：
  - 内存模式 overflow 行为
  - 内存模式 cursor 分页
  - SQLite 模式重建后的日志恢复
  - SQLite 模式容量与 overflow 计数持久化
  - HTTP 导出接口兼容性
  - Smoke demo 的端到端编排与摘要输出

## CI
- GitHub Actions 会在 `push` 到 `main` 和 `pull_request` 时触发
- 运行环境：`macos-15`
- 执行命令：
  - `xcrun swift test`
  - `./scripts/smoke-demo.sh`
