//! 版本更新检查的 FFI 边界。
//!
//! 检查本身是 `core/session` 的旁路，不挂在 `CoreSession` 上，也不进入
//! Session Actor 的命令队列。

use flutter_rust_bridge::frb;
use session::UpdateState as CoreUpdateState;

#[derive(Debug, Clone)]
pub struct UpdateStateView {
    pub available: bool,
    pub latest_version: Option<String>,
    pub release_url: Option<String>,
}

/// 当前构建的版本号，与 Cargo workspace 版本一致。
#[frb(sync)]
pub fn app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// 刷新更新状态，返回可直接渲染的最终结果。
pub async fn check_for_updates() -> UpdateStateView {
    UpdateStateView::from(session::check_for_updates().await)
}

impl From<CoreUpdateState> for UpdateStateView {
    fn from(state: CoreUpdateState) -> Self {
        Self {
            available: state.available,
            latest_version: state.latest_version,
            release_url: state.release_url,
        }
    }
}
