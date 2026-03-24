# Simulator App Demo（iOS）

## 背景

现有 `NeptuneSDKiOSSmokeDemo` 是命令行冒烟，不是可安装到 iOS Simulator 的真实 App。

## 目标

新增一个可在 iOS Simulator 运行的 Demo App，验证以下链路：

1. App 内调用 SDK 写入日志
2. App 内查询 metrics / logs
3. App 内启动本地导出 HTTP 服务
4. 在模拟器环境下可重复执行安装与启动

## 验收标准

1. 存在独立 Demo 工程目录 `Examples/simulator-app`
2. 可通过 `scripts/simulator-demo.sh` 一键完成：生成工程、编译、安装、启动
3. App UI 至少提供三个动作：写日志、看指标、启动导出服务
4. 导出路由保持 `/v2/export/health`、`/v2/export/metrics`、`/v2/export/logs`
5. 不影响现有 `swift test` 与 `smoke-demo.sh` 链路
