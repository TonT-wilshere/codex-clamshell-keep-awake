# Apple 签名与公证

项目已经支持 Developer ID 签名、Hardened Runtime、Apple 公证、票据装订和 Gatekeeper 验证。真正提交前，维护者必须拥有有效的 Apple Developer Program 会员资格和证书。

## 一次性准备

1. 加入 [Apple Developer Program](https://developer.apple.com/programs/)。
2. 由 Account Holder 在 Apple Developer 后台创建 **Developer ID Application** 证书，下载并双击安装。不要使用 Apple Development、Mac Distribution 或临时证书。
3. 确认证书和私钥同时存在：

   ```bash
   security find-identity -v -p codesigning
   ```

4. 在 Apple Account 网站创建一个 app-specific password，然后使用安全交互提示保存公证凭据。不要把密码写进脚本、环境变量或仓库：

   ```bash
   xcrun notarytool store-credentials "clamshell-awake-notary" \
     --apple-id "你的 Apple ID" \
     --team-id "你的 Team ID"
   ```

   该命令会在终端中安全地提示输入 app-specific password，并验证后保存到 macOS 钥匙串。

## 生成已公证发布包

把下面的证书名称替换为 `security find-identity` 输出中的完整名称：

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE="clamshell-awake-notary" \
./notarize-release.sh
```

脚本会依次：

1. 用 Developer ID、Hardened Runtime 和安全时间戳签名 Universal 应用；
2. 向 Apple 提交应用，下载日志，并将公证票据装订到 `.app`；
3. 重新生成 ZIP 和签名 DMG；
4. 向 Apple 提交 DMG，将票据装订到 DMG；
5. 重新计算 SHA-256，并使用 `stapler`、`spctl` 和 `codesign` 验证最终产物。

Apple 返回的完整日志会保存在 `release/notarization-app-log.json` 和 `release/notarization-dmg-log.json`。只有两个状态都为 `Accepted` 且最终验证全部通过，才能在 Release 中标注“Apple notarized”。

## 普通本地构建

没有设置 `CODESIGN_IDENTITY` 时，`./build.sh` 和 `./package-universal.sh` 仍会生成 ad-hoc 签名的测试版本，但这种版本不是 Apple 公证版本。
