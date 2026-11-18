# 候选模组与收录规范

[English](../../en/catalog/mods.md) · **简体中文** · [繁體中文](../../zh-TW/catalog/mods.md)

## 收录操作手册

**当前进度**　仓库已有[投稿表单模板](../../../.github/ISSUE_TEMPLATE/mod-submission.yml)，合入 GitHub 默认分支后才会出现在 New issue 中。以下为目标流程；Release 查询、草案生成、CI、R2 上传和 Worker 发布尚待实现。目前 App 使用随包发布的 `catalog/mods.json`。

| 步骤 | 谁操作 | 做什么、完成后得到什么 |
| --- | --- | --- |
| 1. 投稿 | 任何人，包括维护者 | 在 Issues → New issue 选择“模组收录或版本更新”，填写作者仓库、指定版本和用途。没有 Release 也可以作为候选。投稿者无需编辑 Markdown 或 JSON。 |
| 2. 初审与选文件 | 维护者＋自动流程 | 维护者接受推荐后，流程列出指定 Release 的资产名称、大小与来源，并标出重复投稿。维护者选定要整合的文件及加载器。以 Overtime v1.7 为例，直接改包路径选 CLI ZIP；普通包和 MPML 包用途不同。 |
| 3. 生成收录草案 | 自动流程 | 把选定资产下载到暂存区计算 SHA-256，记录上游标签、资产 ID、长度，创建或更新同一份草案 PR。目前唯一的结构化来源是 `catalog/mods.json`；流程接通后拟拆为每个模组一个 `catalog/mods/*.json`，再生成同格式的目录快照。没有发行文件的留在候选。程序只读取投稿数据与安装包，不执行投稿内容。 |
| 4. 核实能否发布 | 维护者 | 按下方验收单记录授权及 Windows 实测，确认游戏兼容、安装、卸载与离线还原。依赖逐个核对。把结果补入草案，CI 验证字段、哈希、依赖及重复 ID。缺证据时保留候选状态。 |
| 5. 批准上线 | 仓库所有者 | 合并草案后选择 main 的指定提交，在 production 环境核对本次新增／更新／撤回的条目并批准。合并与正式部署分开。 |
| 6. 分发并验证 | 自动发布任务 | 按已批准的哈希重新校验原文件，把允许留存的安装包写入私有 R2（相同哈希可复用），确认资产可读后才部署 Worker 目录，再从正式入口核对修订号与下载内容。若上游已换文件或资产未备齐，停止发布并保留旧目录。玩家下次刷新即可看到新版本。 |

**日常维护。** 新版沿用已有的模组 ID 与收录序号，重新选文件和验收；新版通过前，已发布的版本继续生效。撤回版本时走同一个所有者批准流程，同步撤回目录资格及旧下载入口，保留本机卸载。部署后验证失败按[发布回滚流程](delivery.md)处理。首版可以先用表单收件，流程接通后再启用自动生成 PR；逐个模组的 Markdown 调查用于保留背景，不参与发布。

## 游戏基线

Machine Party（Steam App ID 4108000）官方标注支持 2–4 人、在线合作、共享／分屏与 Remote Play Together。游戏使用 Godot，社区模组可以直接修改 PCK，或通过社区加载器加载外部模组。原版多人能力、模组新增能力及不同联机安装要求，应在条目说明中分别写清楚。[Steam 商店](https://store.steampowered.com/app/4108000/Machine_Party/) · [开发者公告](https://steamcommunity.com/app/4108000/announcements/) · [MPML](https://github.com/Krunk-theduck/MachinePartyModLoader)

## 候选清单

截至 2026-11-18，以下均为文档与上游代码调查，等待团队实机验证。下载次数是指定 GitHub Release 文件的历史快照，供评估需求使用。

| 候选 | 功能与下载观察 | 整合与授权待办 |
| --- | --- | --- |
| [Overtime](https://github.com/DarkJadeStone/MachineParty-Overtime) | 八人在线及本地扩展。v1.7 普通包 2,855 次，CLI 包 1,215 次。 | 优先测试 Steam 游戏 v2.1.2 搭配 v1.7 CLI。确认还原记录与离线卸载；直接改包与 MPML 路径互斥。MIT 只涵盖作者原创部分。[安装文档](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/docs/INSTALL.md) · [授权](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/LICENSE) |
| [MachineParty+](https://github.com/Ghostx10742/MachineParty-Plus) | 公开房间、语音及文字聊天。v2.1.0 模组 ZIP 1,917 次。 | 模组采用 MIT；另需核对 [MPML](https://github.com/Krunk-theduck/MachinePartyModLoader) 的版本、首次安装流程及中转授权。测试房间代码与原版玩家加入；语音聊天需要双方安装。 |
| [Binary1936 八人模组](https://github.com/Binary1936/machine-party-8p) | 在线八人。v1.5 模组 ZIP 5,297 次。 | 上游依赖 Steam 验证来还原，须测试 App 自行备份、还原与识别未知副本。MIT 适用的文件以作者的 [NOTICE](https://github.com/Binary1936/machine-party-8p/blob/main/NOTICE.md) 为准。 |
| [Broadcast 8P Freecam](https://github.com/Lnksoul/MachineParty_Broadcast8P_Freecam_Patcher) | 一位导播加八名参赛者，四队轮换及自由镜头。下载量未核实。 | 安装脚本有 install、verify、uninstall 入口。重点测试已有备份；确认具体文件授权后再决定是否中转。公开仓库首页未见明确的开源授权。[补丁源码](https://github.com/Lnksoul/MachineParty_Broadcast8P_Freecam_Patcher/blob/main/patcher.ps1) |

## 收录验收单（每个版本填写）

- 模组 ID、作者主页、固定发行文件、提交或标签、SHA-256、授权范围及直连／中转决定。
- 测试日期、Windows 与 Steam 游戏版本、原版 PCK 指纹、模组和加载器版本。
- 干净安装、从 Steam 启动、功能验证、重启后识别、离线卸载及还原验证结果。
- 支持的联机组合、已知冲突、游戏更新、下载失败、安装中断及恢复的结果。
- 维护者确认后才发布可安装版本；下架时保留现有用户的本机卸载能力。新增模组才分配收录序号。
- 上架时附大陆三网下载记录、测试资产哈希与最终交付路径。若只能浏览，单独记录下载限制。测试方法见[目录交付方案](delivery.md)。
- 逐一登记主安装包与必需加载器的上游 Release、资产 ID、文件名、大小、SHA-256，以及各自允许的直连、中转或留存方式。同标签同文件名但内容变化时视为新候选；原哈希核对失败即停止安装，重新验证并由所有者批准后再发布。
