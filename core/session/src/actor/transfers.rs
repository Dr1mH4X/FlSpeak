use super::*;

const TRANSFER_PROGRESS_BYTES: u64 = 256 * 1024;
const TRANSFER_PROGRESS_INTERVAL: Duration = Duration::from_millis(200);
type ImageNegotiation =
    Pin<Box<dyn std::future::Future<Output = Result<(String, FileDownloadInfo), ImageFetchError>>>>;
pub(super) type ChannelIconKey = (u64, String, u32);
pub(super) type ChannelIconWaiters = Vec<oneshot::Sender<Result<Vec<u8>, SessionError>>>;
pub(super) type AvatarFetchKey = (u64, String, String, u64);
pub(super) type AvatarWaiters = Vec<oneshot::Sender<Result<Option<Vec<u8>>, SessionError>>>;

#[derive(Debug)]
pub(crate) enum ImageFetchError {
    NotFound(String),
    PermissionDenied(String),
    Session(SessionError),
}

impl ImageFetchError {
    pub(super) fn into_session_error(self) -> SessionError {
        match self {
            Self::NotFound(message) | Self::PermissionDenied(message) => {
                SessionError::Protocol(message)
            }
            Self::Session(err) => err,
        }
    }
}

fn classify_image_protocol_error(err: tsclient_rs::Error) -> ImageFetchError {
    use tsclient_rs::ErrorCode;
    if err.is_server_error_code(ErrorCode::FileNotFound)
        || err.is_server_error_code(ErrorCode::FileInvalidPath)
    {
        ImageFetchError::NotFound(err.to_string())
    } else if err.is_server_error_code(ErrorCode::FileInvalidPermissions)
        || err.is_server_error_code(ErrorCode::PermissionsClientInsufficient)
        || err.is_server_error_code(ErrorCode::Permissions)
    {
        ImageFetchError::PermissionDenied(err.to_string())
    } else {
        ImageFetchError::Session(protocol_error(err))
    }
}

#[derive(Debug)]
pub(crate) struct AvatarDiskLoad {
    pub(super) epoch: u64,
    pub(super) server_id: String,
    pub(super) uid: String,
    pub(super) revision: u64,
    pub(super) avatar_hash: Option<String>,
    pub(super) remote_path: String,
    pub(super) bytes: Option<Vec<u8>>,
}

#[derive(Debug)]
pub(crate) struct AvatarFetchOutcome {
    pub(super) epoch: u64,
    pub(super) server_id: String,
    pub(super) uid: String,
    pub(super) revision: u64,
    pub(super) avatar_hash: Option<String>,
    pub(super) result: Result<Vec<u8>, ImageFetchError>,
}

pub(super) struct PendingImage {
    pub(super) remote_path: String,
    pub(super) reply: oneshot::Sender<Result<Vec<u8>, ImageFetchError>>,
    preempt_retries: u8,
}

pub(super) struct ActiveImage {
    remote_path: String,
    pub(super) negotiation: ImageNegotiation,
    pub(super) reply: oneshot::Sender<Result<Vec<u8>, ImageFetchError>>,
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
        let (tx, rx) = oneshot::channel();
        self.enqueue_server_image(
            &tsclient_rs::icon_file_name(icon_id),
            tx,
            ICON_PREEMPT_RETRIES,
        );
        tokio::task::spawn_local(async move {
            let result = match rx.await {
                Ok(outcome) => outcome.map_err(ImageFetchError::into_session_error),
                Err(_) => Err(SessionError::NotConnected),
            };
            let _ = reply.send(result);
        });
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
                        message: format!("failed to clean the server icon cache: {error}"),
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

    pub(super) fn reset_avatar_session_state(&mut self) {
        for (_, waiters) in self.in_flight_avatars.drain() {
            for reply in waiters {
                let _ = reply.send(Err(SessionError::NotConnected));
            }
        }
        self.avatar_hashes.clear();
        self.avatar_negative_cache.clear();
        self.avatar_revisions.clear();
        self.avatars_fetched_without_hash.clear();
    }

    pub(super) fn sync_avatar_hashes_from_clients(&mut self, clients: &[ClientInfo]) {
        let mut by_uid: HashMap<&str, Option<String>> = HashMap::new();
        for client in clients {
            if client.uid.is_empty() {
                continue;
            }
            let next = client.avatar_hash.as_ref().filter(|s| !s.is_empty());
            by_uid
                .entry(client.uid.as_str())
                .and_modify(|current| {
                    if current.is_none()
                        && let Some(hash) = next
                    {
                        *current = Some(hash.clone());
                    }
                })
                .or_insert_with(|| next.cloned());
        }
        for (uid, hash) in by_uid {
            self.record_avatar_hash(uid, hash, false);
        }
    }

    pub(super) fn sync_avatar_hash_from_join(&mut self, uid: &str, avatar_hash: Option<String>) {
        tracing::debug!(
            target: "session",
            uid,
            avatar_hash = ?avatar_hash,
            "client joined with avatar flag"
        );
        self.record_avatar_hash(uid, avatar_hash, true);
    }

    pub(super) fn sync_avatar_hash_from_update(&mut self, uid: &str, avatar_hash: Option<String>) {
        self.record_avatar_hash(uid, avatar_hash, true);
    }

