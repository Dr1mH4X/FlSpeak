//! 出站 HTTP 的系统代理选择。
//!
//! 图片抓取与更新检查共用同一套规则：环境变量优先，其次读取系统代理。

use reqwest::ClientBuilder;

/// 应用系统代理；返回是否配置了代理。
///
/// reqwest 自身会读取环境变量代理，这里的返回值用于跳过 DNS 预解析等直连步骤。
pub(crate) fn configure(builder: ClientBuilder) -> (ClientBuilder, bool) {
    if has_env_proxy() {
        return (builder, true);
    }
    match system_proxy() {
        Some(proxy) => (builder.proxy(proxy), true),
        None => (builder, false),
    }
}

fn has_env_proxy() -> bool {
    [
        "HTTP_PROXY",
        "http_proxy",
        "HTTPS_PROXY",
        "https_proxy",
        "ALL_PROXY",
        "all_proxy",
    ]
    .iter()
    .any(|k| std::env::var_os(k).is_some_and(|v| !v.is_empty()))
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn system_proxy() -> Option<reqwest::Proxy> {
    if let Ok(sys_proxy) = sysproxy::Sysproxy::get_system_proxy()
        && sys_proxy.enable
        && !sys_proxy.host.is_empty()
        && sys_proxy.port > 0
    {
        let proxy_url = format!("http://{}:{}", sys_proxy.host, sys_proxy.port);
        return reqwest::Proxy::all(&proxy_url).ok();
    }
    None
}

#[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
fn system_proxy() -> Option<reqwest::Proxy> {
    None
}
