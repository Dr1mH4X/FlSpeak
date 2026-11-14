use super::*;

const TRANSFER_PROGRESS_BYTES: u64 = 256 * 1024;
const TRANSFER_PROGRESS_INTERVAL: Duration = Duration::from_millis(200);
type ImageNegotiation =
    Pin<Box<dyn std::future::Future<Output = Result<(String, FileDownloadInfo), SessionError>>>>;
pub(super) type ChannelIconKey = (u64, String, u32);
pub(super) type ChannelIconWaiters = Vec<oneshot::Sender<Result<Vec<u8>, SessionError>>>;

pub(super) struct PendingImage {
    pub(super) remote_path: String,
    pub(super) reply: oneshot::Sender<Result<Vec<u8>, SessionError>>,
    preempt_retries: u8,
}

pub(super) struct ActiveImage {
    remote_path: String,
    pub(super) negotiation: ImageNegotiation,
    pub(super) reply: oneshot::Sender<Result<Vec<u8>, SessionError>>,
    preempt_retries: u8,
}

const ICON_PREEMPT_RETRIES: u8 = 5;

impl Actor {
    pub(super) fn fetch_remote_icon(
        &mut self,
        icon_id: u32,
        reply: oneshot::Sender<Result<Vec<u8>, SessionError>>,
    ) {
        if icon_id == 0 {
            let _ = reply.send(Err(SessionError::Transfer(
                "icon id must be nonzero".into(),
            )));
            return;
        }
        self.enqueue_server_image(
            &tsclient_rs::icon_file_name(icon_id),
            reply,
            ICON_PREEMPT_RETRIES,
        );
    }

    pub(super) fn fetch_channel_icon(
        &mut self,
        icon_id: u32,
        reply: oneshot::Sender<Result<Vec<u8>, SessionError>>,
    ) {
        if icon_id == 0 {
            let _ = reply.send(Err(SessionError::Transfer(
                "icon id must be nonzero".into(),
            )));
            return;
        }
        let Some(server_id) = self.active_server_id.clone() else {
            let _ = reply.send(Err(SessionError::NotConnected));
            return;
        };
        if let Some(bytes) = crate::channel_icons::load_hit(&self.store_path, &server_id, icon_id) {
            let _ = reply.send(Ok(bytes));
            return;
        }
        let epoch = self.connection_epoch;
        let key = (epoch, server_id.clone(), icon_id);
        if let Some(waiters) = self.in_flight_channel_icons.get_mut(&key) {
            waiters.push(reply);
            return;
        }
        self.in_flight_channel_icons.insert(key, vec![reply]);
        let (tx, rx) = oneshot::channel();
        self.fetch_remote_icon(icon_id, tx);
        let signals = self.signals.clone();
        tokio::task::spawn_local(async move {
            let result = match rx.await {
                Ok(result) => result,
                Err(_) => Err(SessionError::NotConnected),
            };
            let _ = signals.send(SessionSignal::ChannelIconFetched {
                epoch,
                server_id,
                icon_id,
                result,
            });
        });
    }

    pub(super) fn clone_image_error(error: &SessionError) -> SessionError {
        match error {
            SessionError::Protocol(msg) => SessionError::Protocol(msg.clone()),
            SessionError::Transfer(msg) => SessionError::Transfer(msg.clone()),
            SessionError::Storage(msg) => SessionError::Storage(msg.clone()),
            SessionError::Stream(msg) => SessionError::Stream(msg.clone()),
            SessionError::Spawn(msg) => SessionError::Spawn(msg.clone()),
            SessionError::Timeout => SessionError::Timeout,
            SessionError::NotConnected => SessionError::NotConnected,
            SessionError::Closed => SessionError::Closed,
            SessionError::ChannelPasswordRequired => SessionError::ChannelPasswordRequired,
            SessionError::NotInChannel => SessionError::NotInChannel,
            other => SessionError::Transfer(other.to_string()),
        }
    }