    pub(super) fn record_avatar_hash(
        &mut self,
        uid: &str,
        next: Option<String>,
        emit_on_initial_some: bool,
    ) {
        if uid.is_empty() {
            return;
        }
        let next = next.filter(|value| !value.is_empty());
        let had_negative = self.avatar_negative_cache.contains(uid);
        let fetched_without_hash = self.avatars_fetched_without_hash.remove(uid);
        let changed = match self.avatar_hashes.get(uid) {
            Some(existing) if existing == &next => return,
            Some(_) => true,
            None => {
                (fetched_without_hash && !had_negative)
                    || ((had_negative || emit_on_initial_some) && next.is_some())
            }
        };
        self.avatar_hashes.insert(uid.to_owned(), next);
        if changed {
            let next_revision = self.avatar_revisions.get(uid).copied().unwrap_or(0) + 1;
            self.avatar_revisions.insert(uid.to_owned(), next_revision);
            self.avatar_negative_cache.remove(uid);
            if let Some(server_id) = self.active_server_id.clone() {
                self.avatar_disk
                    .remove_uid(self.store_path.clone(), server_id, uid.to_owned());
            }
            self.emit(SessionEvent::AvatarUpdated {
                uid: uid.to_owned(),
            });
        }
    }

    pub(super) fn fetch_avatar(
        &mut self,
        uid: String,
        reply: oneshot::Sender<Result<Option<Vec<u8>>, SessionError>>,
    ) {
        let Some(server_id) = self.active_server_id.clone() else {
            let _ = reply.send(Err(SessionError::NotConnected));
            return;
        };
        let avatar_hash = match self.avatar_hashes.get(&uid) {
            Some(None) => {
                let _ = reply.send(Ok(None));
                return;
            }
            Some(Some(hash)) => Some(hash.clone()),
            None => None,
        };
        if self.avatar_negative_cache.contains(&uid) {
            let _ = reply.send(Ok(None));
            return;
        }
        let remote_path = match tsclient_rs::avatar_file_name(&uid) {
            Ok(path) => path,
            Err(err) => {
                let _ = reply.send(Err(SessionError::Transfer(err.to_string())));
                return;
            }
        };
        if avatar_hash.is_none() {
            self.avatars_fetched_without_hash.insert(uid.clone());
        }
        let epoch = self.connection_epoch;
        let revision = self.avatar_revisions.get(&uid).copied().unwrap_or(0);
        let key = (epoch, server_id.clone(), uid.clone(), revision);
        if let Some(waiters) = self.in_flight_avatars.get_mut(&key) {
            waiters.push(reply);
            return;
        }
        self.in_flight_avatars.insert(key, vec![reply]);
        let signals = self.signals.clone();
        self.avatar_disk.load_hit(
            self.store_path.clone(),
            server_id.clone(),
            uid.clone(),
            avatar_hash.clone(),
            move |bytes| {
                let _ = signals.send(SessionSignal::AvatarDiskLoaded(AvatarDiskLoad {
                    epoch,
                    server_id,
                    uid,
                    revision,
                    avatar_hash,
                    remote_path,
                    bytes,
                }));
            },
        );
    }

    pub(super) fn handle_avatar_disk_loaded(&mut self, load: AvatarDiskLoad) {
        let AvatarDiskLoad {
            epoch,
            server_id,
            uid,
            revision,
            avatar_hash,
            remote_path,
            bytes,
        } = load;
        let key = (epoch, server_id.clone(), uid.clone(), revision);
        if epoch != self.connection_epoch
            || self.active_server_id.as_deref() != Some(server_id.as_str())
        {
            if let Some(waiters) = self.in_flight_avatars.remove(&key) {
                for reply in waiters {
                    let _ = reply.send(Err(SessionError::NotConnected));
                }
            }
            return;
        }
        if self.avatar_revisions.get(&uid).copied().unwrap_or(0) != revision {
            if let Some(waiters) = self.in_flight_avatars.remove(&key) {
                for reply in waiters {
                    self.fetch_avatar(uid.clone(), reply);
                }
            }
            return;
        }
        if let Some(bytes) = bytes {
            if let Some(waiters) = self.in_flight_avatars.remove(&key) {
                for reply in waiters {
                    let _ = reply.send(Ok(Some(bytes.clone())));
                }
            }
            return;
        }
        if !self.in_flight_avatars.contains_key(&key) {
            return;
        }
        let (tx, rx) = oneshot::channel();
        self.enqueue_server_image(&remote_path, tx, 0);
        let signals = self.signals.clone();
        tokio::task::spawn_local(async move {
            let result = match rx.await {
                Ok(result) => result,
                Err(_) => Err(ImageFetchError::Session(SessionError::NotConnected)),
            };
            let _ = signals.send(SessionSignal::AvatarFetched(AvatarFetchOutcome {
                epoch,
                server_id,
                uid,
                revision,
                avatar_hash,
                result,
            }));
        });
    }

