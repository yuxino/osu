# 灵动岛字幕模式下线报告

**日期**:2026-09-26
**结论**:独立灵动岛字幕模式自 build 18 起从 Osu 客户端下线。原因是 iOS 系统规则使纯客户端方案不可行,且已通过真机实验取得两种实现路径的直接失败证据。恢复该模式的前提是引入后端服务(见"复活条件")。

## 功能设想

Osu 的字幕由广播扩展(独立后台进程)抓取其他 App 的音频并翻译。设想将该译文显示到灵动岛与锁屏(实时活动),替代或补充画中画窗口,使字幕不受画中画被其他视频小窗顶掉的影响。

## 两次实现与真机失败

### 路径一:主 App 创建活动,扩展更新(2026-09-25 上午)

主 App 在前台创建实时活动,把活动标识经加密回连传给广播扩展,扩展按句更新。

**失败**:扩展进程调用 `Activity<SubtitleActivityAttributes>.activities` 查不到宿主创建的活动。`Activity.activities` 是**进程隔离**的,扩展永远看不到别的进程创建的活动。

**证据**:2026-09-25 07:09 UTC 设备日志,反复出现 `island/activity_unavailable`,随后 `broadcast/ended`;宿主连接正常但零翻译。

### 路径二:扩展自建活动(2026-09-25 下午,build 15)

移除跨进程依赖:广播扩展在收到鉴权配置后调用 `Activity.request` 创建并持有自己的实时活动。

**失败**:扩展进程的 `Activity.request` 抛出 `ActivityAuthorizationError`,错误码 6,对照 iOS 26.5 SDK 接口为 `.visibility`——苹果文档明确定义为"应用在后台时尝试启动实时活动"。系统规定**只有前台进程可以创建实时活动**,广播扩展永远不是前台进程。

**证据**:2026-09-25 12:05:53 UTC 扩展诊断(会话 `96CCCB87B…`):广播启动、配置鉴权解码成功、`island/activity_request_failed` code 6、广播于同一秒结束。20:05 与 22:53 的两次真机广播复现同样结果。

### 佐证

苹果对实时活动的合法更新通道只有三条:前台 App 本地调用、扩展更新**本进程创建**的活动、APNs 远程推送。非前台进程启动活动的唯一豁免是符合 `LiveActivityStartingIntent` 的 App Intent,它必须由用户 UI 操作触发,广播扩展无法使用。

## 已评估并排除的替代方案

- **任意悬浮窗**:iOS 不提供跨 App 悬浮能力,无对应权限或 API。
- **桌面小组件**:WidgetKit 刷新预算由系统控制(每天数十次),无法实时滚动字幕。
- **App Intents**:需要用户逐次手动触发,不适合连续字幕流。
- **Apple Watch 作为第二屏**:技术上可行(设备间直连、无需后端),但依赖用户佩戴手表且表盘过小,仅作为将来可选项,不在本次范围。

## 复活条件

复刻外卖类 App 的成熟模式:**前台创建 + 服务器推送更新**。

1. 主 App 在前台创建实时活动并取得推送 token(现 build 17 起已无此流程,需恢复);
2. 一台后端服务:接收扩展上传的译文,调用 APNs `liveactivity` 推送更新活动;
3. APNs 推送证书及其年度维护、推送 token 的生命周期管理。

代价:字幕文字需出设备再回来(增加约 1-2 秒延迟;音频仍不上传);需长期维护一台服务。若决定重启,客户端的扩展实现与测试管线可直接复用。

## 保留的资产

下线只移除宿主 App 的用户入口(模式切换与相关流程)。以下内容保留在仓库中,供将来 APNs 方案复用:

- `native/widget/SubtitleWidget.swift` 与 OsuSubtitles widget 扩展(实时活动渲染)
- `native/ios/BroadcastIslandSession.swift`、`SubtitleActivityAttributes.swift`、`IslandConfiguration.swift`(扩展侧完整管线,`Activity.request` 在扩展内被系统拒绝的兜底与诊断均保留)
- `native/tests/IslandFixture.swift` 与 `--verify-island-in-process` 模拟器用例(验证活动创建、更新、暂停、清理)
- 全部实验与失败证据:`docs/acceptance/2026-09-25-island.md`、`docs/plans/2026-09-25-dynamic-island.md`

## 用户可见的行为变化

- 模式切换(画中画/灵动岛)从首页移除,画中画成为唯一字幕承载方式;
- 历史版本可能遗留的宿主侧实时活动会在启动时被自动清理(扩展侧遗留活动宿主无法触及,由系统按过期策略回收);
- 画中画相关行为不受影响(含被其他视频小窗接管后的自动恢复)。
