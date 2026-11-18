# ADR-001：项目边界，保留 Tauri 与原生 JS

[English](../../en/architecture/ADR-001-project-boundaries.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-001-project-boundaries.md)

日期：2026-11-18。状态：已接受。

## 问题

原型把 Cargo 工程、前端和 Worker 都放在仓库根目录。所有 Tauri 命令、Steam 检测、偏好与安装记录代码都在 `main.rs`；模组列表在 `ui/app.js` 里硬编码，Rust 又另写了一份白名单；界面在任意位置调用 `window.__TAURI__`；CSS 是手工压缩的。没有每次提交都运行的检查，边界无法约束。

## 决策

- 保留 Tauri 2、Rust 和不使用打包工具的原生 ES 模块。按归属划分目录：`apps/desktop/src-tauri`、`apps/desktop/ui`、`services/update-worker`、`catalog`、`scripts`、`tests`、`docs`。
- `main.rs` 只负责组装；`commands.rs` 校验 IPC 并解析平台路径；`game`、`inventory`、`preferences`、`catalog` 只接收普通路径，不依赖 Tauri，便于单元测试。
- `ui/bridge.js` 是唯一接触 Tauri 的 JavaScript。纯函数模块（`catalog.js`、`versions.js`）在 Node 下测试。
- `scripts/check_architecture.mjs` 与 Source checks 工作流执行这些规则，并运行 `cargo fmt`、`clippy` 与测试。
- 面向贡献者与编码助手的规则写在 `AGENTS.md`。

## 参考

目录组织参考同一维护者的 [miband-agent-buddy](https://github.com/JamesGZM/miband-agent-buddy)（apps/services 拆分、`AGENTS.md`、分语言 ADR、边界检查脚本）。它的多运行时结构、共享协议包和生成式构建在本项目中不需要。

## 替代方案

保持平铺结构、只拆分 `main.rs` 成本更低，但随着服务增加，发布脚本与测试会继续耦合根目录路径。前端框架或打包工具对之后的重设计有帮助，但属于技术栈变更，应在那一轮再决定。

## 兼容性

命令名、`installations.json`、`game-path.json`、更新器 identifier、公钥与稳定端点均未改变。发布工作流改在 `apps/desktop/src-tauri` 中构建，并把产物写到根目录 `dist/`。本地构建输出位于 `apps/desktop/src-tauri/target`。

## 证据

`cargo test`、`clippy -D warnings`、`npm test`、`npm run check:architecture` 均通过。在浏览器中并排加载新旧界面，截图、搜索结果、详情弹窗、设置页与已安装页一致。macOS 桌面构建可以启动。发布工作流尚未以新路径实际运行。
