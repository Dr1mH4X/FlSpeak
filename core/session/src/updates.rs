//! 版本更新检查：固定 GitHub Releases 主机、SemVer 比较与 6 小时缓存。
//!
//! 这是一条旁路，不进入 Session Actor 的命令队列；连接和消息命令不能被更新请求
//! 排在后面。缓存与 `preferences.json` 同目录，只保存远端候选版本与 ETag。

use std::cmp::Ordering;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use reqwest::StatusCode;
use reqwest::Url;
use reqwest::header::{ACCEPT, ETAG, IF_NONE_MATCH, USER_AGENT};
use reqwest::redirect::Policy;
use semver::Version;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::sync::Mutex;

/// 更新缓存有效期。期间直接使用缓存，不访问网络。
pub const CACHE_TTL: Duration = Duration::from_secs(6 * 60 * 60);

const TIMEOUT: Duration = Duration::from_secs(8);
const MAX_RESPONSE_BYTES: usize = 4 * 1024 * 1024;
const CACHE_FILE: &str = "update-cache.json";
const RELEASES_URL: &str = "https://api.github.com/repos/Dr1mH4X/FlSpeak/releases?per_page=100";
const RELEASE_PATH_PREFIX: &str = "/Dr1mH4X/FlSpeak/releases/";
const RELEASE_TAG_URL: &str = "https://github.com/Dr1mH4X/FlSpeak/releases/tag";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateState {
    pub available: bool,
    pub latest_version: Option<String>,
    pub release_url: Option<String>,
}

impl UpdateState {
    fn unavailable() -> Self {
        Self {
            available: false,
            latest_version: None,
            release_url: None,
        }
    }

    fn available(version: String, release_url: String) -> Self {
        Self {
            available: true,
            latest_version: Some(version),
            release_url: Some(release_url),
        }
    }
}

#[derive(Debug, Error)]
enum UpdateError {
    #[error("更新缓存目录不可用: {0}")]
    Storage(String),
    #[error("请求 GitHub Releases 失败: {0}")]
    Request(String),
    #[error("GitHub Releases 返回 HTTP {0}")]
    Http(u16),
    #[error("GitHub Releases 响应过大")]
    TooLarge,
    #[error("解析 GitHub Releases 失败: {0}")]
    Parse(String),
}

static CHECK_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

/// 检查是否有比当前构建更新的版本。
///
/// 返回的始终是最终 UI 状态。网络、解析或缓存失败时回退到最近一次成功缓存；
/// 没有缓存则返回不可用。调用方只负责展示这个状态。
pub async fn check_for_updates() -> UpdateState {
    let lock = CHECK_LOCK.get_or_init(|| Mutex::new(()));
    let _guard = lock.lock().await;
    check_locked().await
}

async fn check_locked() -> UpdateState {
    let local = match Version::parse(env!("CARGO_PKG_VERSION")) {
        Ok(local) => local,
        Err(error) => {
            crate::log_warn!(error = error.to_string(); "本地版本不合法");
            return UpdateState::unavailable();
        }
    };
    let cache_path = match cache_path() {
        Ok(path) => path,
        Err(error) => {
            crate::log_warn!(error = error.to_string(); "更新检查不可用");
            return UpdateState::unavailable();
        }
    };
    let source = match HttpReleaseSource::new() {
        Ok(source) => source,
        Err(error) => {
            crate::log_warn!(error = error.to_string(); "更新检查失败");
            return fallback_from_cache(&cache_path, &local)
                .unwrap_or_else(UpdateState::unavailable);
        }
    };
    check_with_fallback(&source, &cache_path, &local, SystemTime::now()).await
}

async fn check_with_fallback(
    source: &dyn ReleaseSource,
    cache_path: &Path,
    local: &Version,
    now: SystemTime,
) -> UpdateState {
    match check_with_source(source, cache_path, local, now).await {
        Ok(state) => state,
        Err(error) => {
            crate::log_warn!(error = error.to_string(); "更新检查失败");
            fallback_from_cache(cache_path, local).unwrap_or_else(UpdateState::unavailable)
        }
    }
}

