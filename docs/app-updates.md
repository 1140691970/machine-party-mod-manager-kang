# 管理器更新

Windows x64 客户端启动时从 `https://machineparty.ailaogong.men/v1/app-updates/stable/latest.json` 检查更新。玩家也可以在设置页查看当前版本并手动检查。发现较新版本后，玩家点击提示确认安装。客户端下载 Windows 安装包，验证签名及签名中的版本，再启动 NSIS 安装并重启管理器。网络异常时仍可浏览本地目录。

## 维护者发布步骤

1. 在 `Cargo.toml` 和 `tauri.conf.json` 写入相同的稳定版本号，例如 `0.1.1`。运行 `cargo check` 更新锁文件，提交到 main。
2. 在 GitHub Actions 打开 **Release desktop app**，选择 main 后运行。Windows runner 会生成正式安装包和仅用于验收的旧版客户端。
3. 检查提交和构建结果，在 **Review deployments** 核准 production。签名密钥和 R2 凭证由该环境提供。
4. 工作流先上传版本专属安装包和清单，再安装旧版测试客户端，实际经过 Worker 下载、更新与重启。它检查运行版本和本地设置，然后创建 GitHub Release，最后切换稳定清单。此后已安装的客户端下次检查即可收到更新。
5. 失败时先查看失败步骤。若只是网络问题，选择 **Re-run failed jobs** 以复用已构建的安装包。若需要修正发布脚本，可在 main 发起新运行，在 `build_run` 填入原始构建的运行 ID。工作流会核对来源及应用代码，沿用原安装包。勾选 `verify_only` 可对已暂存的版本单独执行 Windows 升级验收。发布后的安装包按版本固定，替换内容需要新版本号。

若使用历史构建重试时 GitHub 在建 Release 步骤返回 403，维护者可用具有推送权限的账号，先运行 `git push origin <已验收的完整提交SHA>:refs/tags/v<版本>`，再重跑失败任务。工作流会检查已有标签与安装包来源一致。

## 托管与签名

Worker 从私有 R2 桶 `machine-party-mods` 的 `app-releases/` 读取。每个版本的安装包和清单位于 `<版本>/setup.exe` 和 `<版本>/manifest.json`。稳定清单位于 `stable/latest.json`，关闭缓存。首次发布前，稳定端点返回 HTTP 204。

首次部署或更改 Worker 时运行 **Deploy app update Worker**，在 production 核准。脚本使用已有的 Workers 权限绑定项目子域名。若无法自动取得区域 ID，可在 production 添加变量 `CLOUDFLARE_ZONE_ID`。部署使用 `CLOUDFLARE_ACCOUNT_ID` 和 `CLOUDFLARE_API_TOKEN`。发布另使用 `R2_BUCKET_NAME`、`R2_ACCESS_KEY_ID`、`R2_SECRET_ACCESS_KEY` 和 `TAURI_SIGNING_PRIVATE_KEY`。

首次安装从 GitHub Release 下载 `setup.exe`。客户端内置更新公钥。请把对应私钥另存于受保护的离线备份，后续版本须能通过已安装客户端的公钥验证。Tauri 更新签名独立于 Windows Authenticode。
