# LyricsX 许可证与 clean-room 边界

验证日期：2026-07-22。证据等级：**Level B（固定提交中的许可证文本）**。

## 固定许可事实

| 仓库 / 提交 | 可验证许可证 | 精确证据 |
| --- | --- | --- |
| LyricsX `e84963a6346b9a99dfdcaf082908f12247f1637b` | MPL-2.0 | [LICENSE L1-L5](https://github.com/MxIris-LyricsX-Project/LyricsX/blob/e84963a6346b9a99dfdcaf082908f12247f1637b/LICENSE#L1-L5) |
| MusicPlayer `ced0ac74f3dd2d364743581e66404af0e35d37e7` | MPL-2.0 | [LICENSE L1-L5](https://github.com/MxIris-LyricsX-Project/MusicPlayer/blob/ced0ac74f3dd2d364743581e66404af0e35d37e7/LICENSE#L1-L5) |
| LyricsKit `6f071990d0c9c6f48d29284db805990bffb912ed` | MPL-2.0 | [LICENSE L1-L5](https://github.com/MxIris-LyricsX-Project/LyricsKit/blob/6f071990d0c9c6f48d29284db805990bffb912ed/LICENSE#L1-L5) |

MPL-2.0 把包含 covered software 或其修改的源码文件纳入义务，同时把与 covered software 以独立文件组合的内容定义为 larger work；分发源码、可执行形式和 larger work 的条件分别见许可证正文（[LyricsX LICENSE L37-L57](https://github.com/MxIris-LyricsX-Project/LyricsX/blob/e84963a6346b9a99dfdcaf082908f12247f1637b/LICENSE#L37-L57)、[L160-L203](https://github.com/MxIris-LyricsX-Project/LyricsX/blob/e84963a6346b9a99dfdcaf082908f12247f1637b/LICENSE#L160-L203)）。这支持“文件级义务”的描述，但不是针对 Lyris 的法律意见。

## Lyris 当前决定

当前只做 **clean-room 研究**，不复制 covered code：

- 研究输出仅记录公开行为、字段语义、模块职责、风险和测试建议。
- Lyris 使用自有命名、自有协议、自有控制流和自有测试重新实现。
- 不复制或逐行翻译源码、注释、常量表、私有 header、entitlement、UI、资源和文案。
- 实现阶段不把第三方源码放在旁边逐行对照。

因此当前没有把 LyricsX、MusicPlayer 或 LyricsKit 的 covered file 混入 Lyris。若未来决定直接复用，必须在复用前单独做许可证评审，标识 covered files，并履行对应源码、许可证与 notice 义务；不能以“只是参考”为由悄悄混入。

## 许可证没有授予的内容

MPL 源码许可证不自动授予第三方歌词数据、品牌、图标、截图、私有 API、账号凭据或服务条款下的使用权。相关来源即使能在源码中看到，Lyris 仍须独立审查并默认不采用。