async fn check_with_source(
    source: &dyn ReleaseSource,
    cache_path: &Path,
    local: &Version,
    now: SystemTime,
) -> Result<UpdateState, UpdateError> {
    let now_secs = unix_seconds(now);
    let cached = read_cache(cache_path);

    if let Some(cache) = &cached
        && cache.checked_at <= now_secs
        && now_secs - cache.checked_at < CACHE_TTL.as_secs()
        && let Some(state) = state_from_cache(cache, local)
    {
        return Ok(state);
    }

    let etag = cached.as_ref().and_then(|cache| cache.etag.clone());
    let outcome = source.fetch(etag.as_deref()).await?;
    let payload = match outcome {
        FetchOutcome::NotModified => {
            let Some(mut cache) = cached.clone() else {
                return Err(UpdateError::Request("304 响应缺少缓存".into()));
            };
            if let Some(state) = state_from_cache(&cache, local) {
                cache.checked_at = now_secs;
                write_cache(cache_path, &cache);
                return Ok(state);
            }
            source.fetch(None).await?
        }
        payload => payload,
    };

    let FetchOutcome::Payload { body, etag } = payload else {
        return Err(UpdateError::Request(
            "GitHub Releases 返回了意外的 304".into(),
        ));
    };
    let candidate = select_candidate(&body, local)?;
    let cache = CachedRelease {
        checked_at: now_secs,
        etag,
        latest_version: candidate
            .as_ref()
            .map(|candidate| candidate.version.to_string()),
        release_url: candidate
            .as_ref()
            .map(|candidate| candidate.release_url.clone()),
    };
    let state = match &candidate {
        Some(candidate) if candidate.version.cmp_precedence(local) == Ordering::Greater => {
            UpdateState::available(candidate.version.to_string(), candidate.release_url.clone())
        }
        _ => UpdateState::unavailable(),
    };
    write_cache(cache_path, &cache);
    Ok(state)
}

fn fallback_from_cache(cache_path: &Path, local: &Version) -> Option<UpdateState> {
    read_cache(cache_path).and_then(|cache| state_from_cache(&cache, local))
}

fn cache_path() -> Result<PathBuf, UpdateError> {
    let dir = crate::settings::SettingsManager::data_dir().map_err(UpdateError::Storage)?;
    Ok(dir.join(CACHE_FILE))
}

fn state_from_cache(cache: &CachedRelease, local: &Version) -> Option<UpdateState> {
    let Some(raw) = cache.latest_version.as_deref() else {
        return Some(UpdateState::unavailable());
    };
    let version = Version::parse(raw).ok()?;
    if local.pre.is_empty() && !version.pre.is_empty() {
        return None;
    }
    if version.cmp_precedence(local) == Ordering::Greater {
        let release_url = cache
            .release_url
            .as_deref()
            .filter(|url| is_trusted_release_url(url))?
            .to_string();
        Some(UpdateState::available(version.to_string(), release_url))
    } else {
        Some(UpdateState::unavailable())
    }
}

#[derive(Debug, Deserialize)]
struct RawRelease {
    tag_name: String,
    #[serde(default)]
    draft: bool,
    #[serde(default)]
    prerelease: bool,
    #[serde(default)]
    html_url: Option<String>,
}

#[derive(Debug, Clone)]
struct Candidate {
    version: Version,
    release_url: String,
}

fn select_candidate(body: &str, local: &Version) -> Result<Option<Candidate>, UpdateError> {
    let releases: Vec<RawRelease> =
        serde_json::from_str(body).map_err(|err| UpdateError::Parse(err.to_string()))?;
    let local_is_prerelease = !local.pre.is_empty();

    Ok(releases
        .into_iter()
        .filter(|release| !release.draft)
        .filter(|release| local_is_prerelease || !release.prerelease)
        .filter_map(|release| {
            let version = parse_tag(&release.tag_name)?;
            if !local_is_prerelease && !version.pre.is_empty() {
                return None;
            }
            let release_url = release_url(release.html_url.as_deref(), &release.tag_name);
            Some(Candidate {
                version,
                release_url,
            })
        })
        .max_by(|left, right| left.version.cmp_precedence(&right.version)))
}

