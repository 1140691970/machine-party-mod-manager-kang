# 正式目录发布与中国大陆连接验收

[English](../../en/catalog/delivery.md) · **简体中文** · [繁體中文](../../zh-TW/catalog/delivery.md)

**在线模组目录**　客户端启动时读取 Worker 快照，缓存通过校验的数据供离线浏览。每个版本通过 Release 资产 ID 对应 R2 键 `packages/sha256/<sha256>.zip`。仅开放允许镜像的安装包。 [ADR-006](../architecture/ADR-006-online-catalog.md)

## 玩家获取列表的路径

桌面端向项目 Worker 请求 `GET /v1/catalog.json?inventory=id&prepare=1`。Worker 从 R2 读取已批准的目录修订，旧版客户端可取得兼容快照。搜索、排序和语言切换均在本机完成。

| 项目 | 目录行为 |
| --- | --- |
| 快照标识 | 包含格式版本、目录修订号和模组清单。修订号标识整份快照，模组版本沿用上游标签。 |
| 模组数据 | 稳定 ID、固定收录序号、作者来源、三语简介与搜索别名、可选 R2 封面（`covers/sha256/<sha256>.<ext>`，通过 `GET /v1/covers/{modId}/{sha256}.{ext}` 提供，见 [ADR-016](../architecture/ADR-016-r2-mod-covers.md)）及已核准的版本数据。可安装版本需要兼容条件、固定资产、SHA-256 与客户端支持的安装方式。 |
| HTTP 响应 | Worker 为各个目录变体提供 ETag。请求的 `If-None-Match` 匹配时返回 304。 |
| 客户端落盘 | 桌面端校验目录格式，并验证签名以授权在线安装包。签名文档会缓存供离线验证，同时保存一份浏览副本。 |

启动时显示有效缓存并在后台刷新。单次请求超时为 15 秒。超时、连接失败或服务端错误（5xx）时自动重试一次。刷新失败时，玩家仍可浏览缓存条目并手动重试。“已安装”页也可通过本机记录离线卸载。

## 中国大陆玩家下载第三方模组

客户端通过 `GET /v1/downloads/{modId}/{version}/{assetId}` 获取已批准的安装包。Worker 核对目录映射及镜像许可，再从边缘缓存或私有 R2 返回文件。部署时会在写入新上游包之前核对大小及 SHA-256，客户端也会在安装前校验下载的包。

验收时屏蔽 GitHub，下载完整安装包及所需加载器，核对哈希，并测试断线和下架后的行为。若客户端支持断点续传，还须核对 Content-Range、条件续传及重组后文件的哈希。

上线前需要逐包核清授权。Overtime 的 MIT 范围只涵盖作者原创部分，补丁中保留了游戏脚本上下文；MachineParty+ 的 MPML 加载器须另行测试，并另行确认可分发范围。授权不明时只提供作者入口或经验收的直连。[Overtime 授权](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/LICENSE) · [MachineParty+ 安装需求](https://github.com/Ghostx10742/MachineParty-Plus#installation)

### 安装包准备与旧版兼容

一键安装先用目录大小和 SHA-256 核对作者发布的 ZIP，再由 Rust 在暂存区准备 MPML 目录。Overtime 读取 CLI 包中的 payload 清单，保留上游的加载时序、版本与原版脚本指纹检查。Broadcast 和 Binary1936 读取资源树。MachineParty+、滚筒嘉年华与房间机器人已采用加载器格式。 `?inventory=id&prepare=1` · `/v1/downloads/overtime/v1.7/594522625`.

旧版客户端仍可使用兼容目录与下载地址。已有的 Overtime MPML 安装可以继续使用。旧式受管 PCK 补丁可在模组详情选择「切换到加载器安装」，先验证新包，再还原已记录的副本并安装。手动安装的 mods/broadcast-8p 须先移出游戏目录。遇到未知文件变更时，还原会停止。

## 谁能发布

1. 贡献者通过 Issue 或 PR 推荐模组。维护者审核发布文件并更新 `catalog/mods.json`。目录 Worker 位于 `services/catalog-worker/`。详见[收录操作手册](mods.md)。
2. 由仓库所有者手动选择已合并的 main 提交发布。部署任务使用 GitHub 的 `production` environment，限制 main 并指定 JamesGZM 为必要审核人；单人维护时允许其批准自己的部署。审核界面应能核对提交 SHA、修订号与变更清单。PR 验证任务没有部署凭证。
3. Cloudflare 部署 Token 存为环境 Secret `CLOUDFLARE_API_TOKEN`，账号 ID 存为环境变量 `CLOUDFLARE_ACCOUNT_ID`，只授予目标账号部署所需的权限。App 只读取公开端点。[GitHub 部署环境](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments) · [Cloudflare Actions 部署](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/)
4. 部署后从正式域名读回 JSON，比对修订号与快照哈希，再用上一版客户端验证同步。记录提交、哈希、部署版本及结果。异常时由所有者批准重新发布上一份正常数据，配新修订号并清缓存；确认普通客户端能从坏版本恢复。回滚前核对已撤回的模组，避免意外重新开放下载。

## 如何验收大陆可达性

普通 Worker 加自定义域名提供稳定的服务名称，可以在同一地址调整部署。跨境连接仍受所在地、运营商与时段影响。Cloudflare China Network 是 Enterprise 客户另购的服务，产品支持范围需另行查询；本项目首版用普通 Worker 实测，尚未采购中国境内服务。[Cloudflare 中国网络说明](https://developers.cloudflare.com/china-network/) · [可用产品清单](https://developers.cloudflare.com/china-network/reference/available-products/)

| 上线前测试项 | 建议首轮通过条件 |
| --- | --- |
| 真实网络冷启动 | 在中国电信、中国联通、中国移动的普通家庭网络测试正式域名，覆盖至少两个省市及白天、晚间高峰，关闭 VPN／代理。每条线路每个时段冷启动 10 次。建议每组至少 9 次在 5 秒内显示正确目录，其余在一次自动重试内成功。逐组判定。 |
| 不依赖 GitHub | 屏蔽测试机到 GitHub、raw 与其资产域名的连接，清除 App 缓存后仍能从 Worker 获取最新修订，搜索与页面可用。另测图片失败时的标题封面。 |
| 版本与故障 | 测试 200、304、下架、回滚、DNS 失败、TLS 失败、超时与损坏 JSON，分别从首次安装及已有缓存开始。确认错误不覆盖有效缓存，恢复连接后可以同步。 |
| 端到端下载 | 每个对大陆开放安装的版本，用上述三网实际下载完整资产并核对哈希，另测中断重试。目录成功与下载成功分开记录。 |

记录日期、城市、运营商、时段、客户端版本、修订号、成功次数、首屏耗时及故障阶段（DNS、TLS、HTTP、解析或资产下载）。这些是发布方的实测数据。建议正式上线后在相同线路定期复测，更换域名或路由后重跑。测试门槛用于首版验收，持续的服务水平需要长期测量。

**未达标时的决策。** 先定位失败阶段，再评估由独立线路提供同一已批准快照的备用入口；只有客户端预置可用入口，才能在主站完全不可达时切换。若需要中国境内交付，再核对供应商支持、资质与成本。备用入口须通过同样的冷启动、更新、撤回与回滚验收，才对外宣布覆盖范围。
