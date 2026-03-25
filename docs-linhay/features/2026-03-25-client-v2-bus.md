# iOS Client `/v2` 总线抽象

日期：2026-03-25

## 背景

当前 iOS SDK 的客户端回调与出站发送仍混用旧的命令模型和旧注册字段：

- `/v2/client/command` 直接接收 `NeptuneClientCommandRequest`
- 客户端出站日志直接发送 `NeptuneIngestLogRecord`
- 注册仍使用 `commandUrl`

这会让 `/v2` 侧协议演进继续背着旧模型前进，难以和其他端统一。

## 验收场景

### 场景 1：`/v2/client/command` 只接收总线 envelope

- Given 本地导出 HTTP 服务已启动
- When CLI 向 `POST /v2/client/command` 发送 `BusEnvelope(direction=cli_to_client, kind=command, command=ping)`
- Then 服务返回 `BusAck(status=ok)`，并保留 `requestId`、`command` 与 `timestamp`

### 场景 2：客户端出站日志先映射总线 envelope

- Given iOS SDK 要向网关发送一条日志
- When `GatewayIngestClient` 构造 `/v2/logs:ingest` 请求
- Then 请求体应为 `BusEnvelope(direction=client_to_cli, kind=log)`
- And envelope 内的日志 payload 能无损解码回原始 `NeptuneIngestLogRecord`

### 场景 3：注册载荷切换到新字段

- Given iOS SDK 要向 `POST /v2/clients:register` 注册自身
- When 构造注册 payload
- Then 载荷应包含 `preferredTransports`、`usbmuxdHint`、`callbackEndpoint`
- And 不再编码历史别名字段

## 约束

- `/v1/client/command` 继续保留旧 `ping` 兼容行为
- 仅修改 `neptune-sdk-ios` 目录
- 不回滚其他开发者改动
