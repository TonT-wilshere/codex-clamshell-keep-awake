# 参与贡献 / Contributing

感谢你愿意改进合盖工作。

## 本地构建

需要 macOS 12+ 和 Xcode Command Line Tools：

```bash
./build.sh
```

产物位于 `build/合盖工作.app`。脚本分别编译 `arm64` 与 `x86_64`，再合并为 Universal binary。

## 提交前检查

```bash
./build.sh
lipo -archs "build/合盖工作.app/Contents/MacOS/KeepCodexAwake"
codesign --verify --deep --strict "build/合盖工作.app"
```

请同时检查中文和 English 界面，并确保开启、关闭、退出、10% 保护和亮度恢复的行为一致。涉及 `pmset` 或授权流程的改动，请在 PR 中解释安全边界。

Bug 请尽量包含 macOS 版本、Mac 型号、应用版本、复现步骤和预期/实际结果，但不要粘贴密码、令牌或其他敏感信息。

---

Thanks for contributing. Build with `./build.sh`, test both UI languages, and verify enable, disable, quit, the 10% battery cutoff, and brightness restoration. Changes to `pmset` or privilege handling should explain their security boundaries in the pull request.
