<div align="center">
  <img src="assets/brand/mimi-maid-v1.png" width="112" height="112" alt="Osu 头像">
  <h1>Osu</h1>
  <p>在 iPhone 上，边听边看译文。</p>
  <p>
    <a href="README.md">English</a>
    · <a href="CONTRIBUTING.md">从源码安装</a>
    · <a href="docs/acceptance/2026-09-20.md">测试记录</a>
  </p>
</div>

将其他 App 的声音变成悬浮字幕，灵感来自桌面端 [Mimi](https://github.com/yuxino/mimi)。

**预览版 · iOS 18+ · 需从源码安装。** 暂未上架 App Store 或 TestFlight。

<img src="docs/media/caption-style.png" width="640" alt="带有 Osu 头像与字标的字幕样式，当前译文醒目显示">

*字幕样式，使用示例文字。*

## 功能

- **像歌词一样显示**：云端字幕逐句上移，当前译文醒目，上一句淡下去。默认只看译文，原文可在首页或设置中开关。
- **自动识别语言**：阿里云模式默认自动识别原文、翻译成中文，想指定语言时再选。
- **本地或云端**：可选 Apple 本地识别与翻译，或阿里云实时同传。Apple 翻译需要 iOS 26 和支持的语言包，本地识别需手动指定原文语言。

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
