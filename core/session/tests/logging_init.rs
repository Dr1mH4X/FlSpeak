use std::fs;
use std::sync::{Arc, Barrier};
use std::thread;

#[test]
fn concurrent_init_writes_ndjson_and_is_idempotent() {
    let dir = std::env::temp_dir().join(format!("flspeak-logging-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);

    let barrier = Arc::new(Barrier::new(4));
    let handles: Vec<_> = (0..4)
        .map(|_| {
            let dir = dir.clone();
            let barrier = Arc::clone(&barrier);
            thread::spawn(move || {
                barrier.wait();
                session::logging::init(&dir)
            })
        })
        .collect();
    for handle in handles {
        assert!(handle.join().expect("init thread panicked").is_ok());
    }

    tracing::info!(target: "logging_test", answer = 42, "hello from test");
    tracing::info!(target: "tsclient", message = "explicit event logger message");
    session::logging::shutdown();

    let file = fs::read_dir(&dir)
        .expect("read log dir")
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .find(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("rust.") && name.ends_with(".log"))
        })
        .expect("rust log file");
    let content = fs::read_to_string(file).expect("read log file");
    let record: serde_json::Value =
        serde_json::from_str(content.lines().next().expect("at least one log line"))
            .expect("valid ndjson");
    assert_eq!(record["message"], "hello from test");
    assert_eq!(record["answer"], 42);
    assert_eq!(record["level"], "INFO");
    assert!(
        record["timestamp"]
            .as_str()
            .is_some_and(|timestamp| timestamp.ends_with('Z')),
        "{record}"
    );
    assert!(
        content.contains("\"message\":\"explicit event logger message\""),
        "{content}"
    );

    let _ = fs::remove_dir_all(&dir);
}
