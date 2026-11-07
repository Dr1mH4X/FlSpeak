//! 全局日志订阅器与滚动文件输出。
//!
//! 日志目录由 Dart 启动阶段传入；Flutter 热重启会再次调用 [`init`]，必须幂等。
//! 写入使用 tracing-appender 的 non-blocking worker，队列满时丢日志而不是阻塞
//! 采集/会话线程。保留策略由 Dart 扫描日志目录统一执行，这里的
//! `max_log_files` 只兜住 Rust 单独运行时的文件数量。

use std::fs;
use std::path::Path;
use std::sync::{Mutex, MutexGuard};

use thiserror::Error;
use tracing_appender::non_blocking::{NonBlockingBuilder, WorkerGuard};
use tracing_appender::rolling::{RollingFileAppender, Rotation};
use tracing_subscriber::filter::LevelFilter;
use tracing_subscriber::fmt::time::ChronoUtc;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::{Layer, fmt};

#[cfg(debug_assertions)]
use tracing_subscriber::EnvFilter;

/// Rust 单独运行时的文件数量上限；Dart 侧还会按 UTC 日期清理两类日志。
const MAX_LOG_FILES: usize = 7;
const BUFFERED_LINES: usize = 4096;

#[derive(Debug, Error)]
pub enum LoggingError {
    #[error("create log directory failed: {0}")]
    Directory(#[from] std::io::Error),
    #[error("build rolling appender failed: {0}")]
    Appender(String),
    #[error("install tracing subscriber failed: {0}")]
    Subscriber(String),
    #[error("logging already shut down")]
    ShutDown,
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
        .filename_prefix("rust")
        .filename_suffix("log")
        .max_log_files(MAX_LOG_FILES)
        .build(log_dir)
        .map_err(|e| LoggingError::Appender(e.to_string()))?;

    // 队列满时丢弃日志，避免磁盘抖动把采集/会话线程一起拖住。
    let (non_blocking, guard) = NonBlockingBuilder::default()
        .lossy(true)
        .buffered_lines_limit(BUFFERED_LINES)
        .finish(appender);

    let file_level = if cfg!(debug_assertions) {
        LevelFilter::DEBUG
    } else {
        LevelFilter::INFO
    };
    let file_layer = fmt::layer()
        .json()
        .flatten_event(true)
        .with_timer(ChronoUtc::new("%Y-%m-%dT%H:%M:%S%.6fZ".to_string()))
        .with_current_span(true)
        .with_span_list(true)
        .with_ansi(false)
        .with_writer(non_blocking)
        .with_filter(file_level);

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
