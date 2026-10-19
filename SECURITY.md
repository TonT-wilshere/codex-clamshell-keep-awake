# 安全说明 / Security

## 权限模型

合盖工作只在用户点击开启后，通过 macOS 自带的管理员授权弹窗运行一次受限的 `pmset` 会话。应用本身不会读取或保存管理员密码，也不会写入 sudoers、安装 LaunchDaemon、内核扩展或常驻 root helper。

会话由当前应用 PID 和保存在用户目录中的随机一次性标记共同约束。以下任一条件满足时，看守都会执行 `pmset -a disablesleep 0`：

- 用户点击关闭；
- 应用正常退出或进程消失；
- 使用电池且电量降至 10%；
- 单次授权会话达到 7 天。

开启时保存的内置屏幕亮度只存入当前用户的偏好设置，用于关闭或下次启动时恢复。应用不调整外接显示器。

## 数据与网络

应用没有网络请求、账户系统、遥测或自动更新逻辑。它只读取本机电源、显示器和电池状态。

## 报告漏洞

请不要在公开 Issue 中发布可被直接利用的细节。请通过 GitHub 账户主页所列的联系方式联系维护者，并包含复现步骤、受影响的 macOS 与应用版本。维护者会尽快确认并协调披露。

---

Clamshell Awake requests administrator approval only after the user clicks Enable. It never reads or stores the password and installs no sudoers rule, daemon, kernel extension, or persistent privileged helper. The session is tied to the current app process and a random one-time marker. It restores normal sleep on disable, exit, process loss, 10% battery, or a seven-day timeout. There is no network request or telemetry.
