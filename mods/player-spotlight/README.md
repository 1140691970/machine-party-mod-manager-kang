# Player Spotlight · 玩家聚光燈 · 玩家聚光灯

**繁體中文**　安裝後從 Steam 照常開遊戲，會自動在所有原版 3D 小遊戲與自研小遊戲中，為**你自己的角色**打上一束只有自己看得到的頭頂工業聚光燈，並將自己的名牌微調為淡 CRT 螢光綠。跳躍時光斑留在原位方便辨識落點，淘汰後自動熄燈；自動避開大廳、過場與第一人稱關卡，不影響其他玩家畫面。遊戲中隨時可按 `F8` 開關。僅需自己安裝即可生效，可與所有載入器模組共存；與「滾筒嘉年華」同裝時會自動接管打光不重複疊加。

**简体中文**　安装后从 Steam 正常启动，会自动在所有原版 3D 小游戏与自研小游戏中，为**你自己的角色**打上一束仅自己可见的头顶工业聚光灯，并将自己的名牌微调为淡 CRT 荧光绿。跳跃时光斑留在原位方便辨识落点，淘汰后自动熄灯；自动避开大厅、过场与第一人称关卡，不影响其他玩家画面。游戏中随时可按 `F8` 开关。仅需自己安装即可生效，可与所有加载器模组共存；与「滚筒嘉年华」同装时会自动接管打光不重复叠加。

**English**　Launch normally from Steam to shine a local-only overhead industrial spotlight onto **your own character** across vanilla and first-party 3D minigames, with a subtle CRT phosphor-green tint on your own nametag. The light pool stays anchored underneath you for quick positioning, switches off on elimination, and automatically skips the lobby, intermission, and first-person minigames. Press `F8` anytime to toggle. Client-side only and compatible with all loader mods; automatically takes over from Roller Carnival's built-in spotlight when both are installed.

`mod.json` declares the loader entry. `main.gd` tracks the local player node across scenes without overriding vanilla scripts. Target: Steam v2.1.2. Windows Steam room acceptance pending. Package check: `node scripts/pack-mod.mjs player-spotlight --verify-catalog`.
