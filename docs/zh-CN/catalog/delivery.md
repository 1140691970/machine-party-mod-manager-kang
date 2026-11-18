# 正式目录发布与中国大陆连接验收

[English](../../en/catalog/delivery.md) · **简体中文** · [繁體中文](../../zh-TW/catalog/delivery.md)

**状态**　首版设计。现有客户端仍使用随包发布的 `catalog/mods.json`（[ADR-002](../architecture/ADR-002-catalog-source.md)）。正式域名、Worker、发布工作流与三网验收结果均待落地。

## 玩家获取列表的路径

Windows App 经 HTTPS 向自有域名的 Worker 请求 `GET /v1/catalog.json`。域名在部署时决定。首版把已批准的完整 JSON 快照随 Worker 一次部署，读取列表时无须回源 GitHub，也无须数据库、玩家账号或 API Token。搜索、排序与三语切换均在本机完成。封面加载失败时显示标题封面，避免图片拖慢目录。作者项目链接只在玩家主动点击时打开。

| 契约 | 首版设计 |
| --- | --- |
| 快照标识 | 包含格式版本、目录修订号、发布时间及模组清单。修订号标识整份快照，模组版本沿用上游标签。 |
| 模组数据 | 稳定 ID、固定收录序号、作者来源、三语简介与搜索别名、封面及已核准的版本数据。可安装版本需要兼容条件、固定资产、SHA-256 与客户端支持的安装方式。 |
| HTTP 响应 | 成功时返回 JSON 与对应内容的 ETag；内容相同且客户端带有匹配的 If-None-Match 时返回 304。最新版缓存建议不超过 5 分钟，紧急下架时清除该路径缓存。 |
| 客户端落盘 | 收到 200 后先验证格式版本、必要字段、唯一 ID 和资产数据，再用临时文件原子替换本机快照及 ETag。304 沿用有效快照；本机缺文件或损坏时改发无条件请求。错误页、截断内容与不支持的格式都保留上一份有效快照。 |

**启动与刷新。** 有缓存时立即显示，后台检查新版。首次安装没有缓存时请求 Worker，建议单次超时 4 秒，短暂网络错误最多再试一次，之后提供手动重试。首次同步失败时显示“尚未获取在线目录”及重试入口，设置与本机安装记录仍可打开。已有缓存时标注“使用缓存”和上次成功同步的时间。已安装页合并本机记录与目录，下架后仍可查看及离线卸载。安装或更新前重新确认发布状态，无法确认时保留原安装。

## 中国大陆玩家下载第三方模组

