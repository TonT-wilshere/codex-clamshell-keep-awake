<div align="center">

<img src="Assets/hero.svg" alt="合盖工作 — 让 AI 编程任务在 MacBook 合盖后继续运行" width="900">

# 合盖工作 · Clamshell Awake

**合上 MacBook，Codex、Claude Code、终端脚本和下载任务继续跑。**

[English](README_EN.md) · [下载最新版](https://github.com/TonT-wilshere/codex-clamshell-keep-awake/releases/latest) · [报告问题](https://github.com/TonT-wilshere/codex-clamshell-keep-awake/issues)

![macOS](https://img.shields.io/badge/macOS-12%2B-111827?logo=apple)
![Universal](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-Universal-2563eb)
![Swift](https://img.shields.io/badge/Swift-native-f05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-16a34a)
![No telemetry](https://img.shields.io/badge/telemetry-none-7c3aed)
[![Build](https://github.com/TonT-wilshere/codex-clamshell-keep-awake/actions/workflows/ci.yml/badge.svg)](https://github.com/TonT-wilshere/codex-clamshell-keep-awake/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/TonT-wilshere/codex-clamshell-keep-awake?color=0ea5e9)](https://github.com/TonT-wilshere/codex-clamshell-keep-awake/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/TonT-wilshere/codex-clamshell-keep-awake/total?color=f59e0b)](https://github.com/TonT-wilshere/codex-clamshell-keep-awake/releases)
[![Stars](https://img.shields.io/github/stars/TonT-wilshere/codex-clamshell-keep-awake?style=social)](https://github.com/TonT-wilshere/codex-clamshell-keep-awake/stargazers)

</div>

## 为什么做这个

把一个长任务交给 Codex、Claude Code 或其他本地 AI 编程代理后，我们常常只想合上电脑去吃饭、通勤或休息。但 macOS 默认会在合盖时睡眠，终端进程、构建、下载和本地代理也会随之暂停。

`合盖工作` 是一个原生、轻量、开源的 macOS 小工具：点一次开启，确认绿色状态后即可合盖；任务结束后点一次关闭，系统恢复正常合盖睡眠。

> 适合长时间 coding agent、编译、下载、数据处理和远程任务。不是“关机后继续运行”——电脑真正关机后，任何应用都无法继续工作。

## 特性

| 功能 | 行为 |
| --- | --- |
| 真正支持合盖 | 使用 macOS `pmset disablesleep`，不只是阻止空闲睡眠的 `caffeinate` |
| 中英双语 | 右上角一键切换中文 / English，并记住上次选择 |
| 10% 低电量保护 | 使用电池降至 10% 时自动结束会话并恢复正常睡眠 |
| 亮度联动 | 开启成功后把 MacBook 内置屏幕降到最低；关闭、退出或保护触发时恢复原亮度 |
| 状态可信 | 直接读取内核 `SleepDisabled`，只有系统真正接受设置才显示绿色 |
| 自动收尾 | 点击关闭、正常退出、进程结束或单次会话达到 7 天时恢复默认睡眠 |
| 权限克制 | 每次会话由 macOS 请求管理员授权；不安装 sudoers、不留常驻 root 服务 |
| 隐私优先 | 无网络请求、无账户、无遥测，全部逻辑可审计 |
| 通用构建 | 一个安装包同时支持 Apple Silicon 和 Intel，最低 macOS 12 |

## 下载与安装

1. 前往 [Releases](https://github.com/TonT-wilshere/codex-clamshell-keep-awake/releases/latest)，下载 Universal `.dmg`（推荐）或 `.zip`。
2. 将 `合盖工作.app` 拖进“应用程序”。
3. 这是未经 Apple 公证的独立开源构建；若首次打开被拦截，请在 Finder 中右键应用并选择“打开”。
4. 点击“开启合盖工作模式”，在 macOS 系统弹窗中完成一次管理员授权。
5. 看到绿色“已开启 · 合盖后继续工作”再合上屏幕。

也可以从源码构建：

```bash
git clone https://github.com/TonT-wilshere/codex-clamshell-keep-awake.git
cd codex-clamshell-keep-awake
./build.sh
open "build/合盖工作.app"
```

构建仅使用 macOS 自带的 Swift 工具链和系统框架，不需要第三方依赖。

维护者的 Developer ID 签名与 Apple 公证流程见 [NOTARIZATION.md](NOTARIZATION.md)。普通 `./build.sh` 仍生成仅供测试的 ad-hoc 签名版本；只有 Apple 返回 `Accepted` 且票据装订、Gatekeeper 验证通过的包才可称为“已公证”。

## 开启与关闭的边界

| 操作 / 状态 | 合盖工作 | 内置屏幕亮度 |
| --- | --- | --- |
| 绿色“已开启” | 合盖后继续运行 | 降到最低 |
| 点击窗口左上角红色按钮 | **继续运行**，只隐藏界面 | 保持最低 |
| 再次双击应用或从菜单栏打开 | 恢复控制界面 | 保持最低 |
| 点击“关闭并恢复正常睡眠” | 恢复系统默认合盖睡眠 | 恢复开启前亮度 |
| 从菜单栏退出 | 先恢复默认睡眠，再退出 | 恢复开启前亮度 |
| 使用电池降至 10% | 自动恢复默认睡眠 | 恢复开启前亮度 |
| 真正关机 | 所有任务停止 | — |

如果应用被强制终止，特权看守会因应用进程消失而恢复正常睡眠；下次启动应用时还会尝试恢复之前保存的屏幕亮度。你也可以随时使用键盘亮度键手动调高。

## 安全与隐私

- 开启后不要把仍在运行的 Mac 放进包里。请放在坚硬、通风的表面，长任务最好连接电源。
- 管理员密码由 macOS 系统弹窗处理；本工具无法读取，也不会保存密码。
- 每个会话使用一次性随机标记，并绑定当前应用进程；应用结束后看守自动收尾。
- 不写入 `/etc/sudoers`，不安装 LaunchDaemon、内核扩展或持久化 root helper。
- 不联网、不上传数据、不收集使用统计。

更完整的威胁模型和报告方式见 [SECURITY.md](SECURITY.md)。

## 工作原理

```text
点击开启
   ↓
macOS 管理员授权
   ↓
pmset -a disablesleep 1  +  保存并降低内置屏幕亮度
   ↓
看守：应用 PID + 一次性标记 + 电池电量
   ↓
关闭 / 退出 / 进程消失 / 电量 ≤ 10% / 7 天超时
   ↓
pmset -a disablesleep 0  +  恢复原始亮度
```

`caffeinate` 可以阻止空闲睡眠，却不能可靠覆盖合盖触发的睡眠，因此本项目使用 `pmset disablesleep`。这是 macOS 的未公开参数，系统大版本升级后请重新验证行为。

## 路线图

- [x] Developer ID 签名与 Apple 公证自动化流程
- [ ] 首个 Apple 返回 `Accepted` 的正式公证版本
- [ ] Homebrew Cask 安装
- [ ] 可选的自定义低电量阈值
- [ ] 更多语言

欢迎提交 Issue 和 Pull Request。开发说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## License

[MIT](LICENSE)

---

如果它替你守住了一次长任务，欢迎点一下右上角的 **Star**。这会让更多 Codex、Claude Code 和本地 AI agent 用户找到它。⭐
