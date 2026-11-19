# ADR-009：自研模組、R2 確定性打包與自管載入器規範

[English](../../en/architecture/ADR-009-bundled-first-party-mods.md) · [简体中文](../../zh-CN/architecture/ADR-009-bundled-first-party-mods.md) · **繁體中文**

日期：2026-11-19。狀態：提議中；已在 macOS 完成 L1/L3 模擬驗證，尚待 Windows Steam 實機對局驗收。

## 問題

在本儲存庫開發的自研玩法模組（如首款玩法 `mods/roller-carnival/`）應與其他社群模組一致，透過 `catalog/mods.json` 與 Cloudflare Worker / R2（`packages/sha256/<sha256>.zip`）統一分發，使模組更新不需重編桌面端安裝程式或讓執行檔膨脹；同時，傳統載入器模組要求玩家先手動執行外部 `MachinePartyModLoader.exe`，不利於一鍵安裝與在解除安裝後自動無損還原遊戲本體。

## 決策

1. **自研模組原始碼規範（`mods/<id>/`）與確定性 R2 打包（`scripts/pack-mod.mjs`）**：
   - 自研模組置於儲存庫 `mods/<id>/` 下，包含合法 `mod.json`（`id` 符合 `^[a-z0-9-]+$`）、純淨 GDScript 原始碼與 `README.md`。
   - `scripts/pack-mod.mjs` 自動略過本機開發輔助與文件檔案（`project.godot`、`*_scene.tscn`、`*.sh`、`*.md`、隱藏項目與符號連結），產生固定時間戳記與排序的 `ZIP_STORED` 封存檔 `<id>-<version>.zip`，並將精確檔案大小與 SHA-256 登錄於 `catalog/mods.json`（同時標示 `"firstParty": true`）。
   - `.github/workflows/catalog-worker.yml` 於部署目錄時執行 `node scripts/pack-mod.mjs --all --verify-catalog`，自動將封裝好的 ZIP 上傳至 R2 的 `packages/sha256/<sha256>.zip`，驗證所有 `mirrorApproved` 套件存在且長度吻合後再寫入 `catalog/revisions/<revision>.json` 並部署 `services/catalog-worker`。
2. **淨室實作內建載入器（`pck_loader.rs` + `assets/mpm_bootstrap.gd`）**：
   - 依本專案 GPL-3.0-only 授權從零淨室編寫，不重製或隨附第三方執行檔與上游載入器原始碼。
   - 當目錄條目宣告 `adapter.autoLoader: true`（僅允許 `kind: "loader-files"`）時，`installer.rs` 在 `install_from_zip` 完成下載與 ZIP 校驗後、複製模組檔案至 `<pckDir>/mods/<id>/` 前呼叫 `pck_loader::ensure_loader_installed`：
     - 若磁碟上已有外部載入器（`MachinePartyModLoader.exe` 或非本管理器建立的 `Machine Party.pck.modloader.json`），則保留玩家原有的外部載入器不動，直接寫入該模組資料夾。
     - 否則先驗證原版 `Machine Party.pck` 基準指紋並於 `_mpm_loader` 保存經校驗的完整備份，以 GDPC Format 3 尾端附加方式寫入將 `*res://modloader/bootstrap.gd` 置首的 `project.binary`、`modloader/bootstrap.gd` 與 `.stamp`，讀回解析驗證後寫入含 `"managed_by": "machine-party-mod-manager"` 標記的 `Machine Party.pck.modloader.json`。
   - 當解除安裝最後一個由管理器維護的 `loader-files` 模組、且無外部載入器或殘留 `mods/` 子目錄時，`installer.rs` 呼叫 `pck_loader::restore_managed_loader` 恢復原版目錄指標、截斷回原版長度、驗證原版 SHA-256、刪除側車標記與 `_mpm_loader` 備份；若期間 Steam 更新了 PCK，則拒絕覆寫並回報 `gameUpdatedOrModified`。
3. **目錄與介面整合（`firstParty: true`、`autoLoader: true`）**：
   - `catalog/mods.json` 為自研模組記錄 `firstParty: true` 與標準 `package` 中繼資料（`assetId`、`filename`、`size`、`sha256`、`mirrorApproved: true`）及可選 `adapter.autoLoader: true`。
   - `catalog.rs::project_url` 將 `firstParty` 條目自動導向 `https://github.com/{app_repo}/tree/main/mods/{id}`。
   - 桌面端與介面完全共用統一的 `download_mod` → `verify_package` → `install_mod` 流程，並在卡片顯示「官方自研」標籤與於詳情說明自動載入與無損還原機制。

## 替代方案

- **編譯期直接將自研模組包入桌面端執行檔**：每次微調模組都需要發布新版桌面客戶端，與其餘模組走 R2 + catalog Worker 的機制不一致。
- **直接隨包附帶第三方 `MachinePartyModLoader.exe`**：存在第三方授權標示、防毒誤報與子進程脆弱問題，不如原生 Rust GDPC v3 讀寫與截斷還原單純可控。
- **要求玩家另行手動安裝外部 MPML**：增加上手門檻，且無法於解除安裝時自動無損還原 PCK。

## 相容性

- `catalog/mods.json` 維持 `schema: 1`；省略 `firstParty` 與 `autoLoader` 時預設為 `false`。
- `installations.json`、`game-path.json`、Tauri IPC 命令名稱及現有第三方 `upstream-cli` / `loader-files` 模組皆完全相容。
- 與玩家既有的 `MachinePartyModLoader.exe` 和平共存，並與 `overtime` 等直接修補 PCK 的模組嚴格互斥（`loaderConflict` / `modConflict`）。

## 證據

- `scripts/pack-mod.mjs` 產生的 `roller-carnival-0.1.0.zip` 已通過 `tests/contracts/catalog.test.mjs` 與 `tests/contracts/online-catalog.test.mjs` 契約驗證。
- `apps/desktop/src-tauri/assets/mpm_bootstrap.gd` 與 `mods/roller-carnival/` 皆已通過 Godot 4.5.2 headless 語法檢查與 `--self-test`。
- Rust `pck_loader` 與 `installer` 單元測試（含 `l1_zip_loader_mod_auto_installs_and_restores_loader_on_last_uninstall`）及隔離複本實測原版 Steam v2.1.2 `Machine Party.pck`（`634,798,100` bytes）的 L3 檢查全數通過：可正常寫入並讀回首項 autoload 與引導腳本、攔截外部篡改/Steam 更新，且解除安裝還原後與原版 SHA-256 `326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e` 逐位元組相符。
- Windows + Steam 原版遊戲中的 R2 下載、自動載入器配置、大廳視窗、自訂歌單、中場抽籤、多人 RPC 同步與解除安裝還原仍待 Windows 實機驗收。
