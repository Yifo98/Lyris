# Lyris 本机数据

开发版 Lyris 会把可管理的运行数据集中到这里：

- `Config/settings.json`：Spotify Client ID、翻译服务、模型、联动效果、歌词校准等非敏感配置镜像。
- `Lyrics/generated/`：从歌词源取得并完成翻译的自动歌词缓存。
- `Lyrics/manual/`：用户为具体 Spotify 曲目编写的歌词，优先级高于自动歌词。
- `Cache/Network/`：封面和普通网络响应缓存；不包含 Spotify 音频。

DeepSeek API Key 与 Spotify 刷新令牌不会写入本目录，只保存在 macOS Keychain。

通过 Lyris 设置里的“歌词与缓存”清理这些目录，能够避免误删用户手写歌词。
