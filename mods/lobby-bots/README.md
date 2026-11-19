# Lobby Bots · 房間機器人 · 房间机器人

**繁體中文**　所有真人玩家使用同版 MPML 模組。在 Steam 線上房間，房主用「加入機器人」填入空席，或用該列的「移除」騰出位置。每個 Bot 獨立計分，回合簡報會自動準備。在 Escalator Pit，每個 Bot 依編號使用固定步速，房主出局後關卡仍可繼續。Junk Platform 的出生點及鏡頭方向沿用開局時的大廳座位。若 Junk Platform 補丁載入失敗，大廳會顯示原因並停用新增 Bot。建議先測滾筒嘉年華、Disco Dodge 或 Junk Platform 的淘汰與結算。

**简体中文**　所有真人玩家安装同版 MPML 模组。房主在 Steam 在线房间点“添加机器人”填入空位，或点对应行的“移除”。每个 Bot 独立计分，回合简报会自动准备。在 Escalator Pit，每个 Bot 按编号使用固定步速，房主出局后关卡仍可继续。Junk Platform 的出生点和镜头方向沿用开局时的大厅座位。如果 Junk Platform 补丁加载失败，大厅会显示原因并禁用添加 Bot。建议先测滚筒嘉年华、Disco Dodge 或 Junk Platform 的淘汰与结算。

**English**　Install the same MPML mod on each human participant's game copy. In the Steam lobby the host can add one bot per free seat and remove a specific bot before starting. Each bot has its own presence, ready state and score. In Escalator Pit each bot walks at a fixed pace based on its number so the race can continue after the host goes out. Junk Platform uses each participant’s lobby seat for their spawn point and camera orientation. If the Junk Platform override fails to load, the lobby explains why adding bots is disabled. Start with Roller Carnival, Disco Dodge or Junk Platform for idle elimination tests. Other minigames may require specific player inputs or client-side simulation.

## Runtime and verification

`mod.json` declares the MPML entry. `main.gd` manages Steam room capacity, the lobby controls and the host's test participants. `junk_platform.gd` adapts online spawns for rooms with bots so each human receives the camera orientation for their seat. The manager uses its loader-files adapter to install the packaged files under `mods/lobby-bots/`.

Build and verify from the repository root with `node scripts/pack-mod.mjs lobby-bots --verify-catalog`. The package targets Steam v2.1.2. Windows acceptance is pending. Check solo-host and mixed-client sessions, add to capacity, remove the middle bot, join with a human, then play two rounds and compare all scoreboards. In Escalator Pit, finish or eliminate the host with two bots remaining and check native elimination, scores and advancement to the next round. In Disco Dodge, eliminate the host while two bots remain and check that a bot can fall and the round ends. In Junk Platform, check the fourth seat with a bot and again with a human guest. Reopen an empty lobby to verify cleanup.
