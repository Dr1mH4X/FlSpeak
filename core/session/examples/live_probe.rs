//! 临时探针：打印连接后的成员列表、目录快照与自身频道。
//! `FLSPEAK_TEST_SERVER=host cargo run -p session --example live_probe`

use std::time::Duration;

use session::{SessionEvent, SessionHandle, SessionOptions};

#[tokio::main]
async fn main() {
    let Ok(address) = std::env::var("FLSPEAK_TEST_SERVER") else {
        eprintln!("需要 FLSPEAK_TEST_SERVER");
        return;
    };
    let nickname =
        std::env::var("FLSPEAK_TEST_NICKNAME").unwrap_or_else(|_| "flspeak-probe".into());
    let dir = std::env::temp_dir().join(format!("flspeak-probe-{}", std::process::id()));
    let _ = tokio::fs::remove_dir_all(&dir).await;

    let handle = SessionHandle::spawn_with_options(
        dir.join("servers.json"),
        SessionOptions { audio: false },
    )
    .expect("启动会话");
    let mut events = handle.subscribe();
    let log_path = std::path::PathBuf::from("/tmp/flspeak-probe.log");
    let logger = tokio::spawn(async move {
        use tokio::io::AsyncWriteExt;
        let mut file = tokio::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .await
            .ok();
        loop {
            match events.recv().await {
                Ok(SessionEvent::ClientJoined(client)) => {
                    println!(
                        "[enter] {}:{}@{}",
                        client.id, client.nickname, client.channel_id
                    );
                }
                Ok(SessionEvent::ClientMoved { id, channel_id }) => {
                    println!("[moved] {id} -> {channel_id}");
                }
                Ok(SessionEvent::Log { level, message }) => println!("[log/{level}] {message}"),
                Ok(SessionEvent::TextMessage(message)) => {
                    println!("[text] {}: {}", message.from, message.message);
                    if let Some(file) = file.as_mut() {
                        let _ = file.write_all(message.message.as_bytes()).await;
                        let _ = file.write_all(b"\n").await;
                    }
                }
                Ok(SessionEvent::Snapshot { channels, clients }) => {
                    let rows = clients
                        .iter()
                        .map(|c| format!("{}:{}@{},", c.id, c.nickname, c.channel_id))
                        .collect::<String>();
                    println!("[snapshot clients] {rows}");
                    let chs = channels
                        .iter()
                        .filter(|c| {
                            c.name.contains("入口") || c.name.contains("t2a") || c.parent_id == 0
                        })
                        .map(|c| format!("{}:{},", c.id, c.name))
                        .collect::<String>();
                    println!("[snapshot channels] {chs}");
                }
                Ok(_) => {}
                Err(_) => break,
            }
        }
    });

    let profile = handle
        .register_server("probe".into(), address)
        .await
        .expect("录入地址");
    tokio::time::timeout(
        Duration::from_secs(30),
        handle.connect(profile.id.clone(), nickname.clone()),
    )
    .await
    .expect("connect 超时")
    .expect("连接失败");

    tokio::time::sleep(Duration::from_secs(3)).await;
    let state = handle.state().await.expect("state");
    println!("[state] {state:?}");

    match handle.list_clients().await {
        Ok(clients) => {
            for c in &clients {
                println!(
                    "[client] id={} ch={} name={} in={:?} out={:?} away={:?}",
                    c.id, c.channel_id, c.nickname, c.input_muted, c.output_muted, c.away
                );
            }
        }
        Err(err) => println!("[list_clients error] {err}"),
    }

    handle.disconnect().await.ok();
    handle.shutdown().await.ok();
    logger.abort();
    let _ = tokio::fs::remove_dir_all(&dir).await;
}
