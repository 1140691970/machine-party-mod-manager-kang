# ADR-016 · 基于 R2 图床的可选模组封面规范

[English](../../en/architecture/ADR-016-r2-mod-covers.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-016-r2-mod-covers.md)

## 问题

此前桌面端管理器直接从打包进客户端前端的 `apps/desktop/ui/images/<image>.png` 读取卡片封面，带来三个问题：

1. 新增模组或更换封面图必须重新发布桌面客户端，即使目录与模组压缩包已通过 Cloudflare R2 和 `services/catalog-worker` 实现动态更新。
2. 内置高清 PNG 截图使桌面安装包增大约 5.8 MB，且会随模组数量线性膨胀。
3. 封面图缺乏明确的目录与模组开发规范。

## 决策

1. **移除内置模组封面图**：删除 `apps/desktop/ui/images/` 中所有模组封面文件，仅保留应用自身图标（`logo.svg`）。契约测试强制禁止再将模组封面内置到 `apps/desktop/ui/images/`。
2. **可选 `cover` 规范**：模组封面为选填项。若提供封面，源文件统一存放于 `catalog/covers/<id>.<ext>`（支持 `.png`、`.webp`、`.jpg`，推荐 `1280×720` 16:9，上限 4 MiB），并在 `catalog/mods.json` 中声明：
   ```json
   "cover": {
     "filename": "spike-ring.png",
     "contentType": "image/png",
     "size": 832988,
     "sha256": "<64位十六进制>"
   }
   ```
   不提供 `cover` 完全合法，界面会自动渲染卡片标题占位（`cover-title`）。
3. **内容寻址 R2 存储与 Worker 分发**：
   - CI（`.github/workflows/catalog-worker.yml`）校验每个声明封面的本地大小与 SHA-256，并以不可变对象键 `covers/sha256/<sha256>.<ext>` 上传至 R2。
   - `services/update-worker` 网关将 `/v1/covers/*` 转发给 `services/catalog-worker`。
   - `services/catalog-worker` 仅对外提供已发布目录中声明的封面 `GET|HEAD /v1/covers/<modId>/<sha256>.<ext>`，校验 R2 对象大小，返回 `Cache-Control: public, max-age=86400, s-maxage=604800, immutable`、`X-Content-Type-Options: nosniff` 并启用边缘缓存。
4. **桌面 UI 与 CSP**：
   - `tauri.conf.json` 在 `img-src` 中放行 `https://machineparty.ailaogong.men`。
   - `online-catalog.js` 校验 `cover` 元数据并生成 `coverUrl(mod)`；`catalog-view.js` 懒加载封面图，在网络不可达或加载失败时平滑回退到标题占位。

## 备选方案

- **继续内置于桌面前端**：离线最简单，但无法随在线目录动态更新，且持续膨胀安装包体积。
- **公开 R2 桶或 GitHub raw 直链**：GitHub 直链在中国大陆不可靠；公开 R2 桶会绕过目录白名单与大小/类型校验。

## 兼容性

- 旧版桌面客户端（v0.2.3 及更早）会忽略未知字段 `cover` 并允许省略 `image`，在自动更新至 v0.2.4 前平滑显示标题占位。
- `online-catalog.js` 仍容忍旧本地缓存中的 `image` 字段，确保升级过程无报错。

## 验证证据

- `tests/contracts/catalog.test.mjs` 校验 `apps/desktop/ui/images/` 仅含 `logo.svg`、目录不再使用旧 `image` 字段，且所有 `cover` 与 `catalog/covers/<filename>` 的大小、SHA-256、类型与 4 MiB 上限完全一致。
- `tests/contracts/online-catalog.test.mjs` 校验网关转发、Worker R2 键解析、边缘缓存、响应头、错误码及非法 `cover` 拒绝逻辑。
- `.github/workflows/catalog-worker.yml` 在发布时自动上传封面至 R2 并验证线上每条 `HEAD /v1/covers/<modId>/<sha256>.<ext>`。
