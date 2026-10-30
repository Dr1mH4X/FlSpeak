//! 统一的设置与配置系统。
//!
//! 提供强类型配置 Schema 声明与单例 `SettingsManager` 内存/持久化管理，
//! 实现业务消费与底层 IO/反序列化的彻底解耦。

pub mod manager;
pub mod schema;

pub use manager::SettingsManager;
pub use schema::{AppSettings, AudioSettings, NetworkSettings, UiSettings};
