# 实时翻译链路与显示审查（2026-09-09）

审查代码：main d7838d6。此次只分析和离线回放，没有修改业务代码，没有调用阿里付费服务或发送用户录音。

## 结论

“底部很多翻译中”由两个层面共同放大：未完成条目没有终态/超时处理，UI 又把所有未持久化条目统一标成翻译中并排在已完成记录之后。代码可复现这些积累路径；尚无用户本次会话事件日志，不能认定阿里丢事件或确认某一路径就是本次现场根因。

## 官方依据

- 使用指南：https://help.aliyun.com/zh/model-studio/qwen3-5-livetranslate-flash-realtime
- 服务端事件：https://help.aliyun.com/zh/model-studio/live-translator-server-events
- 客户端事件：https://help.aliyun.com/zh/model-studio/live-translator-client-events

本次已直接阅读以上官方页面：
1. 原文和译文通过 assistant conversation.item.created.previous_item_id 与 ASR item_id 关联，当前关联方向正确。不要用 FIFO、相似文本或时间强行匹配。
2. text/stash 是确认与预测文本，最终文本来自 text.done/text 或 audio_transcript.done/transcript。不能套用 Omni 的 response.text.delta 协议。
3. response.done 包含状态以及除音频原始数据外的全部输出；text.done 也可能在响应中断、不完整或取消时返回，不能等同业务成功。
4. source transcription.failed 携带 item_id，支持精确标记失败条目。
5. 发送完音频必须 session.finish，再等待 session.finished 后关闭。
6. 输入采样率支持 8/16kHz，当前 16kHz PCM 与 Base64 append 符合配置要求。图片 JPEG、编码前 <=500KB、<=2张/秒，且必须先发音频。

## 已确定的问题

### P1：单条终态缺失，导致永久等待

位置：LiveTranslateService.swift:965、1030；LiveTranslateModels.swift:575、655；LiveTranslateViewModel.swift:573。

- sourceTranscriptFailed 只弹全局错误，丢弃 item_id，没有推进对应条目的状态。
- response.done 只转发 responseID，丢弃 status 和 output；协调器写入 isResponseDone，但它不参与展示或保存决策。
- 要进入完成记录，必须同时有非空原文、非空译文、关联、ASR final 和译文 final。任何一项不满足，就一直是 provisional。
- 没有单条 failed/incomplete/empty/timedOut 状态。不能简单把 response.done 一律当成功；应读状态，并在 completed 时从最终 output 恢复同一 response 的文本和输出项 ID。缺失 source 关联仍须明确标为无法关联，不应猜配。
- text.done 在中断时也可能出现，当前只看 isFinal 可能把非空的不完整译文保存为普通完成记录。

### P1：页面退出绕过协议收尾，末句可能丢失

位置：LiveTranslateView.swift:66；LiveTranslateViewModel.swift:239、294；LiveTranslateService.swift:305、437。

停止录音按钮会调用 finishSession；但关闭页面 onDisappear -> disconnect 会取消 finalizationTask 并直接关闭 socket。录音中退出、或者停止后还没收尾就退出，都可能丢掉末句/取消排队播报。应统一为异步收尾所有权，页面离开不提前销毁尚在收尾的服务；超时后保留明确的不完整状态。

### P1：播放队列前项未收尾会阻塞后续播报

位置：LiveTranslateService.swift:924、1030、1063；LiveTranslateModels.swift:326。

response.created 注册队列；队首必须有音频或 audio.done 才能推进。response.done 没有处理失败/空输出的队列终态。如果前一条失败/无音频且未收到 audio.done，后续已有音频也无法激活。应根据已收到的终态、模态和输出内容收尾队列，失败条目允许退出，不能靠无限等待。是否发生于用户本次现场待日志验证。

### P2：UI 列表身份、顺序和标签不准确

位置：LiveTranslateView.swift:214、227、291；LiveTranslateViewModel.swift:573。

先 ForEach(currentSessionRecords)，后 ForEach(activeTurns)，不是统一时间线。旧等待条目永远压在新完成条目之后；完成时跨 ForEach 移动，可能造成跳动。isStreaming 对 activeTurns 固定为 true，不读取 final 标志，即便译文已结束也写“翻译中”。

建议一个稳定 ID 的统一展示数组，按语音开始序号排序，状态区分“识别中/翻译中/等待原文确认/已完成/失败/未完整保存”。状态更新不移动条目；自动滚动节流，并尊重用户回看。

### P2：结束会话清掉未完成条目，用户无法知道哪里失败

位置：LiveTranslateViewModel.swift:550；LiveTranslateModels.swift:604、678。

finalize() 只重新计算已完成记录；finalizeCurrentSession 清空 activeTurns。等待条目会消失，不是被修复。正常完成的结果继续保存；缺关联、缺 final、空文本或失败条目应保留可解释状态，不能冒充完整双语记录。

### P2：长会话更新和持久化存在放大开销

位置：LiveTranslateModels.swift:640、655；LiveTranslateHistoryStorage.swift:75；LiveTranslateViewModel.swift:573；LiveTranslateView.swift:245、315。

每个事件遍历全部 source，对每条 source 再扫描/排序 responses；历史状态不释放。每条新完成记录又在 MainActor 同步读全量 JSON、排序、写全量 JSON，并发送变更通知。每次 activeTurns 文本变化都触发滚动动画。长会话可能出现 UI 卡顿、跳动和处理延后，但这是代码层面的风险，尚未测量真机耗时。

建议映射索引直接查找、只更新受影响条目、保留必要已完成索引、批量异步写盘、流式 UI 刷新与滚动节流。