    pub(super) fn sync_server_icon(&mut self, server_id: String, icon_id: Option<u32>) {
        let Some(icon_id) = icon_id else {
            return;
        };
        self.active_server_icon_id = Some(icon_id);
        if icon_id == 0 {
            self.fetching_server_icon = None;
            match crate::server_icons::remove(&self.store_path, &mut self.server_icons, &server_id)
            {
                Ok(true) => {
                    self.emit(SessionEvent::ServerIconUpdated {
                        server_id,
                        bytes: None,
                    });
                }
                Ok(false) => {}
                Err(error) => {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!("清理服务器图标缓存失败: {error}"),
                    });
                }
            }
            return;
        }
        if self
            .server_icons
            .get(&server_id)
            .is_some_and(|entry| entry.icon_id == icon_id)
        {
            return;
        }
        if self
            .fetching_server_icon
            .as_ref()
            .is_some_and(|(epoch, id, icon)| {
                *epoch == self.connection_epoch && id == &server_id && *icon == icon_id
            })
        {
            return;
        }
        let epoch = self.connection_epoch;
        self.fetching_server_icon = Some((epoch, server_id.clone(), icon_id));
        let (reply, rx) = oneshot::channel();
        self.fetch_remote_icon(icon_id, reply);
        let signals = self.signals.clone();
        tokio::task::spawn_local(async move {
            let result = match rx.await {
                Ok(result) => result,
                Err(_) => Err(SessionError::NotConnected),
            };
            let _ = signals.send(SessionSignal::ServerIconFetched {
                epoch,
                server_id,
                icon_id,
                result,
            });
        });
    }

    pub(super) fn fetch_server_image(
        &mut self,
        remote_path: &str,
        reply: oneshot::Sender<Result<Vec<u8>, SessionError>>,
    ) {
        self.enqueue_server_image(remote_path, reply, 0);
    }

    fn enqueue_server_image(
        &mut self,
        remote_path: &str,
        reply: oneshot::Sender<Result<Vec<u8>, SessionError>>,
        preempt_retries: u8,
    ) {
        if self.pending_images.len() >= 32 {
            let _ = reply.send(Err(SessionError::Transfer(
                "image request queue is full".into(),
            )));
            return;
        }
        self.pending_images.push_back(PendingImage {
            remote_path: remote_path.to_owned(),
            reply,
            preempt_retries,
        });
    }

    pub(super) fn start_next_image(&mut self) {
        if self.active_image.is_some() {
            return;
        }
        let Some(pending) = self.pending_images.pop_front() else {
            return;
        };
        let target = (|| {
            let client = self.connected()?;
            let target = self
                .transfer_target
                .as_ref()
                .ok_or(SessionError::NotConnected)?;
            proto::check_transfer_host(target, &target.host)?;
            Ok::<_, SessionError>((client, target.host.clone()))
        })();
        let (client, host) = match target {
            Ok(target) => target,
            Err(error) => {
                let _ = pending.reply.send(Err(error));
                return;
            }
        };
        let remote_path = pending.remote_path;
        let path = remote_path.clone();
        self.active_image = Some(ActiveImage {
            remote_path,
            reply: pending.reply,
            preempt_retries: pending.preempt_retries,
            negotiation: Box::pin(async move {
                let info = tokio::time::timeout(
                    Duration::from_secs(5),
                    client.file_transfer_init_download(0, &path, ""),
                )
                .await
                .map_err(|_| SessionError::Timeout)?
                .map_err(protocol_error)?;
                validate_port(info.port)?;
                if info.size == 0 || info.size > 1024 * 1024 {
                    return Err(SessionError::Transfer(
                        "image size must be between 1 byte and 1 MiB".into(),
                    ));
                }
                Ok((host, info))
            }),
        });
    }

    pub(super) fn interrupt_active_image(&mut self) {
        if let Some(active) = self.active_image.take() {
            if active.preempt_retries > 0 {
                self.pending_images.push_back(PendingImage {
                    remote_path: active.remote_path,
                    reply: active.reply,
                    preempt_retries: active.preempt_retries - 1,
                });
            } else {
                let _ = active.reply.send(Err(SessionError::Transfer(
                    "image negotiation interrupted".into(),
                )));
            }
        }
    }

    pub(super) fn cancel_active_image(&mut self) {
        if let Some(active) = self.active_image.take() {
            let _ = active.reply.send(Err(SessionError::NotConnected));
        }
    }

    pub(super) fn finish_server_image(
        &self,
        negotiated: Result<(String, FileDownloadInfo), SessionError>,
        reply: oneshot::Sender<Result<Vec<u8>, SessionError>>,
    ) {
        let (host, info) = match negotiated {
            Ok(value) => value,
            Err(error) => {
                let _ = reply.send(Err(error));
                return;
            }
        };
        let epoch = self.connection_epoch;
        let mut disconnect_rx = self.disconnect_rx.clone();
        // 仅 TCP 字节传输离开 actor；Client 的协商仍在命令队列中串行执行。
        tokio::task::spawn_local(async move {
            let download = async {
                let mut bytes = Vec::with_capacity(info.size as usize);
                tsclient_rs::downloadFileData(&host, &info, &mut bytes)
                    .await
                    .map_err(protocol_error)?;
                Ok(bytes)
            };
            let outcome = tokio::select! {
                res = tokio::time::timeout(Duration::from_secs(20), download) => {
                    res.unwrap_or(Err(SessionError::Timeout))
                }
                _ = async {
                    while disconnect_rx.changed().await.is_ok() {
                        if *disconnect_rx.borrow() != epoch {
                            break;
                        }
                    }
                } => {
                    Err(SessionError::NotConnected)
                }
            };
            let _ = reply.send(outcome);
        });
    }

    pub(super) async fn upload_file(
        &mut self,
        local_path: String,
        remote_path: String,
        channel_id: u64,
        password: Option<String>,
        overwrite: bool,
    ) -> Result<u64, SessionError> {
        if channel_id == 0 {
            return Err(SessionError::NotInChannel);
        }
        let client = self.connected()?;
        let target = self
            .transfer_target
            .as_ref()
            .ok_or(SessionError::NotConnected)?;
        proto::check_transfer_host(target, &target.host)?;

        let file = tokio::fs::File::open(&local_path)
            .await
            .map_err(|err| SessionError::Transfer(format!("打开本地文件失败: {err}")))?;
        let size = file
            .metadata()
            .await
            .map_err(|err| SessionError::Transfer(format!("读取文件大小失败: {err}")))?
            .len();
        let info = client
            .file_transfer_init_upload(
                channel_id,
                &remote_path,
                &crate::channel_tools::channel_password(password.as_deref().unwrap_or("")),
                size,
                overwrite,
            )
            .await
            .map_err(protocol_error)?;
        validate_port(info.port)?;

        let id = self.next_transfer_id;
        self.next_transfer_id = self.next_transfer_id.wrapping_add(1);
        self.emit(SessionEvent::TransferStarted {
            id,
            direction: TransferDirection::Upload,
            remote_path: remote_path.clone(),
            total: size,
        });

        let events = self.events.clone();
        let host = target.host.clone();
        tokio::task::spawn_local(async move {
            let reader = ProgressReader::new(file, id, size, events.clone());
            let outcome = tsclient_rs::uploadFileData(&host, &info, reader).await;
            let _ = events.send(SessionEvent::TransferFinished {
                id,
                error: outcome.err().map(|err| err.to_string()),
            });
        });
        Ok(id)
    }

    pub(super) async fn download_file(
        &mut self,
        remote_path: String,
        local_path: String,
        channel_id: u64,
        password: Option<String>,
    ) -> Result<u64, SessionError> {
        crate::channel_tools::remote_path(&remote_path)?;
        if PathBuf::from(&local_path)
            .try_exists()
            .map_err(|error| SessionError::Transfer(error.to_string()))?
        {
            return Err(SessionError::Transfer("destination already exists".into()));
        }
        if channel_id == 0 {
            return Err(SessionError::NotInChannel);
        }
        let client = self.connected()?;
        let target = self
            .transfer_target
            .as_ref()
            .ok_or(SessionError::NotConnected)?;
        proto::check_transfer_host(target, &target.host)?;

        let info: FileDownloadInfo = client
            .file_transfer_init_download(
                channel_id,
                &remote_path,
                &crate::channel_tools::channel_password(password.as_deref().unwrap_or("")),
            )
            .await
            .map_err(protocol_error)?;
        validate_port(info.port)?;

        let id = self.next_transfer_id;
        self.next_transfer_id = self.next_transfer_id.wrapping_add(1);
        self.emit(SessionEvent::TransferStarted {
            id,
            direction: TransferDirection::Download,
            remote_path: remote_path.clone(),
            total: info.size,
        });
        let events = self.events.clone();
        let host = target.host.clone();
        let epoch = self.connection_epoch;
        let current = Arc::clone(&self.epoch);
        tokio::task::spawn_local(async move {
            let outcome = crate::downloads::receive(
                host,
                info,
                PathBuf::from(local_path),
                id,
                events.clone(),
                epoch,
                current,
            )
            .await;
            let _ = events.send(SessionEvent::TransferFinished {
                id,
                error: outcome.err().map(|error| error.to_string()),
            });
        });
        Ok(id)
    }
}