    pub(super) fn handle_avatar_fetched(&mut self, outcome: AvatarFetchOutcome) {
        let AvatarFetchOutcome {
            epoch,
            server_id,
            uid,
            revision,
            avatar_hash,
            result,
        } = outcome;
        let key = (epoch, server_id.clone(), uid.clone(), revision);
        let Some(waiters) = self.in_flight_avatars.remove(&key) else {
            return;
        };
        if epoch != self.connection_epoch
            || self.active_server_id.as_deref() != Some(server_id.as_str())
        {
            for reply in waiters {
                let _ = reply.send(Err(SessionError::NotConnected));
            }
            return;
        }
        if self.avatar_revisions.get(&uid).copied().unwrap_or(0) != revision {
            for reply in waiters {
                self.fetch_avatar(uid.clone(), reply);
            }
            return;
        }
        match result {
            Ok(bytes) => {
                self.avatar_disk.save(
                    self.store_path.clone(),
                    server_id,
                    uid,
                    avatar_hash,
                    bytes.clone(),
                );
                for reply in waiters {
                    let _ = reply.send(Ok(Some(bytes.clone())));
                }
            }
            Err(ImageFetchError::NotFound(_) | ImageFetchError::PermissionDenied(_)) => {
                self.avatar_negative_cache.insert(uid);
                for reply in waiters {
                    let _ = reply.send(Ok(None));
                }
            }
            Err(ImageFetchError::Session(error)) => {
                if !matches!(error, SessionError::NotConnected) {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!("failed to fetch avatar for {uid}: {error}"),
                    });
                }
                for reply in waiters {
                    let _ = reply.send(Err(Self::clone_image_error(&error)));
                }
            }
        }
    }

    pub(super) fn enqueue_server_image(
        &mut self,
        remote_path: &str,
        reply: oneshot::Sender<Result<Vec<u8>, ImageFetchError>>,
        preempt_retries: u8,
    ) {
        if self.pending_images.len() >= 32 {
            let _ = reply.send(Err(ImageFetchError::Session(SessionError::Transfer(
                "image request queue is full".into(),
            ))));
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
                let _ = pending.reply.send(Err(ImageFetchError::Session(error)));
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
                .map_err(|_| ImageFetchError::Session(SessionError::Timeout))?
                .map_err(classify_image_protocol_error)?;
                validate_port(info.port).map_err(ImageFetchError::Session)?;
                if info.size == 0 || info.size > 1024 * 1024 {
                    return Err(ImageFetchError::Session(SessionError::Transfer(
                        "image size must be between 1 byte and 1 MiB".into(),
                    )));
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
                let _ = active
                    .reply
                    .send(Err(ImageFetchError::Session(SessionError::Transfer(
                        "image negotiation interrupted".into(),
                    ))));
            }
        }
    }

    pub(super) fn cancel_active_image(&mut self) {
        if let Some(active) = self.active_image.take() {
            let _ = active
                .reply
                .send(Err(ImageFetchError::Session(SessionError::NotConnected)));
        }
    }

    pub(super) fn finish_server_image(
        &self,
        negotiated: Result<(String, FileDownloadInfo), ImageFetchError>,
        reply: oneshot::Sender<Result<Vec<u8>, ImageFetchError>>,
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
                    .map_err(classify_image_protocol_error)?;
                Ok(bytes)
            };
            let outcome = tokio::select! {
                res = tokio::time::timeout(Duration::from_secs(20), download) => {
                    res.unwrap_or(Err(ImageFetchError::Session(SessionError::Timeout)))
                }
                _ = async {
                    while disconnect_rx.changed().await.is_ok() {
                        if *disconnect_rx.borrow() != epoch {
                            break;
                        }
                    }
                } => {
                    Err(ImageFetchError::Session(SessionError::NotConnected))
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

        let file = tokio::fs::File::open(&local_path).await.map_err(|err| {
            SessionError::Transfer(format!("failed to open the local file: {err}"))
        })?;
        let size = file
            .metadata()
            .await
            .map_err(|err| SessionError::Transfer(format!("failed to read the file size: {err}")))?
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

    pub(super) async fn upload_avatar(&mut self, bytes: Vec<u8>) -> Result<(), SessionError> {
        let client = self.connected()?;
        if !crate::avatars::is_supported_image(&bytes) {
            return Err(SessionError::AvatarUnsupportedFormat);
        }
        let limit = crate::channel_tools::avatar_size_limit(&client, &mut self.channel_tools).await;
        crate::avatars::validate_size(bytes.len(), limit)?;
        let host = {
            let target = self
                .transfer_target
                .as_ref()
                .ok_or(SessionError::NotConnected)?;
            proto::check_transfer_host(target, &target.host)
                .map_err(|_| SessionError::AvatarUnavailable)?;
            target.host.clone()
        };
        let uid = self.self_uid(&client).await?;
        let md5 = match tsclient_rs::upload_avatar(&client, &host, &uid, &bytes).await {
            Ok(md5) => md5,
            Err(error) => {
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("avatar upload failed: {error}"),
                });
                return Err(classify_avatar_error(error, limit));
            }
        };
        self.apply_avatar_upload(&uid, md5, bytes);
        Ok(())
    }

    pub(super) async fn delete_avatar(&mut self) -> Result<(), SessionError> {
        let client = self.connected()?;
        let uid = self.self_uid(&client).await?;
        if let Err(error) = tsclient_rs::delete_avatar(&client).await {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("avatar delete failed: {error}"),
            });
            return Err(classify_avatar_error(error, None));
        }
        self.apply_avatar_delete(&uid);
        Ok(())
    }

    async fn self_uid(&mut self, client: &Client) -> Result<String, SessionError> {
        let Some(self_id) = self.self_client_id else {
            return Err(SessionError::AvatarUnavailable);
        };
        if let Some((_, clients)) = &self.last_snapshot
            && let Some(me) = clients.iter().find(|client| client.id == self_id)
            && !me.uid.is_empty()
            && tsclient_rs::avatar_file_name(&me.uid).is_ok()
        {
            return Ok(me.uid.clone());
        }
        let info = match tsclient_rs::getClientInfo(client, self_id).await {
            Ok(info) => info,
            Err(error) => {
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("failed to resolve the avatar client uid: {error}"),
                });
                return Err(SessionError::AvatarUnavailable);
            }
        };
        let uid = info
            .get("client_unique_identifier")
            .cloned()
            .unwrap_or_default();
        if uid.is_empty() || tsclient_rs::avatar_file_name(&uid).is_err() {
            return Err(SessionError::AvatarUnavailable);
        }
        Ok(uid)
    }

    fn apply_avatar_upload(&mut self, uid: &str, md5: String, bytes: Vec<u8>) {
        // 上传已确认成功，负缓存不应再阻止读取。
        self.avatar_negative_cache.remove(uid);
        let unchanged = matches!(self.avatar_hashes.get(uid), Some(Some(hash)) if hash == &md5);
        if unchanged {
            // 同图重传时 hash 不变，仍要清旧缓存并广播一次让 UI 重新读取新写入的缓存。
            if let Some(server_id) = self.active_server_id.clone() {
                self.avatar_disk
                    .remove_uid(self.store_path.clone(), server_id, uid.to_owned());
            }
            let next_revision = self.avatar_revisions.get(uid).copied().unwrap_or(0) + 1;
            self.avatar_revisions.insert(uid.to_owned(), next_revision);
            self.emit(SessionEvent::AvatarUpdated {
                uid: uid.to_owned(),
            });
        } else {
            // 先应用 hash 让 record_avatar_hash 清旧缓存并广播；再入队 save，
            // 磁盘队列顺序为 remove -> save，后续 load_hit 能命中新图。
            self.record_avatar_hash(uid, Some(md5.clone()), true);
        }
        if let Some(server_id) = self.active_server_id.clone() {
            self.avatar_disk.save(
                self.store_path.clone(),
                server_id,
                uid.to_owned(),
                Some(md5),
                bytes,
            );
        }
    }

    fn apply_avatar_delete(&mut self, uid: &str) {
        // 删除结果已由服务器确认，负缓存不应再阻止后续读取。
        self.avatar_negative_cache.remove(uid);
        self.record_avatar_hash(uid, None, true);
    }
}

