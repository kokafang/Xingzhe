# Xingzhe · 醒着

一个「保持清醒」开关，让 Mac 持续运行。

原生 Swift / AppKit 顶栏工具，没有普通窗口或 Dock 图标。英文名为 **Xingzhe**。

[English](README.md) · [下载安装包](https://github.com/kokafang/Xingzhe/releases/latest) · [反馈问题](https://github.com/kokafang/Xingzhe/issues)

## 支持范围

- Apple 芯片 Mac（M 系列），macOS 13 或更高版本。
- 首次使用需要批准后台服务。
- 下载包使用本地 ad-hoc 签名，**尚未经过 Apple 公证**，用于试用；首次打开可能被系统拦截。此构建不支持 Intel Mac 和 Windows。

## 安装与使用

1. 从 [Releases](https://github.com/kokafang/Xingzhe/releases/latest) 下载 ZIP 并解压。
2. 将 **醒着.app** 放进「应用程序」文件夹，再打开。
3. 点击屏幕顶部菜单栏的月亮图标，打开「保持清醒」。太阳图标表示开启。
4. 如果系统请求批准，在「系统设置 → 通用 → 登录项与扩展」中允许「醒着」后台运行，再打开开关。部分 macOS 版本的页面名称是「登录项」。

如果首次打开提示开发者无法验证，请在确认来源可信后按 [Apple 官方说明](https://support.apple.com/zh-cn/102445)处理，无需关闭整个系统的安全保护。

首次运行会申请登录自启动，但每次启动时「保持清醒」默认关闭。删除应用前，请先关闭开关并退出。

## 工作方式

开启时通过系统电源设置禁止睡眠，并使用临时 IOKit 断言抑制显示器空闲休眠与自动锁屏。它不会修改密码设置，也不会解锁手动锁屏。

如果其他程序在开启期间重置防睡眠设置，后台会在下一次心跳重新应用并校验，保留最初的恢复记录。重新应用失败会结束保持清醒并尝试恢复，错误原因会记录到系统日志。

关闭、退出、连接断开或心跳超时（20 秒）时，会恢复开启前的 SleepDisabled 值。后台崩溃后由系统重启，并根据磁盘记录恢复；恢复失败保留记录，每 2 秒重试。后台服务被强制停止或移除期间无法执行恢复。

合盖效果需要在目标电脑上分别用电池和接电实测；读回电源设置不能替代此项验收。公司设备的强制安全策略可能限制自动锁屏抑制。

## 构建与测试

在装有 Xcode 及命令行工具的 Apple 芯片 Mac 上执行：

```sh
git clone https://github.com/kokafang/Xingzhe.git
cd Xingzhe
bash scripts/build.sh
python3 scripts/test-launch-path.py
```

产物是 `build/醒着.app`。构建包含恢复逻辑测试、应用和后台编译、代码签名及 plist 校验，无第三方运行时依赖。

生成包含应用、说明和许可证的分享包：

```sh
bash scripts/package-release.sh
```

产物是 `build/releases/Xingzhe-1.0.1-macOS-arm64.zip`，同目录下有 SHA-256 校验文件 `SHA256SUMS.txt`。

## 项目结构

- `Sources/App`：顶栏界面、后台连接、临时防空闲断言。
- `Sources/Helper`：系统后台服务和电源配置。
- `Sources/Shared`：连接协议、双向签名验证和恢复逻辑。
- `Tests`：恢复机制和故障路径测试。
- `Resources`：应用图标及应用、后台服务配置。
- `scripts`：构建、发布打包和启动路径回归检查。

## 许可证

源代码采用 [MIT License](LICENSE)。应用图片素材不包含在源码许可证中，详见 [NOTICE](NOTICE)。
