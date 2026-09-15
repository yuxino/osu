# osu / Mimi iPhone prototype

React Native + TypeScript 应用中的 Mimi 真机可行性实验。
目标：用户开启屏幕广播后，将其他 App 的英语声音转为本地识别的英文和中文翻译，以画中画字幕窗显示。

当前为实验版本，不保证所有 App、受保护内容或长时间后台会话兼容。已验证与尚未验证的范围见 [实验记录](docs/iphone-prototype.md)。

## iPhone 上使用

1. 打开「真机实验」，准备英中本地翻译语言包。
2. 开启字幕小窗，允许语音识别。
3. 点击屏幕广播按钮，选择 Mimi Audio 并开始广播。
4. 切换到播放英语内容的 App。
5. 返回后点击「停止采集与字幕」，或关闭字幕小窗。

测试屏幕广播时先关闭 iPhone 镜像；系统不支持同时进行屏幕录制和屏幕镜像。
视频帧和麦克风样本会直接丢弃，音频仅通过手机内部回环连接传输。识别强制使用设备本地处理，翻译使用 Apple 下载的语言包；没有云端识别兜底。音频和字幕不保存，诊断文件只包含计数和运行状态。

## 构建独立 iPhone App

需要 Node.js 22.13+、Xcode、Ruby/Bundler，以及配置好的 Apple 签名团队。
此原型的翻译会话需要 iOS 26；仅在真机独立安装包中提供，不能在 Expo Go 运行。

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
bundle exec ruby -c scripts/configure-ios-prototype.rb
git diff --check
```

仓库保留旧 Flutter 项目的 Git 历史。
