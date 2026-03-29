# 2026-03-27 iOS 真实视图树采集

## 背景

iOS 导出服务之前仅返回视图树占位节点，无法满足 Inspector 页面展示和调试保真需求。

## 目标

- `GET /v2/ui-tree/snapshot` 不再对外暴露
- `GET /v2/ui-tree/inspector` 返回原始树 payload，且 payload 必须是 JSON object/array
- 遍历来源必须基于运行时视图层级，不依赖手动锚点

## 验收场景

### 场景 1：snapshot 路由不可用

- Given iOS App 已挂载 UIKit 视图层级
- When 导出服务请求 `GET /v2/ui-tree/snapshot`
- Then 返回 `404`

### 场景 2：inspector 返回原始树 payload

- Given iOS App 已挂载 UIKit 视图层级
- When 导出服务请求 `GET /v2/ui-tree/inspector`
- Then 返回 `available=true`
- And `payload` 为 JSON object/array
- And `payload` 不是字符串化 JSON

## 约束

- 仅修改 `neptune-sdk-ios`
- 不依赖手动锚点注册
- 测试必须覆盖 snapshot 路由不可达和 inspector 原始 payload 两路