首版为允许中转的已验证安装包提供同域名下载入口，建议路径为 `GET /v1/downloads/{modId}/{version}/{assetId}`。App 只向这个地址取文件；Worker 根据本次核准发布的快照查找资产，在服务端向作者固定的 Release 文件取回内容。GitHub 若把请求重定向到发行资产主机，由 Worker 处理重定向，确认最终主机属于允许的上游，再把响应主体流式传给 App。直接把 302 或作者下载地址交给玩家仍要求玩家能连上 GitHub。下载端点只接受已收录的标识符。[Workers 流式文档](https://developers.cloudflare.com/workers/runtime-apis/streams/)

| 每个发行文件的条件 | 交付方式 |
| --- | --- |
| 已验证，授权允许中转 | App 统一从 Worker 下载；能中转但不能留存时才采用流式回源，并核实适用的服务条款。下载成功后用已发布的大小和 SHA-256 校验，再进入安装。 |
| 已批准固定版本且允许留存与再分发 | 建议首版即使用私有 R2 安装包库。发布时上传已校验的原文件，以 SHA-256 标识对象，Worker 经 binding 读取。玩家沿用同一下载入口。 |
| 仅允许作者直连，或再分发授权待确认 | 显示作者来源与直连限制；经大陆三网实测后才标注直连可用。不得通过中转或镜像改变授权条件。 |

下架时先撤回下载映射并清除该文件的公开缓存，新请求核查发布状态后才读取缓存或 R2。上游缺文件时报告安装包暂不可用。首版验收需要在测试机屏蔽 GitHub 与其 Release 资产域名后，从正式 Worker 域名下载完整安装包及所有必需的加载器，确认没有跳转到外站并核对哈希；另测上游失效、断线及下架后再次请求。测试覆盖三网，目录和各安装包分开记录结果。

### 2026-11-18 交付路径调研

从 [Overtime v1.7](https://github.com/DarkJadeStone/MachineParty-Overtime/releases/tag/v1.7) 获取 CLI ZIP。GitHub 返回 302 到 release-assets.githubusercontent.com；下载 854,623 bytes，SHA-256 为 `f98b51526c9ba38167adc0578f24d2d998f6d2f4df51e6146580df27b589245c`，与 Release API 的资产摘要一致。包内含安装器与 payload ZIP。本次只检查字节与封装。

| 本机 Miniflare / workerd 测试 | 完整 GET | Range: bytes=0-1023 |
| --- | --- | --- |
| Worker 流式转发真实 GitHub Release | 200，854,623 bytes，哈希相同 | 206，1,024 bytes，逐字节相同 |
| Worker 读取模拟私有 R2 的同一对象 | 200，854,623 bytes，哈希相同 | 206，1,024 bytes，逐字节相同 |

部分读取只证实了范围数据正确；正式端点仍需测试 Content-Range、条件续传、完整重组及中断恢复。上述测试不含正式 Cloudflare 边缘、Windows 游戏安装和大陆线路。

另外两个候选在 GitHub Release API 中的安装包大小分别为 [MachineParty+ v2.1.0](https://github.com/Ghostx10742/MachineParty-Plus/releases/tag/v2.1.0) 的 94,946 bytes 与 [Binary1936 v1.5](https://github.com/Binary1936/machine-party-8p/releases/tag/v1.5) 的 32,387,456 bytes。三个包合计约 33.34 MB，尚未计入加载器与多版本。对于允许再分发的原文件，这个规模可以优先选择私有 R2，以固定快照解除玩家下载对上游在线状态的依赖。R2 Standard 每月免费额度为 10 GB-month 存储、100 万次 A 类及 1,000 万次 B 类操作，直接从 R2 的出站流量免费；Worker 请求另计。Cloudflare CDN 对大文件传输有服务条款，应按实际账号方案核实，不能把橙云视为无限制的文件分发服务。[R2 计费](https://developers.cloudflare.com/r2/pricing/) · [Workers 计费](https://developers.cloudflare.com/workers/platform/pricing/) · [CDN 服务条款](https://www.cloudflare.com/service-specific-terms-application-services/)

上线前需要逐包核清授权。Overtime 的 MIT 范围只涵盖作者原创部分，补丁中保留了游戏脚本上下文；MachineParty+ 的 MPML 加载器须另行测试，并另行确认可分发范围。授权不明时只提供作者入口或经验收的直连。[Overtime 授权](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/LICENSE) · [MachineParty+ 安装需求](https://github.com/Ghostx10742/MachineParty-Plus#installation)

## 谁能发布

1. 社区通过同仓库的 Issue 表单推荐模组，维护者选定资产后由流程生成草案 PR；熟悉数据格式的贡献者也可以直接提 PR。完整步骤见[收录操作手册](mods.md)。收录数据位于 `catalog/`，目录 Worker 拟放在 `services/`，与现有的 `services/update-worker` 并列。PR CI 检查格式、重复 ID、版本与资产数据，并生成可预览的快照。合并只更新仓库。
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

## 实现顺序

先在仓库定义快照格式与验证样本；再完成 Worker、部署审核与正式域名，验证所有者可以发布、撤回和回滚。接着让 Rust 客户端读取、缓存与刷新目录，执行三网冷启动验收。最后配合 Overtime 的 Windows 安装与还原测试，验证第一个可下载版本。
