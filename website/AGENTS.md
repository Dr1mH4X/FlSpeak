# AGENTS.md — 官网与展示站点

本目录包含 FlSpeak 项目官方站点与下载展示页面（React 19 + TypeScript + Vite）。

## 规则与约束

- 站点仅负责产品展示、功能介绍与各平台构建产物下载指引；不在此处维护应用运行期协议或业务状态。
- 使用 `pnpm` 管理依赖，构建前先跑数据同步：
  ```sh
  pnpm --dir website install --frozen-lockfile
  pnpm --dir website run typecheck
  pnpm --dir website run build
  ```
- 保持静态产物（`dist/`）干净，不手动提交构建产物或临时缓存。
- 子目录规则见 [src/AGENTS.md](src/AGENTS.md)。
