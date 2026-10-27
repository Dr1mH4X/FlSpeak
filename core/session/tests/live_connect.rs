//! 真实服务器连接链路测试。
//!
//! 默认忽略；显式运行：
//! `FLSPEAK_TEST_SERVER=ts.example.com cargo test -p session --test live_connect -- --ignored --nocapture`
//!
//! 可选 `FLSPEAK_TEST_NICKNAME`。测试关闭音频，不会申请麦克风/扬声器权限。

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use session::{SessionEvent, SessionHandle, SessionOptions, SessionState};

#[tokio::test]
#[ignore = "需要 FLSPEAK_TEST_SERVER 与网络"]
async fn live_connect_chain() {
    let Ok(address) = std::env::var("FLSPEAK_TEST_SERVER") else {
        eprintln!("跳过：未设置 FLSPEAK_TEST_SERVER");
        return;
    };
    let nickname =
        std::env::var("FLSPEAK_TEST_NICKNAME").unwrap_or_else(|_| "flspeak-probe".to_string());
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0);
    let dir = std::env::temp_dir().join(format!("flspeak-live-{}-{stamp}", std::process::id()));
    let _ = tokio::fs::remove_dir_all(&dir).await;

    let handle = SessionHandle::spawn_with_options(
        dir.join("servers.json"),
        SessionOptions { audio: false },
    )
    .expect("启动会话");
    let mut events = handle.subscribe();
    let logger = tokio::spawn(async move {
        loop {
            match events.recv().await {
                Ok(SessionEvent::Log { level, message }) => {
                    println!("[log/{level}] {message}");
                }
                Ok(SessionEvent::Denied { message }) => println!("[denied] {message}"),
                Ok(SessionEvent::Failed { message }) => println!("[failed] {message}"),
                Ok(SessionEvent::State(state)) => println!("[state] {state:?}"),
                Ok(_) => {}
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                Err(_) => break,
            }
        }
    });

    let profile = handle
        .register_server("live".to_string(), address.clone())
        .await
        .expect("录入地址");
    println!("registered: {} -> {}", profile.label, profile.id);
    assert_eq!(profile.port, 9987);

    tokio::time::timeout(
        Duration::from_secs(30),
        handle.connect(profile.id.clone(), nickname.clone()),
    )
    .await
    .expect("connect 不应超过 30s")
    .expect("连接失败");

    let SessionState::Connected { channel_id, .. } = handle.state().await.expect("state") else {
        panic!("连接后应处于 Connected");
    };
    assert_ne!(channel_id, 0, "欢迎目录应恢复自己的真实频道");
    println!("connected, client_id/channel_id 已就绪");

    // 很多服务器拒绝显式 channellist/clientlist；actor 应回退到欢迎目录。
    match handle.list_channels().await {
        Ok(channels) => {
            println!("channels: {}", channels.len());
            assert!(!channels.is_empty(), "服务器至少应有一个频道");
            assert!(
                channels.iter().any(|channel| channel.order.is_some()),
                "欢迎目录应包含频道顺序"
            );
        }
        Err(err) => eprintln!("listChannels 被拒绝（权限不足时正常）: {err}"),
    }

    if let Ok(output) = std::env::var("FLSPEAK_TEST_ICON_DIR") {
        let output = std::path::PathBuf::from(output);
        tokio::fs::create_dir_all(&output)
            .await
            .expect("icon output directory");
        let channels = handle.list_channels().await.expect("channel directory");
        let mut downloaded = std::collections::HashSet::new();
        let mut rows = Vec::new();
        for channel in channels {
            if let Some(id) = channel.icon_id.filter(|id| *id != 0)
                && downloaded.insert(id)
            {
                let bytes = handle
                    .fetch_icon(id)
                    .await
                    .expect("download channel icon through actor");
                assert!(!bytes.is_empty());
                println!("icon_id={id} bytes={}", bytes.len());
                tokio::fs::write(output.join(format!("icon_{id}")), bytes)
                    .await
                    .expect("save icon");
            }
            rows.push(serde_json::json!({"id":channel.id,"parentId":channel.parent_id,"order":channel.order,"name":channel.name,"description":channel.description,"iconId":channel.icon_id}));
        }
        assert!(
            !downloaded.is_empty(),
            "server must have a custom channel icon for this probe"
        );
        tokio::fs::write(
            output.join("channels.json"),
            serde_json::to_vec_pretty(&rows).expect("encode directory"),
        )
        .await
        .expect("save directory");
    }

    match handle.list_clients().await {
        Ok(clients) => {
            println!("clients: {}", clients.len());
            assert!(
                clients.iter().any(|client| client.nickname == nickname),
                "在线列表里应当有自己 {nickname}"
            );
        }
        Err(err) => eprintln!("listClients 被拒绝（权限不足时正常）: {err}"),
    }

    handle.disconnect().await.expect("disconnect");
    handle.shutdown().await.expect("shutdown");
    logger.abort();
    tokio::time::sleep(Duration::from_millis(100)).await;
    let _ = tokio::fs::remove_dir_all(&dir).await;
}
