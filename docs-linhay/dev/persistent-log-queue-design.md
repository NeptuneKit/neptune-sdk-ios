# 持久化日志队列设计

关联需求：[persistent-log-queue](../features/persistent-log-queue.md)

## 设计目标

1. 保持 `NeptuneLogQueue` 公开 API 尽量稳定。
2. 默认行为仍为内存模式，避免影响现有接入方。
3. 用成熟库 `GRDB` 实现 SQLite 持久化。
4. 继续兼容导出层与 HTTP 层现有接口。

## 方案概览

### 公开层

- `NeptuneLogQueue()`：默认内存模式。
- `try NeptuneLogQueue(storage: .memory)`：显式内存模式。
- `try NeptuneLogQueue(storage: .sqlite(path: ...), capacity: ...)`：SQLite 持久化模式。
- `NeptuneExportService` 与 `NeptuneSDKiOS.makeExportService` 新增显式存储初始化入口。

### 存储层

`NeptuneLogQueue` 保持为 actor，但内部委托给存储后端：

1. `NeptuneInMemoryLogQueueStorage`
2. `NeptuneSQLiteLogQueueStorage`

这样导出服务和 HTTP 服务无需感知底层存储介质。

## SQLite Schema

### `neptune_log_queue_records`

字段：
- `id`：自增语义的逻辑主键，由状态表中的 `nextRecordID` 管理
- `timestamp`
- `level`
- `message`
- `platform`
- `appId`
- `sessionId`
- `deviceId`
- `category`
- `attributesPayload`：JSON blob
- `sourcePayload`：JSON blob

### `neptune_log_queue_state`

单行状态表，持久化以下信息：
- `nextRecordID`
- `capacity`
- `droppedOverflowCount`

## 关键行为

1. 首次建库时写入默认 `capacity`。
2. 同一路径重建队列时，优先使用已持久化的状态。
3. 每次入队后执行容量裁剪，删除最旧记录。
4. `droppedOverflowCount` 在 SQLite 模式下为持久化累计值。
5. `page(cursor:limit:)` 继续按 `id ASC` 返回，确保导出游标语义不变。

## 取舍

1. 采用 `DatabaseQueue` 而非 `DatabasePool`
原因：当前访问模式天然串行，且 `NeptuneLogQueue` 已经是 actor，单连接模型更简单稳定。

2. 保持公开查询 API 非 throwing
原因：兼容现有调用面。初始化阶段暴露错误，运行期数据库异常按不可恢复错误处理。
