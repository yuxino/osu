<div align="center">
  <img src="assets/brand/mimi-maid-v1.png" width="112" height="112" alt="Osu 头像">
  <h1>Osu</h1>
  <p>iPhone 上的悬浮翻译字幕。</p>
  <p>
    <a href="README.md">English</a>
    · <a href="CONTRIBUTING.md">从源码安装</a>
    · <a href="docs/acceptance/2026-09-20.md">测试记录</a>
  </p>
</div>

Osu 将其他 iPhone App 播放的声音识别、翻译成字幕，显示在画中画小窗中。灵感来自桌面端 [Mimi](https://github.com/yuxino/mimi)。

**预览版 · iOS 18+ · 需从源码安装。** 暂未上架 App Store 或 TestFlight。

<img src="docs/media/caption-style.png" width="640" alt="带有 Osu 头像与字标的字幕样式，当前译文醒目显示">

*字幕样式，使用示例文字。*

## 功能

- **像歌词一样显示**：云端字幕逐句上移，当前译文醒目，上一句淡下去。默认只看译文，原文可在首页或设置中开关。
- **自动识别语言**：阿里云模式默认自动识别原文语言、翻译成中文，也可手动选择语言。
- **本地或云端**：可选 Apple 本地识别与翻译，或阿里云实时同传。Apple 翻译需要 iOS 26 和支持的语言包，本地识别需手动指定原文语言。

## 灵动岛模式（暂不可用）

独立灵动岛字幕需要由收音进程持有实时活动，而 iOS 把两条路都堵死了：扩展查不到 App 创建的活动（进程隔离），扩展自己调用 `Activity.request` 会因 `ActivityAuthorizationError.visibility` 被拒——实时活动只允许前台 App 创建。两种失败均已在真机确认。Osu 在打开广播前拦截该模式，并提示切换画中画。

恢复该模式需要通过 APNs 推送更新 App 创建的活动，依赖后端服务。详见[验证记录](docs/acceptance/2026-09-25-island.md)。

## 开始使用

1. [编译安装](CONTRIBUTING.md)后，按提示填写阿里云百炼北京地域 API Key，或在设置中选择 Apple 本地模式。
2. 点「开始听」直接打开系统广播面板，选择「Osu Audio」并确认「开始广播」。
3. 切回视频 App。关闭字幕小窗或点「停止」即可结束收音。

视频请留在原 App 内播放：其他 App 的画中画可能替换 Osu 小窗并结束收音。开始广播前需关闭 iPhone 镜像。不同 App 的兼容性和长时间后台表现仍在验证。

## 隐私

Osu 不保存音频和字幕，视频帧与麦克风样本会直接丢弃。Apple 模式在本地处理；阿里云模式会上传 App 音频并产生账户用量，密钥保存在 iOS 钥匙串。

## 开发

使用 React Native、TypeScript 与 iOS 原生收音能力。详见[构建与检查](CONTRIBUTING.md)、[阿里云指南](docs/alibaba.md)和[语言与诊断](docs/languages-and-diagnostics.md)。

[MIT](LICENSE)
