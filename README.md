# NeptuneSDKiOS

iOS 端 Neptune v2 SDK 最小骨架。

## 目前能力
- 统一日志模型：`NeptuneIngestLogRecord`
- 内存队列：容量 2000，超限丢最旧并计数
- 导出服务：`health()`、`metrics()`、`logs(cursor:limit:)`

## 开发说明
- 依赖：Swift 6 / `swift test`
- 测试框架：Swift Testing
- 该仓只包含 iOS SDK 骨架，后续可再接本地 HTTP serve 与持久化层
