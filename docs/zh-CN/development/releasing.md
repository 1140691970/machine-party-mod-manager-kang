# 发布管理器更新

[English](../../en/development/releasing.md) · **简体中文** · [繁體中文](../../zh-TW/development/releasing.md)

Windows x64 和 Apple Silicon Mac 客户端启动时静默从 `https://machineparty.ailaogong.men/v1/app-updates/stable/latest.json` 检查更新。发现较新版本时，设置页会显示红点，并对每个新版本自动弹出一次非强制更新弹窗（若当前已有弹窗则顺延队列），并在清单包含 `notes` 时展示更新说明；玩家也可随时在设置页点击版本号手动检查或重开更新提示。客户端验证下载包的签名及版本。Windows 调用 NSIS 安装程序，Mac 替换当前应用程序包并重启管理器。网络异常时仍可浏览本地目录。设计取舍见 [ADR-003](../architecture/ADR-003-desktop-updates.md)。

## 维护者发布步骤

1. 在 `apps/desktop/src-tauri/Cargo.toml`、`apps/desktop/src-tauri/tauri.conf.json` 和根目录 `package.json` 写入相同的稳定版本号，例如 `0.1.2`。在 `apps/desktop/src-tauri` 运行 `cargo check` 更新锁文件，在 `CHANGELOG.md`（及对应中文版）的 `## <version>` 节记录变更，提交到 main。`npm test` 会检查三处版本一致。
2. 在 GitHub Actions 打开 **Release desktop app**，选择 main 后运行。Windows runner 生成正式安装包和验收用旧版，Mac runner 生成 Apple Silicon 应用归档。两个平台共用稳定清单。
3. 检查提交和构建结果，在 **Review deployments** 核准 production。签名密钥和 R2 凭证由该环境提供。
4. 工作流先上传版本专属安装包和清单，再安装旧版测试客户端，实际经过 Worker 下载、更新与重启。它检查运行版本和本地设置，然后创建 GitHub Release，最后切换稳定清单。此后已安装的客户端下次检查即可收到更新。
5. 失败时先查看失败步骤。若只是网络问题，选择 **Re-run failed jobs** 以复用已构建的安装包。若需要修正发布脚本，可在 main 发起新运行，在 `build_run` 填入原始构建的运行 ID。工作流会核对来源及应用代码（文档、测试、脚本和工作流的改动除外），沿用原安装包。勾选 `verify_only` 可对已暂存的版本单独执行 Windows 升级验收。发布后的安装包按版本固定，替换内容需要新版本号。

若使用历史构建重试时 GitHub 在建 Release 步骤返回 403，维护者可用具有推送权限的账号，先运行 `git push origin <已验收的完整提交SHA>:refs/tags/v<版本>`，再重跑失败任务。工作流会检查已有标签与安装包来源一致。

## 托管与签名

Worker（`services/update-worker`）从私有 R2 桶 `machine-party-mods` 的 `app-releases/` 读取。每个版本目录包含 setup.exe、MachineParty-aarch64.app.tar.gz 和 manifest.json。`scripts/app-release.py` 会在设置环境变量 `RELEASE_NOTES` 时优先写入其中的内容作为 `manifest.json` 的 `"notes"`，否则自动从根目录 `CHANGELOG.md` 提取对应 `## <version>` 节。稳定清单位于 `stable/latest.json`，关闭缓存。首次发布前，稳定端点返回 HTTP 204。

首次部署或更改 Worker 时运行 **Deploy app update Worker**，在 production 核准。脚本使用已有的 Workers 权限绑定项目子域名。若无法自动取得区域 ID，可在 production 添加变量 `CLOUDFLARE_ZONE_ID`。部署使用 `CLOUDFLARE_ACCOUNT_ID` 和 `CLOUDFLARE_API_TOKEN`。发布另使用 `R2_BUCKET_NAME`、`R2_ACCESS_KEY_ID`、`R2_SECRET_ACCESS_KEY` 和 `TAURI_SIGNING_PRIVATE_KEY`。

首次安装时，Windows 从 Cloudflare 镜像下载 setup.exe。Apple Silicon Mac 下载 MachineParty-aarch64.app.tar.gz，解压后将 .app 放到可写的应用程序目录。Mac 包使用 ad hoc 代码签名，尚未经过 Apple Developer ID 公证。早期 Mac 原型缺少更新器，需要手动安装一次支持更新的版本。客户端内置更新公钥。请把对应私钥另存于受保护的离线备份，后续版本须能通过已安装客户端的公钥验证。Tauri 更新签名独立于 Windows Authenticode。

Windows 专用包的默认程序目录为 MachinePartyModManager。设置仓库变量 WINDOWS_SIGNING_RUNNER 和 WINDOWS_SIGNING_THUMBPRINT，使用已在签名存储区配置代码签名证书及私钥的专用 Windows runner，并将其限于受信任的发布任务。构建时签署主程序与 NSIS 安装程序并加时间戳。所有版本都可选用 Windows Authenticode。未设置发行者时，正式版与测试版均可发布未签名安装包；设置后须通过签名与发行者验证。发布新版本号的测试版时，在桌面发布工作流启用 publish_preview。已签名安装包在 GitHub 发布与 Cloudflare 镜像时分别验证内嵌 Authenticode 签名、证书指纹和时间戳。使用 app Worker 工作流的 preview_tag 同步同一份安装包。

使用 Azure Artifact Signing 时，WINDOWS_SIGNING_PROVIDER 设为 azure，WINDOWS_SIGNING_SUBJECT 填写已验证证书的完整主体名称。创建 Public Trust 配置文件，授权应用程序使用该配置签名。仓库变量设置 AZURE_ARTIFACT_SIGNING_ENDPOINT、AZURE_ARTIFACT_SIGNING_ACCOUNT、AZURE_ARTIFACT_SIGNING_CERTIFICATE_PROFILE、AZURE_CLIENT_ID 和 AZURE_TENANT_ID；AZURE_CLIENT_SECRET 存入仓库 Secret。测试包作为 GitHub 附件发布。需要时才单独同步 R2，同步安装包时跳过 Worker 部署。
