# ADR-007：模组适配层与 macOS 模拟验证

[English](../../en/architecture/ADR-007-mod-adapters.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-007-mod-adapters.md)

日期：2026-11-18。状态：提议；待 Windows 上的 Overtime 验收（P2）后与 [ADR-005](ADR-005-install-transactions.md) 一并定稿。

## 问题

上游模组均以未经修改的原版压缩包发布，安装方式各有不同：

1. Overtime v1.7：`.NET` 控制台程序（`overtime_install.exe` 搭配 `overtime_payload.zip`），向 `Machine Party.pck` 追加脚本并改写索引，同时生成几 KB 的差量还原记录（`overtime_restore.dat`）。
2. Binary1936 八人模组 v1.5：Python 补丁脚本（`install.py`，Windows 包内附 `python/python.exe`），重写整个 `Machine Party.pck` 且不保留备份。
3. Broadcast 8P Freecam v0.91：PowerShell 补丁脚本（`patcher.ps1`），重写 `Machine Party.pck` 并保存整包备份（`Machine Party.pck.broadcast_backup`）。
4. MachineParty+ v2.1.0：加载器模组包（`mod.json`、`main.gd`、脚本与翻译），放入 MPML 的 `mods/` 目录。

若为每个模组在 Rust 中硬编码安装逻辑，后续收录成本会越来越高；但若直接执行在线目录随附的可执行适配脚本，会引入远程代码执行风险，也违反 [ADR-005](ADR-005-install-transactions.md)。此外，Steam 上的 Machine Party 仅支持 Windows，在 macOS 上需要分层的模拟方式来提前验证核心逻辑。

## 提议的决策

### 1. 交易引擎 + 内置适配器工厂 + 目录声明式 `adapter` 配置

继续以 `catalog/mods.json` 作为唯一数据源（[ADR-002](ADR-002-catalog-source.md)），为可安装模组追加可选的声明式 `adapter` 对象。配置只是纯数据，绝不包含可执行脚本。

无 Tauri 依赖的 Rust 交易引擎统一负责跨模组的安全保障：

- **游戏目录解析**：把已保存的 Steam 游戏根目录（用作 `installations.json` 的键，例如 `.../party project`）映射到实际包含 `Machine Party.pck` 的内层目录（例如 `Machine Party_Windows`）。
- **进程与文件锁检查**：写入前确认游戏未运行，并取得独占文件锁。
- **暂存下载与完整校验**：在 Rust 端从既有 Worker 域名（`https://machineparty.ailaogong.men/v1/downloads/{id}/{version}/{assetId}`）下载到暂存区，对照目录核对外层 ZIP 字节数与 SHA-256，原样解压后核对内部校验清单（`SHA256SUMS.txt` 及/或 preflight 命令）。
- **写入前基线与交易日志**：为 `Machine Party.pck` 及声明的 `touches` 文件计算安装前 `size` 与 `sha256` 指纹；校验 `exclusive` 互斥组（所有直接改包模组共用 `"exclusive": "pck"`，并与 MPML 互斥）；写入 `pending` 交易日志；写入后执行读回自检（并检查游戏目录内没有未声明文件被改动）；提交 `committed` / `rolled_back` 状态并在启动时对账。

适配器工厂根据 Rust 内置适配器种类派发：

- `upstream-cli`：在已校验的解压目录内，使用白名单允许的解释器（`exe`、`bundled-python`、`powershell`）运行相对路径程序或脚本；使用固定的动作参数模板（`preflight`、`status`、`install`、`uninstall`）、仅限引擎提供的占位符（`{gameDir}`）、关闭 `stdin`、强制非交互参数（如 `--no-pause`）、禁用参数守卫（始终拒绝 `--force`），以及用于判定 `installed`、`vanilla`、`older` 状态的正则或退出码规则。
- `loader-files`（P3 使用）：在 MPML `mods/<id>` 等加载器目录中复制或移除声明的模组文件。

后续新增模组只要符合既有适配器种类，只需在 `catalog/mods.json` 中补充声明式 `adapter` 配置并通过实机验收即可，无需改动代码；新增适配器种类则需要 Rust 代码与新的 ADR。

