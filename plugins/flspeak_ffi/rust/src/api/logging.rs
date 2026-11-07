use std::fs;
use std::path::PathBuf;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicBool, Ordering};
use tracing_appender::non_blocking::{NonBlockingBuilder, WorkerGuard};
use tracing_appender::rolling::{RollingFileAppender, Rotation};
use tracing_subscriber::{
    EnvFilter, Layer, filter::LevelFilter, fmt, layer::SubscriberExt, util::SubscriberInitExt,
};

static INITIALIZED: AtomicBool = AtomicBool::new(false);
static _GUARD: OnceLock<WorkerGuard> = OnceLock::new();

/// 异步 FFI 接口：供 Dart 端在启动阶段调用
pub fn init_logging(log_dir: String) -> Result<(), String> {
    if INITIALIZED.load(Ordering::SeqCst) {
        return Ok(()); // 幂等保护，Flutter 热重启直接放行
    }

    let dir = PathBuf::from(log_dir);
    fs::create_dir_all(&dir).map_err(|e| format!("create_dir_all failed: {e}"))?;

    // 1. 每日 UTC 轮转，保留 7 天
    let file_appender = RollingFileAppender::builder()
        .rotation(Rotation::DAILY)
        .filename_prefix("rust")
        .filename_suffix("log")
        .max_log_files(7)
        .build(dir)
        .map_err(|e| format!("build RollingFileAppender failed: {e}"))?;

    // 2. non_blocking 异步写入包装
    let (non_blocking, guard) = NonBlockingBuilder::default()
        .lossy(false)
        .buffered_lines_limit(4096)
        .finish(file_appender);
    _GUARD.set(guard).ok();

    // 3. 文件层：本地时区带偏移的 RFC3339 时间戳、保留 Span、JSON Lines
    let file_layer = fmt::layer()
        .json()
        .with_timer(fmt::time::ChronoLocal::rfc_3339())
        .with_current_span(true)
        .with_span_list(true)
        .with_ansi(false)
        .with_writer(non_blocking)
        .with_filter(LevelFilter::INFO);

    let registry = tracing_subscriber::registry().with(file_layer);

    // 4. 控制台层：Debug 或测试模式下输出 stderr
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

    // 5. 移动端 Release：仅在 Android 下把 Warn+ 通过 NDK 输出至 logcat
    #[cfg(all(not(debug_assertions), target_os = "android"))]
    let registry = {
        let android_layer = tracing_android::layer("FlSpeak-Rust")
            .map_err(|e| format!("tracing_android failed: {e}"))?
            .with_filter(LevelFilter::WARN);
        registry.with(android_layer)
    };

    registry
        .try_init()
        .map_err(|e| format!("try_init failed: {e}"))?;
    INITIALIZED.store(true, Ordering::SeqCst);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_init_logging_idempotent() {
        let temp_dir =
            std::env::temp_dir().join(format!("flspeak_test_log_{}", std::process::id()));
        let res1 = init_logging(temp_dir.to_string_lossy().to_string());
        assert!(res1.is_ok());

        // 第二次调用必须成功（幂等）
        let res2 = init_logging(temp_dir.to_string_lossy().to_string());
        assert!(res2.is_ok());

        let _ = fs::remove_dir_all(&temp_dir);
    }
}
