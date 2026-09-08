# 首页 Wayfarer 3D 展示

## 资源与再生成

参考 Meta 官方商品页面的正面、侧面与背面图片：
- https://www.meta.com/ai-glasses/ray-ban-meta-wayfarer-gen-2/
- https://www.meta.com/ai-glasses/ray-ban-meta-wayfarer-shiny-black-green-gen-2/

本模型是按图片比例制作的展示模型，不是厂商 CAD；未公开尺寸、鼻托、铰链与镜腿内部结构为近似。没有使用官方商标贴图。

运行 `python3 scripts/wayfarer/generate.py`（标准库 Python 3 + Apple USD 工具）重新生成：
- `assets/wayfarer/wayfarer.usda`：可编辑 USD 源文件，米制、Y 向上。
- `assets/wayfarer/wayfarer.usdc`：二进制 USD。
- `CameraAccess/Resources/Models/Wayfarer.usdz`：随 App 离线打包。
- `assets/wayfarer/metrics.json`：网格统计。

当前 20 个网格、7,194 个顶点、14,120 个三角面；USDZ 174,827 字节。生成脚本同时调用 `usdchecker --arkit`，检查通过。

独立背景 `HomeGlassesBackdrop` 由 imagegen 编辑原图生成：移除全部眼镜、镜腿、镜片以及投影和反射，保持左侧桃粉与右侧淡紫摄影棚光线，无文字、标志或物体。原 `HomeGlassesHero` 保留为加载和失败占位。

## 实现

`WayfarerView.swift` 使用非 AR RealityKit 视图，不启动摄像头会话。USDZ 异步加载，成功后缓存原型；各可见场景克隆独立实体。环境反射为代码生成的小尺寸摄影棚贴图。

首页纵向滚动手势优先；模型只接管横向超过 8pt 且横纵比超过 1.2 的拖动。全屏姿态为首页姿态的副本，关闭后不回写。缩放限制 0.7–2.5，俯仰限制 ±75°。没有惯性和自动旋转。不可见、后台和被全屏覆盖时隐藏渲染表面，保留场景复用；页面销毁时取消加载和延迟截图任务并清空场景。

保留既有 Live AI 按钮和功能路由。没有更改 Android、设备连接或记录数据。

## 验证

- `TurboMeta` 模拟器及 iOS 真机构建已通过（Xcode 27 beta）。
- USDZ 合规检查通过。
- `CameraAccessTests/WayfarerTests.swift` 覆盖方向阈值、旋转归一化、缩放和俯仰边界，并提供四视角及浅深色首页截图测试。
- 实际渲染截图、交互流畅度和真机安装状态以本次最终验证记录为准；编译成功不能替代视觉验收。

### 真机复查

2026-09-08：用户 iPhone 17 Pro 恢复连接后，安装并启动成功；实际截图确认模型正常加载及渲染。用户试用发现首页旋转与纵向滚动竞争，以及全屏背景撑宽导致关闭按钮超出屏幕。

修复：渲染表面和图片按 GeometryReader 的可用尺寸约束；首页外层滚动手势等待方向识别失败，竖向由滚动视图接管、横向由模型接管。新增全屏渲染边界回归断言。修复版真机构建通过。XCTest 此前在模拟器安装/启动阶段停滞，未声称测试通过；持续操作、辅助功能、浅深色成套截图和录屏仍待完成。

### 可见卡片滚动性能调整

用户进一步确认，卡片没有离开屏幕时也卡顿，因此离屏重建不是本次卡顿的已证实原因。当前优化针对滚动与实时 3D 并行的开销：
- 列表进入 interacting/decelerating/animating 时，用已缓存的当前姿态画面替换可见 Metal 表面；tracking 阶段不冻结，保留横向旋转方向判断。
- 停止滚动恢复原场景，场景、灯光与材质不重新建立。
- 仅模型加载完成或姿态稳定后生成缓存画面，滚动回调不执行截图；没有可用缓存时保持实时画面。
- 不重复写入相同实体变换；关闭不需要的运动模糊、景深、摄像机颗粒与系统落影。

此调整尚未取得真机帧率/耗时对比，不能据此认定根因或宣称卡顿已消除。
