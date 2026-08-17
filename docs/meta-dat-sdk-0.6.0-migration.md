# Meta Wearables DAT SDK 0.6.0 升级说明

本文记录 TurboMeta iOS 端从 Meta Wearables DAT SDK 0.5.0 升级到 0.6.0 的功能变化、破坏性 API 变更和迁移方式。0.6.0 发布于 2026-04-15。

## 更新概览

| 类别 | 0.6.0 变化 | 对项目的影响 |
| --- | --- | --- |
| 设备支持 | 新增 Ray-Ban Meta Optics 支持 | SDK 可识别新增眼镜类型，无需业务层单独创建流实现 |
| 会话模型 | 新增 `DeviceSession`、`Capability` 和明确的设备生命周期 | 摄像头流必须挂载到已启动的设备会话，不能再直接初始化 `StreamSession` |
| Objective-C | Camera API 现已完整支持 Objective-C | 提供流、帧、拍照、错误、配置、设备选择器及通知封装 |
| Mock 测试 | MockDeviceKit 支持启停、初始注册/权限配置和权限结果模拟 | 测试应显式调用 `enable(config:)` 与 `disable()` |
| Mock 摄像头 | 可用手机前/后摄像头模拟视频流 | 新增 `setCameraFeed(cameraFacing:)` |
| 并发模型 | Mock 相关协议移除 `@MainActor` 限制并遵循 `Sendable` | Mock API 可安全地从不同执行上下文调用 |
| 行为修复 | 改善 mock 设备关机和摘下眼镜时的状态模拟 | 集成测试更接近真实设备状态变化 |

0.5.0 已有的 HEVC 后台流、App Attestation、`thermalCritical` 错误以及 720×1280 高分辨率支持均继续保留。

## 关键 API 变化

### 摄像头流改为 DeviceSession 生命周期

0.5.0 可直接创建流：

```swift
let stream = StreamSession(
  streamSessionConfig: config,
  deviceSelector: selector)
await stream.start()
```

0.6.0 必须先创建并启动设备会话，等待 `.started` 后再添加流能力：

```swift
let deviceSession = try wearables.createSession(deviceSelector: selector)
try deviceSession.start()

// 观察 statePublisher/stateStream，等待状态变为 .started。
guard let stream = try deviceSession.addStream(config: config) else {
  throw CameraError.streamUnavailable
}
await stream.start()

// 清理顺序：先停止能力，再停止父会话。
await stream.stop()
deviceSession.stop()
```

同时应监听 `DeviceSession.errorPublisher`，并处理 `noEligibleDevice`、`sessionAlreadyExists`、`capabilityAlreadyActive` 等类型化错误。已停止的设备会话不应复用；重新开始时创建新会话。

### MockDeviceKit 迁移

- `MockDisplaylessGlasses.getCameraKit()` 已移除，改用 `glasses.services.camera`。
- `setCameraFeed(fileURL:)` 与 `setCapturedImage(fileURL:)` 改为同步方法，应移除 `await`。
- `MockDeviceKitError` 已移除。
- 测试可通过 `MockDeviceKitConfig(initiallyRegistered:initialPermissionsGranted:)` 设置初始状态，并通过 `MockPermissions` 模拟权限请求结果。

```swift
MockDeviceKit.shared.enable(
  config: MockDeviceKitConfig(
    initiallyRegistered: true,
    initialPermissionsGranted: true))

let glasses = MockDeviceKit.shared.pairRaybanMeta()
glasses.services.camera.setCameraFeed(fileURL: videoURL)

// 测试结束
MockDeviceKit.shared.disable()
```

## TurboMeta 适配位置

- `CameraAccess/ViewModels/StreamSessionViewModel.swift`：创建、启动、监听和释放 `DeviceSession`，再挂载 `StreamSession`。
- `CameraAccess/ViewModels/MockDeviceKit/MockDeviceViewModel.swift`：迁移到 `services.camera`。
- `CameraAccessTests/CameraAccessTests.swift`：显式管理 MockDeviceKit 生命周期并改用同步摄像头方法。

## 验证

```bash
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -project CameraAccess.xcodeproj \
  -scheme TurboMeta \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

升级后至少验证：设备注册、权限授权、开始/停止/重新开始视频流、拍照、Mock 视频帧和 Mock 图片捕获。

## 参考资料

- [Meta Wearables DAT iOS SDK 0.6.0 Changelog](https://github.com/facebook/meta-wearables-dat-ios/blob/0.6.0/CHANGELOG.md)
- [Meta Wearables DAT iOS SDK](https://github.com/facebook/meta-wearables-dat-ios)
