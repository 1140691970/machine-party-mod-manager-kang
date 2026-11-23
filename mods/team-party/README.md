# Team Party（組隊派對）

`team-party` 是《Machine Party》的**房間層全域組隊管理與原版關卡組隊掛接模組**：在大廳左上角提供 **OFF（自由混戰）／2/TEAM／4/TEAM／FREE（自由 2–4 隊）**切換、3D 座椅點擊／拖曳換位、Smart Bot Swap 與房主單鍵隨機洗牌（含房內既有 `lobby-bots` 機器人），對無法修改原始碼的官方原版關卡透過動態場景掛載提供隊伍名牌染色、`▼ [TEAM]` 標記、友軍防推過濾與小隊同步計分，並透過 `Engine` Meta（`&"mpm_team_party"`）向第一方自研小遊戲（[`bubble-blitz`](../bubble-blitz/README.md)、[`spike-ring`](../spike-ring/README.md)、[`roller-carnival`](../roller-carnival/README.md)）公開共享團隊註冊表——各款自研小遊戲則以共享的 `team_support.gd` **在自身模組內原生實作專屬團隊規則**（`team-party` 未安裝時自動無痕降級為 FFA）。

- **模組 ID**：`team-party`
- **版本**：`0.1.0`（待確認發布；目錄目前標註為 `"verified": false`）
- **授權**：`GPL-3.0-only`
- **目標遊戲版本**：Steam Windows `v2.1.2`
- **載入優先權**：`-5`

---

## 核心機制（繁體中文 / 简体中文 / English）

### 繁體中文
- **職責分離架構（房間管理＋原版掛接 vs. 自研小遊戲原生實作）**：
  - `team-party` 專責大廳分隊管理、右上角無邊框 Squad HUD、原版官方關卡動態掛接與共享團隊註冊表 API，已完全移除早期對自研小遊戲的執行期程式碼覆寫包裝。
  - [`bubble-blitz`](../bubble-blitz/README.md)、[`spike-ring`](../spike-ring/README.md)、[`roller-carnival`](../roller-carnival/README.md) 各自內建共享輔助腳本 `team_support.gd`，在模組內部原生處理出生分組、友軍豁免／救援／護盾共振、AI 敵我識別、提前勝出與小隊同步計分。
- **大廳內全權手動／隨機分隊（絕不自動補機器人）**：
  - 房主可在大廳左上角面板切換 `OFF`、`2/TEAM`、`4/TEAM`、`FREE (自由 2–4 隊)`，支援 `2v2v2v2`、`4v4`、`3v3` 或如 `3v2v2` 的不對稱人數分組。
  - **絕不自動生成機器人**：僅對房內目前已存在的真人與既有 [`lobby-bots`](../lobby-bots/README.md) 機器人進行指派或隨機洗牌；人類可點擊椅子、請求換位或由房主直接在 3D 大廳拖曳人物換椅，開局前未分隊成員會自動補入人數最少的隊伍並透過 RPC 同步全房。
- **隊友識別與聚光燈共存**：
  - 大廳與各 3D 小遊戲角色頭頂名牌附加對應語系標籤（`[紅]` / `[红]` / `[RED]` 等）並著隊色；搭配 [`player-spotlight`](../player-spotlight/README.md) 時保留本地主角聚光燈色彩，並以標籤與頭頂備援標記維持清晰識別。
- **各模式友軍與計分規則**：
  - **原版推擠淘汰（由 `team-party` 動態掛接：Disco Dodge / DVD Roomba / Train Race / Scavenger Chairs）＆ `lobby-bots`**：過濾推擠範圍與機器人 AI 目標中的同隊隊友；僅剩 1 隊存活時提前勝出。
  - **泡泡爆破（Bubble Blitz，由其自身原生支援）**：依隊順時針分組角落出生、免疫隊友炸彈；瀕死 4 秒顯示 `[救命!]`，**隊友碰觸立即救援回 1 血＋1.5 秒無敵**（AI 隊友亦會救人）；僅剩 1 隊存活提前勝出。
  - **尖刺圓環（Spike Ring，由其自身原生支援）**：同隊相鄰環形出生、免疫隊友推搡與 360° 衝擊波（AI 亦不誤推隊友）；撿取防爆護盾時 `3.5m` 內存活隊友同步觸發**護盾共振**；僅剩 1 隊存活提前勝出。
  - **滾筒嘉年華（Roller Carnival，由其自身原生支援）**：依隊伍排列相鄰 Z 軸跑道與隊色底座／名牌；僅剩 1 隊存活提前勝出。
- **Fall Guys Squads 式小隊同步計分**：
  - 結算取同隊最高個人分數＋「全員存活 `+1`」獎勵，確保隊友共享完全一致的過場分數。

