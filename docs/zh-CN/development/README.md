# 开发指南

[English](../../en/development/README.md) · **简体中文** · [繁體中文](../../zh-TW/development/README.md)

## 环境准备

- Rust stable 1.88 或更新版本（edition 2024，使用 let-chains），并安装 `rustfmt` 与 `clippy`。
- Node.js 22 或更新版本。不安装任何 npm 依赖，Node 只用于运行测试和脚本。
- Windows：Microsoft C++ Build Tools 与 WebView2（Windows 11 已预装）。macOS：Xcode Command Line Tools。
- 打包安装程序还会使用 `npx @tauri-apps/cli@2.12.5`，与发布工作流一致。

## 目录结构

| 路径 | 内容 |
| --- | --- |
| `apps/desktop/src-tauri` | Rust 工程、`tauri.conf.json`、capabilities 与图标 |
| `apps/desktop/ui` | 由 WebView 直接加载的 HTML、CSS 与 ES 模块 |
| `catalog/mods.json` | 随 App 发布的模组目录 |
| `mods/<id>/` | 通过 `scripts/pack-mod.mjs` 打包为 `.zip` 并经 R2 与目录 Worker 分发的自研 GDScript 模组 |
| `services/update-worker` | 负责应用更新的 Cloudflare Worker |
| `scripts` | 发布、部署、升级验收与 `check_architecture.mjs` |
| `tests` | Node 测试：`ui`、`contracts`、`architecture` |

各部分职责见[现行架构](../architecture/README.md)，所有改动都需遵守的规则见 [AGENTS.md](../../../AGENTS.md)。

## 运行

```sh
npm run dev
```

该命令对桌面端执行 `cargo run`。Steam 检测与游戏目录操作在各平台均可运行，安装功能以 Windows 为目标。

不经 Tauri、在浏览器里预览界面时，从仓库根目录启动静态服务器并打开界面页面，仅桌面端可用的操作会被隐藏。

```sh
python3 -m http.server 8000
# 打开 http://127.0.0.1:8000/apps/desktop/ui/index.html
```

## 验证

先运行最小相关检查，提交 PR 前运行全部：

```sh
npm run check:architecture
npm test
npm run lint:rust
npm run test:rust
```

**Source checks** 工作流在每次 push 与 PR 时运行同样的命令。界面改动需附截图。构建成功不代表 Windows 安装、游戏还原或更新已验证，请说明实际做过的实机测试。

## 在 macOS 上模拟模组安装

Steam 上的 Machine Party 仅支持 Windows，不考虑在 macOS 上游玩。在进入 Windows 实机验收（P2）之前，macOS 开发期通过三层模拟验证安装逻辑（[ADR-007](../architecture/ADR-007-mod-adapters.md)）：

- **L1（单元与契约测试）**：`FakeRunner` 搭配合成的 Godot PCK（仅数 KB，含合法 `GDPC` 文件头与 `res://` 索引）及故障注入，验证下载中断、写入崩溃、Steam 更新、未知修改与文件占用。
- **L2（真实子进程测试）**：`ProcessRunner` 执行复现 Overtime 参数与 `State:` 输出协议的跨平台假 CLI 脚本，并在 `python3` 下使用跨平台上游脚本（如 `install.py`）操作合成 PCK。
- **L3（本机原版 PCK + Mono）**：仅限本机验证，使用 Mono 运行 `overtime_install.exe` 操作未提交的 Windows 原版 `Machine Party.pck`（v2.1.2，SHA-256 `326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e`）。切勿将游戏文件（`Machine Party.pck`）提交到仓库。

## 常见改动

- **新增或修改模组**：只改 `catalog/mods.json`。三种语言的 `name`、`summary`、`detail` 都要填写，保持 `id` 与 `repo` 不变；封面为选填，如需封面请将图片放入 `catalog/covers/<id>.<ext>` 并在条目中填写对应的 `cover` 元数据（`filename`、`contentType`、`size`、`sha256`），由 R2 图床分发（禁止再将模组封面内置到 `apps/desktop/ui/images/`）。收录流程见[模组目录指南](../catalog/mods.md)。
- **新增仓库自研模组**：遵循[自研模组开发、测试、接入与打包规范](mod-development.md)与[模组 SDK 参考手册](mod-sdk.md)（在 `mods/<id>/` 提供 `README.md`、`mod.json` 与 GDScript 脚本），执行 `node scripts/pack-mod.mjs <id>`（自动排除 `project.godot`、`*_scene.tscn`、`*.sh` 与 `*.md`），按与其他模组完全相同的格式在 `catalog/mods.json` 新增 `package` 及 `adapter.kind: "loader-files"`（`autoLoader: true`）条目，并执行 Godot 校验、`npm run test:rust` 与 `npm test`（[ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)）。
- **新增界面文案**：在 `apps/desktop/ui/languages.js` 增加一个键，同时填写简体中文、繁体中文与英文。
- **新增命令**：在不依赖 Tauri 的模块中实现逻辑并写单元测试，在 `commands.rs` 暴露，在 `main.rs` 注册，并且只从 `bridge.js` 调用。
- **调整架构**：在 `docs/en`、`docs/zh-CN`、`docs/zh-TW` 各新增一份 ADR，并更新现行架构页面。

发布流程见[发布](releasing.md)。