fn parse_tag(tag: &str) -> Option<Version> {
    let trimmed = tag.trim();
    let trimmed = trimmed
        .strip_prefix('v')
        .or_else(|| trimmed.strip_prefix('V'))
        .unwrap_or(trimmed);
    Version::parse(trimmed).ok()
}

fn release_url(api_url: Option<&str>, tag: &str) -> String {
    if let Some(url) = api_url
        && is_trusted_release_url(url)
    {
        return url.to_string();
    }
    build_tag_url(tag)
}

fn build_tag_url(tag: &str) -> String {
    let Ok(mut url) = Url::parse(RELEASE_TAG_URL) else {
        return "https://github.com/Dr1mH4X/FlSpeak/releases".to_string();
    };
    if let Ok(mut segments) = url.path_segments_mut() {
        segments.push(tag);
    }
    url.to_string()
}

fn is_trusted_release_url(raw: &str) -> bool {
    Url::parse(raw).is_ok_and(|url| {
        url.scheme() == "https"
            && url.host_str() == Some("github.com")
            && url.path().starts_with(RELEASE_PATH_PREFIX)
    })
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CachedRelease {
    checked_at: u64,
    #[serde(default)]
    etag: Option<String>,
    #[serde(default)]
    latest_version: Option<String>,
    #[serde(default)]
    release_url: Option<String>,
}

fn read_cache(path: &Path) -> Option<CachedRelease> {
    let raw = std::fs::read_to_string(path).ok()?;
    match serde_json::from_str(&raw) {
        Ok(cache) => Some(cache),
        Err(error) => {
            crate::log_warn!(error = error.to_string(); "更新缓存无法解析");
            None
        }
    }
}

fn write_cache(path: &Path, cache: &CachedRelease) {
    let serialized = match serde_json::to_vec(cache) {
        Ok(serialized) => serialized,
        Err(error) => {
            crate::log_warn!(error = error.to_string(); "更新缓存序列化失败");
            return;
        }
    };
    let Some(parent) = path.parent() else {
        crate::log_warn!("更新缓存缺少父目录");
        return;
    };
    if let Err(error) = std::fs::create_dir_all(parent) {
        crate::log_warn!(error = error.to_string(); "创建更新缓存目录失败");
        return;
    }
    let temporary = path.with_extension("json.tmp");
    if let Err(error) = std::fs::write(&temporary, serialized) {
        crate::log_warn!(error = error.to_string(); "写入更新缓存失败");
        return;
    }
    if let Err(error) = std::fs::rename(&temporary, path) {
        let _ = std::fs::remove_file(&temporary);
        crate::log_warn!(error = error.to_string(); "替换更新缓存失败");
    }
}

fn unix_seconds(now: SystemTime) -> u64 {
    now.duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or(0)
}

#[async_trait]
trait ReleaseSource: Send + Sync {
    async fn fetch(&self, etag: Option<&str>) -> Result<FetchOutcome, UpdateError>;
}

enum FetchOutcome {
    NotModified,
    Payload { body: String, etag: Option<String> },
}

struct HttpReleaseSource {
    client: reqwest::Client,
}

impl HttpReleaseSource {
    fn new() -> Result<Self, UpdateError> {
        let (builder, _) = crate::proxy::configure(
            reqwest::Client::builder()
                .timeout(TIMEOUT)
                .redirect(Policy::none()),
        );
        let client = builder
            .build()
            .map_err(|err| UpdateError::Request(err.to_string()))?;
        Ok(Self { client })
    }
}

#[async_trait]
impl ReleaseSource for HttpReleaseSource {
    async fn fetch(&self, etag: Option<&str>) -> Result<FetchOutcome, UpdateError> {
        let request = self
            .client
            .get(RELEASES_URL)
            .header(USER_AGENT, format!("FlSpeak/{}", env!("CARGO_PKG_VERSION")))
            .header(ACCEPT, "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28");
        let request = match etag {
            Some(etag) => request.header(IF_NONE_MATCH, etag),
            None => request,
        };

        tokio::time::timeout(TIMEOUT, async {
            let response = request
                .send()
                .await
                .map_err(|err| UpdateError::Request(err.to_string()))?;
            if response.status() == StatusCode::NOT_MODIFIED {
                return Ok(FetchOutcome::NotModified);
            }
            if !response.status().is_success() {
                return Err(UpdateError::Http(response.status().as_u16()));
            }
            let etag = response
                .headers()
                .get(ETAG)
                .and_then(|value| value.to_str().ok())
                .map(str::to_string);
            let body = read_limited(response).await?;
            Ok(FetchOutcome::Payload { body, etag })
        })
        .await
        .map_err(|_| UpdateError::Request("请求超时".into()))?
    }
}

async fn read_limited(mut response: reqwest::Response) -> Result<String, UpdateError> {
    let mut bytes = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|err| UpdateError::Request(err.to_string()))?
    {
        if bytes.len().saturating_add(chunk.len()) > MAX_RESPONSE_BYTES {
            return Err(UpdateError::TooLarge);
        }
        bytes.extend_from_slice(&chunk);
    }
    String::from_utf8(bytes).map_err(|err| UpdateError::Parse(err.to_string()))
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use serde_json::json;

    use super::*;

    struct FakeSource {
        responses: Mutex<VecDeque<Result<FetchOutcome, UpdateError>>>,
        calls: AtomicUsize,
    }

    impl FakeSource {
        fn new(responses: Vec<Result<FetchOutcome, UpdateError>>) -> Self {
            Self {
                responses: Mutex::new(responses.into()),
                calls: AtomicUsize::new(0),
            }
        }

        fn calls(&self) -> usize {
            self.calls.load(Ordering::SeqCst)
        }
    }

    #[async_trait]
    impl ReleaseSource for FakeSource {
        async fn fetch(&self, _etag: Option<&str>) -> Result<FetchOutcome, UpdateError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            self.responses
                .lock()
                .expect("fake source lock")
                .pop_front()
                .unwrap_or_else(|| Err(UpdateError::Request("unexpected fetch".into())))
        }
    }

    fn now() -> SystemTime {
        UNIX_EPOCH + Duration::from_secs(1_800_000_000)
    }

    fn cache_path() -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("flspeak-update-cache-{:x}", rand::random::<u64>()));
        std::fs::create_dir_all(&dir).expect("create temp dir");
        dir.join(CACHE_FILE)
    }

    fn cleanup(path: &Path) {
        if let Some(dir) = path.parent() {
            let _ = std::fs::remove_dir_all(dir);
        }
    }

    fn payload(releases: Vec<serde_json::Value>) -> FetchOutcome {
        FetchOutcome::Payload {
            body: serde_json::to_string(&releases).expect("serialize releases"),
            etag: Some("\"etag-1\"".into()),
        }
    }

    fn release(tag: &str, prerelease: bool) -> serde_json::Value {
        json!({
            "tag_name": tag,
            "draft": false,
            "prerelease": prerelease,
            "html_url": format!("https://github.com/Dr1mH4X/FlSpeak/releases/tag/{tag}"),
        })
    }

    async fn check(
        source: &FakeSource,
        path: &Path,
        local: &str,
    ) -> Result<UpdateState, UpdateError> {
        let local = Version::parse(local).expect("local version");
        check_with_source(source, path, &local, now()).await
    }

    #[test]
    fn parses_v_prefixed_and_plain_tags() {
        assert_eq!(parse_tag("v0.2.0"), Some(Version::new(0, 2, 0)));
        assert_eq!(parse_tag("0.2.0"), Some(Version::new(0, 2, 0)));
        assert_eq!(parse_tag("V0.2.0"), Some(Version::new(0, 2, 0)));
        assert_eq!(parse_tag("nightly"), None);
    }

    #[test]
    fn stable_local_ignores_prerelease_versions_even_without_the_flag() {
        let local = Version::parse("0.1.0").expect("local version");
        let body = serde_json::to_string(&vec![
            release("v0.2.0-beta.1", false),
            release("v0.1.1", false),
        ])
        .expect("serialize releases");
        let candidate = select_candidate(&body, &local).expect("parse releases");
        assert_eq!(
            candidate.map(|candidate| candidate.version),
            Some(Version::parse("0.1.1").expect("stable version"))
        );
    }

    #[test]
    fn stable_local_honors_the_prerelease_flag() {
        let local = Version::parse("0.1.0").expect("local version");
        let body = serde_json::to_string(&vec![release("v0.2.0", true), release("v0.1.1", false)])
            .expect("serialize releases");
        let candidate = select_candidate(&body, &local).expect("parse releases");
        assert_eq!(
            candidate.map(|candidate| candidate.version),
            Some(Version::parse("0.1.1").expect("stable version"))
        );
    }

    #[test]
    fn prerelease_local_can_upgrade_to_stable() {
        let local = Version::parse("0.2.0-beta.1").expect("local version");
        let body = serde_json::to_string(&vec![release("v0.2.0", false)]).expect("serialize");
        let candidate = select_candidate(&body, &local).expect("parse releases");
        assert_eq!(
            candidate.map(|candidate| candidate.version),
            Some(Version::new(0, 2, 0))
        );
    }

    #[test]
    fn invalid_release_url_falls_back_to_the_tag_url() {
        let local = Version::parse("0.1.0").expect("local version");
        let body = serde_json::to_string(&vec![json!({
            "tag_name": "v0.2.0",
            "draft": false,
            "prerelease": false,
            "html_url": "https://example.com/releases/v0.2.0",
        })])
        .expect("serialize");
        let candidate = select_candidate(&body, &local)
            .expect("parse releases")
            .expect("candidate");
        assert_eq!(
            candidate.release_url,
            "https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0"
        );
    }

    #[tokio::test]
    async fn reports_available_for_a_newer_stable_release() {
        let path = cache_path();
        let source = FakeSource::new(vec![Ok(payload(vec![release("v0.2.0", false)]))]);
        let result = check(&source, &path, "0.1.0").await.expect("check");
        assert!(result.available);
        assert_eq!(result.latest_version.as_deref(), Some("0.2.0"));
        assert_eq!(
            result.release_url.as_deref(),
            Some("https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0")
        );
        cleanup(&path);
    }

    #[tokio::test]
    async fn stable_local_does_not_upgrade_to_a_prerelease() {
        let path = cache_path();
        let source = FakeSource::new(vec![Ok(payload(vec![release("v0.2.0-beta.1", true)]))]);
        let result = check(&source, &path, "0.1.0").await.expect("check");
        assert!(!result.available);
        cleanup(&path);
    }

    #[tokio::test]
    async fn prerelease_local_upgrades_to_a_newer_stable_release() {
        let path = cache_path();
        let source = FakeSource::new(vec![Ok(payload(vec![release("v0.2.0", false)]))]);
        let result = check(&source, &path, "0.2.0-beta.1").await.expect("check");
        assert!(result.available);
        assert_eq!(result.latest_version.as_deref(), Some("0.2.0"));
        cleanup(&path);
    }

    #[tokio::test]
    async fn prerelease_local_upgrades_to_a_higher_prerelease() {
        let path = cache_path();
        let source = FakeSource::new(vec![Ok(payload(vec![release("v0.2.0-beta.2", true)]))]);
        let result = check(&source, &path, "0.2.0-beta.1").await.expect("check");
        assert!(result.available);
        assert_eq!(result.latest_version.as_deref(), Some("0.2.0-beta.2"));
        cleanup(&path);
    }

    #[tokio::test]
    async fn reports_up_to_date_for_equal_build_metadata() {
        let path = cache_path();
        let source = FakeSource::new(vec![Ok(payload(vec![release("v0.1.0+3", false)]))]);
        let result = check(&source, &path, "0.1.0").await.expect("check");
        assert!(!result.available);
        cleanup(&path);
    }

    #[tokio::test]
    async fn reports_up_to_date_when_local_is_ahead() {
        let path = cache_path();
        let source = FakeSource::new(vec![Ok(payload(vec![release("v0.1.0", false)]))]);
        let result = check(&source, &path, "0.2.0").await.expect("check");
        assert!(!result.available);
        cleanup(&path);
    }

    #[tokio::test]
    async fn reports_up_to_date_for_an_empty_release_list() {
        let path = cache_path();
        let source = FakeSource::new(vec![Ok(payload(Vec::new()))]);
        let result = check(&source, &path, "0.1.0").await.expect("check");
        assert!(!result.available);
        cleanup(&path);
    }

    #[tokio::test]
    async fn skips_non_semver_tags() {
        let path = cache_path();
        let source = FakeSource::new(vec![Ok(payload(vec![release("nightly", false)]))]);
        let result = check(&source, &path, "0.1.0").await.expect("check");
        assert!(!result.available);
        cleanup(&path);
    }

    #[tokio::test]
    async fn surfaces_http_errors() {
        let path = cache_path();
        let source = FakeSource::new(vec![Err(UpdateError::Http(403))]);
        let result = check(&source, &path, "0.1.0").await;
        assert!(matches!(result, Err(UpdateError::Http(403))));
        cleanup(&path);
    }

    #[tokio::test]
    async fn surfaces_timeouts() {
        let path = cache_path();
        let source = FakeSource::new(vec![Err(UpdateError::Request("请求超时".into()))]);
        let result = check(&source, &path, "0.1.0").await;
        assert!(matches!(result, Err(UpdateError::Request(_))));
        cleanup(&path);
    }

    #[tokio::test]
    async fn surfaces_malformed_json() {
        let path = cache_path();
        let source = FakeSource::new(vec![Ok(FetchOutcome::Payload {
            body: "not json".into(),
            etag: None,
        })]);
        let result = check(&source, &path, "0.1.0").await;
        assert!(matches!(result, Err(UpdateError::Parse(_))));
        cleanup(&path);
    }

    #[tokio::test]
    async fn uses_a_fresh_cache_without_fetching() {
        let path = cache_path();
        write_cache(
            &path,
            &CachedRelease {
                checked_at: unix_seconds(now()) - 1,
                etag: None,
                latest_version: Some("0.2.0".into()),
                release_url: Some("https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0".into()),
            },
        );
        let source = FakeSource::new(Vec::new());
        let result = check(&source, &path, "0.1.0").await.expect("check");
        assert!(result.available);
        assert_eq!(source.calls(), 0);
        cleanup(&path);
    }

    #[tokio::test]
    async fn a_cached_release_disappears_after_the_local_version_passes_it() {
        let path = cache_path();
        write_cache(
            &path,
            &CachedRelease {
                checked_at: unix_seconds(now()) - 1,
                etag: None,
                latest_version: Some("0.1.0".into()),
                release_url: Some("https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.1.0".into()),
            },
        );
        let source = FakeSource::new(Vec::new());
        let result = check(&source, &path, "0.2.0").await.expect("check");
        assert!(!result.available);
        assert_eq!(source.calls(), 0);
        cleanup(&path);
    }

    #[tokio::test]
    async fn refetches_an_expired_cache_and_refreshes_the_etag() {
        let path = cache_path();
        write_cache(
            &path,
            &CachedRelease {
                checked_at: unix_seconds(now()) - CACHE_TTL.as_secs() - 1,
                etag: Some("\"old\"".into()),
                latest_version: Some("0.1.0".into()),
                release_url: Some("https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.1.0".into()),
            },
        );
        let source = FakeSource::new(vec![Ok(payload(vec![release("v0.2.0", false)]))]);
        let result = check(&source, &path, "0.1.0").await.expect("check");
        assert!(result.available);
        assert_eq!(source.calls(), 1);
        let cache = read_cache(&path).expect("cache");
        assert_eq!(cache.etag.as_deref(), Some("\"etag-1\""));
        assert_eq!(cache.latest_version.as_deref(), Some("0.2.0"));
        cleanup(&path);
    }

    #[tokio::test]
    async fn handles_not_modified_and_extends_the_cache_ttl() {
        let path = cache_path();
        let old_checked_at = unix_seconds(now()) - CACHE_TTL.as_secs() - 1;
        write_cache(
            &path,
            &CachedRelease {
                checked_at: old_checked_at,
                etag: Some("\"etag-1\"".into()),
                latest_version: Some("0.2.0".into()),
                release_url: Some("https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0".into()),
            },
        );
        let source = FakeSource::new(vec![Ok(FetchOutcome::NotModified)]);
        let result = check(&source, &path, "0.1.0").await.expect("check");
        assert!(result.available);
        let cache = read_cache(&path).expect("cache");
        assert_eq!(cache.checked_at, unix_seconds(now()));
        assert!(unix_seconds(now()) > old_checked_at);
        cleanup(&path);
    }

    #[tokio::test]
    async fn keeps_the_last_successful_cache_when_a_check_fails() {
        let path = cache_path();
        let cached = CachedRelease {
            checked_at: unix_seconds(now()) - CACHE_TTL.as_secs() - 1,
            etag: Some("\"etag-1\"".into()),
            latest_version: Some("0.2.0".into()),
            release_url: Some("https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0".into()),
        };
        write_cache(&path, &cached);
        let source = FakeSource::new(vec![Err(UpdateError::Http(403))]);
        let result = check(&source, &path, "0.1.0").await;
        assert!(matches!(result, Err(UpdateError::Http(403))));
        let after = read_cache(&path).expect("cache");
        assert_eq!(after.checked_at, cached.checked_at);
        assert_eq!(after.latest_version, cached.latest_version);
        cleanup(&path);
    }

    #[tokio::test]
    async fn a_failed_check_keeps_the_cached_update_state() {
        let path = cache_path();
        write_cache(
            &path,
            &CachedRelease {
                checked_at: unix_seconds(now()) - CACHE_TTL.as_secs() - 1,
                etag: Some("\"etag-1\"".into()),
                latest_version: Some("0.2.0".into()),
                release_url: Some("https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0".into()),
            },
        );
        let local = Version::parse("0.1.0").expect("local version");
        let source = FakeSource::new(vec![Err(UpdateError::Http(403))]);
        let state = check_with_fallback(&source, &path, &local, now()).await;
        assert!(state.available);
        assert_eq!(state.latest_version.as_deref(), Some("0.2.0"));
        cleanup(&path);
    }

    #[tokio::test]
    async fn a_failed_check_without_cache_returns_unavailable() {
        let path = cache_path();
        let local = Version::parse("0.1.0").expect("local version");
        let source = FakeSource::new(vec![Err(UpdateError::Request("请求超时".into()))]);
        let state = check_with_fallback(&source, &path, &local, now()).await;
        assert!(!state.available);
        cleanup(&path);
    }

    #[tokio::test]
    async fn malformed_json_keeps_the_cached_update_state() {
        let path = cache_path();
        write_cache(
            &path,
            &CachedRelease {
                checked_at: unix_seconds(now()) - CACHE_TTL.as_secs() - 1,
                etag: None,
                latest_version: Some("0.2.0".into()),
                release_url: Some("https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0".into()),
            },
        );
        let local = Version::parse("0.1.0").expect("local version");
        let source = FakeSource::new(vec![Ok(FetchOutcome::Payload {
            body: "not json".into(),
            etag: None,
        })]);
        let state = check_with_fallback(&source, &path, &local, now()).await;
        assert!(state.available);
        cleanup(&path);
    }

    #[tokio::test]
    async fn refetches_without_etag_when_cached_channel_no_longer_matches() {
        let path = cache_path();
        write_cache(
            &path,
            &CachedRelease {
                checked_at: unix_seconds(now()) - CACHE_TTL.as_secs() - 1,
                etag: Some("\"etag-1\"".into()),
                latest_version: Some("0.2.0-beta.1".into()),
                release_url: Some(
                    "https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0-beta.1".into(),
                ),
            },
        );
        let source = FakeSource::new(vec![
            Ok(FetchOutcome::NotModified),
            Ok(payload(vec![release("v0.2.0", false)])),
        ]);
        let result = check(&source, &path, "0.1.0").await.expect("check");
        assert!(result.available);
        assert_eq!(result.latest_version.as_deref(), Some("0.2.0"));
        assert_eq!(source.calls(), 2);
        cleanup(&path);
    }
}