### 简体中文
- **职责分离架构**：`team-party` 专注大厅分队管理、全局注册表、`Squad` 顶部状态栏与官方原版小游戏动态挂接（已退役旧版自研小游戏执行期源码包装），`bubble-blitz`、`spike-ring`、`roller-carnival` 各自通过 `team_support.gd` 原生实现本局组队机制并在未安装 `team-party` 时无痕降级为个人混战。
- 支持大厅自由混战 / 2人队 / 4人队 / 自由队数手动、拖拽换椅及洗牌分队（绝不自动补全机器人）、名牌染色与队伍前缀、原版防友军误推，以及同队最高分 + 全员存活 `+1` 同步结算。

### English
- **Clean Responsibility Split**: `team-party` owns lobby team management, the shared Engine team registry, the frameless top-right Squad HUD, and runtime hooks for vanilla minigames (no runtime source-rewriting wrappers). `bubble-blitz`, `spike-ring`, and `roller-carnival` natively read the registry via shared `team_support.gd` and degrade cleanly to FFA when `team-party` is disabled.
- Provides FFA / 2-per-team / 4-per-team / custom 2-4 team selection, 3D chair drag-and-drop & one-click shuffle across existing room members + bots (never auto-filling bots), team nameplate coloring/badges (cooperating with `player-spotlight`), vanilla friendly-fire filtering, early team wins, and Fall Guys Squads-style synchronized scores.

---

## macOS 多模組整合測試沙盒（推薦本機試玩）

因 macOS 無法直接啟動 Steam Windows 版《Machine Party》，我們提供了一套完整的整合測試沙盒，讓你能在 macOS 上直接把 `team-party` 搭配 `lobby-bots`、`player-spotlight`、`Bubble Blitz`、`Spike Ring`、`Roller Carnival` 與 `Disco Dodge` 一次測完：

```sh
# 1. 啟動可互動 macOS 整合測試視窗（大廳分隊＋一鍵切換 4 款小遊戲＋F5/F6/F7/F8 實測組隊能力）
./mods/team-party/run_mac.sh

# 2. 執行 Godot headless 全模組端對端自動化驗證（Lobby 3v2v2 + 4 款小遊戲組隊機制全測）
./mods/team-party/run_mac.sh --self-test

# 3. 擷取測試沙盒畫面截圖
./mods/team-party/run_mac.sh --screenshot "$PWD/.agent/mod-dev/dist/team_party_sandbox.png"

# 4. 全倉契約與單元測試
node scripts/pack-mod.mjs --all --verify-catalog
npm run check:architecture && npm test
```

### 沙盒內建快速操作
- 頂部工具列 / 數字鍵 `1`–`5`：於 **房間大廳**、**泡泡爆破**、**尖刺圓環**、**滾筒嘉年華**、**迪斯可推擠** 之間即時切換（沿用大廳目前分配好的陣容與隊伍）。
- 大廳右側面板：自由增減模擬真人玩家與 `Lobby Bots` 機器人，或一鍵套用 `2v2`、`3v2v2 (不對稱)`、`8人 2v2v2v2` 預設隊形。
- 各小遊戲左下角實測工具列 / 熱鍵 `F5` / `F6` / `F7` / `F8`：一鍵驗證「友軍炸彈免傷」、「瀕死碰觸救援」、「360° 衝擊波免傷隊友」、「3.5m 護盾共振」、「提前勝出」與「團隊同步計分結算面板」。

---

## 檔案結構

| 檔案 | 打入 R2 ZIP | 職責 |
| --- | --- | --- |
| `mod.json` | 是 | MPML 模組清單、`priority: -5` 與入口聲明 |
| `main.gd` | 是 | 精簡入口、子腳本載入／註冊、RPC 端點與公開 API 門面 |
| `team_registry.gd` | 是 | 全域隊伍註冊表、隊色／語系標籤、名冊排序與 Squads 同步計分 |
| `lobby_assignment.gd` | 是 | 大廳分隊模式、席位區域計算、Smart Bot Swap 與客機換位請求 |
| `lobby_ui.gd` | 是 | 大廳左上角 CRT 分隊控制列與換位確認提示 UI |
| `lobby_drag_3d.gd` | 是 | 大廳 3D 座椅隊色光環、布娃娃拖曳換位動畫與遠端同步插值 |
| `vanilla_ingame.gd` | 是 | 原版官方關卡掛接、角色底座／徽章、`DiscoDodge` 友軍過濾與提前勝出 |
| `ingame_hud.gd` | 是 | 右上角無邊框 Squad 狀態列與原生組隊關卡追蹤 |
| `README.md` | 否 | 本說明文件（`*.md` 自動跳過） |
| `project.godot` | 否 | macOS 獨立 Godot 4.5.2 專案設定 |
| `run_mac.sh` | 否 | macOS 多模組整合測試沙盒啟動、headless `--self-test` 與 `--screenshot` 腳本（`*.sh` 自動跳過） |
