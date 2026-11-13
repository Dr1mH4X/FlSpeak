use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use session::logging::{self, LogLevel};

fn temp_log_dir() -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system time")
        .as_nanos();
    std::env::temp_dir().join(format!(
        "flspeak-logging-hot-switch-{}-{nanos}",
        std::process::id()
    ))
}

fn read_all_logs(dir: &PathBuf) -> String {
    let mut combined = String::new();
    for entry in fs::read_dir(dir).expect("read log dir") {
        let entry = entry.expect("dir entry");
        if entry.path().is_file() {
            combined.push_str(&fs::read_to_string(entry.path()).expect("read log file"));
        }
    }
    combined
}

#[test]
fn set_level_hot_switches_written_events() {
    let dir = temp_log_dir();
    logging::set_level(LogLevel::Info);
    logging::init(&dir).expect("init logging");

    fn emit_probe(tag: &str) {
        tracing::debug!(target: "hot_switch_probe", tag, "probe-debug");
        tracing::info!(target: "hot_switch_probe", tag, "probe-info");
        tracing::warn!(target: "hot_switch_probe", tag, "probe-warn");
        tracing::error!(target: "hot_switch_probe", tag, "probe-error");
    }

    emit_probe("phase-info");

    logging::set_level(LogLevel::Debug);
    emit_probe("phase-debug");

    logging::set_level(LogLevel::Error);
    emit_probe("phase-error");

    logging::shutdown();

    let logs = read_all_logs(&dir);
    let _ = fs::remove_dir_all(&dir);

    assert!(
        !logs.contains("phase-info") || !logs.contains(r#""tag":"phase-info","level":"DEBUG""#)
    );
    let lines: Vec<&str> = logs.lines().collect();
    let has = |tag: &str, level: &str| {
        lines
            .iter()
            .any(|line| line.contains(tag) && line.contains(&format!(r#""level":"{level}""#)))
    };

    assert!(!has("phase-info", "DEBUG"));
    assert!(has("phase-info", "INFO"));

    assert!(has("phase-debug", "DEBUG"));
    assert!(has("phase-debug", "INFO"));

    assert!(!has("phase-error", "DEBUG"));
    assert!(!has("phase-error", "INFO"));
    assert!(!has("phase-error", "WARN"));
    assert!(has("phase-error", "ERROR"));
}
