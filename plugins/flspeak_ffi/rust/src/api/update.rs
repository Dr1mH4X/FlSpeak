//! 版本更新检查的 FFI 边界：检查是 `core/session` 的旁路，不挂在 `CoreSession` 上。

use flutter_rust_bridge::frb;
use session::UpdateState as CoreUpdateState;

use super::session::CoreError;

#[derive(Debug, Clone)]
pub struct UpdateStateView {
    pub available: bool,
    pub latest_version: Option<String>,
    pub release_url: Option<String>,
    pub release_notes: Option<String>,
}

/// 当前构建的展示版本号；未注入 `APP_DISPLAY_VERSION` 时回退到 Cargo workspace 版本。
#[frb(sync)]
pub fn app_version() -> String {
    resolve_display_version(
        option_env!("APP_DISPLAY_VERSION"),
        env!("CARGO_PKG_VERSION"),
    )
}

fn resolve_display_version(override_version: Option<&str>, package_version: &str) -> String {
    match override_version {
        Some(version) if !version.is_empty() => version.to_string(),
        _ => package_version.to_string(),
    }
}

/// 刷新更新状态，返回可直接渲染的最终结果。
pub async fn check_for_updates() -> UpdateStateView {
    UpdateStateView::from(session::check_for_updates().await)
}

/// 绕过本地 6 小时 TTL 缓存强制检查更新，失败时向上抛出 `CoreError`。
pub async fn force_check_for_updates() -> Result<UpdateStateView, CoreError> {
    session::force_check_for_updates()
        .await
        .map(UpdateStateView::from)
        .map_err(|error| CoreError::Internal {
            message: error.to_string(),
        })
}

impl From<CoreUpdateState> for UpdateStateView {
    fn from(state: CoreUpdateState) -> Self {
        Self {
            available: state.available,
            latest_version: state.latest_version,
            release_url: state.release_url,
            release_notes: state.release_notes,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::resolve_display_version;

    #[test]
    fn resolve_display_version_prefers_non_empty_override() {
        assert_eq!(
            resolve_display_version(Some("0.1.13-pr.42.10.abc1234"), "0.1.13"),
            "0.1.13-pr.42.10.abc1234"
        );
        assert_eq!(resolve_display_version(Some(""), "0.1.13"), "0.1.13");
        assert_eq!(resolve_display_version(None, "0.1.13"), "0.1.13");
    }
}
