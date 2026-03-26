# 持久化日志队列

## 背景

当前 `NeptuneLogQueue` 仅支持内存模式。进程退出后日志、游标位置相关数据和 overflow 计数都会丢失，不利于本地导出与排障。

## 目标

为日志队列提供两种初始化方式：

1. 内存模式：保持当前默认行为。
2. 持久化模式：基于 SQLite 持久化日志队列，优先采用成熟库 `GRDB`。

## 非目标

1. 不修改导出接口路径与返回模型。
2. 不引入远端上传或同步能力。

## 验收场景

### 场景 1：默认内存模式兼容现有行为

- Given 使用 `NeptuneLogQueue()` 或 `NeptuneExportService()` 初始化
- When 写入日志并查询 metrics 与 logs
- Then 行为与当前版本一致
- And 导出 API 继续兼容 `/v2/export/health`、`/v2/export/metrics`、`/v2/logs`

### 场景 2：持久化模式在重建实例后保留日志

- Given 使用 SQLite 模式初始化队列并写入多条日志
- When 释放队列并使用同一数据库路径重新初始化
- Then `logs(cursor:limit:)` 还能读到之前的日志
- And 游标继续基于已持久化的记录 ID 工作

### 场景 3：持久化模式保留容量上限和 overflow 计数

- Given SQLite 模式下写入超过容量上限的日志
- When 查询 `metrics()`
- Then 只保留最新的 `capacity` 条日志
- And `droppedOverflow` 为累计溢出次数
- And 重建实例后该计数仍存在

### 场景 4：持久化模式支持 cursor/limit 分页

- Given SQLite 模式下已有顺序写入的日志
- When 使用不同的 `cursor` 与 `limit` 查询
- Then 结果顺序稳定且 `nextCursor`、`hasMore` 语义不变
