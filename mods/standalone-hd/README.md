# Standalone HD · 獨立高清 · 独立高清

**繁體中文**　安裝後從 Steam 照常開遊戲。預設將視窗置中並設為 1920×1080、60 FPS 上限、關閉垂直同步，保留遊戲的介面基準並隱藏畫面後製濾鏡。房主和其他玩家照常入座，只有想套用畫面的玩家需要安裝。Steam → 內容 → 啟動選項可填下表參數，多個用空格分隔。清空參數後重開即回到預設。實驗性內部解析度可能造成選單錯位。與 Broadcast 8P Freecam 同裝時由 Broadcast 控制顯示。

**简体中文**　安装后从 Steam 正常启动。默认居中显示 1920×1080 窗口、60 FPS 上限、关闭垂直同步，保留游戏界面基准并隐藏后处理滤镜。房主和其他玩家照常入座，仅需要高清画面的玩家安装。可在 Steam 属性的启动选项中输入下表参数，以空格分隔；清空后重启恢复默认。实验性内部分辨率可能导致菜单错位。与 Broadcast 8P Freecam 同装时由 Broadcast 管理显示。

**English**　Launch normally from Steam for a centered 1080p window, a 60 FPS cap, VSync off, the game's original UI base and reduced post-processing. This local display mod uses the existing lobby and seats. Enter optional flags under Steam Properties → Launch Options, separated by spaces. Clear the flags and restart to restore the defaults. Experimental internal scaling can misalign fixed-size menus. Broadcast controls the display when both mods are installed.

| Steam 啟動選項 / Launch option | 效果 / Effect |
| --- | --- |
| `--party-hd-1440` | 2560×1440 輸出視窗 / output window |
| `--party-hd-120` | 120 FPS 上限 / frame cap |
| `--party-hd-internal` | 實驗性：將介面與內部基準設為輸出尺寸 / use output dimensions as the internal base |

Example: `--party-hd-1440 --party-hd-120`.

`mod.json` declares the loader entry. `main.gd` applies display settings and hides filter nodes as scenes load. Target: Steam v2.1.2. Windows Steam room acceptance pending. Package check: `node scripts/pack-mod.mjs standalone-hd --verify-catalog`.
