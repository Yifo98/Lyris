# Lyricify 许可证与内容边界

验证日期：2026-07-22。

## Lyricify Lyrics Helper（Level B）

固定提交 `983709b2519f7c5ba32206424896533d14159c97` 的根许可证是 Apache License 2.0（[LICENSE L1-L5](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/983709b2519f7c5ba32206424896533d14159c97/LICENSE#L1-L5)），项目文件也声明 `Apache-2.0` package license（[csproj L23-L33](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/983709b2519f7c5ba32206424896533d14159c97/Lyricify.Lyrics.Helper/Lyricify.Lyrics.Helper.csproj#L23-L33)）。

若未来直接复制、修改或分发 Helper 代码，Apache-2.0 的固定文本要求至少包括：向接收者提供许可证副本、让修改文件带有显著修改说明，并保留适用的版权/专利/商标/署名 notice；只有原作品带有 `NOTICE` 文件时，才触发对应 `NOTICE` 复制要求（[LICENSE L89-L119](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/983709b2519f7c5ba32206424896533d14159c97/LICENSE#L89-L119)）。这不是针对具体分发方案的法律意见。

当前 Lyris 决定仍是 clean-room：

- Helper 只做模型、格式与行为研究；Swift 模型、parser、generator、matcher 和测试全部自行设计。
- 不复制源码、注释、常量表、测试样本、资源或操作文案。
- 若未来直接复用，先做单独许可证与依赖审查，再履行许可证、修改标注和 attribution 义务。

## Lyricify 4 主程序（Level C 边界）

Helper 的 Apache-2.0 **不覆盖** Lyricify 4 主程序、UI、品牌、图标、截图、产品文案或未公开内部实现。Lyricify 4 的官方文档只能用于记录其明确声明的产品事实，不能据此获得复制许可，也不能从 Helper 源码反推主程序实现。

## 源码许可不等于数据与接口授权

即使 Helper 源码可见，Apache-2.0 也不授予以下权利：

- 第三方歌词内容与数据库权利；
- Spotify 或其他服务的 Cookie、私有 token、私有歌词接口和认证绕过；
- QRC/KRC 解密所涉及的数据访问权；
- Lyricify、Spotify 或其他第三方品牌与资源使用权。

因此 Lyris 明确拒绝移植私有协议、QRC/KRC 解密、私有 Token、Spotify 私有歌词路径以及任何绕过第三方认证的实现。