fn known_avatar_limit(limit: Option<i32>) -> Option<u64> {
    match limit {
        Some(value) if value > 0 => {
            Some((value as u64).min(crate::avatars::MAX_AVATAR_BYTES as u64))
        }
        _ => None,
    }
}

fn classify_avatar_error(error: tsclient_rs::Error, limit: Option<i32>) -> SessionError {
    match error.error_code() {
        Some(tsclient_rs::ErrorCode::PermissionInvalidSize) => SessionError::AvatarTooLarge {
            max_bytes: known_avatar_limit(limit),
        },
        Some(
            tsclient_rs::ErrorCode::PermissionsClientInsufficient
            | tsclient_rs::ErrorCode::FileInvalidPermissions
            | tsclient_rs::ErrorCode::Permissions,
        ) => SessionError::AvatarPermissionDenied,
        _ => SessionError::AvatarUnavailable,
    }
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
                assert!(matches!(
                    outcome,
                    Err(ImageFetchError::Session(SessionError::NotConnected))
                ));
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
            actor.enqueue_server_image("/avatar_test", reply, 0);
            replies.push(result);
        }
        let (reply, result) = oneshot::channel();
        actor.enqueue_server_image("/avatar_test", reply, 0);
        assert!(matches!(
            result.await.unwrap(),
            Err(ImageFetchError::Session(SessionError::Transfer(_)))
        ));
        actor.invalidate_handlers();
        assert!(actor.pending_images.is_empty());
        for result in replies {
            assert!(matches!(
                result.await.unwrap(),
                Err(ImageFetchError::Session(SessionError::NotConnected))
            ));
        }
    }

    #[test]
    fn avatar_paths_use_tsclient_rs_for_ts3_and_ts6_uids() {
        let ts3_uid =
            base64::engine::general_purpose::STANDARD.encode((0_u8..20).collect::<Vec<_>>());
        assert_eq!(
            tsclient_rs::avatar_file_name(&ts3_uid).unwrap(),
            "/avatar_aaabacadaeafagahaiajakalamanaoapbabbbcbd"
        );
        let ts6_uid =
            base64::engine::general_purpose::STANDARD.encode((0_u8..32).collect::<Vec<_>>());
        assert_eq!(
            tsclient_rs::avatar_file_name(&ts6_uid).unwrap(),
            "/avatar_aaabacadaeafagahaiajakalamanaoapbabbbcbdbebfbgbhbibjbkblbmbnbobp"
        );
        for invalid in ["", "../avatar", "https://example.com/a.png", "YQ=="] {
            assert!(tsclient_rs::avatar_file_name(invalid).is_err());
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

    #[tokio::test]
    async fn avatar_fetch_skips_transfer_when_hash_is_explicitly_none() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let mut actor = audio_actor();
                actor.active_server_id = Some("a.example:9987".into());
                let ts3_uid = base64::engine::general_purpose::STANDARD.encode([1u8; 20]);
                let ts6_uid = base64::engine::general_purpose::STANDARD.encode([2u8; 32]);

                actor.handle_directory_snapshot(tsclient_rs::DirectorySnapshot {
                    channels: Vec::new(),
                    clients: vec![
                        ClientInfo {
                            uid: ts3_uid.clone(),
                            avatar_hash: None,
                            ..client_info(2, 5, "NoAvatar3")
                        },
                        ClientInfo {
                            uid: ts6_uid.clone(),
                            avatar_hash: None,
                            ..client_info(3, 5, "NoAvatar6")
                        },
                    ],
                    truncated: false,
                });

                for uid in [ts3_uid, ts6_uid] {
                    let (reply, rx) = oneshot::channel();
                    actor.fetch_avatar(uid, reply);
                    assert!(actor.pending_images.is_empty());
                    assert_eq!(rx.await.unwrap().unwrap(), None);
                }
            })
            .await;
    }

    #[tokio::test]
    async fn avatar_fetch_coalesces_misses_and_serves_disk_hits_for_hashed_and_unhashed_paths() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-avatar-cache-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.active_server_id = Some("a.example:9987".into());

                let ts6_uid = base64::engine::general_purpose::STANDARD.encode([7u8; 32]);
                let fallback_uid = base64::engine::general_purpose::STANDARD.encode([8u8; 20]);

                actor.handle_directory_snapshot(tsclient_rs::DirectorySnapshot {
                    channels: Vec::new(),
                    clients: vec![ClientInfo {
                        uid: ts6_uid.clone(),
                        avatar_hash: Some("hash_v1".into()),
                        ..client_info(2, 5, "Ts6Peer")
                    }],
                    truncated: false,
                });

                // 未命中时并发请求合并为一次远程下载，并带 32 字节 UID 路径
                let (reply_a, rx_a) = oneshot::channel();
                let (reply_b, rx_b) = oneshot::channel();
                actor.fetch_avatar(ts6_uid.clone(), reply_a);
                actor.fetch_avatar(ts6_uid.clone(), reply_b);
                actor.avatar_disk.flush().await;
                let disk_signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(disk_signal).await;

                assert_eq!(actor.pending_images.len(), 1);
                let pending = actor.pending_images.pop_front().unwrap();
                assert_eq!(
                    pending.remote_path,
                    tsclient_rs::avatar_file_name(&ts6_uid).unwrap()
                );
                let _ = pending.reply.send(Ok(vec![10, 20, 30]));
                let fetched_signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(fetched_signal).await;
                actor.avatar_disk.flush().await;

                assert_eq!(rx_a.await.unwrap().unwrap(), Some(vec![10, 20, 30]));
                assert_eq!(rx_b.await.unwrap().unwrap(), Some(vec![10, 20, 30]));

                // 同服再次请求直接命中磁盘缓存，不再发起传输
                let (reply_hit, rx_hit) = oneshot::channel();
                actor.fetch_avatar(ts6_uid.clone(), reply_hit);
                actor.avatar_disk.flush().await;
                let hit_signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(hit_signal).await;
                assert!(actor.pending_images.is_empty());
                assert_eq!(rx_hit.await.unwrap().unwrap(), Some(vec![10, 20, 30]));

                // 未知 hash 时退回无 hash 路径落盘并命中
                let (reply_fb, rx_fb) = oneshot::channel();
                actor.fetch_avatar(fallback_uid.clone(), reply_fb);
                actor.avatar_disk.flush().await;
                let fb_disk_signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(fb_disk_signal).await;
                let fb_pending = actor.pending_images.pop_front().unwrap();
                let _ = fb_pending.reply.send(Ok(vec![55, 66]));
                let fb_fetched = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(fb_fetched).await;
                actor.avatar_disk.flush().await;
                assert_eq!(rx_fb.await.unwrap().unwrap(), Some(vec![55, 66]));
                assert_eq!(
                    crate::avatars::load_hit(
                        &actor.store_path,
                        "a.example:9987",
                        &fallback_uid,
                        None
                    ),
                    Some(vec![55, 66])
                );

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    #[tokio::test]
    async fn avatar_hash_changes_invalidate_disk_cache_and_emit_events() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-avatar-events-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.active_server_id = Some("a.example:9987".into());
                let mut events = actor.events.subscribe();

                let uid = base64::engine::general_purpose::STANDARD.encode([3u8; 20]);
                crate::avatars::save(&actor.store_path, "a.example:9987", &uid, Some("h1"), &[1])
                    .unwrap();

                let drain_avatar_updates =
                    |rx: &mut broadcast::Receiver<SessionEvent>| -> Vec<String> {
                        std::iter::from_fn(|| rx.try_recv().ok())
                            .filter_map(|event| match event {
                                SessionEvent::AvatarUpdated { uid } => Some(uid),
                                _ => None,
                            })
                            .collect()
                    };

                // 1. 首次快照建立已知 hash，不误触发 AvatarUpdated
                actor.handle_directory_snapshot(tsclient_rs::DirectorySnapshot {
                    channels: Vec::new(),
                    clients: vec![ClientInfo {
                        uid: uid.clone(),
                        avatar_hash: Some("h1".into()),
                        ..client_info(2, 5, "Alice")
                    }],
                    truncated: false,
                });
                assert!(drain_avatar_updates(&mut events).is_empty());

                // 2. 仅昵称变化（hash 仍是 h1）不清理缓存、不触发事件
                actor
                    .handle_signal(SessionSignal::ClientUpdated {
                        epoch: actor.connection_epoch,
                        id: 2,
                        uid: uid.clone(),
                        channel_id: 5,
                        input_muted: None,
                        output_muted: None,
                        away: None,
                        away_message: None,
                        server_groups: Vec::new(),
                        avatar_hash: Some("h1".into()),
                    })
                    .await;
                assert!(drain_avatar_updates(&mut events).is_empty());
                assert_eq!(
                    crate::avatars::load_hit(&actor.store_path, "a.example:9987", &uid, Some("h1")),
                    Some(vec![1])
                );

                // 3. hash 从 h1 变为 h2：清理旧磁盘缓存并广播 AvatarUpdated
                actor
                    .handle_signal(SessionSignal::ClientUpdated {
                        epoch: actor.connection_epoch,
                        id: 2,
                        uid: uid.clone(),
                        channel_id: 5,
                        input_muted: None,
                        output_muted: None,
                        away: None,
                        away_message: None,
                        server_groups: Vec::new(),
                        avatar_hash: Some("h2".into()),
                    })
                    .await;
                actor.avatar_disk.flush().await;
                assert_eq!(drain_avatar_updates(&mut events), vec![uid.clone()]);
                assert_eq!(
                    crate::avatars::load_hit(&actor.store_path, "a.example:9987", &uid, Some("h1")),
                    None
                );

                // 4. 写入新 h2 后通过 ClientUpdated 清空为 None：清理 h2 磁盘缓存并广播 AvatarUpdated
                crate::avatars::save(&actor.store_path, "a.example:9987", &uid, Some("h2"), &[2])
                    .unwrap();
                actor
                    .handle_signal(SessionSignal::ClientUpdated {
                        epoch: actor.connection_epoch,
                        id: 2,
                        uid: uid.clone(),
                        channel_id: 5,
                        input_muted: None,
                        output_muted: None,
                        away: None,
                        away_message: None,
                        server_groups: Vec::new(),
                        avatar_hash: None,
                    })
                    .await;
                actor.avatar_disk.flush().await;
                assert_eq!(drain_avatar_updates(&mut events), vec![uid.clone()]);
                assert_eq!(
                    crate::avatars::load_hit(&actor.store_path, "a.example:9987", &uid, Some("h2")),
                    None
                );

                // 5. ClientJoined 从 None 新增为 h3：触发 AvatarUpdated
                actor
                    .handle_signal(SessionSignal::ClientJoined {
                        epoch: actor.connection_epoch,
                        client: ClientView::from(ClientInfo {
                            uid: uid.clone(),
                            avatar_hash: Some("h3".into()),
                            ..client_info(9, 5, "Alice")
                        }),
                        avatar_hash: Some("h3".into()),
                    })
                    .await;
                assert_eq!(drain_avatar_updates(&mut events), vec![uid]);

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    #[tokio::test]
    async fn avatar_join_records_flag_and_hash_join_emits() {
        let mut actor = audio_actor();
        let mut events = actor.events.subscribe();

        let unknown_uid = "KqXRNkJgnzjGFbp0GTCPJN1ODJY=";
        actor.sync_avatar_hash_from_join(unknown_uid, None);
        assert_eq!(actor.avatar_hashes.get(unknown_uid), Some(&None));
        assert!(events.try_recv().is_err());

        actor.sync_avatar_hash_from_join("hashed-uid", Some("hash".into()));
        assert_eq!(
            actor.avatar_hashes.get("hashed-uid"),
            Some(&Some("hash".into()))
        );
        assert!(matches!(
            events.try_recv(),
            Ok(SessionEvent::AvatarUpdated { uid }) if uid == "hashed-uid"
        ));
    }

    #[tokio::test]
    async fn avatar_upload_preseed_writes_new_hash_and_same_hash_echo_is_noop() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-avatar-upload-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.active_server_id = Some("a.example:9987".into());
                let mut events = actor.events.subscribe();
                let uid = "avatar-uid";
                let md5 = "0123456789abcdef0123456789abcdef";
                actor.avatar_negative_cache.insert(uid.to_string());

                actor.apply_avatar_upload(uid, md5.into(), vec![7, 8, 9]);
                actor.avatar_disk.flush().await;
                assert!(!actor.avatar_negative_cache.contains(uid));

                assert_eq!(
                    crate::avatars::load_hit(&actor.store_path, "a.example:9987", uid, Some(md5)),
                    Some(vec![7, 8, 9])
                );
                assert!(matches!(
                    events.try_recv(),
                    Ok(SessionEvent::AvatarUpdated { uid: ref updated }) if updated == uid
                ));

                // 服务器回显相同 hash：不重复广播，也不删除刚写入的缓存
                actor.record_avatar_hash(uid, Some(md5.into()), true);
                actor.avatar_disk.flush().await;
                assert!(events.try_recv().is_err());
                assert_eq!(
                    crate::avatars::load_hit(&actor.store_path, "a.example:9987", uid, Some(md5)),
                    Some(vec![7, 8, 9])
                );

                // 显式重传同一张图仍刷新一次 UI
                actor.apply_avatar_upload(uid, md5.into(), vec![7, 8, 9]);
                actor.avatar_disk.flush().await;
                assert!(matches!(
                    events.try_recv(),
                    Ok(SessionEvent::AvatarUpdated { uid: ref updated }) if updated == uid
                ));

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    #[tokio::test]
    async fn avatar_upload_preseed_is_visible_to_the_next_disk_load() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-avatar-order-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.active_server_id = Some("a.example:9987".into());
                let uid = "avatar-uid";
                let md5 = "0123456789abcdef0123456789abcdef";

                actor.apply_avatar_upload(uid, md5.into(), vec![1, 2, 3]);

                // 不等待 flush：remove -> save 必须排在这次 load 之前。
                let (tx, rx) = oneshot::channel();
                actor.avatar_disk.load_hit(
                    actor.store_path.clone(),
                    "a.example:9987".into(),
                    uid.into(),
                    Some(md5.into()),
                    move |bytes| {
                        let _ = tx.send(bytes);
                    },
                );
                assert_eq!(rx.await.unwrap(), Some(vec![1, 2, 3]));

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    #[tokio::test]
    async fn avatar_delete_preseed_clears_cache_and_is_idempotent() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-avatar-delete-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.active_server_id = Some("a.example:9987".into());
                let mut events = actor.events.subscribe();
                let uid = "avatar-uid";
                let md5 = "0123456789abcdef0123456789abcdef";

                actor.apply_avatar_upload(uid, md5.into(), vec![4, 5]);
                actor.avatar_disk.flush().await;
                let _ = events.try_recv();
                actor.avatar_negative_cache.insert(uid.to_string());

                actor.apply_avatar_delete(uid);
                actor.avatar_disk.flush().await;
                assert!(matches!(
                    events.try_recv(),
                    Ok(SessionEvent::AvatarUpdated { uid: ref updated }) if updated == uid
                ));
                assert!(!actor.avatar_negative_cache.contains(uid));
                assert_eq!(
                    crate::avatars::load_hit(&actor.store_path, "a.example:9987", uid, Some(md5)),
                    None
                );

                actor.apply_avatar_delete(uid);
                actor.avatar_disk.flush().await;
                assert!(events.try_recv().is_err());

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    #[test]
    fn avatar_error_codes_map_to_typed_session_errors() {
        let server_error = |id: &str| tsclient_rs::Error::ServerError {
            id: id.to_string(),
            server_message: "refused".to_string(),
            extra_message: None,
        };

        assert!(matches!(
            classify_avatar_error(server_error("2565"), Some(200_000)),
            SessionError::AvatarTooLarge {
                max_bytes: Some(200_000)
            }
        ));
        assert!(matches!(
            classify_avatar_error(server_error("2565"), None),
            SessionError::AvatarTooLarge { max_bytes: None }
        ));
        for id in ["2568", "2049", "2572"] {
            assert!(matches!(
                classify_avatar_error(server_error(id), None),
                SessionError::AvatarPermissionDenied
            ));
        }
        assert!(matches!(
            classify_avatar_error(server_error("524"), None),
            SessionError::AvatarUnavailable
        ));
    }

    struct AvatarErrorMiddleware {
        code: Arc<std::sync::Mutex<Option<String>>>,
        calls: Arc<std::sync::atomic::AtomicUsize>,
    }

    impl tsclient_rs::CommandMiddleware for AvatarErrorMiddleware {
        fn wrap(&self, _: TestCommandHandler) -> TestCommandHandler {
            let code = Arc::clone(&self.code);
            let calls = Arc::clone(&self.calls);
            Arc::new(move |command| {
                let code = Arc::clone(&code);
                let calls = Arc::clone(&calls);
                Box::pin(async move {
                    if command.starts_with("ftinitdownload ") {
                        calls.fetch_add(1, Ordering::SeqCst);
                        let error_id = code.lock().unwrap().clone();
                        return match error_id {
                            Some(id) => Err(tsclient_rs::Error::ServerError {
                                id,
                                server_message: "server failure".into(),
                                extra_message: None,
                            }),
                            None => Err(tsclient_rs::Error::CommandTimeout {
                                command: "ftinitdownload".into(),
                            }),
                        };
                    }
                    Ok(())
                })
            })
        }
    }

    #[tokio::test]
    async fn avatar_negative_cache_classifies_errors_and_clears_on_update_or_reconnect() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-avatar-neg-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let code = Arc::new(std::sync::Mutex::new(Some("2051".to_string())));
                let calls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
                let client = Client::new(
                    tsclient_rs::generateIdentity(0),
                    "127.0.0.1:9987".into(),
                    "test".into(),
                    tsclient_rs::ClientOptions {
                        command_middleware: vec![Box::new(AvatarErrorMiddleware {
                            code: Arc::clone(&code),
                            calls: Arc::clone(&calls),
                        })],
                        ..Default::default()
                    },
                );
                client.mark_connected();

                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.active_server_id = Some("127.0.0.1:9987".into());
                actor.client = Some(Arc::new(client));
                actor.transfer_target = Some(ServerTarget {
                    host: "127.0.0.1".into(),
                    port: 9987,
                });

                let (commands, rx) = mpsc::unbounded_channel();
                let task = tokio::task::spawn_local(async move {
                    actor.run(rx).await;
                });

                let uid_not_found = base64::engine::general_purpose::STANDARD.encode([10u8; 20]);
                let uid_invalid_path = base64::engine::general_purpose::STANDARD.encode([11u8; 20]);
                let uid_perm = base64::engine::general_purpose::STANDARD.encode([12u8; 32]);
                let uid_file_perm = base64::engine::general_purpose::STANDARD.encode([14u8; 20]);
                let uid_generic_perm = base64::engine::general_purpose::STANDARD.encode([15u8; 20]);
                let uid_transient = base64::engine::general_purpose::STANDARD.encode([13u8; 20]);

                // 2051 (FileNotFound) 命中负缓存并返回 Ok(None)
                let (reply, res) = oneshot::channel();
                commands
                    .send(SessionCommand::FetchAvatar {
                        uid: uid_not_found.clone(),
                        reply,
                    })
                    .unwrap();
                assert_eq!(res.await.unwrap().unwrap(), None);
                assert_eq!(calls.load(Ordering::SeqCst), 1);

                // 二次拉取命中内存负缓存，不发起任何 ftinitdownload
                let (reply, res) = oneshot::channel();
                commands
                    .send(SessionCommand::FetchAvatar {
                        uid: uid_not_found.clone(),
                        reply,
                    })
                    .unwrap();
                assert_eq!(res.await.unwrap().unwrap(), None);
                assert_eq!(calls.load(Ordering::SeqCst), 1);

                // 2054 (FileInvalidPath) 与 2568 (PermissionsClientInsufficient) 同样进入负缓存
                *code.lock().unwrap() = Some("2054".into());
                let (reply, res) = oneshot::channel();
                commands
                    .send(SessionCommand::FetchAvatar {
                        uid: uid_invalid_path.clone(),
                        reply,
                    })
                    .unwrap();
                assert_eq!(res.await.unwrap().unwrap(), None);
                assert_eq!(calls.load(Ordering::SeqCst), 2);

                *code.lock().unwrap() = Some("2568".into());
                let (reply, res) = oneshot::channel();
                commands
                    .send(SessionCommand::FetchAvatar {
                        uid: uid_perm.clone(),
                        reply,
                    })
                    .unwrap();
                assert_eq!(res.await.unwrap().unwrap(), None);
                assert_eq!(calls.load(Ordering::SeqCst), 3);

                *code.lock().unwrap() = Some("2049".into());
                let (reply, res) = oneshot::channel();
                commands
                    .send(SessionCommand::FetchAvatar {
                        uid: uid_file_perm.clone(),
                        reply,
                    })
                    .unwrap();
                assert_eq!(res.await.unwrap().unwrap(), None);
                assert_eq!(calls.load(Ordering::SeqCst), 4);

                *code.lock().unwrap() = Some("2572".into());
                let (reply, res) = oneshot::channel();
                commands
                    .send(SessionCommand::FetchAvatar {
                        uid: uid_generic_perm.clone(),
                        reply,
                    })
                    .unwrap();
                assert_eq!(res.await.unwrap().unwrap(), None);
                assert_eq!(calls.load(Ordering::SeqCst), 5);

                // 瞬态超时错误不进入负缓存，仍向调用方返回 Err
                *code.lock().unwrap() = None;
                let (reply, res) = oneshot::channel();
                commands
                    .send(SessionCommand::FetchAvatar {
                        uid: uid_transient.clone(),
                        reply,
                    })
                    .unwrap();
                assert!(matches!(res.await.unwrap(), Err(SessionError::Timeout)));
                assert_eq!(calls.load(Ordering::SeqCst), 6);

                let (reply, res) = oneshot::channel();
                commands
                    .send(SessionCommand::FetchAvatar {
                        uid: uid_transient.clone(),
                        reply,
                    })
                    .unwrap();
                assert!(matches!(res.await.unwrap(), Err(SessionError::Timeout)));
                assert_eq!(calls.load(Ordering::SeqCst), 7);

                // 不应落盘任何负缓存文件
                assert!(!temp.join("avatars").exists());

                // 收到 avatar_hash 更新后，负缓存被清除并广播 AvatarUpdated
                commands.send(SessionCommand::Shutdown).unwrap();
                task.await.unwrap();

                // 用独立 Actor 验证更新事件与重连清除负缓存
                let mut actor = audio_actor();
                actor.active_server_id = Some("127.0.0.1:9987".into());
                let mut events = actor.events.subscribe();
                actor.avatar_negative_cache.insert(uid_not_found.clone());
                actor.avatar_negative_cache.insert(uid_perm.clone());

                actor
                    .handle_signal(SessionSignal::ClientUpdated {
                        epoch: actor.connection_epoch,
                        id: 4,
                        uid: uid_not_found.clone(),
                        channel_id: 5,
                        input_muted: None,
                        output_muted: None,
                        away: None,
                        away_message: None,
                        server_groups: Vec::new(),
                        avatar_hash: Some("fresh_hash".into()),
                    })
                    .await;
                assert!(!actor.avatar_negative_cache.contains(&uid_not_found));
                assert!(actor.avatar_negative_cache.contains(&uid_perm));
                assert!(matches!(
                    events.try_recv(),
                    Ok(SessionEvent::AvatarUpdated { uid: ref updated }) if updated == &uid_not_found
                ));

                // 重连失效清理全部会话级负缓存与状态
                actor.invalidate_handlers();
                assert!(actor.avatar_negative_cache.is_empty());
                assert!(actor.avatar_hashes.is_empty());

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }
}