pub(super) fn avatar_file_name(uid: &str) -> Result<String, SessionError> {
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(uid)
        .map_err(|error| SessionError::Transfer(format!("invalid avatar UID: {error}")))?;
    if bytes.len() != 20 {
        return Err(SessionError::Transfer(
            "avatar UID must contain 20 bytes".into(),
        ));
    }
    // TeamSpeak 头像文件把 UID 的每个半字节映射到 a..p。
    let suffix: String = bytes
        .into_iter()
        .flat_map(|byte| {
            [
                char::from(b'a' + (byte >> 4)),
                char::from(b'a' + (byte & 15)),
            ]
        })
        .collect();
    Ok(format!("/avatar_{suffix}"))
}
/// 上传进度读取器：每 256KiB 或 200ms 发一次进度。
pub(super) struct ProgressReader {
    inner: tokio::fs::File,
    id: u64,
    total: u64,
    transferred: u64,
    last_emit_bytes: u64,
    last_emit_at: Instant,
    events: broadcast::Sender<SessionEvent>,
}

impl ProgressReader {
    pub(super) fn new(
        inner: tokio::fs::File,
        id: u64,
        total: u64,
        events: broadcast::Sender<SessionEvent>,
    ) -> Self {
        Self {
            inner,
            id,
            total,
            transferred: 0,
            last_emit_bytes: 0,
            last_emit_at: Instant::now(),
            events,
        }
    }

