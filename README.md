# NeptuneSDKiOS

iOS 端 Neptune v2 SDK 最小骨架。

## 目前能力
- 统一日志模型：`NeptuneIngestLogRecord`
- 内存队列：容量 2000，超限丢最旧并计数
- 导出服务：`health()`、`metrics()`、`logs(cursor:limit:)`
- 本地 HTTP 导出服务：`NeptuneExportHTTPServer`
  - `GET /v2/export/health`
  - `GET /v2/export/metrics`
  - `GET /v2/export/logs?cursor&limit`

## 依赖
- Swift 6
- [Vapor](https://github.com/vapor/vapor)（优先采用成熟库；官方 `Package.swift` 支持 iOS SwiftPM 场景）

## 运行示例
```swift
import NeptuneSDKiOS

let service = NeptuneSDKiOS.makeExportService()
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

## 开发说明
- 运行测试：`swift test`
- 测试框架：Swift Testing
- 本地 HTTP 导出服务已从 `FlyingFox` 迁移到 `Vapor`
- 路由与行为保持不变：`/v2/export/health`、`/v2/export/metrics`、`/v2/export/logs?cursor&limit`
- 当前实现优先保证本地导出服务可编译、可集成；持久化层后续补齐
