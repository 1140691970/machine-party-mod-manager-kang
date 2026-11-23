# Team Party（組隊派對）

`team-party` 是《Machine Party》的**完全獨立外掛式全域組隊規則模組**——**無需修改任何其他模組程式碼或版本號**，只需單獨安裝 `team-party` 即可在大廳左上角提供 **自由混戰（FFA）／2 隊／3 隊／4 隊**切換、房主單鍵隨機洗牌與手動指定成員（含房內既有 `lobby-bots` 機器人），並在執行期透過動態場景腳本掛載，自動為原版小遊戲與既有的第一方自研小遊戲（[`bubble-blitz`](../bubble-blitz/README.md)、[`spike-ring`](../spike-ring/README.md)、[`roller-carnival`](../roller-carnival/README.md)、[`lobby-bots`](../lobby-bots/README.md)、[`player-spotlight`](../player-spotlight/README.md)）啟用一致的隊友辨識、友軍互動規則與小隊同步結算。

- **模組 ID**：`team-party`
- **版本**：`0.1.0`（待確認發布；目錄目前標註為 `"verified": false`）
- **授權**：`GPL-3.0-only`
- **目標遊戲版本**：Steam Windows `v2.1.2`
- **載入優先權**：`-5`

---

## 核心機制（繁體中文 / 简体中文 / English）

### 繁體中文
- **零侵入設計（不改動任何其他模組）**：
  - 所有對 `bubble-blitz`、`spike-ring`、`roller-carnival`、`lobby-bots` 的組隊適配皆由 `team-party` 在場景進入時於記憶體動態包裝與外掛，完全不更動既有模組檔案。
- **大廳內全權手動／隨機分隊（絕不自動補機器人）**：
  - 房主可在大廳左上角面板循環切換 `FFA`、`2 隊（紅藍）`、`3 隊（紅藍綠）`、`4 隊（紅藍綠黃）`，支援 `2v2v2v2`、`4v4`、`3v3` 或如 `3v2v2` 的不對稱人數分組。
  - **絕不自動生成機器人**：僅對房內目前已存在的真人與既有 [`lobby-bots`](../lobby-bots/README.md) 機器人進行指派或隨機洗牌；人類可點「切換我的隊伍」自選顏色，開局前未分隊成員會自動補入人數最少的隊伍並透過 RPC 同步全房。
- **隊友識別與聚光燈共存**：
  - 大廳與各 3D 小遊戲角色頭頂名牌附加對應語系標籤（`[紅]` / `[红]` / `[RED]` 等）並著隊色；搭配 [`player-spotlight`](../player-spotlight/README.md) 時保留本地主角聚光燈色彩，並以標籤與頭頂備援標記維持清晰識別。
- **依遊戲類型自動套用的固定友軍規則**：
  - **原版推擠淘汰（Disco Dodge / DVD Roomba / Train Race / Scavenger Chairs）＆ `lobby-bots`**：過濾推擠範圍與機器人 AI 目標中的同隊隊友；僅剩 1 隊存活時提前勝出。
  - **泡泡爆破（Bubble Blitz，經典泡泡堂規則）**：依隊順時針分組角落出生、免疫隊友炸彈；瀕死 4 秒顯示 `[救命!]`，**隊友碰觸立即救援回 1 血＋1.5 秒無敵**（AI 隊友亦會救人）；僅剩 1 隊存活提前勝出。
  - **尖刺圓環（Spike Ring）**：同隊相鄰環形出生、免疫隊友推搡與 360° 衝擊波（AI 亦不誤推隊友）；撿取防爆護盾時 `3.5m` 內存活隊友同步觸發**護盾共振**；僅剩 1 隊存活提前勝出。
  - **滾筒嘉年華（Roller Carnival）**：依隊伍排列相鄰 Z 軸跑道與名牌染色；僅剩 1 隊存活提前勝出。
- **Fall Guys Squads 式小隊同步計分**：
  - 結算取同隊最高個人分數＋「全員存活 `+1`」獎勵，確保隊友共享完全一致的過場分數。

### 简体中文
- **零侵入外挂设计（不改动任何其他模组）**：`team-party` 在对局进入场景树时动态挂接既有的 `bubble-blitz`、`spike-ring`、`roller-carnival`、`lobby-bots` 与原版关卡，无需升级其他模组。
- 支持大厅自由混战 / 2 / 3 / 4 队手动及洗牌分队（绝不自动补全机器人）、名牌染色与队伍前缀、分关卡固定友军规则，以及同队最高分 + 全员存活 `+1` 同步结算。

### English
- **Zero-Invasion Standalone Architecture**: Leaves every other first-party mod untouched on disk; hooks vanilla minigames, `lobby-bots`, `bubble-blitz`, `spike-ring`, and `roller-carnival` dynamically at runtime.
- Provides FFA / 2 / 3 / 4 team selection & one-click shuffle across existing room members + bots (never auto-filling bots), team nameplate coloring/badges (cooperating with `player-spotlight`), game-tailored friendly-fire rules, early team wins, and Fall Guys Squads-style synchronized scores.

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
| `main.gd` | 是 | 全域隊伍註冊表、`TeamPartyPanel` 大廳分隊、RPC 同步、原版過濾／結算與第一方關卡動態掛載 |
| `README.md` | 否 | 本說明文件（`*.md` 自動跳過） |
| `project.godot` | 否 | macOS 獨立 Godot 4.5.2 專案設定 |
| `run_mac.sh` | 否 | macOS 多模組整合測試沙盒啟動、headless `--self-test` 與 `--screenshot` 腳本（`*.sh` 自動跳過） |