    fn maybe_emit(&mut self) {
        if self.transferred.saturating_sub(self.last_emit_bytes) < TRANSFER_PROGRESS_BYTES
            && self.last_emit_at.elapsed() < TRANSFER_PROGRESS_INTERVAL
        {
            return;
        }
        self.last_emit_bytes = self.transferred;
        self.last_emit_at = Instant::now();
        let _ = self.events.send(SessionEvent::TransferProgress {
            id: self.id,
            transferred: self.transferred,
            total: self.total,
        });
    }
}

impl AsyncRead for ProgressReader {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        let this = self.get_mut();
        let before = buf.filled().len();
        let poll = Pin::new(&mut this.inner).poll_read(cx, buf);
        if let Poll::Ready(Ok(())) = &poll {
            let read = buf.filled().len() - before;
            this.transferred += read as u64;
            this.maybe_emit();
        }
        poll
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actor::test_support::*;

    #[tokio::test]
    async fn active_download_is_cancelled_promptly_on_disconnect() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let mut actor = audio_actor();
                let (reply, rx) = oneshot::channel();
                let info = FileDownloadInfo {
                    client_file_transfer_id: 1,
                    server_file_transfer_id: 1,
                    file_transfer_key: "key".into(),
                    port: 30033,
                    size: 100,
                };
                actor.finish_server_image(Ok(("127.0.0.1".into(), info)), reply);
                // 立即失效
                actor.invalidate_handlers();
                let outcome = tokio::time::timeout(Duration::from_millis(200), rx)
                    .await
                    .expect("should not hang for 20 seconds")
                    .expect("channel not dropped");
                assert!(matches!(outcome, Err(SessionError::NotConnected)));
            })
            .await;
    }

    #[tokio::test]
    async fn image_queue_is_bounded_and_invalidated_with_the_connection() {
        let mut actor = audio_actor();
        let client = Client::new(
            tsclient_rs::generateIdentity(0),
            "127.0.0.1:9987".into(),
            "test".into(),
            Default::default(),
        );
        actor.client = Some(Arc::new(client));
        actor.transfer_target = Some(ServerTarget {
            host: "127.0.0.1".into(),
            port: 9987,
        });
        let mut replies = Vec::new();
        for _ in 0..32 {
            let (reply, result) = oneshot::channel();
            actor.fetch_server_image("/avatar_test", reply);
            replies.push(result);
        }
        let (reply, result) = oneshot::channel();
        actor.fetch_server_image("/avatar_test", reply);
        assert!(matches!(
            result.await.unwrap(),
            Err(SessionError::Transfer(_))
        ));
        actor.invalidate_handlers();
        assert!(actor.pending_images.is_empty());
        for result in replies {
            assert!(matches!(
                result.await.unwrap(),
                Err(SessionError::NotConnected)
            ));
        }
    }

    #[test]
    fn avatar_paths_encode_uid_bytes_without_allowing_arbitrary_paths() {
        let uid = base64::engine::general_purpose::STANDARD.encode((0_u8..20).collect::<Vec<_>>());
        assert_eq!(
            avatar_file_name(&uid).unwrap(),
            "/avatar_aaabacadaeafagahaiajakalamanaoapbabbbcbd"
        );
        for invalid in ["", "../avatar", "https://example.com/a.png", "YQ=="] {
            assert!(avatar_file_name(invalid).is_err());
        }
    }

    #[tokio::test]
    async fn upload_reader_preserves_exact_payload() {
        use tokio::io::AsyncReadExt;

        let dir = std::env::temp_dir().join("flspeak-transfer-payload-test");
        let path = dir.join("payload.bin");
        let _ = tokio::fs::remove_dir_all(&dir).await;
        tokio::fs::create_dir_all(&dir).await.unwrap();
        tokio::fs::write(&path, b"hello").await.unwrap();

        let file = tokio::fs::File::open(&path).await.unwrap();
        let (events, _) = broadcast::channel(8);
        let mut reader = ProgressReader::new(file, 1, 5, events);
        let mut output = Vec::new();
        reader.read_to_end(&mut output).await.unwrap();

        assert_eq!(output, b"hello");

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn server_icon_cache_dedupes_fetches_and_clears_on_zero_icon_id() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-server-icon-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                let mut events = actor.events.subscribe();
                actor.active_server_id = Some("127.0.0.1:9987".into());

                // 模拟首次收到有效服务器图标 id 触发入队并完成下载
                actor.sync_server_icon("127.0.0.1:9987".into(), Some(12345));
                assert_eq!(
                    actor.fetching_server_icon,
                    Some((actor.connection_epoch, "127.0.0.1:9987".into(), 12345))
                );
                assert_eq!(actor.pending_images.len(), 1);
                let pending = actor.pending_images.pop_front().unwrap();
                assert_eq!(pending.remote_path, "/icon_12345");
                let _ = pending.reply.send(Ok(vec![137, 80, 78, 71]));
                let signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(signal).await;

                assert!(actor.fetching_server_icon.is_none());
                assert_eq!(
                    actor.server_icons.get("127.0.0.1:9987").map(|e| e.icon_id),
                    Some(12345)
                );

                // 重复收到相同 icon_id 不重复入队
                actor.sync_server_icon("127.0.0.1:9987".into(), Some(12345));
                assert!(actor.pending_images.is_empty());

                // 收到 None 时保留已有缓存
                actor.sync_server_icon("127.0.0.1:9987".into(), None);
                assert!(actor.server_icons.contains_key("127.0.0.1:9987"));

                // 收到 Some(0) 时清除缓存并广播清除事件
                actor
                    .handle_signal(SessionSignal::ServerInfoUpdated {
                        epoch: actor.connection_epoch,
                        icon_id: Some(0),
                    })
                    .await;
                assert!(!actor.server_icons.contains_key("127.0.0.1:9987"));
                assert!(
                    crate::server_icons::load(&actor.store_path, &["127.0.0.1:9987"]).is_empty()
                );

                let updates: Vec<(String, Option<Vec<u8>>)> =
                    std::iter::from_fn(|| events.try_recv().ok())
                        .filter_map(|ev| match ev {
                            SessionEvent::ServerIconUpdated { server_id, bytes } => {
                                Some((server_id, bytes))
                            }
                            _ => None,
                        })
                        .collect();
                assert_eq!(
                    updates,
                    vec![
                        ("127.0.0.1:9987".into(), Some(vec![137, 80, 78, 71])),
                        ("127.0.0.1:9987".into(), None),
                    ]
                );

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    #[tokio::test]
    async fn channel_icon_cache_dedupes_in_flight_and_serves_disk_hits_per_server() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-channel-icon-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.active_server_id = Some("a.example:9987".into());

                // 未命中时并发请求同一 (server_id, icon_id) 只入队一次
                let (reply_a, rx_a) = oneshot::channel();
                let (reply_b, rx_b) = oneshot::channel();
                actor.fetch_channel_icon(777, reply_a);
                actor.fetch_channel_icon(777, reply_b);
                assert_eq!(actor.pending_images.len(), 1);
                let pending = actor.pending_images.pop_front().unwrap();
                assert_eq!(pending.remote_path, "/icon_777");
                let _ = pending.reply.send(Ok(vec![1, 2, 3, 4]));
                let signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(signal).await;

                assert_eq!(rx_a.await.unwrap().unwrap(), vec![1, 2, 3, 4]);
                assert_eq!(rx_b.await.unwrap().unwrap(), vec![1, 2, 3, 4]);

                // 同服再次请求直接命中磁盘缓存，不再入队
                let (reply_hit, rx_hit) = oneshot::channel();
                actor.fetch_channel_icon(777, reply_hit);
                assert!(actor.pending_images.is_empty());
                assert_eq!(rx_hit.await.unwrap().unwrap(), vec![1, 2, 3, 4]);

                // 切服后相同 icon_id 不串图，重新入队拉取
                actor.active_server_id = Some("b.example:9987".into());
                let (reply_other, rx_other) = oneshot::channel();
                actor.fetch_channel_icon(777, reply_other);
                assert_eq!(actor.pending_images.len(), 1);
                let pending_other = actor.pending_images.pop_front().unwrap();
                let _ = pending_other.reply.send(Ok(vec![9, 9, 9]));
                let signal_other = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(signal_other).await;
                assert_eq!(rx_other.await.unwrap().unwrap(), vec![9, 9, 9]);

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    struct StallFirstFtInit {
        started: Arc<tokio::sync::Notify>,
        calls: Arc<std::sync::atomic::AtomicUsize>,
    }

    impl tsclient_rs::CommandMiddleware for StallFirstFtInit {
        fn wrap(&self, _: TestCommandHandler) -> TestCommandHandler {
            let started = Arc::clone(&self.started);
            let calls = Arc::clone(&self.calls);
            Arc::new(move |command| {
                let started = Arc::clone(&started);
                let calls = Arc::clone(&calls);
                Box::pin(async move {
                    if command.starts_with("ftinitdownload ")
                        && calls.fetch_add(1, Ordering::SeqCst) == 0
                    {
                        started.notify_one();
                        tokio::time::sleep(Duration::from_millis(300)).await;
                    }
                    Err(tsclient_rs::Error::ServerError {
                        id: "2568".into(),
                        server_message: "denied".into(),
                        extra_message: None,
                    })
                })
            })
        }
    }

    #[tokio::test]
    async fn icon_negotiation_requeues_when_preempted_by_control_command() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let started = Arc::new(tokio::sync::Notify::new());
                let calls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
                let client = Client::new(
                    tsclient_rs::generateIdentity(0),
                    "127.0.0.1:9987".into(),
                    "test".into(),
                    tsclient_rs::ClientOptions {
                        command_middleware: vec![Box::new(StallFirstFtInit {
                            started: Arc::clone(&started),
                            calls: Arc::clone(&calls),
                        })],
                        ..Default::default()
                    },
                );
                client.mark_connected();
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-icon-requeue-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.client = Some(Arc::new(client));
                actor.active_server_id = Some("127.0.0.1:9987".into());
                actor.transfer_target = Some(ServerTarget {
                    host: "127.0.0.1".into(),
                    port: 9987,
                });
                let (commands, rx) = mpsc::unbounded_channel();
                let task = tokio::task::spawn_local(async move {
                    actor.run(rx).await;
                });

                let (reply, result) = oneshot::channel();
                commands
                    .send(SessionCommand::FetchIcon {
                        icon_id: 777,
                        reply,
                    })
                    .unwrap();
                started.notified().await;

                // 控制命令抢占后，图标协商被重新入队而不是直接失败。
                let (ptt_reply, ptt_rx) = oneshot::channel();
                commands
                    .send(SessionCommand::SetPttMode {
                        enabled: true,
                        reply: ptt_reply,
                    })
                    .unwrap();
                tokio::time::timeout(Duration::from_millis(100), ptt_rx)
                    .await
                    .unwrap()
                    .unwrap()
                    .unwrap();

                let icon_err = tokio::time::timeout(Duration::from_secs(1), result)
                    .await
                    .unwrap()
                    .unwrap()
                    .unwrap_err();
                assert!(
                    matches!(icon_err, SessionError::Protocol(ref msg) if msg.contains("denied")),
                    "expected second attempt protocol error after requeue, got {icon_err:?}"
                );
                assert_eq!(calls.load(Ordering::SeqCst), 2);

                commands.send(SessionCommand::Shutdown).unwrap();
                task.await.unwrap();
                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }
}