```json
"adapter": {
  "kind": "upstream-cli",
  "platforms": ["windows"],
  "target": "pckDir",
  "touches": ["Machine Party.pck", "overtime_restore.dat"],
  "exclusive": "pck",
  "baseline": {"file": "Machine Party.pck", "size": 634798100, "sha256": "326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e"},
  "verifyFiles": "SHA256SUMS.txt",
  "run": {"interpreter": "exe", "program": "overtime_install.exe", "common": ["--game", "{gameDir}", "--lang", "en", "--no-pause"]},
  "actions": {"preflight": ["--verify-package"], "status": ["--status"], "install": [], "uninstall": ["--uninstall"]},
  "status": {"installed": "^State:\\s+Overtime overtime-1\\.7 installed", "vanilla": "^State:\\s+vanilla", "older": "^State:\\s+Overtime .* installed \\(this program"},
  "forbiddenArgs": ["--force"]
}
```

### 2. 分级且由 App 托管的备份策略

备份不能只交给上游工具，因为各模组的备份行为不同，部分上游甚至完全不留备份。

- 写入前始终计算并记录 `Machine Party.pck` 的文件大小与 SHA-256。
- **支持差量还原的安装器**（如 Overtime 会生成含原始长度、基线 SHA-256 及新旧索引的 `overtime_restore.dat`）：交易引擎将该还原记录与已校验的卸载程序（`overtime_install.exe`）复制到 App 按副本保存的存储目录中，确保即使暂存区或游戏目录内的记录丢失也能离线卸载。
- **无差量还原的安装器或后备路径**（`"upstreamUninstall": false`，如 Binary1936 `install.py`）：修改前由交易引擎在按副本存储中保存已校验的完整 `Machine Party.pck` 备份（约 605 MB），卸载时直接还原。
- **检测到的手动安装**：若 `status` 报告磁盘已有安装但 `installations.json` 没有记录，在界面明确提示；仅当还原记录的基线 SHA-256 与已知原版 PCK 指纹（v2.1.2 为 `326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e`）一致时，才允许接管或卸载。来历不明的备份绝不当作原版。

### 3. Windows 目标平台与 macOS 三层模拟验证

Steam 上的 Machine Party（App ID 4108000）仅支持 Windows，不支持在 macOS 游玩。macOS 桌面端用于目录浏览、校验及开发期模拟，正式界面不开放常规 Windows 模组安装。

在 Windows 实机验收（P2）前，macOS 开发与测试分为三层：

- **L1（单元与契约测试）**：`FakeRunner` + 合成 Godot PCK 生成器（仅数 KB，含合法 `GDPC` 魔数、文件头与 `res://` 索引）+ 故障注入（下载中断、写入中途崩溃、Steam 更新替换 PCK、未知第三方修改、游戏进程占用）。
- **L2（真实子进程测试）**：`ProcessRunner` 启动跨平台假 CLI 脚本（复现 Overtime 参数与 `State:` 输出协议），并用真实跨平台上游脚本（`python3` 运行 Binary1936 `install.py`）对合成 PCK 进行实测。
- **L3（本机原版 PCK + Mono 验证）**：仅限本机开发验证，不提交游戏文件；使用从 Windows 复制的未提交原版 `Machine Party.pck`（v2.1.2，`634,798,100` 字节，SHA-256 `326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e`）与 Mono 运行真正的 `overtime_install.exe`，跑通 `--verify-package`、`--status`、安装、安装后 `--status`、`--uninstall` 与原版 SHA-256 逐字节还原校验。

## 替代方案

- **在线目录随附可执行适配脚本**：否决，存在远程代码执行风险并违反 [ADR-005](ADR-005-install-transactions.md)。
- **在 Rust 中重写所有 PCK 补丁器**：否决，重复上游逻辑且一旦上游格式变化就会失效。
- **拆出独立的 `catalog/adapters/*.json` 文件**：否决，现阶段会过早拆分单一数据源（[ADR-002](ADR-002-catalog-source.md)）；若日后按模组拆分目录文件再一并生成。
- **所有模组一律复制 605 MB 整包备份**：否决其作为 Overtime 的首选方案，因经过校验的差量还原仅占数 KB 且能做全包 SHA-256 核验；但对无差量记录的安装器（如 Binary1936）仍必须使用整包备份。

## 兼容性

- `catalog/mods.json` 维持 `schema: 1`；新增的可选 `adapter` 字段为增量扩展，旧版客户端会直接忽略。
- `installations.json`、`game-path.json`、既有 Tauri 命令名称及桌面更新配置（[ADR-003](ADR-003-desktop-updates.md)）均保持不变。

## 所需证据

macOS 上通过 L1、L2、L3 模拟验证，随后在 Windows Steam v2.1.2 完成实机验收（P2）：安装 Overtime v1.7，从 Steam 启动完成一局，断网后单次卸载并确认还原后的 `Machine Party.pck` 与原版 SHA-256 一致，详见[产品需求](../requirements.md)与[开发指南](../development/README.md)。
