# 阿里云实时同传

## 配置与使用

在「真机实验」选择阿里云引擎，打开密钥设置，输入阿里云百炼北京地域 API Key。密钥仅保存到该安装环境的系统钥匙串，不会读取桌面 Mimi 的凭据。可在同一界面移除；模拟器与手机配置互不共享。

开始云端会话意味着将采集到的 App 音频上传给阿里云并产生账户用量。云端数据处理以服务商规则为准；本 App 不落盘音频、字幕、密钥或服务端原始错误消息。默认仍为 Apple 本地模式。

使用固定模型 `qwen3.5-livetranslate-flash-realtime`，北京 DashScope WebSocket，16 kHz 单声道 PCM16，与桌面 Mimi 低延迟方案一致。源语言自动/中/英/日/韩；目标中/英/日。显式相同源与目标不能启动；仅显示原文使用 Apple 模式。

先等云端连接成功，再开始 Mimi Audio 屏幕广播。停止或关闭字幕窗会关闭连接和采集，不自动重连。发送缓存限制约两秒；拥塞、超时或服务错误会停止，需手动重试。停止时不等待末句，可能丢失未完成字幕。原文和译文分别显示最新结果，不提供逐句配对历史。

## 模拟器测试

Apple 翻译模型不支持模拟器，因此云端路径绕开了这一限制；ReplayKit 能否采到实际网页声音仍需单独验证。

「云端日语测试」只生成固定合成日语，内存转换并按实时速度发送；不录麦克风、不采网页。收到原文及译文时报告成功，但不判断翻译质量。需要有效密钥及网络。停止按钮可取消测试。

2026-09-19 已通过完整 Release 模拟器构建和未签名 iPhone 编译，并在独立 App 界面验证阿里云切换、日语 → 中文及缺密钥时阻止启动。

本轮已通过协议/缓冲/过期事件测试、模拟器钥匙串增改查删、模拟 WebSocket 的生产客户端收发停止流程，以及模拟器日语合成 PCM 生成。模拟服务返回不能证明阿里云真实推理成功。真实云端识别、B站跨 App 收音和新版手机后台验收尚未完成，不能将旧版英文真机结果当作新云端方案的证明。

```sh
scripts/test-native.sh
bundle exec ruby scripts/configure-simulator-harness.rb
scripts/test-simulator.sh SIMULATOR_UDID --verify-cloud
scripts/test-simulator.sh SIMULATOR_UDID --verify-sample
scripts/test-simulator.sh SIMULATOR_UDID --verify-transport
```

## 协议来源

- [阿里云客户端事件](https://www.alibabacloud.com/help/en/model-studio/live-translator-client-events)
- [阿里云服务端事件](https://www.alibabacloud.com/help/en/model-studio/live-translator-server-events)
- 桌面 Mimi：`src-tauri/src/core/protocols/live_translate.rs`、`src-tauri/src/clients/live_translate_client.rs`。

当前交付为源码预览版。iPhone 编译通过不等于已签名分发；没有 TestFlight/App Store 发布，需使用自己的 Apple 开发签名安装。不会在本轮自动操作手机。
