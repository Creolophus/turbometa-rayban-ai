# iOS Liquid Glass 首页

以 2026-09-07 确认的第二版设计稿为基准。仅调整 iOS 首页和共享系统 TabView，最低 iOS 版本保持 26.0。

## 行为

- 顶部只显示「首页」，圆形按钮跳转设置标签。
- 使用当前 AutoDeviceSelector 选中的眼镜名称和 SDK LinkState；设备 ID 不用于展示。空名称显示「Meta 眼镜」，无活动设备显示「未连接眼镜」。
- 连接事件、设备切换及 App 返回前台会刷新设备栏；SDK 未提供名称变化事件，所以外部改名后以前台刷新为准。
- Live AI 与 Siri 继续共用 MainTabView 中的路由；识图、翻译、语音笔记、OpenClaw、直播、RTMP 和 LeanEat 继续使用原来的功能页面。
- 退出 LeanEat 仅停止媒体会话，不再停止首页共享的设备监听。
- 使用系统 Liquid Glass 底栏与按钮，减少透明度时首页按钮切换为不透明背景。大字号助手区改为纵向排列，主图和文字分开显示；页面允许滚动。
- 浅深色随系统；文案提供中文、英文。首页样式常量独立于全局 AppColors。

## 主图来源

使用内置 imagegen 工具，参考已确认设计稿生成独立图片；文字和按钮由 SwiftUI 绘制。

资源：`CameraAccess/Assets.xcassets/HomeGlassesHero.imageset/home-glasses-hero.png`

生成提示词：

> Create a SINGLE standalone raster background asset for the Live AI hero card visible in the reference UI design. The reference is ONLY to guide matching the hero photograph style, not an edit of the full UI. Output only the rectangular photo background, no phone, no board, no UI. Wide landscape 16:9 aspect ratio. High-quality photorealistic black wayfarer smart glasses with a tiny visible camera at the outer corner, three-quarter angle, positioned on the RIGHT HALF (roughly x 55-96 percent), sitting on a soft satin blush surface. Premium subtle lighting, dark black frames and smoked dark violet lenses. All glasses fully inside the image with space from edges. Background smooth warm blush pink on left, muted dusky lavender at upper right, plum charcoal lower right with a subtle realistic shadow under the glasses. IMPORTANT entire LEFT HALF must be light soft blush pink with no objects and no dark patches, to provide excellent contrast for black native UI text that will later overlay it. Keep bottom left blush as well. Delicate premium Apple Music editorial photography mood. No text, no letters, no labels, no logos, no buttons, no rounded corners, no borders, no watermarks. This asset will be bundled in an actual iOS app, not a design board.

## 验证方式

`HomeDeviceStatusTests` 使用可控的设备选择器、设备名称和连接事件测试正常连接、空名称、断开、切换、前台改名刷新、旧回调失效、停止会话后继续监听及清理。

`HomeVisualTests` 在模拟器中渲染真实 MainTabView 和首页，并保存浅色、深色、英文、大字号截图到 XCTest 附件。截图中的「我的 Ray-Ban」为测试夹具，不代表真实眼镜连接。

```sh
xcodebuild -project CameraAccess.xcodeproj -scheme TurboMeta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:CameraAccessTests/HomeDeviceStatusTests \
  -only-testing:CameraAccessTests/HomeVisualTests \
  CODE_SIGN_IDENTITY=- test
```

真机需另外确认 SDK 返回的名称、眼镜断开重连、从 Meta AI 改名后返回 App，以及实际媒体功能。模拟器夹具测试不代替真机验收。

## 本次验证结果（2026-09-07）

- iOS Simulator 构建通过；8 项设备状态单测、2 项首轮视觉测试通过（iPhone 17 Pro / iOS 26.5）。
- 随后调整了首页间距、录音入口文案和暗色底色；最终版本的真机签名构建通过，并更新安装到用户连接的 iPhone 17 Pro / iOS 27。
- 真机 Meta SDK 初始化正常；当前 SDK 眼镜名称为 `00K8`，首页显示绿色「已连接」。
- 最终真机截图保存于 `screenshots/liquid-glass/`：`home-dark-device.png`、`home-light-device.png`、`home-reduced-transparency-device.png`、`home-large-text-device.png`。
- 检查了浅深色、减少透明度时的不透明按钮、大字号主图与文字分离及助手纵向排列。用户原始深色、小字号、关闭辅助大字号、关闭减少透明度的设置已恢复。
- 用户选择暂不操作眼镜，故真机断开重连和外部改名刷新尚未验证；对应状态转换已有自动化单测。
- 扩展的视频/拍照回归和小屏滚动截图因模拟器启动停滞未完成，随后按用户要求切换真机调试。功能入口、Siri 路由沿用原有逻辑，完整媒体操作与 VoiceOver 朗读仍需人工验收。

最初禁用模拟器签名时，Meta SDK 在宿主启动阶段失败。改用 `CODE_SIGN_IDENTITY=-` 的标准模拟器签名后，上述 10 项测试正常通过；无需向仓库写入测试凭据。

结束调试时尝试恢复为普通启动，但手机已锁屏，系统拒绝启动；安装和此前真机截图验证均已成功。解锁手机后可手动打开 TurboMeta。
