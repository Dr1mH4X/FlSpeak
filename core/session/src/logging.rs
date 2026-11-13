//! 全局日志订阅器与滚动文件输出。
//!
//! 日志目录由 Dart 启动阶段传入；Flutter 热重启会再次调用 [`init`]，必须幂等。
//! 写入使用 tracing-appender 的 non-blocking worker，队列满时丢日志而不是阻塞
//! 采集/会话线程。保留策略由 Dart 扫描日志目录统一执行，这里的
//! `max_log_files` 只兜住 Rust 单独运行时的文件数量。

use std::fs;
use std::path::Path;
use std::str::FromStr;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Mutex, MutexGuard};

use thiserror::Error;
use tracing::Metadata;
use tracing::subscriber::Interest;
use tracing_appender::non_blocking::{NonBlockingBuilder, WorkerGuard};
use tracing_appender::rolling::{RollingFileAppender, Rotation};
use tracing_subscriber::filter::LevelFilter;
use tracing_subscriber::fmt::time::ChronoUtc;
use tracing_subscriber::layer::{Context, Filter, SubscriberExt};
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::{Layer, fmt};

#[cfg(debug_assertions)]
use tracing_subscriber::EnvFilter;

/// Rust 单独运行时的文件数量上限；Dart 侧还会按 UTC 日期清理两类日志。
const MAX_LOG_FILES: usize = 7;
const BUFFERED_LINES: usize = 4096;

/// 后端文件日志筛选等级。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum LogLevel {
    Debug = 0,
    Info = 1,
    Warning = 2,
    Error = 3,
}

impl LogLevel {
    /// 当前构建形态的默认日志等级。
    pub fn default_for_build() -> Self {
        if cfg!(debug_assertions) {
            Self::Debug
        } else {
            Self::Info
        }
    }

    /// 转换为协议/配置约定的小写字符串。
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Debug => "debug",
            Self::Info => "info",
            Self::Warning => "warning",
            Self::Error => "error",
        }
    }

    fn from_code(code: u8) -> Self {
        match code {
            0 => Self::Debug,
            1 => Self::Info,
            2 => Self::Warning,
            3 => Self::Error,
            _ => Self::default_for_build(),
        }
    }

    fn to_tracing_level(self) -> tracing::Level {
        match self {
            Self::Debug => tracing::Level::DEBUG,
            Self::Info => tracing::Level::INFO,
            Self::Warning => tracing::Level::WARN,
            Self::Error => tracing::Level::ERROR,
        }
    }
}

impl FromStr for LogLevel {
    type Err = LoggingError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.trim().to_ascii_lowercase().as_str() {
            "debug" => Ok(Self::Debug),
            "info" => Ok(Self::Info),
            "warning" | "warn" => Ok(Self::Warning),
            "error" => Ok(Self::Error),
            _ => Err(LoggingError::InvalidLevel(s.to_string())),
        }
    }
}

const DEFAULT_LEVEL_CODE: u8 = if cfg!(debug_assertions) { 0 } else { 1 };
static ACTIVE_LEVEL: AtomicU8 = AtomicU8::new(DEFAULT_LEVEL_CODE);

fn current_level() -> LogLevel {
    LogLevel::from_code(ACTIVE_LEVEL.load(Ordering::Relaxed))
}

struct DynamicFileFilter;

impl<S> Filter<S> for DynamicFileFilter {
    fn enabled(&self, meta: &Metadata<'_>, _ctx: &Context<'_, S>) -> bool {
        *meta.level() <= current_level().to_tracing_level()
    }

    fn callsite_enabled(&self, meta: &'static Metadata<'static>) -> Interest {
        if *meta.level() <= current_level().to_tracing_level() {
            Interest::always()
        } else {
            Interest::never()
        }
    }

