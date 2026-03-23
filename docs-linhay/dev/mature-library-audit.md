# 成熟库优先审计 - NeptuneSDKiOS

日期：2026-03-24

## 审计范围

检查仓库内是否存在手搓的基础设施实现，重点关注：

- HTTP 服务
- 编码 / 解析
- 重试 / 队列发送
- SQLite / 持久化
- CLI / 协议解析

## 结论

当前实现没有发现需要替换的重型自研基础设施。

### 已采用成熟库的部分

- HTTP 导出服务使用 `FlyingFox` / `FlyingSocks`，不是自研 socket server。
- JSON 编码 / 解码直接使用 `Foundation` 的 `Codable` / `JSONEncoder` / `JSONDecoder`。
- 测试层使用 `Swift Testing`，没有额外自研测试框架。

### 自定义实现的部分

- `NeptuneLogQueue` 是一个内存队列，用于存放最近日志并支持分页。
- `parseLogsQuery(cursorValue:limitValue:)` 只做基础 query 参数转型，没有引入自研协议解析器。

这些实现都属于业务轻量逻辑，不属于 SQLite / HTTP / CLI / 协议解析这类应优先复用成熟三方库的基础设施。

## 风险判断

- 当前没有持久化层，因此不需要引入 SQLite。
- 当前没有 CLI 能力，因此不需要引入命令行解析库。
- 当前 HTTP 服务已经基于成熟库实现，符合“成熟库优先”要求。
- 现有内存队列容量固定，复杂度和风险都较低，后续如果演进为持久化或跨进程发送，再评估引入成熟队列 / 存储方案。

## 验证

- 已执行：`xcrun swift test`
- 结果：4 个测试全部通过

## 结论摘要

本仓库当前状态符合“成熟库优先”的审计要求，因此本次未做代码替换，只补充审计记录。
