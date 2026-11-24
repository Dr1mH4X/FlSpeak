# 新增配置项实操指南

本文介绍如何在 FlSpeak 中新增一个用户设置项，完成从 Rust 存储模型到 Flutter 设置界面的全链路接入。

## 前置条件

- 已确定新配置项落在 `core/session` 的哪个子结构体：`NetworkSettings`、`AudioSettings` 或 `UiSettings`，三者都挂在根结构体 `AppSettings` 下。
- 已读 [设置页导航与排版规则](../../lib/features/settings/AGENTS.md)。

## 操作步骤

### 1. 修改 Rust 侧数据模型

在 `core/session/src/settings/schema.rs` 对应子结构体中添加字段：

1. 为字段补文档注释，说明它控制的行为。
2. 在 `impl Default` 中提供明确的默认值；布尔与枚举字段不依赖 `Default` 派生。
3. 字段类型必须可 `Serialize` + `Deserialize` + `Clone` + `PartialEq`；枚举另需 `Eq`。

结构体已统一带 `#[serde(default, rename_all = "camelCase")]`，新增字段不必重复标注；缺字段时自动回退到默认值。

### 2. 通过 SettingsManager 读写配置

业务代码不直接接触设置 JSON 文件：

- 读取：`SettingsManager::with(|s| s.audio.field.clone())`
- 修改：`SettingsManager::update(|s| s.audio.field = new_val)`
- 只改界面或音频子集时用 `update_ui` / `update_audio`，避免整体覆盖服务器列表；音频字段变化会通知音频订阅者。

### 3. 暴露给 Dart（仅当 UI 需要读写）

1. 在 `plugins/flspeak_ffi/rust/src/api/session.rs` 增加转发方法或视图字段，不在 `core/` 类型上直接挂 `#[frb]`。
2. 重跑绑定生成：

   ```sh
   cd plugins/flspeak_ffi
   flutter_rust_bridge_codegen generate
   ```

### 4. 接入 Flutter 设置页

1. 在 `arb/intl_en.arb` 与 `arb/intl_zh.arb` 同步添加标题与选项文案。
2. 重跑本地化生成：`flutter gen-l10n`。
3. 在 `lib/features/settings/` 对应层级的页面里加 `SettingsTile` 或 `SettingsRadioGroup`，按[模块导航规则](../../lib/features/settings/AGENTS.md)决定它是二级入口还是三级终末项。

## 验证

1. 跑最小检查集：

   ```sh
   just check
   ```

2. 启动应用，进入设置页切换该项，确认改动即时生效。
3. 重启应用，确认配置已持久化且状态正确恢复。