    fn max_level_hint(&self) -> Option<LevelFilter> {
        // 静态上限保持为 DEBUG，避免运行期由更高等级切回 debug 时 callsite 被永久裁掉。
        Some(LevelFilter::DEBUG)
    }
}

#[derive(Debug, Error)]
pub enum LoggingError {
    #[error("create log directory failed: {0}")]
    Directory(#[from] std::io::Error),
    #[error("build rolling appender failed: {0}")]
    Appender(String),
    #[error("install tracing subscriber failed: {0}")]
    Subscriber(String),
    #[error("invalid log level: {0}")]
    InvalidLevel(String),
    #[error("logging already shut down")]
    ShutDown,
}

/// 运行期热更新后端文件日志筛选等级。
pub fn set_level(level: LogLevel) {
    let previous = ACTIVE_LEVEL.swap(level as u8, Ordering::Relaxed);
    if previous != level as u8 {
        tracing::callsite::rebuild_interest_cache();
    }
}

enum Phase {
    Uninitialized,
    Initialized,
    ShutDown,
}

struct State {
    phase: Phase,
    guard: Option<WorkerGuard>,
}

static STATE: Mutex<State> = Mutex::new(State {
    phase: Phase::Uninitialized,
    guard: None,
});

fn lock_state() -> MutexGuard<'static, State> {
    STATE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// 安装全局日志订阅器。重复调用直接返回成功，初始化失败后可以重试。
pub fn init(log_dir: &Path) -> Result<(), LoggingError> {
    let mut state = lock_state();
    match state.phase {
        Phase::Initialized => return Ok(()),
        Phase::ShutDown => return Err(LoggingError::ShutDown),
        Phase::Uninitialized => {}
    }

    fs::create_dir_all(log_dir)?;

    let appender = RollingFileAppender::builder()
        .rotation(Rotation::DAILY)
        .filename_prefix("backend")
        .filename_suffix("log")
        .max_log_files(MAX_LOG_FILES)
        .build(log_dir)
        .map_err(|e| LoggingError::Appender(e.to_string()))?;

    // 队列满时丢弃日志，避免磁盘抖动把采集/会话线程一起拖住。
    let (non_blocking, guard) = NonBlockingBuilder::default()
        .lossy(true)
        .buffered_lines_limit(BUFFERED_LINES)
        .finish(appender);

    let file_layer = fmt::layer()
        .json()
        .flatten_event(true)
        .with_timer(ChronoUtc::new("%Y-%m-%dT%H:%M:%S%.6fZ".to_string()))
        .with_current_span(true)
        .with_span_list(true)
        .with_ansi(false)
        .with_writer(non_blocking)
        .with_filter(DynamicFileFilter);

    let registry = tracing_subscriber::registry().with(file_layer);

    #[cfg(debug_assertions)]
    let registry = {
        let env_filter =
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
        let console_layer = fmt::layer()
            .with_writer(std::io::stderr)
            .with_ansi(true)
            .with_filter(env_filter);
        registry.with(console_layer)
    };

    // logcat 只作为附加输出；它不可用时不能拖垮文件日志。
    #[cfg(all(not(debug_assertions), target_os = "android"))]
    let registry = {
        let android_layer = tracing_android::layer("FlSpeak-Rust")
            .map_err(|e| eprintln!("tracing_android layer unavailable: {e}"))
            .ok()
            .map(|layer| layer.with_filter(LevelFilter::WARN));
        registry.with(android_layer)
    };

    registry
        .try_init()
        .map_err(|e| LoggingError::Subscriber(e.to_string()))?;

    state.guard = Some(guard);
    state.phase = Phase::Initialized;
    Ok(())
}

/// 释放 worker，把队列里的日志写完。停止后不能再 [`init`]。
pub fn shutdown() {
    let guard = {
        let mut state = lock_state();
        if matches!(state.phase, Phase::Initialized) {
            state.phase = Phase::ShutDown;
            state.guard.take()
        } else {
            None
        }
    };
    drop(guard);
}
