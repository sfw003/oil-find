# Fork 发版与更新

本节仅适用于 `sfw003/oil-find`。上游的 `ci.yml`、官网及 `scripts/package.sh` 保持不变；fork 通过 `build-app.yml` 构建免费版，不依赖私有模块或上游发布说明。

## 固定签名

GitHub 仓库 Secrets 使用 `MACOS_SIGNING_P12`（base64 PKCS#12）及 `MACOS_SIGNING_P12_PASSWORD`。证书 CN 为 `Oil Find Self-Signed`，RSA 2048、3650 天、digitalSignature/codeSigning、CA:false。OpenSSL 3 导出时使用兼容 macOS 的 PKCS#12 算法（例如 `-legacy`）。首次配置需要用户明确同意；不要每次构建重新生成证书，也不要把密钥或密码写进 Git。

按要求，初始化后不在 box 保留密钥、证书包或密码备份。GitHub Secrets 无法读回；如果丢失这套 Secrets，重新生成的同名证书也不是原签名身份，现有用户必须手动安装并重新授权。仓库中能修改并运行 workflow 的人实际上拥有签名权限，请限制写入权限。

构建将证书导入临时 keychain，签名后验证完整包，日志输出 `codesign -dvv`（应包含 `Authority=Oil Find Self-Signed`）及 designated requirement。退出时清理 keychain 和临时文件。普通分支没有 Secrets 时允许 ad-hoc；部分 Secrets 缺失、导入失败或 tag 构建缺少证书均失败，不降级发布。

自签名并非 Apple Developer ID，也未公证，首次安装仍可能需要在 macOS「隐私与安全性」中允许打开。原有 ad-hoc/上游安装无法凭这次修改自动切换签名；请手动安装一次固定签名的 fork 包。之后仅接受与当前应用 designated requirement 匹配的更新，不再接受上游 Developer ID 回退。

## 版本与发版

源文件 `Resources/Info.plist` 的 `CFBundleShortVersionString` 保持上游版本。CI 仅在构建副本中把 `CFBundleVersion` 设为 `1_000_000 + github.run_number`，不提交版本覆盖。`run_number` 随本 workflow 递增，重跑同一次 run 不增加；此值远大于当前上游 build 22。`UpdateVersion` 先比较 SemVer，再在相同版本下比较 build，因此同为 1.8.2 时可以从 22 升至 1000001，再升至 1000002。不要删除并重建 workflow 以免重置序号；如必须重建，或上游构建号超过此范围，先增加脚本中的 `BUILD_BASE`，确保超过已分发构建号。

普通分支 push / workflow_dispatch 只生成 artifact `Oil-Find-macOS`，包含 `Oil-Find-macOS.zip`、校验过的模拟 `latest-v2.json` 和 `signature.txt`，不发布。模拟清单中的 tag 不是已经存在的 Release，不能作为在线更新源。

只有用户确认发版后，才推送一个 `v*` tag。tag 必须是 `v<Info.plist version>` 或 `v<version>+sfw.N`；例如：

```sh
# 先确认该提交的 CI 与签名构建均通过，并征得用户发版同意。
git tag -a 'v1.8.2+sfw.1' -m 'Fork release: double Control shortcut and independent updates'
git push origin 'v1.8.2+sfw.1'
```

`+sfw.1` 是 tag 的构建元数据，不把应用版本改成低于 1.8.2 的 prerelease（不要改成 `1.8.2-sfw.1`）。再次发布同一应用版本可用 `+sfw.2`；构建号由新的 run 自动递增。不要同时推送多个发版 tag，也不要覆盖既有 tag/Release。

tag workflow 必须成功使用固定证书签名，生成与最终 zip 的 size/SHA-256 及实际包版本一致的 `latest-v2.json`；中英文 notes 来自 tag 内容（缺省通用说明）。再创建正式、非 prerelease 的 GitHub Release，附加 zip 与清单并标记为 latest。该发布路径只在真正推 tag 后执行，普通分支测试不会创建 Release。

## 更新边界

- 清单固定为 `https://github.com/sfw003/oil-find/releases/latest/download/latest-v2.json`。尚无正式 Release 时，检查可能返回 404，自动检查按原逻辑静默失败。
- 清单里的 zip 必须位于 `github.com/sfw003/oil-find/releases/download/<tag>/<asset>.zip`。
- 仅允许 HTTPS 且精确匹配 `github.com`、`objects.githubusercontent.com`、`release-assets.githubusercontent.com` 的跳转；不允许第三方、子域通配、非标准端口、凭证或降级到 HTTP。公开 GitHub CLI release asset 实测为 `github.com` 302 → `release-assets.githubusercontent.com` 200。
- `allowLocalhost` 仅供原有受控更新演练，保留 loopback 请求及同源本地跳转，不允许 GitHub 与 localhost 之间跳转。
- 下载后的大小、SHA-256、完整代码签名、bundle id、版本匹配、备份与回滚校验均保留。
- 原有「跳过此版本」按版本字符串记录，因此同一 1.8.2 的后续 build 也会被自动跳过；手动检查不受影响。需要新的独立版本提示时提升 SemVer。

`Tests/Scripts/test_fork_release.py` 在任意 Python 3 环境验证构建号、tag 和清单约束；Build App 还用 Swift 的 `UpdateManifest.parse` 和实际应用、zip 再核验生成结果，并在有证书时测试同一证书跨构建更新及篡改拒绝。
