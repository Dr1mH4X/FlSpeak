# 新增配置项实操指南

本文介绍如何在 FlSpeak 中新增一个用户设置项，完成从底层 Rust 存储模型到 Flutter 设置界面的全链路接入。

## 前置条件

- 已确定新配置项的归属分类（语言、外观、语音、通用、数据与存储）。
- 熟悉 Rust `SettingsManager` 与 Flutter 设置页组件规范（参见 [../../lib/features/settings/AGENTS.md](../../lib/features/settings/AGENTS.md)）。

## 操作步骤

### 1. 修改 Rust 侧数据模型 (`schema.rs`)

在 `core/server/src/settings/schema.rs` 中定位到对应子分类的结构体（例如 `VoiceSettings` 或 `AppearanceSettings`）：

1. 添加新字段，并确认包含 `#[serde(default)]`。
2. 在 `impl Default` 中为新字段提供明确的默认值。
3. 若新字段是枚举类型，为其实现 `Serialize`, `Deserialize`, `Clone`, `PartialEq`, `Eq`。

### 2. 通过 SettingsManager 读写配置

在业务或 FFI 层，不要直接操作底层 JSON 文件：

- 读取配置：`SettingsManager::with(|s| s.category.field.clone())`
- 修改配置：`SettingsManager::update(|s| s.category.field = new_val)`

### 3. FFI 绑定更新（如涉及 Dart 可见类型）

若新设置类型需直接暴露给 Flutter：

1. 在 `plugins/flspeak_ffi/rust/src/api/session.rs` 中暴露对应字段或转换方法。
2. 运行绑定代码生成：
   ```sh
   cd plugins/flspeak_ffi && flutter_rust_bridge_codegen generate
   ```

### 4. 接入 Flutter 设置页 UI

1. 在 `arb/app_en.arb` 与 `arb/app_zh.arb` 中添加对应标题与说明文案。
2. 运行 l10n 代码生成：
   ```sh
   flutter gen-l10n
   ```
3. 在 `lib/features/settings/` 对应的二级分类页面中添加 `SettingsTile` 或 `SettingsRadioGroup`，绑定对应状态。

## 验证步骤

1. 运行代码检查与单测：
   ```sh
   just check
   ```
2. 启动应用，进入「设置」页面，切换该设置项。
3. 重启应用，验证该配置项是否成功持久化保存且状态正确恢复。
