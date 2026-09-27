<div align="center">
  <img src="assets/brand/mimi-maid-v1.png" width="112" height="112" alt="Osu 头像">
  <h1>Osu</h1>
  <p>iPhone 上的悬浮翻译字幕。</p>
  <p>
    <a href="README.md">English</a>
    · <a href="CONTRIBUTING.md">从源码安装</a>
  </p>
</div>

Osu 将其他 iPhone App 播放的声音识别、翻译成字幕，显示在画中画小窗中。灵感来自桌面端 [Mimi](https://github.com/yuxino/mimi)。

**iOS 18+ · 开源 · 使用 Xcode 编译安装。**

<img src="docs/media/caption-style.png" width="640" alt="带有 Osu 头像与字标的字幕样式，当前译文醒目显示">

*字幕样式，使用示例文字。*

## 功能

- **像歌词一样显示**：云端字幕逐句上移，当前译文醒目，上一句淡下去。默认只看译文，原文可在首页或设置中开关。
- **自动识别语言**：阿里云模式默认自动识别原文语言、翻译成中文，也可手动选择语言。
- **本地或云端**：可选 Apple 本地识别与翻译，或阿里云实时同传。Apple 翻译需要 iOS 26 和支持的语言包，本地识别需手动指定原文语言。

## 灵动岛模式（已下线）

独立灵动岛字幕模式已下线：iOS 要求前台进程才能启动实时活动，收音扩展永远不满足；扩展也无法查到 App 创建的活动。两种失败均经真机确认，详见[下线报告](docs/dynamic-island-retirement.md)。恢复该模式需要引入 APNs 后端服务。

## 从源码安装

Osu 目前以源码形式提供。下载本仓库，在 Mac 上编译，再通过 Xcode 安装到自己的 iPhone。

需要 **Mac、Xcode、Node.js 22.13+、Ruby/Bundler、Apple 签名团队，以及运行 iOS 18 或更新版本的 iPhone**。

```sh
git clone https://github.com/yuxino/osu.git
cd osu
npm ci
bundle install
npm run ios:prebuild
npm run ios:configure
cd ios
bundle exec pod install
cd ..
npm run ios:device
```

首次安装时，用 Xcode 打开 `ios/` 内生成的 `.xcworkspace`。为主 App、**Osu Audio** 广播扩展和 **OsuSubtitles** 小组件扩展选择自己的签名团队，再连接并选择 iPhone。Release 构建会打包 JavaScript，安装后无需一直开着开发服务器。原生项目的详细说明见[构建指南](CONTRIBUTING.md)。

## 开始使用

1. [编译安装](CONTRIBUTING.md)后，按提示填写阿里云百炼北京地域 API Key，或在设置中选择 Apple 本地模式。
2. 点「开始听」直接打开系统广播面板，选择「Osu Audio」并确认「开始广播」。
3. 切回视频 App。在 Osu 里点「停止」即可结束收音。

视频请留在原 App 内播放。若其他 App 的画中画顶掉了 Osu 的字幕窗，收音和翻译会继续，对方小窗关闭后字幕窗自动恢复。开始广播前需关闭 iPhone 镜像。

## 隐私

Osu 不保存音频和字幕，视频帧与麦克风样本会直接丢弃。Apple 模式在本地处理；阿里云模式会上传 App 音频并产生账户用量，密钥保存在 iOS 钥匙串。

## 开发

使用 React Native、TypeScript 与 iOS 原生收音能力。详见[构建与检查](CONTRIBUTING.md)、[阿里云指南](docs/alibaba.md)和[语言与诊断](docs/languages-and-diagnostics.md)。

[MIT](LICENSE)
