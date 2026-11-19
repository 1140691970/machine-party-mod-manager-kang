# Standalone HD · 獨立高清 · 独立高清

**繁體中文**　安裝後從 Steam 照常開遊戲。預設以 1080p 為 3D 渲染目標，沿用遊戲的全螢幕、視窗及介面尺寸、60 FPS 上限、關閉垂直同步，保留遊戲的介面基準並隱藏畫面後製濾鏡。房主和其他玩家照常入座，只有想套用畫面的玩家需要安裝。Steam → 內容 → 啟動選項可填下表參數，多個用空格分隔。清空參數後重開即回到預設。3D 放大最高為原本的兩倍。與 Broadcast 8P Freecam 同裝時由 Broadcast 控制顯示。

**简体中文**　安装后从 Steam 正常启动。默认以 1080p 为 3D 渲染目标，沿用游戏的全屏、窗口和界面大小、60 FPS 上限、关闭垂直同步，保留游戏界面基准并隐藏后处理滤镜。房主和其他玩家照常入座，仅需要高清画面的玩家安装。可在 Steam 属性的启动选项中输入下表参数，以空格分隔；清空后重启恢复默认。3D 放大上限为原来的两倍。与 Broadcast 8P Freecam 同装时由 Broadcast 管理显示。

**English**　Launch normally from Steam for a 1080p 3D rendering target with your existing fullscreen, window and UI settings, a 60 FPS cap, VSync off, the game's original UI base and reduced post-processing. This local display mod uses the existing lobby and seats. Enter optional flags under Steam Properties → Launch Options, separated by spaces. Clear the flags and restart to restore the defaults. 3D supersampling is capped at twice the viewport resolution. Broadcast controls the display when both mods are installed.

| Steam 啟動選項 / Launch option | 效果 / Effect |
| --- | --- |
| `--party-hd-1440` | 1440p 3D 渲染目標 / 3D rendering target |
| `--party-hd-120` | 120 FPS 上限 / frame cap |

Example: `--party-hd-1440 --party-hd-120`.

`mod.json` declares the loader entry. `main.gd` applies display settings and hides filter nodes as scenes load. Target: Steam v2.1.2. Windows Steam room acceptance pending. Package check: `node scripts/pack-mod.mjs standalone-hd --verify-catalog`.
