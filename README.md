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
- 本地 HTTP 导出服务：`NeptuneExportHTTPServer`
  - `GET /v2/export/health`
  - `GET /v2/export/metrics`
  - `GET /v2/export/logs?cursor&limit`

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
```

停止服务：

```swift
await server.stop()
```

## 接口兼容性
- 导出路由保持不变：`/v2/export/health`、`/v2/export/metrics`、`/v2/export/logs?cursor&limit`
- `cursor` 解析失败时按 `nil` 处理
- `limit` 缺省时默认为 `100`
- `limit` 为负数时钳制为 `0`

## 开发说明
- 运行测试：`xcrun swift test`
- 测试框架：Swift Testing
- 当前测试覆盖：
  - 内存模式 overflow 行为
  - 内存模式 cursor 分页
  - SQLite 模式重建后的日志恢复
  - SQLite 模式容量与 overflow 计数持久化
  - HTTP 导出接口兼容性

## CI
- GitHub Actions 会在 `push` 到 `main` 和 `pull_request` 时触发
- 运行环境：`macos-15`
- 执行命令：`xcrun swift test`
