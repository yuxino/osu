# osu / Mimi iPhone prototype

React Native + TypeScript 应用中的 Mimi 真机可行性实验。
用户开启屏幕广播后，将其他 App 的声音转为本地识别的原文和所选语言的翻译，以画中画字幕窗显示。源语言和目标语言根据设备能力提供，不再写死为英语 → 中文。

当前为实验版本，不保证所有 App、受保护内容或长时间后台会话兼容。已验证与尚未验证的范围见 [实验记录](docs/iphone-prototype.md)。

## iPhone 上使用

1. 打开「真机实验」，选择声音语言与字幕语言，也可选择「仅显示原文」。
   源语言标为「本地不可用」时不可选；目标组合显示需下载时，先点「准备翻译语言包」并完成系统下载。
2. 开启字幕小窗，允许语音识别。
3. 点击屏幕广播按钮，选择 Mimi Audio 并开始广播。
4. 切换到播放所选源语言内容的 App。
5. 返回后点击「停止采集与字幕」，或关闭字幕小窗。

测试屏幕广播时先关闭 iPhone 镜像；系统不支持同时进行屏幕录制和屏幕镜像。
视频帧和麦克风样本会直接丢弃，音频仅通过手机内部回环连接传输。识别强制使用设备本地处理，翻译使用 Apple 下载的语言包；没有云端识别兜底。音频和字幕不保存，诊断日志只保留会话编号、时间、阶段、错误代码、语言设置和性能计数；可复制或导出。不会保存字幕、音频、密钥或任意错误描述。

## 构建独立 iPhone App

需要 Node.js 22.13+、Xcode、Ruby/Bundler，以及配置好的 Apple 签名团队。
此原型的翻译会话需要 iOS 26；iOS 18–25 可使用本地原文识别（取决于设备能力）。需要包含原生模块的独立安装包，不能在 Expo Go 运行。模拟器可验证界面与本地连接，但不能证明真机的语言资源或跨 App 采集可用。

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
