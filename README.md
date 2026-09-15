# osu

React Native + Expo + TypeScript 的全新项目起点。

## 开发

需要 Node.js 22.13 或更高版本。

```sh
npm install
npm start
```

- `npm run ios`：构建并启动独立 iOS 开发版（需要 Xcode 和 CocoaPods）。
- `npm run android`：构建并启动独立 Android 开发版（需要 Android SDK）。
- `npm run typecheck`：检查 TypeScript。

入口为 `App.tsx`。iOS / Android 原生目录由 Expo 按需生成。

仓库保留旧项目的 Git 历史；当前工作目录已重新初始化。

## 安装到 iPhone

手机需开启开发者模式并信任电脑，Xcode 中登录 Apple 账号并选择个人开发团队。

```sh
npm run ios:device
```

此命令构建 Release 版本并安装到所选手机，JavaScript 随 App 打包，启动无需 Expo Go 或电脑上的开发服务器。
