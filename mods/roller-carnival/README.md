# Roller Carnival（滾筒嘉年華）

`roller-carnival` 是由 `machine-party-mod-manager` 開發維護的第一方原創 3D 躲避派對小遊戲模組（透過 R2 + 目錄 Worker 發布 ZIP 套件），接管原版《Machine Party》未使用的小遊戲槽位 `Globals.MinigameIdentifier.ShapeCutter = 6`，讓自研小遊戲能直接加入官方預設輪換、自訂清單、街機模式與過場 CRT 抽籤池。

![滾筒嘉年華小遊戲圖示](../../apps/desktop/ui/images/roller-carnival.png)

- **模組 ID**：`roller-carnival`
- **版本**：`0.1.1`（目錄清單對應 `v0.1.1`）
- **授權**：`GPL-3.0-only`
- **目標遊戲版本**：Steam Windows `v2.1.2`
- **開發與打包規範**：[自研模組開發、測試、接入與打包規範](../../docs/zh-TW/development/mod-development.md) · [ADR-009](../../docs/zh-TW/architecture/ADR-009-bundled-first-party-mods.md)

## 核心玩法與計分規則

- **純淨橫向躲避＋擊退淘汰**：
  - **金色高滾筒**：出現於中層高度，需按 `S` 或 `↓` **下蹲**閃避。
  - **銀色低滾筒**：貼地滾動，需按 `Space`（空白鍵）**跳躍**越過。
  - **只推擠不扣血**：被滾筒撞擊不會扣減 HP，而是累積向左擊退約一個身位；玩家被推落左側岩漿即立刻淘汰。
- **同一起跑線齊平站位與動態人數（1–16 人）**：
  - 全員沿場景內側垂直黃銅起跑線一字排開，無水平移動操作，聚焦精準跳蹲時機。
  - 連線時依實際參賽名單生成角色，房主判定碰撞、淘汰與得分。
- **對局畫面**：開場中央倒數三秒，開始後只保留場內角色名牌與動作回饋。連線結束時由本體顯示成績，單機試玩於結束後顯示排名。
- **安全間隔底線保證**：
  - 50 秒分成三段：前 10 秒先認識單根，之後每組兩根，32 秒起每組三根。固定透視鏡頭對準玩家，滾筒從右側進入畫面，每組之間留有喘息。
  - 滾筒生成間隔強制滿足 `jump_air_time + landing_recovery_time + min_safe_reaction_time`，避免無解連發陷阱；另有 `max_same_type_streak` 限制同色連發。
- **依躲避數排名與階梯加分**：
  - 每次安全閃過滾筒累積 +1 次躲避；回合結束依躲避數排序發放排名加分（原始分為人數減名次加一，同躲避數並列；雙人第一、第二名分別提交 2、1 分，官方主遊戲套用倍率）。

## 操作按鍵

| 環境 | 按鍵 | 功能 |
| --- | --- | --- |
| 遊戲對局 | `S` / `↓` | 按住下蹲，鬆手即起身；最多蹲 0.75 秒，再蹲需放開重按 |
| 遊戲對局 | `Space`（空白鍵） | 跳躍越過銀色低滾筒 |

## 遊戲整合與雙人驗收

- **輪換與挑選器整合**：透過 `override_game.gd`、`override_playlist.gd` 與 `override_picker.gd` 將槽位 `ShapeCutter (6)` 註冊為「滾筒嘉年華」，同步補齊歌單項目與 15 格過場 CRT 挑選器圖示及操作教學卡。
- 雙方安裝同一版本，房主建立自訂清單，只選滾筒嘉年華、兩輪。兩人載入後自動倒數三秒，使用預設 50 秒規則。
- 第一輪房主跳、客人長按蹲，再交換。雙方都應看到對應角色動作，長按只蹲一次。遊戲後段速度提高、出筒間隔縮短。
- 一人刻意撞筒，另一人閃避。雙方應看到相同淘汰與分數，第二輪可正常繼續。

## 檔案結構（打入 R2 ZIP vs. 本機開發檔案）

依 [`scripts/pack-mod.mjs`](../../scripts/pack-mod.mjs) 規則，僅以下**執行期檔案**會被封裝為確定性 `roller-carnival-0.1.1.zip` 並隨目錄 Worker 與 R2 分發：

