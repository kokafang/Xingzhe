# Xingzhe · 醒着

一个「保持清醒」开关，让 Mac 持续运行。

原生 Swift / AppKit 顶栏工具，没有普通窗口或 Dock 图标。英文名为 **Xingzhe**。

[English](README.md) · [下载安装包](https://github.com/kokafang/Xingzhe/releases/latest) · [反馈问题](https://github.com/kokafang/Xingzhe/issues)

## 支持范围

- Apple 芯片 Mac（M 系列），macOS 13 或更高版本。
- 首次使用需要批准后台服务。
- 从 1.1.1 起，正式发布流程要求 Developer ID 签名和 Apple 公证。本地开发构建默认仍使用 ad-hoc 签名。此构建不支持 Intel Mac 和 Windows。

## 安装与使用

1. 从 [Releases](https://github.com/kokafang/Xingzhe/releases/latest) 下载 ZIP 并解压。
2. 将 **醒着.app** 放进「应用程序」文件夹，再打开。
3. 点击屏幕顶部菜单栏的月亮图标，打开「保持清醒」。太阳图标表示开启。
4. 如果系统请求批准，在「系统设置 → 通用 → 登录项与扩展」中允许「醒着」后台运行，再打开开关。部分 macOS 版本的页面名称是「登录项」。

如果使用早期未公证版本，请下载最新公证版本。macOS 仍可能显示从互联网下载应用后的正常首次打开确认。

首次运行会申请登录自启动，但每次启动时「保持清醒」默认关闭。删除应用前，请先关闭开关并退出。

## 应用内更新

在顶部菜单点击「检查更新…」，也可以开启「自动检查更新」，每天检查一次。首次会询问是否允许自动检查；是否安装由你决定，不会静默下载安装。

发现新版后展示更新说明和下载进度。更新信息与安装包均经过签名验证。安装前确认恢复原电源设置，恢复失败会暂停退出；重启后保持清醒默认关闭，并自动刷新后台服务。系统仍可能要求批准后台服务。

1.0.2 及更早版本需要先手动安装一次最新版；之后可在应用内完成更新。

## 工作方式

开启时通过系统电源设置禁止睡眠，并使用临时 IOKit 断言抑制显示器空闲休眠与自动锁屏。它不会修改密码设置，也不会解锁手动锁屏。

如果其他程序在开启期间重置防睡眠设置，后台会在下一次心跳重新应用并校验，保留最初的恢复记录。重新应用失败会结束保持清醒并尝试恢复，错误原因会记录到系统日志。

后台使用自适应调度。前台每 5 秒发起心跳，同一时间只等待一个心跳；单次回复最多等待 12 秒，后台租约仍为 20 秒。

关闭、退出、连接断开或后台心跳超时（20 秒）时，会恢复开启前的 SleepDisabled 值。后台崩溃后由系统重启，并根据磁盘记录恢复；恢复失败保留记录，每 2 秒重试。后台服务被强制停止或移除期间无法执行恢复。

合盖效果需要在目标电脑上分别用电池和接电实测；读回电源设置不能替代此项验收。公司设备的强制安全策略可能限制自动锁屏抑制。

## 构建与测试

在装有 Xcode 及命令行工具的 Apple 芯片 Mac 上执行：

```sh
git clone https://github.com/kokafang/Xingzhe.git
cd Xingzhe
bash scripts/build.sh
python3 scripts/test-launch-path.py
```

产物是 `build/醒着.app`。构建包含恢复逻辑和本地 XPC 超时测试、应用和后台编译、代码签名及 plist 校验，更新框架 Sparkle 2.9.6 随应用打包；构建脚本会下载并校验官方发行包。

生成包含应用、说明和许可证的分享包：

```sh
export CODE_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAM_ID)"
export NOTARY_PROFILE="YOUR_KEYCHAIN_PROFILE"
bash scripts/package-release.sh
```

产物是 `build/releases/1.1.1/Xingzhe-1.1.1-macOS-arm64.zip`，同目录下有 SHA-256 校验文件 `SHA256SUMS.txt` 和签名后的 `appcast.xml`。发布需要带私钥的 Developer ID Application 证书、有效的 notarytool 钥匙串配置和 Sparkle 更新签名密钥。运行 `xcrun notarytool store-credentials YOUR_KEYCHAIN_PROFILE` 交互式保存公证凭据；不要将密码或私钥写入仓库。脚本先完成公证并附加票据，再生成最终 ZIP 和更新签名。

## 项目结构

- `Sources/App`：顶栏界面、后台连接、临时防空闲断言。
- `Sources/Helper`：系统后台服务和电源配置。
- `Sources/Shared`：连接协议、双向签名验证和恢复逻辑。
- `Tests`：恢复机制和故障路径测试。
- `Resources`：应用图标及应用、后台服务配置。
- `scripts`：构建、发布打包和启动路径回归检查。

## 许可证

源代码采用 [MIT License](LICENSE)。应用图片素材不包含在源码许可证中，详见 [NOTICE](NOTICE)。

## 维护者发布

更新私钥只保存在本机登录钥匙串，Sparkle 账户为 `local.xingzhe.awake`；不得提交或上传私钥。Fork 项目需生成自己的密钥，并更换更新源、公钥和脚本中的签名账户。

递增 `Resources/Info.plist` 两个版本号，添加 `updates/release-notes/版本号.html`，更新日志并提交合并到 `main`，然后运行 `bash scripts/publish-release.sh`。脚本先发布并核验安装包，再提交签名更新源。已有版本不得覆盖安装包或手工修改签名 XML；发布中断时应恢复匹配的签名更新源附件，或发布新版本。

在有签名密钥的本机运行 `python3 scripts/test-updates.py` 可测试真实下载、签名验证、替换和重启。隔离测试应用不会注册正式后台服务，也不会修改系统电源设置。第三方许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
