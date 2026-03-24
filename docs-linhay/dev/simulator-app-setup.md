# iOS Simulator Demo 工程说明

## 工程结构

- `Examples/simulator-app/Project.swift`：Tuist 工程描述
- `Examples/simulator-app/App/Sources/`：App 代码
- `Examples/simulator-app/App/Resources/`：启动页等资源
- `scripts/simulator-demo.sh`：一键构建/安装/启动脚本

## 关键技术选择

1. 使用 Tuist 管理 Demo App 工程，不提交生成产物
2. 通过本地 Swift Package 依赖 `../..` 引用 `NeptuneSDKiOS`
3. 运行时采用 SDK 的 SQLite 存储模式，保证模拟器重启后可观测

## 本地验证

```bash
bash scripts/simulator-demo.sh
```

脚本预期输出：

- `** BUILD SUCCEEDED **`
- `Simulator demo launched: simulator_id=<id> app=<path>`

## 故障排查

1. `No booted iOS simulator found`：先手动启动一个 iOS 模拟器
2. `tuist is required`：安装 Tuist 或补 PATH
3. Xcode 构建空间不足：清理 `DerivedData` 后重试