## 其他协议观察

- VAD=0.5、静音500ms均在官方范围内；比文档默认1000ms更容易把有停顿的话拆成多条，这是产品参数选择，不能单独解释永久等待。
- 视觉增强采用每 VAD 一帧，但没有全局 <=2fps 限速；短 VAD 连续触发可能越过官方上限。JPEG 压缩在主队列也有开销。应加全局限速和图像尺寸约束，并异步编码。
- 当前原文/译文关联和文本快照替换思路合理，不需要推倒重做传输方案。
- 现有测试 CameraAccessTests.swift:315 期待未关联响应到达后 turns 为空，但当前实现保留已有 source-only turn；测试与当前展示策略不一致。需先统一策略再补失败和超时测试，不能仅凭已有用例数量认为覆盖充分。

## 离线复现

直接运行当前 LiveTranslateModels.swift，仅给 String.localized 添加原样返回的替身；合成数据，不连接网络：

| 输入事件序列 | 当前代码结果 |
|---|---|
| 五条 ASR final + 五条译文 final + response.done，但缺 previous_item_id 关联 | 五条原文卡片保留，完成记录零条 |
| ASR interim + 有效关联 + 译文 final + response.done | 译文 final=true，但仍是 provisional |
| ASR final + 有效关联 + 空译文 final + response.done | 双 final=true，仍无完成记录 |
| 前响应仅 created，后响应已有音频且 audio.done | activateNextIfReady 返回 nil，后响应阻塞 |
| 有效关联 + 双方非空 final | 正常生成一条完成记录 |

五个检查均通过。这里只验证状态机行为，没有运行完整 iOS XCTest、真机录音或端到端网络测试。

## 建议修复顺序与现场诊断

1. 先补 response.done/status/output、ASR failed/item_id、超时和空结果终态；不要隐藏未完成条目来掩盖问题。
2. 统一时间线、稳定排序、状态文案与未完成保留策略。
3. 修复关闭页面收尾和失败音频队列推进。
4. 最后优化刷新/持久化、图片限速和 VAD 参数。

现场需关联日志字段：业务sessionID、事件type、response_id、item_id、previous_item_id、status、ASR/译文final标记、原译文字数、等待原因与持续时间。现有服务日志已有事件类型和ID，但没有卡片等待原因；200条环形容量也可能很快被音频delta耗尽。无需记录原始音频、完整译文或API Key。用一次出现积累的真机过程，才能区分缺关联、ASR尚未完成、空输出、响应失败或客户端收尾问题。

## 修复实施结果（2026-09-09）

以上为修复前审查；本节记录修复后的行为：

- 统一状态：recognizing/translating/confirming/completed/failed/incomplete/empty/timedOut/unlinked。正常成功必须确认 response.done 状态；原译文不完整也明确保留，30 秒无文本进展显示超时，迟到结果可以原位恢复。
- 解析 response.done 的最终 output，并以其状态收尾；completed 空 output 显式结束为空结果。识别失败按 item_id 更新对应条目，不再只弹全局错误。
- 原文/译文仍按官方 ID 关联，不用先后顺序猜配。无法关联的译文在超时/结束时单独保留并标记未关联，后续关联通过 responseID 替换保存记录。
- 实时页面只有一个稳定时间线，保存后不搬动 cell；时间戳固定为条目创建时间。流式显示最多约 20Hz 更新，自动滚动节流150ms，无逐包滚动动画，用户回看仍暂停自动滚动。
- 页面退出走原有异步 finishSession，任务强持有 ViewModel/Service 直到收尾并提交保存；保留原有8秒网络结束超时。response.done 同时封口播放队列，失败/空响应不能挡住后续音频。
- 记录新增可选 status，兼容现有 schema 2 中没有 status 的记录；不完整状态在记录详情页显示。无新增破坏性迁移。
- 保存移到串行后台队列，一次合并批量变更。删除代际阻止排队写入恢复已删除记录。保存失败提示并提供重试入口。
- 图片异步压缩、最长边1280、最大500KB，发送端全局限制2fps，退出录音后丢弃未发送的编码结果。

验证：
- 29 个 XCTest（原关联测试、原播放队列测试、原历史存储测试、11个新增恢复/兼容/后台保存测试）使用实际 Foundation 状态机及存储源码，在 macOS XCTest 框架下执行，全部通过。本地化仅使用原样返回的测试替身，无网络和录音。
- TurboMeta 真机构建通过；模拟器 build-for-testing 通过，包含 App 与 XCTest 编译。不是完整模拟器 XCTest 执行结果。
- 尚未在本轮使用真实音频访问阿里服务；实际网络/VAD事件时序、持续翻译体验和退出末句应在手机上复验。没有宣称线上链路已无所有问题。

## 后续交付更新

- 实时翻译改为纯音频功能：移除视觉增强开关、设置、视频预览及图片发送链路；此前图像编码优化不再保留。
- 页面采用随系统切换的浅深色、珊瑚红按钮和原生 Liquid Glass。译文使用正文大小，原文使用较小字号；列表从固定语言栏后方滚动，按实际测量高度预留内容空间。
- 新增后台持久化 JSONL 诊断日志，仅记录时间、事件关联 ID、状态、输出长度及会话相对耗时，不记录原文、译文或音频。保留两个约 1 MB 的轮转文件，写入时清理超过七天未修改的文件，排除系统备份。
- 最终 TurboMeta 真机构建通过，并已安装、启动到连接的 iPhone。实际玻璃滚动观感由用户在手机上验收；未将设计生成图当作运行截图。