| 檔案 | 打入 R2 ZIP | 職責 |
| --- | --- | --- |
| `mod.json` | 是 | 模組中繼資料、入口腳本宣告與優先權 |
| `main.gd` | 是 | MPML API v2 入口：註冊虛擬腳本、場景 Hook與 `ShapeCutter` 替換 |
| `config.gd` | 是 | 預設平衡參數、安全生成間隔底線與積分計算 |
| `carnival_meshes.gd` | 是 | 程序化 3D 齒輪、滾筒、岩漿池、齊平起跑線與燈泡框舞台建構器 |
| `roller_carnival_game.gd` | 是 | 主遊戲場景迴圈、跳蹲物理、純擊退與淘汰判定、精簡 HUD 與 `--self-test` |
| `official_minigame.gd` | 是 | 官方開局、參賽名單與結算入口 |
| `override_game.gd` | 是 | 覆寫 `res://scripts/scenes/game/game.gd` 以納入官方預設與街機輪換池 |
| `override_playlist.gd` | 是 | 覆寫 `res://scenes/lobby/components/playlist_handler.gd` 補入自訂歌單項目 |
| `override_picker.gd` | 是 | 覆寫過場 `intermission_game_picker.gd` 補上 15 格 CRT 圖示與簡報說明 |
| `README.md` | 否 | 本說明文件（`*.md` 自動跳過） |
| `project.godot` | 否 | macOS 獨立 Godot 4.5.2 預覽專案設定 |
| `roller_carnival_scene.tscn` | 否 | 獨立啟動測試場景（`*_scene.tscn` 自動跳過） |
| `run_mac.sh` | 否 | macOS 本機試玩、`--self-test` 與封面截圖輔助腳本（`*.sh` 自動跳過） |

## 本機開發、打包測試與封面擷取

在安裝本機 Godot 4.5.2（`.agent/mod-dev/tools/Godot.app`）的 macOS 環境中，可直接執行。要預覽原版素材，可將環境變數 `MP_PCK_PATH` 指向本機的 `Machine Party.pck`。

```sh
# 1. 單人試玩：與正式對局共用倒數、操作及回合排名；結束後關閉視窗。
./mods/roller-carnival/run_mac.sh play

# 2. 執行 Godot headless 核心邏輯自我測試（應輸出 SELF_TEST_PASSED）
./mods/roller-carnival/run_mac.sh --self-test

# 3. 擷取舞台截圖至本機開發目錄
./mods/roller-carnival/run_mac.sh --screenshot

# 4. 驗證確定性 ZIP 打包、目錄契約、架構邊界與 Rust 測試
node scripts/pack-mod.mjs --all --verify-catalog
npm run check:architecture && npm test && npm run lint:rust && npm run test:rust
```

## 安裝、共存與驗證狀態

- **R2 鏡像分發與自動載入器**：桌面端透過目錄 Worker 從 R2 下載並校驗 `roller-carnival-0.1.1.zip` 的 SHA-256；首次安裝且偵測不到外部載入器時，管理器會透過潔淨室 `pck_loader.rs` + `mpm_bootstrap.gd` 自動設定載入環境；解除安裝最後一個受管模組時會無損截斷還原原版 `Machine Party.pck`。
- **外部載入器與互斥**：若玩家遊戲目錄已有 `MachinePartyModLoader.exe`，會保留原有載入器僅放入 `mods/roller-carnival/`；與 `overtime` 等直接修補 PCK 檔案的模組保持互斥保護。
- **目前驗證狀態**：
  - ✅ macOS Godot 4.5.2 語法檢查與 `--self-test` 通過、`scripts/pack-mod.mjs` 確定性 ZIP 與 Rust L1/L3 原版 Steam v2.1.2 `Machine Party.pck` 寫入/無損還原模擬測試通過。
  - ⏳ Windows Steam v2.1.2 實機對局（Worker 下載安裝、雙人連玩兩輪、歌單與輪換抽籤、多人連線 RPC 同步及解除安裝／還原）仍待 Windows 驗收後，再於 [`catalog/mods.json`](../../catalog/mods.json) 開放正式安裝（`"verified": true`）。
