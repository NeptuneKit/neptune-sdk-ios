# 成熟库决策说明 - 本地 HTTP 导出服务

日期：2026-03-24

## 背景

`NeptuneExportHTTPServer` 原先依赖 `FlyingFox` / `FlyingSocks` 暴露本地导出接口：

- `GET /v2/export/health`
- `GET /v2/export/metrics`
- `GET /v2/export/logs?cursor&limit`

本次按“成熟库优先”硬切要求，评估是否迁移到更主流、维护更活跃的通用 HTTP 框架。

## 结论

选择 `Vapor`，不使用 `Hummingbird` 作为当前实现。

## 决策理由

1. `Vapor` 官方仓库当前 `Package.swift` 明确声明支持 `iOS` SwiftPM 平台，可满足本仓库的 iOS SPM 集成前提。
2. `Vapor` 社区规模、发布频率、生态完整度都明显高于当前的轻量本地 server 方案，更符合“成熟库优先”目标。
3. 现有接口非常薄，只需要路由、端口监听和 JSON 响应；迁移到 `Vapor` 不需要改变业务层 `NeptuneExportService` 和 `NeptuneLogQueue`。
4. `Hummingbird` 仅作为备选。由于 `Vapor` 在当前场景已可行，没有必要再引入第二优先级方案。

## 保持不变的语义

迁移后保持以下行为不变：

1. 路由路径不变：
   - `GET /v2/export/health`
   - `GET /v2/export/metrics`
   - `GET /v2/export/logs?cursor&limit`
2. `logs` 的 query 解析语义不变：
   - `cursor` 解析失败时按 `nil` 处理
   - `limit` 缺省时默认为 `100`
   - `limit` 为负数时钳制为 `0`
3. 返回仍为 JSON，业务快照结构不变。
4. `port = 0` 时仍支持系统分配可用端口，并可查询实际监听端口。

## 实现说明

1. 移除 `FlyingFox` / `FlyingSocks` 依赖，改为 `Vapor`。
2. `NeptuneExportHTTPServer` 改为通过 `Application.make(...)` 与 `startup()/asyncShutdown()` 管理生命周期。
3. 为避免 `swift test` 注入的测试参数被 `Vapor` 命令系统误解析，服务启动时使用最小化 `Environment(arguments:)`。
4. 保留原有手写 JSON 响应，避免迁移时引入额外的内容协商差异。

## 验证

执行命令：

```bash
swift test
```

验证点：

1. `health` 路由可访问。
2. `metrics` 路由返回队列快照。
3. `logs` 路由分页行为保持不变。
4. `logs` 对非法 query 参数的回退语义保持不变。
5. 现有 `NeptuneLogQueue` 单元测试继续通过。

## 风险与取舍

1. `Vapor` 首次冷编译成本明显高于 `FlyingFox`，依赖树更大。
2. 当前收益在于统一到更成熟、维护更活跃的 HTTP 框架，而不是减少体积。
3. 由于本地导出接口非常简单，后续若启动成本成为瓶颈，再评估是否做更细粒度裁剪，而不是回退到轻量但生态更弱的方案。
