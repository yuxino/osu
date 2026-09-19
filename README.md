# osu / Mimi iPhone prototype

React Native + TypeScript 应用中的 Mimi 真机可行性实验。
用户开启屏幕广播后，将其他 App 的声音转为原文和翻译，以画中画字幕窗显示。支持 Apple 本地处理，或沿用桌面 Mimi 协议的阿里云实时同传。

当前为实验版本，不保证所有 App、受保护内容或长时间后台会话兼容。已验证与尚未验证的范围见 [实验记录](docs/iphone-prototype.md)。

## iPhone 上使用

1. 打开「真机实验」，选择引擎、声音语言与字幕语言。
   - Apple 本地：可选「仅显示原文」。源语言标为「本地不可用」时不可选；需要翻译语言包时先下载。
   - 阿里云：配置百炼北京地域 API Key；源语言支持自动、中、英、日、韩，翻译目标支持中、英、日。密钥只存入当前设备系统钥匙串。
2. 开启字幕小窗。Apple 模式需允许语音识别；阿里云模式先建立云端连接，无需 Apple 语言包。
3. 点击屏幕广播按钮，选择 Mimi Audio 并开始广播。
4. 切换到播放所选源语言内容的 App。
5. 返回后点击「停止采集与字幕」，或关闭字幕小窗。

测试屏幕广播时先关闭 iPhone 镜像；系统不支持同时进行屏幕录制和屏幕镜像。
视频帧和麦克风样本会直接丢弃。Apple 模式强制本地识别并使用 Apple 下载的翻译语言包；阿里云模式将 App 音频上传至北京 DashScope，并产生账户用量，不会自动切换引擎或重连计费。App 不保存音频和字幕，诊断日志只保留会话编号、时间、阶段、错误代码、语言设置和性能计数；可复制或导出。不会保存字幕、音频、密钥或任意错误描述。

## 阿里云测试

选阿里云、日语 → 中文并配置密钥后，可点「云端日语测试」。App 在内存生成固定日语并实时发送，不用麦克风。此测试只验证云端识别与翻译，不能代替跨 App 收音验收。

本次移植 Mimi 的低延迟 LiveTranslate 模式；暂未包含 Audio 3.0 / Qwen-MT 高质量模式。停止会立即断开并丢弃待发送音频，末句可能未完成。使用说明与验证边界见 [阿里云指南](docs/alibaba.md)。

## 构建独立 iPhone App

需要 Node.js 22.13+、Xcode、Ruby/Bundler，以及配置好的 Apple 签名团队。
Apple 本地翻译需要 iOS 26；iOS 18–25 可使用本地原文识别（取决于设备能力）或阿里云模式。需要包含原生模块的独立安装包，不能在 Expo Go 运行。模拟器可验证界面与本地连接，但不能证明真机的语言资源或跨 App 采集可用。

```sh
npm ci
bundle install
npx expo prebuild --platform ios --no-install
npm run ios:configure
cd ios && bundle exec pod install && cd ..
npm run ios:device
```

首次在 Xcode 选择自己的开发团队。`ios:device` 构建 Release 包，JavaScript 已包含在 App 中，启动无需电脑开发服务器。

`native/ios/` 保存原生实验源码；`ios/` 为本机生成目录和缓存，不提交。每次重新 prebuild 后需运行 `ios:configure`。
独立音源测试工具源码在 `native/fixtures/`，不包含在正式 App 中。

## 检查

```sh
npm run typecheck
scripts/test-native.sh
bundle exec ruby -c scripts/configure-ios-prototype.rb
git diff --check
```

## 诊断与后续真机测试

- App 内点「复制诊断日志」或「导出诊断日志」，可在系统分享面板中保存到文件。
- 最近的记录会轮换，单个进程最多 6 个 128 KiB 日志文件，外加一份最多约 768 KiB 的导出副本。
- 手机必须连接电脑、信任并获得系统开发权限后，才能读取本地历史记录。**未连接时无法实时查看手机状态。**
- 采集日志、模拟器复现命令和最终真机步骤见 [语言与诊断验证指南](docs/languages-and-diagnostics.md)。

仓库保留旧 Flutter 项目的 Git 历史。
