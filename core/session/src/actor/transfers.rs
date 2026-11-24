use std::collections::{HashSet, VecDeque};

use super::*;

const TRANSFER_PROGRESS_BYTES: u64 = 256 * 1024;
const TRANSFER_PROGRESS_INTERVAL: Duration = Duration::from_millis(200);
pub(crate) const MAX_CHANNEL_ICON_RETRIES: u8 = 5;
pub(crate) const CHANNEL_ICON_RETRY_STEP: Duration = Duration::from_millis(300);
pub(crate) const MAX_AVATAR_TRANSIENT_RETRIES: u8 = 5;
pub(crate) const AVATAR_TRANSIENT_RETRY_DELAY: Duration = Duration::from_millis(500);
pub(crate) const AVATAR_FAILURE_COOLDOWN: Duration = Duration::from_secs(30);
pub(crate) const MAX_AVATAR_FAILURE_ATTEMPTS: u8 = 3;
const IMAGE_QUEUE_CAPACITY: usize = 32;

type ImageNegotiation =
    Pin<Box<dyn std::future::Future<Output = Result<(String, FileDownloadInfo), ImageFetchError>>>>;
type ChannelIconKey = (u64, String, u32);
type ChannelIconWaiters = Vec<oneshot::Sender<Result<Vec<u8>, SessionError>>>;
type AvatarFetchKey = (u64, String, String, u64);
type AvatarWaiters = Vec<oneshot::Sender<Result<Option<Vec<u8>>, SessionError>>>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ImageTransientReason {
    QueueFull,
    Interrupted,
    ServerBusy(String),
    Timeout,
}

impl ImageTransientReason {
    pub(crate) fn is_prompt_retryable(&self) -> bool {
        matches!(
            self,
            Self::QueueFull | Self::Interrupted | Self::ServerBusy(_)
        )
    }

    pub(crate) fn into_session_error(self) -> SessionError {
        match self {
            Self::QueueFull => SessionError::Transfer("image request queue is full".into()),
            Self::Interrupted => SessionError::Transfer("image negotiation interrupted".into()),
            Self::ServerBusy(message) => SessionError::Protocol(message),
            Self::Timeout => SessionError::Timeout,
        }
    }
}

#[derive(Debug)]
pub(crate) enum ImageFetchError {
    NotFound(String),
    PermissionDenied(String),
    Transient(ImageTransientReason),
    Permanent(SessionError),
}

impl ImageFetchError {
    pub(super) fn into_session_error(self) -> SessionError {
        match self {
            Self::NotFound(message) | Self::PermissionDenied(message) => {
                SessionError::Protocol(message)
            }
            Self::Transient(reason) => reason.into_session_error(),
            Self::Permanent(err) => err,
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
    } else if matches!(err, tsclient_rs::Error::CommandTimeout { .. }) {
        ImageFetchError::Transient(ImageTransientReason::Timeout)
    } else if matches!(err, tsclient_rs::Error::ServerError { ref id, .. } if id == "524") {
        ImageFetchError::Transient(ImageTransientReason::ServerBusy(err.to_string()))
    } else {
        ImageFetchError::Permanent(protocol_error(err))
    }
}

pub(crate) fn channel_icon_retry_delay(attempt: u8, error: &ImageFetchError) -> Option<Duration> {
    match error {
        ImageFetchError::Transient(reason)
            if attempt < MAX_CHANNEL_ICON_RETRIES && reason.is_prompt_retryable() =>
        {
            Some(CHANNEL_ICON_RETRY_STEP * u32::from(attempt + 1))
        }
        _ => None,
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
    pub(super) remote_path: String,
    pub(super) attempt: u8,
    pub(super) result: Result<Vec<u8>, ImageFetchError>,
}

#[derive(Debug)]
pub(crate) struct AvatarRetry {
    pub(super) epoch: u64,
    pub(super) server_id: String,
    pub(super) uid: String,
    pub(super) revision: u64,
    pub(super) avatar_hash: Option<String>,
    pub(super) remote_path: String,
    pub(super) attempt: u8,
}

#[derive(Debug)]
struct AvatarCooldown {
    attempts: u8,
    retry_not_before: Option<tokio::time::Instant>,
    last_error: SessionError,
}

struct PendingImage {
    remote_path: String,
    reply: oneshot::Sender<Result<Vec<u8>, ImageFetchError>>,
    preempt_retries: u8,
}

struct ActiveImage {
    remote_path: String,
    negotiation: ImageNegotiation,
    reply: oneshot::Sender<Result<Vec<u8>, ImageFetchError>>,
    preempt_retries: u8,
}

const ICON_PREEMPT_RETRIES: u8 = 5;

fn clone_image_error(error: &SessionError) -> SessionError {
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

/// 服务器/频道图标与成员头像的在途协商队列、会话缓存与磁盘调度状态。
pub(super) struct MediaTransferState {
    pending_images: VecDeque<PendingImage>,
    active_image: Option<ActiveImage>,
    icons: crate::media::IconCache,
    active_server_icon_id: Option<u32>,
    fetching_server_icon: Option<(u64, String, u32)>,
    in_flight_channel_icons: HashMap<ChannelIconKey, ChannelIconWaiters>,
    avatar_hashes: HashMap<String, Option<String>>,
    avatar_negative_cache: HashSet<String>,
    avatar_cooldowns: HashMap<String, AvatarCooldown>,
    avatar_revisions: HashMap<String, u64>,
    avatars_fetched_without_hash: HashSet<String>,
    in_flight_avatars: HashMap<AvatarFetchKey, AvatarWaiters>,
    avatar_disk: crate::media::AvatarDiskQueue,
}

impl MediaTransferState {
    pub(super) fn new(store_path: &std::path::Path, active_server_ids: &[&str]) -> Self {
        let icons = crate::media::IconCache::load(store_path, active_server_ids);
        let avatar_disk = crate::media::AvatarDiskQueue::new();
        avatar_disk.prune_orphans(
            store_path.to_path_buf(),
            active_server_ids
                .iter()
                .map(|id| (*id).to_owned())
                .collect(),
        );
        Self {
            pending_images: VecDeque::new(),
            active_image: None,
            icons,
            active_server_icon_id: None,
            fetching_server_icon: None,
            in_flight_channel_icons: HashMap::new(),
            avatar_hashes: HashMap::new(),
            avatar_negative_cache: HashSet::new(),
            avatar_cooldowns: HashMap::new(),
            avatar_revisions: HashMap::new(),
            avatars_fetched_without_hash: HashSet::new(),
            in_flight_avatars: HashMap::new(),
            avatar_disk,
        }
    }

    pub(super) fn reset_on_disconnect(&mut self) {
        self.cancel_active_image();
        for request in self.pending_images.drain(..) {
            let _ = request
                .reply
                .send(Err(ImageFetchError::Permanent(SessionError::NotConnected)));
        }
        for (_, waiters) in self.in_flight_channel_icons.drain() {
            for reply in waiters {
                let _ = reply.send(Err(SessionError::NotConnected));
            }
        }
        self.reset_avatar_session_state();
        self.active_server_icon_id = None;
        self.fetching_server_icon = None;
    }

    pub(super) fn reset_avatar_session_state(&mut self) {
        for (_, waiters) in self.in_flight_avatars.drain() {
            for reply in waiters {
                let _ = reply.send(Err(SessionError::NotConnected));
            }
        }
        self.avatar_hashes.clear();
        self.avatar_negative_cache.clear();
        self.avatar_cooldowns.clear();
        self.avatar_revisions.clear();
        self.avatars_fetched_without_hash.clear();
    }

    pub(super) fn can_start_next_image(&self) -> bool {
        self.active_image.is_none() && !self.pending_images.is_empty()
    }

    pub(super) async fn poll_active_image(
        &mut self,
    ) -> Result<(String, FileDownloadInfo), ImageFetchError> {
        match &mut self.active_image {
            Some(active) => active.negotiation.as_mut().await,
            None => std::future::pending().await,
        }
    }

    pub(super) fn take_active_image_reply(
        &mut self,
    ) -> oneshot::Sender<Result<Vec<u8>, ImageFetchError>> {
        self.active_image
            .take()
            .expect("polled image request")
            .reply
    }

    fn pop_next_image(&mut self) -> Option<PendingImage> {
        self.pending_images.pop_front()
    }

    fn set_active_image(&mut self, active: ActiveImage) {
        self.active_image = Some(active);
    }

    pub(super) fn enqueue_image(
        &mut self,
        remote_path: &str,
        reply: oneshot::Sender<Result<Vec<u8>, ImageFetchError>>,
        preempt_retries: u8,
    ) {
        if self.pending_images.len() >= IMAGE_QUEUE_CAPACITY {
            let _ = reply.send(Err(ImageFetchError::Transient(
                ImageTransientReason::QueueFull,
            )));
            return;
        }
        self.pending_images.push_back(PendingImage {
            remote_path: remote_path.to_owned(),
            reply,
            preempt_retries,
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
                let _ = active.reply.send(Err(ImageFetchError::Transient(
                    ImageTransientReason::Interrupted,
                )));
            }
        }
    }

    pub(super) fn cancel_active_image(&mut self) {
        if let Some(active) = self.active_image.take() {
            let _ = active
                .reply
                .send(Err(ImageFetchError::Permanent(SessionError::NotConnected)));
        }
    }

    pub(super) fn list_server_icons(&self) -> Vec<crate::ServerIconView> {
        self.icons.list_server_icons()
    }

    pub(super) fn load_self_avatar_snapshot(
        &self,
        store_path: PathBuf,
        callback: impl FnOnce(Option<Vec<u8>>) + Send + 'static,
    ) {
        self.avatar_disk.load_self_snapshot(store_path, callback);
    }

    pub(super) fn remove_server(&mut self, store_path: &std::path::Path, server_id: &str) -> bool {
        self.avatar_disk
            .remove_server(store_path.to_path_buf(), server_id.to_owned());
        self.icons
            .remove_server(store_path, server_id)
            .unwrap_or(false)
    }

    pub(super) fn move_server(
        &mut self,
        store_path: &std::path::Path,
        old_id: &str,
        new_id: &str,
    ) -> Option<Vec<u8>> {
        self.avatar_disk.move_server(
            store_path.to_path_buf(),
            old_id.to_owned(),
            new_id.to_owned(),
        );
        self.icons
            .move_server(store_path, old_id, new_id)
            .ok()
            .flatten()
    }

    pub(super) fn record_avatar_hash(
        &mut self,
        uid: &str,
        next: Option<String>,
        emit_on_initial_some: bool,
    ) -> bool {
        if uid.is_empty() {
            return false;
        }
        let next = next.filter(|value| !value.is_empty());
        let had_negative = self.avatar_negative_cache.contains(uid);
        let fetched_without_hash = self.avatars_fetched_without_hash.remove(uid);
        let changed = match self.avatar_hashes.get(uid) {
            Some(existing) if existing == &next => return false,
            Some(_) => true,
            None => {
                (fetched_without_hash && !had_negative)
                    || ((had_negative || emit_on_initial_some) && next.is_some())
            }
        };
        self.avatar_hashes.insert(uid.to_owned(), next);
        if changed {
            self.bump_avatar_revision(uid);
            self.avatar_negative_cache.remove(uid);
            self.avatar_cooldowns.remove(uid);
        }
        changed
    }

    pub(super) fn avatar_hash(&self, uid: &str) -> Option<&Option<String>> {
        self.avatar_hashes.get(uid)
    }

    pub(super) fn avatar_revision(&self, uid: &str) -> u64 {
        self.avatar_revisions.get(uid).copied().unwrap_or(0)
    }

    pub(super) fn bump_avatar_revision(&mut self, uid: &str) -> u64 {
        let next = self.avatar_revision(uid) + 1;
        self.avatar_revisions.insert(uid.to_owned(), next);
        next
    }

    pub(super) fn clear_avatar_failure_state(&mut self, uid: &str) {
        self.avatar_negative_cache.remove(uid);
        self.avatar_cooldowns.remove(uid);
    }

    pub(super) fn mark_avatar_not_found(&mut self, uid: String) {
        self.avatar_cooldowns.remove(&uid);
        self.avatar_negative_cache.insert(uid);
    }

    pub(super) fn record_avatar_failure_cooldown(
        &mut self,
        uid: &str,
        error: &SessionError,
        now: tokio::time::Instant,
    ) {
        let attempts = self
            .avatar_cooldowns
            .get(uid)
            .map_or(0, |existing| existing.attempts)
            .saturating_add(1);
        let retry_not_before =
            (attempts < MAX_AVATAR_FAILURE_ATTEMPTS).then_some(now + AVATAR_FAILURE_COOLDOWN);
        self.avatar_cooldowns.insert(
            uid.to_owned(),
            AvatarCooldown {
                attempts,
                retry_not_before,
                last_error: clone_image_error(error),
            },
        );
    }

    pub(super) fn active_avatar_cooldown_error(
        &self,
        uid: &str,
        now: tokio::time::Instant,
    ) -> Option<SessionError> {
        let cooldown = self.avatar_cooldowns.get(uid)?;
        cooldown
            .retry_not_before
            .is_none_or(|deadline| now < deadline)
            .then(|| clone_image_error(&cooldown.last_error))
    }

    fn register_channel_icon_waiter(
        &mut self,
        key: ChannelIconKey,
        reply: oneshot::Sender<Result<Vec<u8>, SessionError>>,
    ) -> bool {
        if let Some(waiters) = self.in_flight_channel_icons.get_mut(&key) {
            waiters.push(reply);
            return false;
        }
        self.in_flight_channel_icons.insert(key, vec![reply]);
        true
    }

    fn has_in_flight_channel_icon(&self, key: &ChannelIconKey) -> bool {
        self.in_flight_channel_icons.contains_key(key)
    }

    fn take_channel_icon_waiters(&mut self, key: &ChannelIconKey) -> Option<ChannelIconWaiters> {
        self.in_flight_channel_icons.remove(key)
    }

    fn fail_channel_icon_waiters(&mut self, key: &ChannelIconKey) {
        if let Some(waiters) = self.in_flight_channel_icons.remove(key) {
            for reply in waiters {
                let _ = reply.send(Err(SessionError::NotConnected));
            }
        }
    }

    fn register_avatar_waiter(
        &mut self,
        key: AvatarFetchKey,
        reply: oneshot::Sender<Result<Option<Vec<u8>>, SessionError>>,
    ) -> bool {
        if let Some(waiters) = self.in_flight_avatars.get_mut(&key) {
            waiters.push(reply);
            return false;
        }
        self.in_flight_avatars.insert(key, vec![reply]);
        true
    }

    fn has_in_flight_avatar(&self, key: &AvatarFetchKey) -> bool {
        self.in_flight_avatars.contains_key(key)
    }

    fn take_in_flight_avatar(&mut self, key: &AvatarFetchKey) -> Option<AvatarWaiters> {
        self.in_flight_avatars.remove(key)
    }

    fn fail_avatar_waiters(&mut self, key: &AvatarFetchKey) {
        if let Some(waiters) = self.in_flight_avatars.remove(key) {
            for reply in waiters {
                let _ = reply.send(Err(SessionError::NotConnected));
            }
        }
    }
}

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
        self.media.enqueue_image(
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
        if let Some(bytes) =
            self.media
                .icons
                .load_channel_icon(&self.store_path, &server_id, icon_id)
        {
            let _ = reply.send(Ok(bytes));
            return;
        }
        let epoch = self.connection_epoch;
        let key = (epoch, server_id.clone(), icon_id);
        if !self.media.register_channel_icon_waiter(key, reply) {
            return;
        }
        self.dispatch_channel_icon_attempt(epoch, server_id, icon_id, 0);
    }

    pub(super) fn dispatch_channel_icon_attempt(
        &mut self,
        epoch: u64,
        server_id: String,
        icon_id: u32,
        attempt: u8,
    ) {
        let (tx, rx) = oneshot::channel();
        self.media.enqueue_image(
            &tsclient_rs::icon_file_name(icon_id),
            tx,
            ICON_PREEMPT_RETRIES,
        );
        let signals = self.signals.clone();
        tokio::task::spawn_local(async move {
            let result = match rx.await {
                Ok(result) => result,
                Err(_) => Err(ImageFetchError::Permanent(SessionError::NotConnected)),
            };
            let _ = signals.send(SessionSignal::ChannelIconFetched {
                epoch,
                server_id,
                icon_id,
                attempt,
                result,
            });
        });
    }

    pub(super) fn handle_channel_icon_fetched(
        &mut self,
        epoch: u64,
        server_id: String,
        icon_id: u32,
        attempt: u8,
        result: Result<Vec<u8>, ImageFetchError>,
    ) {
        let key = (epoch, server_id.clone(), icon_id);
        if !self.media.has_in_flight_channel_icon(&key) {
            return;
        }
        if epoch != self.connection_epoch
            || self.active_server_id.as_deref() != Some(server_id.as_str())
        {
            self.media.fail_channel_icon_waiters(&key);
            return;
        }
        if let Err(ref err) = result
            && let Some(delay) = channel_icon_retry_delay(attempt, err)
        {
            let signals = self.signals.clone();
            tokio::task::spawn_local(async move {
                tokio::time::sleep(delay).await;
                let _ = signals.send(SessionSignal::RetryChannelIcon {
                    epoch,
                    server_id,
                    icon_id,
                    attempt: attempt + 1,
                });
            });
            return;
        }
        let Some(waiters) = self.media.take_channel_icon_waiters(&key) else {
            return;
        };
        match result {
            Ok(bytes) => {
                if let Err(error) = self.media.icons.save_channel_icon(
                    &self.store_path,
                    &server_id,
                    icon_id,
                    &bytes,
                ) {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!("failed to save the channel icon cache: {error}"),
                    });
                }
                for reply in waiters {
                    let _ = reply.send(Ok(bytes.clone()));
                }
            }
            Err(error) => {
                let error = error.into_session_error();
                if !matches!(error, SessionError::NotConnected) {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!("failed to fetch channel icon {icon_id}: {error}"),
                    });
                }
                for reply in waiters {
                    let _ = reply.send(Err(clone_image_error(&error)));
                }
            }
        }
    }

    pub(super) fn handle_retry_channel_icon(
        &mut self,
        epoch: u64,
        server_id: String,
        icon_id: u32,
        attempt: u8,
    ) {
        let key = (epoch, server_id.clone(), icon_id);
        if !self.media.has_in_flight_channel_icon(&key) {
            return;
        }
        if epoch != self.connection_epoch
            || self.active_server_id.as_deref() != Some(server_id.as_str())
        {
            self.media.fail_channel_icon_waiters(&key);
            return;
        }
        self.dispatch_channel_icon_attempt(epoch, server_id, icon_id, attempt);
    }

    pub(super) fn sync_server_icon(&mut self, server_id: String, icon_id: Option<u32>) {
        let Some(icon_id) = icon_id else {
            return;
        };
        self.media.active_server_icon_id = Some(icon_id);
        if icon_id == 0 {
            self.media.fetching_server_icon = None;
            match self
                .media
                .icons
                .clear_server_icon(&self.store_path, &server_id)
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
        if self.media.icons.has_server_icon(&server_id, icon_id) {
            return;
        }
        if self
            .media
            .fetching_server_icon
            .as_ref()
            .is_some_and(|(epoch, id, icon)| {
                *epoch == self.connection_epoch && id == &server_id && *icon == icon_id
            })
        {
            return;
        }
        let epoch = self.connection_epoch;
        self.media.fetching_server_icon = Some((epoch, server_id.clone(), icon_id));
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

    pub(super) fn handle_server_icon_fetched(
        &mut self,
        epoch: u64,
        server_id: String,
        icon_id: u32,
        result: Result<Vec<u8>, SessionError>,
    ) {
        if epoch != self.connection_epoch
            || self.active_server_id.as_deref() != Some(server_id.as_str())
            || self.media.active_server_icon_id != Some(icon_id)
        {
            return;
        }
        self.media.fetching_server_icon = None;
        match result {
            Ok(bytes) => {
                if let Err(error) = self.media.icons.save_server_icon(
                    &self.store_path,
                    &server_id,
                    icon_id,
                    bytes.clone(),
                ) {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!("failed to save the server icon cache: {error}"),
                    });
                }
                self.emit(SessionEvent::ServerIconUpdated {
                    server_id,
                    bytes: Some(bytes),
                });
            }
            Err(error) => {
                if !matches!(error, SessionError::NotConnected) {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!("failed to fetch server icon {icon_id}: {error}"),
                    });
                }
            }
        }
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
        if self
            .media
            .record_avatar_hash(uid, next, emit_on_initial_some)
        {
            if let Some(server_id) = self.active_server_id.clone() {
                self.media.avatar_disk.remove_uid(
                    self.store_path.clone(),
                    server_id,
                    uid.to_owned(),
                );
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
        let avatar_hash = match self.media.avatar_hash(&uid) {
            Some(None) => {
                let _ = reply.send(Ok(None));
                return;
            }
            Some(Some(hash)) => Some(hash.clone()),
            None => None,
        };
        if self.media.avatar_negative_cache.contains(&uid) {
            let _ = reply.send(Ok(None));
            return;
        }
        if let Some(err) = self
            .media
            .active_avatar_cooldown_error(&uid, tokio::time::Instant::now())
        {
            let _ = reply.send(Err(err));
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
            self.media.avatars_fetched_without_hash.insert(uid.clone());
        }
        let epoch = self.connection_epoch;
        let revision = self.media.avatar_revision(&uid);
        let key = (epoch, server_id.clone(), uid.clone(), revision);
        if !self.media.register_avatar_waiter(key, reply) {
            return;
        }
        let signals = self.signals.clone();
        self.media.avatar_disk.load_hit(
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
            self.media.fail_avatar_waiters(&key);
            return;
        }
        if self.media.avatar_revision(&uid) != revision {
            if let Some(waiters) = self.media.take_in_flight_avatar(&key) {
                for reply in waiters {
                    self.fetch_avatar(uid.clone(), reply);
                }
            }
            return;
        }
        if let Some(bytes) = bytes {
            self.media.avatar_cooldowns.remove(&uid);
            if self.self_uid_from_snapshot().as_deref() == Some(uid.as_str()) {
                self.media
                    .avatar_disk
                    .save_self_snapshot(self.store_path.clone(), bytes.clone());
            }
            if let Some(waiters) = self.media.take_in_flight_avatar(&key) {
                for reply in waiters {
                    let _ = reply.send(Ok(Some(bytes.clone())));
                }
            }
            return;
        }
        if !self.media.has_in_flight_avatar(&key) {
            return;
        }
        self.dispatch_avatar_remote_attempt(
            epoch,
            server_id,
            uid,
            revision,
            avatar_hash,
            remote_path,
            0,
        );
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) fn dispatch_avatar_remote_attempt(
        &mut self,
        epoch: u64,
        server_id: String,
        uid: String,
        revision: u64,
        avatar_hash: Option<String>,
        remote_path: String,
        attempt: u8,
    ) {
        let (tx, rx) = oneshot::channel();
        self.media.enqueue_image(&remote_path, tx, 0);
        let signals = self.signals.clone();
        tokio::task::spawn_local(async move {
            let result = match rx.await {
                Ok(result) => result,
                Err(_) => Err(ImageFetchError::Permanent(SessionError::NotConnected)),
            };
            let _ = signals.send(SessionSignal::AvatarFetched(AvatarFetchOutcome {
                epoch,
                server_id,
                uid,
                revision,
                avatar_hash,
                remote_path,
                attempt,
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
            remote_path,
            attempt,
            result,
        } = outcome;
        let key = (epoch, server_id.clone(), uid.clone(), revision);
        if !self.media.has_in_flight_avatar(&key) {
            return;
        }
        if epoch != self.connection_epoch
            || self.active_server_id.as_deref() != Some(server_id.as_str())
        {
            self.media.fail_avatar_waiters(&key);
            return;
        }
        if self.media.avatar_revision(&uid) != revision {
            if let Some(waiters) = self.media.take_in_flight_avatar(&key) {
                for reply in waiters {
                    self.fetch_avatar(uid.clone(), reply);
                }
            }
            return;
        }
        if let Err(ImageFetchError::Transient(ref reason)) = result
            && reason.is_prompt_retryable()
            && attempt < MAX_AVATAR_TRANSIENT_RETRIES
        {
            let signals = self.signals.clone();
            tokio::task::spawn_local(async move {
                tokio::time::sleep(AVATAR_TRANSIENT_RETRY_DELAY).await;
                let _ = signals.send(SessionSignal::RetryAvatarFetch(AvatarRetry {
                    epoch,
                    server_id,
                    uid,
                    revision,
                    avatar_hash,
                    remote_path,
                    attempt: attempt + 1,
                }));
            });
            return;
        }
        let Some(waiters) = self.media.take_in_flight_avatar(&key) else {
            return;
        };
        match result {
            Ok(bytes) => {
                self.media.avatar_cooldowns.remove(&uid);
                if self.self_uid_from_snapshot().as_deref() == Some(uid.as_str()) {
                    self.media
                        .avatar_disk
                        .save_self_snapshot(self.store_path.clone(), bytes.clone());
                }
                self.media.avatar_disk.save(
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
                self.media.mark_avatar_not_found(uid);
                for reply in waiters {
                    let _ = reply.send(Ok(None));
                }
            }
            Err(error @ (ImageFetchError::Transient(_) | ImageFetchError::Permanent(_))) => {
                let error = error.into_session_error();
                if !matches!(error, SessionError::NotConnected) {
                    self.media.record_avatar_failure_cooldown(
                        &uid,
                        &error,
                        tokio::time::Instant::now(),
                    );
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!("failed to fetch avatar for {uid}: {error}"),
                    });
                }
                for reply in waiters {
                    let _ = reply.send(Err(clone_image_error(&error)));
                }
            }
        }
    }

    pub(super) fn handle_retry_avatar_fetch(&mut self, retry: AvatarRetry) {
        let AvatarRetry {
            epoch,
            server_id,
            uid,
            revision,
            avatar_hash,
            remote_path,
            attempt,
        } = retry;
        let key = (epoch, server_id.clone(), uid.clone(), revision);
        if !self.media.has_in_flight_avatar(&key) {
            return;
        }
        if epoch != self.connection_epoch
            || self.active_server_id.as_deref() != Some(server_id.as_str())
        {
            self.media.fail_avatar_waiters(&key);
            return;
        }
        if self.media.avatar_revision(&uid) != revision {
            if let Some(waiters) = self.media.take_in_flight_avatar(&key) {
                for reply in waiters {
                    self.fetch_avatar(uid.clone(), reply);
                }
            }
            return;
        }
        self.dispatch_avatar_remote_attempt(
            epoch,
            server_id,
            uid,
            revision,
            avatar_hash,
            remote_path,
            attempt,
        );
    }

    pub(super) fn start_next_image(&mut self) {
        if !self.media.can_start_next_image() {
            return;
        }
        let Some(pending) = self.media.pop_next_image() else {
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
                let _ = pending.reply.send(Err(ImageFetchError::Permanent(error)));
                return;
            }
        };
        let remote_path = pending.remote_path;
        let path = remote_path.clone();
        self.media.set_active_image(ActiveImage {
            remote_path,
            reply: pending.reply,
            preempt_retries: pending.preempt_retries,
            negotiation: Box::pin(async move {
                let info = tokio::time::timeout(
                    Duration::from_secs(5),
                    client.file_transfer_init_download(0, &path, ""),
                )
                .await
                .map_err(|_| ImageFetchError::Transient(ImageTransientReason::Timeout))?
                .map_err(classify_image_protocol_error)?;
                validate_port(info.port).map_err(ImageFetchError::Permanent)?;
                if info.size == 0 || info.size > 1024 * 1024 {
                    return Err(ImageFetchError::Permanent(SessionError::Transfer(
                        "image size must be between 1 byte and 1 MiB".into(),
                    )));
                }
                Ok((host, info))
            }),
        });
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
                    res.unwrap_or(Err(ImageFetchError::Transient(ImageTransientReason::Timeout)))
                }
                _ = async {
                    while disconnect_rx.changed().await.is_ok() {
                        if *disconnect_rx.borrow() != epoch {
                            break;
                        }
                    }
                } => {
                    Err(ImageFetchError::Permanent(SessionError::NotConnected))
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
        if !crate::media::is_supported_avatar_image(&bytes) {
            return Err(SessionError::AvatarUnsupportedFormat);
        }
        let limit =
            crate::channel_tools::avatar_size_limit(&client, self.directory.channel_tools_mut())
                .await;
        crate::media::validate_avatar_size(bytes.len(), limit)?;
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

    fn self_uid_from_snapshot(&self) -> Option<String> {
        let self_id = self.self_client_id?;
        self.directory.snapshot_client_uid(self_id)
    }

    async fn self_uid(&mut self, client: &Client) -> Result<String, SessionError> {
        let Some(self_id) = self.self_client_id else {
            return Err(SessionError::AvatarUnavailable);
        };
        if let Some(uid) = self.directory.snapshot_client_uid(self_id)
            && tsclient_rs::avatar_file_name(&uid).is_ok()
        {
            return Ok(uid);
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
        // 上传已确认成功，负缓存与冷却不应再阻止读取。
        self.media.clear_avatar_failure_state(uid);
        let unchanged = matches!(self.media.avatar_hash(uid), Some(Some(hash)) if hash == &md5);
        if unchanged {
            // 同图重传时 hash 不变，仍要清旧缓存并广播一次让 UI 重新读取新写入的缓存。
            if let Some(server_id) = self.active_server_id.clone() {
                self.media.avatar_disk.remove_uid(
                    self.store_path.clone(),
                    server_id,
                    uid.to_owned(),
                );
            }
            self.media.bump_avatar_revision(uid);
            self.emit(SessionEvent::AvatarUpdated {
                uid: uid.to_owned(),
            });
        } else {
            // 先应用 hash 让 record_avatar_hash 清旧缓存并广播；再入队 save，
            // 磁盘队列顺序为 remove -> save，后续 load_hit 能命中新图。
            self.record_avatar_hash(uid, Some(md5.clone()), true);
        }
        self.media
            .avatar_disk
            .save_self_snapshot(self.store_path.clone(), bytes.clone());
        if let Some(server_id) = self.active_server_id.clone() {
            self.media.avatar_disk.save(
                self.store_path.clone(),
                server_id,
                uid.to_owned(),
                Some(md5),
                bytes,
            );
        }
    }

    fn apply_avatar_delete(&mut self, uid: &str) {
        // 删除结果已由服务器确认，负缓存与冷却不应再阻止后续读取。
        self.media.clear_avatar_failure_state(uid);
        self.media
            .avatar_disk
            .clear_self_snapshot(self.store_path.clone());
        self.record_avatar_hash(uid, None, true);
    }
}

fn known_avatar_limit(limit: Option<i32>) -> Option<u64> {
    match limit {
        Some(value) if value > 0 => Some((value as u64).min(crate::media::MAX_AVATAR_BYTES as u64)),
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

    const SELF_AVATAR_PNG: [u8; 16] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44,
        0x52,
    ];

    fn install_self_client(actor: &mut Actor, uid: &str) {
        actor.self_client_id = Some(1);
        actor.directory.set_snapshot_for_test(
            Vec::new(),
            vec![ClientView::from(ClientInfo {
                uid: uid.to_string(),
                ..client_info(1, 5, "Self")
            })],
        );
    }

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
                    Err(ImageFetchError::Permanent(SessionError::NotConnected))
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
            actor.media.enqueue_image("/avatar_test", reply, 0);
            replies.push(result);
        }
        let (reply, result) = oneshot::channel();
        actor.media.enqueue_image("/avatar_test", reply, 0);
        assert!(matches!(
            result.await.unwrap(),
            Err(ImageFetchError::Transient(ImageTransientReason::QueueFull))
        ));
        actor.invalidate_handlers();
        assert!(actor.media.pending_images.is_empty());
        for result in replies {
            assert!(matches!(
                result.await.unwrap(),
                Err(ImageFetchError::Permanent(SessionError::NotConnected))
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
                    actor.media.fetching_server_icon,
                    Some((actor.connection_epoch, "127.0.0.1:9987".into(), 12345))
                );
                assert_eq!(actor.media.pending_images.len(), 1);
                let pending = actor.media.pending_images.pop_front().unwrap();
                assert_eq!(pending.remote_path, "/icon_12345");
                let _ = pending.reply.send(Ok(vec![137, 80, 78, 71]));
                let signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(signal).await;

                assert!(actor.media.fetching_server_icon.is_none());
                assert_eq!(
                    actor.media.icons.server_icon_id("127.0.0.1:9987"),
                    Some(12345)
                );

                // 重复收到相同 icon_id 不重复入队
                actor.sync_server_icon("127.0.0.1:9987".into(), Some(12345));
                assert!(actor.media.pending_images.is_empty());

                // 收到 None 时保留已有缓存
                actor.sync_server_icon("127.0.0.1:9987".into(), None);
                assert!(actor.media.icons.server_icon_id("127.0.0.1:9987").is_some());

                // 收到 Some(0) 时清除缓存并广播清除事件
                actor
                    .handle_signal(SessionSignal::ServerInfoUpdated {
                        epoch: actor.connection_epoch,
                        icon_id: Some(0),
                    })
                    .await;
                assert!(actor.media.icons.server_icon_id("127.0.0.1:9987").is_none());
                assert!(
                    crate::media::IconCache::load(&actor.store_path, &["127.0.0.1:9987"])
                        .is_empty()
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
                assert_eq!(actor.media.pending_images.len(), 1);
                let pending = actor.media.pending_images.pop_front().unwrap();
                assert_eq!(pending.remote_path, "/icon_777");
                let _ = pending.reply.send(Ok(vec![1, 2, 3, 4]));
                let signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(signal).await;

                assert_eq!(rx_a.await.unwrap().unwrap(), vec![1, 2, 3, 4]);
                assert_eq!(rx_b.await.unwrap().unwrap(), vec![1, 2, 3, 4]);

                // 同服再次请求直接命中磁盘缓存，不再入队
                let (reply_hit, rx_hit) = oneshot::channel();
                actor.fetch_channel_icon(777, reply_hit);
                assert!(actor.media.pending_images.is_empty());
                assert_eq!(rx_hit.await.unwrap().unwrap(), vec![1, 2, 3, 4]);

                // 切服后相同 icon_id 不串图，重新入队拉取
                actor.active_server_id = Some("b.example:9987".into());
                let (reply_other, rx_other) = oneshot::channel();
                actor.fetch_channel_icon(777, reply_other);
                assert_eq!(actor.media.pending_images.len(), 1);
                let pending_other = actor.media.pending_images.pop_front().unwrap();
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
                    assert!(actor.media.pending_images.is_empty());
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
                actor.media.avatar_disk.flush().await;
                let disk_signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(disk_signal).await;

                assert_eq!(actor.media.pending_images.len(), 1);
                let pending = actor.media.pending_images.pop_front().unwrap();
                assert_eq!(
                    pending.remote_path,
                    tsclient_rs::avatar_file_name(&ts6_uid).unwrap()
                );
                let _ = pending.reply.send(Ok(vec![10, 20, 30]));
                let fetched_signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(fetched_signal).await;
                actor.media.avatar_disk.flush().await;

                assert_eq!(rx_a.await.unwrap().unwrap(), Some(vec![10, 20, 30]));
                assert_eq!(rx_b.await.unwrap().unwrap(), Some(vec![10, 20, 30]));

                // 同服再次请求直接命中磁盘缓存，不再发起传输
                let (reply_hit, rx_hit) = oneshot::channel();
                actor.fetch_avatar(ts6_uid.clone(), reply_hit);
                actor.media.avatar_disk.flush().await;
                let hit_signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(hit_signal).await;
                assert!(actor.media.pending_images.is_empty());
                assert_eq!(rx_hit.await.unwrap().unwrap(), Some(vec![10, 20, 30]));

                // 未知 hash 时退回无 hash 路径落盘并命中
                let (reply_fb, rx_fb) = oneshot::channel();
                actor.fetch_avatar(fallback_uid.clone(), reply_fb);
                actor.media.avatar_disk.flush().await;
                let fb_disk_signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(fb_disk_signal).await;
                let fb_pending = actor.media.pending_images.pop_front().unwrap();
                let _ = fb_pending.reply.send(Ok(vec![55, 66]));
                let fb_fetched = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(fb_fetched).await;
                actor.media.avatar_disk.flush().await;
                assert_eq!(rx_fb.await.unwrap().unwrap(), Some(vec![55, 66]));
                assert_eq!(
                    crate::media::load_avatar_hit(
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
                crate::media::save_avatar(
                    &actor.store_path,
                    "a.example:9987",
                    &uid,
                    Some("h1"),
                    &[1],
                )
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
                    crate::media::load_avatar_hit(
                        &actor.store_path,
                        "a.example:9987",
                        &uid,
                        Some("h1")
                    ),
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
                actor.media.avatar_disk.flush().await;
                assert_eq!(drain_avatar_updates(&mut events), vec![uid.clone()]);
                assert_eq!(
                    crate::media::load_avatar_hit(
                        &actor.store_path,
                        "a.example:9987",
                        &uid,
                        Some("h1")
                    ),
                    None
                );

                // 4. 写入新 h2 后通过 ClientUpdated 清空为 None：清理 h2 磁盘缓存并广播 AvatarUpdated
                crate::media::save_avatar(
                    &actor.store_path,
                    "a.example:9987",
                    &uid,
                    Some("h2"),
                    &[2],
                )
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
                actor.media.avatar_disk.flush().await;
                assert_eq!(drain_avatar_updates(&mut events), vec![uid.clone()]);
                assert_eq!(
                    crate::media::load_avatar_hit(
                        &actor.store_path,
                        "a.example:9987",
                        &uid,
                        Some("h2")
                    ),
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
        assert_eq!(actor.media.avatar_hashes.get(unknown_uid), Some(&None));
        assert!(events.try_recv().is_err());

        actor.sync_avatar_hash_from_join("hashed-uid", Some("hash".into()));
        assert_eq!(
            actor.media.avatar_hashes.get("hashed-uid"),
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
                actor.media.avatar_negative_cache.insert(uid.to_string());

                actor.apply_avatar_upload(uid, md5.into(), vec![7, 8, 9]);
                actor.media.avatar_disk.flush().await;
                assert!(!actor.media.avatar_negative_cache.contains(uid));

                assert_eq!(
                    crate::media::load_avatar_hit(
                        &actor.store_path,
                        "a.example:9987",
                        uid,
                        Some(md5)
                    ),
                    Some(vec![7, 8, 9])
                );
                assert!(matches!(
                    events.try_recv(),
                    Ok(SessionEvent::AvatarUpdated { uid: ref updated }) if updated == uid
                ));

                // 服务器回显相同 hash：不重复广播，也不删除刚写入的缓存
                actor.record_avatar_hash(uid, Some(md5.into()), true);
                actor.media.avatar_disk.flush().await;
                assert!(events.try_recv().is_err());
                assert_eq!(
                    crate::media::load_avatar_hit(
                        &actor.store_path,
                        "a.example:9987",
                        uid,
                        Some(md5)
                    ),
                    Some(vec![7, 8, 9])
                );

                // 显式重传同一张图仍刷新一次 UI
                actor.apply_avatar_upload(uid, md5.into(), vec![7, 8, 9]);
                actor.media.avatar_disk.flush().await;
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
                actor.media.avatar_disk.load_hit(
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
                actor.media.avatar_disk.flush().await;
                let _ = events.try_recv();
                actor.media.avatar_negative_cache.insert(uid.to_string());

                actor.apply_avatar_delete(uid);
                actor.media.avatar_disk.flush().await;
                assert!(matches!(
                    events.try_recv(),
                    Ok(SessionEvent::AvatarUpdated { uid: ref updated }) if updated == uid
                ));
                assert!(!actor.media.avatar_negative_cache.contains(uid));
                assert_eq!(
                    crate::media::load_avatar_hit(
                        &actor.store_path,
                        "a.example:9987",
                        uid,
                        Some(md5)
                    ),
                    None
                );

                actor.apply_avatar_delete(uid);
                actor.media.avatar_disk.flush().await;
                assert!(events.try_recv().is_err());

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    #[tokio::test]
    async fn self_avatar_upload_saves_snapshot_and_delete_clears_it() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-self-avatar-upload-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.active_server_id = Some("a.example:9987".into());
                let uid = "self-avatar-uid";

                actor.apply_avatar_upload(
                    uid,
                    "0123456789abcdef0123456789abcdef".into(),
                    SELF_AVATAR_PNG.to_vec(),
                );
                actor.media.avatar_disk.flush().await;
                assert_eq!(
                    crate::media::load_self_avatar_snapshot(&actor.store_path),
                    Some(SELF_AVATAR_PNG.to_vec())
                );

                actor.apply_avatar_delete(uid);
                actor.media.avatar_disk.flush().await;
                assert_eq!(
                    crate::media::load_self_avatar_snapshot(&actor.store_path),
                    None
                );

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    #[tokio::test]
    async fn fetched_self_avatar_updates_snapshot_and_disconnect_keeps_it() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-self-avatar-fetch-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.active_server_id = Some("a.example:9987".into());
                let uid = "self-avatar-uid";
                install_self_client(&mut actor, uid);

                let (reply, rx) = oneshot::channel();
                actor.media.in_flight_avatars.insert(
                    (
                        actor.connection_epoch,
                        "a.example:9987".into(),
                        uid.into(),
                        0,
                    ),
                    vec![reply],
                );
                actor.handle_avatar_fetched(AvatarFetchOutcome {
                    epoch: actor.connection_epoch,
                    server_id: "a.example:9987".into(),
                    uid: uid.into(),
                    revision: 0,
                    avatar_hash: Some("h1".into()),
                    remote_path: "/avatar_self".into(),
                    attempt: 0,
                    result: Ok(SELF_AVATAR_PNG.to_vec()),
                });
                actor.media.avatar_disk.flush().await;
                assert_eq!(rx.await.unwrap().unwrap(), Some(SELF_AVATAR_PNG.to_vec()));
                assert_eq!(
                    crate::media::load_self_avatar_snapshot(&actor.store_path),
                    Some(SELF_AVATAR_PNG.to_vec())
                );

                actor.media.reset_avatar_session_state();
                actor.media.avatar_disk.flush().await;
                assert_eq!(
                    crate::media::load_self_avatar_snapshot(&actor.store_path),
                    Some(SELF_AVATAR_PNG.to_vec())
                );

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    #[tokio::test]
    async fn self_avatar_disk_hit_writes_snapshot_and_missing_fetch_keeps_it() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-self-avatar-hit-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.active_server_id = Some("a.example:9987".into());
                let uid = "self-avatar-uid";
                install_self_client(&mut actor, uid);

                let (reply, rx) = oneshot::channel();
                actor.media.in_flight_avatars.insert(
                    (
                        actor.connection_epoch,
                        "a.example:9987".into(),
                        uid.into(),
                        0,
                    ),
                    vec![reply],
                );
                actor.handle_avatar_disk_loaded(AvatarDiskLoad {
                    epoch: actor.connection_epoch,
                    server_id: "a.example:9987".into(),
                    uid: uid.into(),
                    revision: 0,
                    avatar_hash: Some("h1".into()),
                    remote_path: "/avatar_self".into(),
                    bytes: Some(SELF_AVATAR_PNG.to_vec()),
                });
                actor.media.avatar_disk.flush().await;
                assert_eq!(rx.await.unwrap().unwrap(), Some(SELF_AVATAR_PNG.to_vec()));
                assert_eq!(
                    crate::media::load_self_avatar_snapshot(&actor.store_path),
                    Some(SELF_AVATAR_PNG.to_vec())
                );

                let (reply, rx) = oneshot::channel();
                actor.media.in_flight_avatars.insert(
                    (
                        actor.connection_epoch,
                        "a.example:9987".into(),
                        uid.into(),
                        0,
                    ),
                    vec![reply],
                );
                actor.handle_avatar_fetched(AvatarFetchOutcome {
                    epoch: actor.connection_epoch,
                    server_id: "a.example:9987".into(),
                    uid: uid.into(),
                    revision: 0,
                    avatar_hash: Some("h1".into()),
                    remote_path: "/avatar_self".into(),
                    attempt: 0,
                    result: Err(ImageFetchError::NotFound("gone".into())),
                });
                actor.media.avatar_disk.flush().await;
                assert!(rx.await.unwrap().unwrap().is_none());
                assert_eq!(
                    crate::media::load_self_avatar_snapshot(&actor.store_path),
                    Some(SELF_AVATAR_PNG.to_vec())
                );

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

                // 瞬态超时错误不进入负缓存，向调用方返回 Err 并受服务端/Actor 30 秒冷却保护。
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
                assert_eq!(calls.load(Ordering::SeqCst), 6);

                // 不应落盘任何负缓存文件
                assert!(!temp.join("avatars").exists());

                // 收到 avatar_hash 更新后，负缓存被清除并广播 AvatarUpdated
                commands.send(SessionCommand::Shutdown).unwrap();
                task.await.unwrap();

                // 用独立 Actor 验证更新事件与重连清除负缓存
                let mut actor = audio_actor();
                actor.active_server_id = Some("127.0.0.1:9987".into());
                let mut events = actor.events.subscribe();
                actor
                    .media
                    .avatar_negative_cache
                    .insert(uid_not_found.clone());
                actor.media.avatar_negative_cache.insert(uid_perm.clone());

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
                assert!(!actor.media.avatar_negative_cache.contains(&uid_not_found));
                assert!(actor.media.avatar_negative_cache.contains(&uid_perm));
                assert!(matches!(
                    events.try_recv(),
                    Ok(SessionEvent::AvatarUpdated { uid: ref updated }) if updated == &uid_not_found
                ));

                // 重连失效清理全部会话级负缓存与状态
                actor.invalidate_handlers();
                assert!(actor.media.avatar_negative_cache.is_empty());
                assert!(actor.media.avatar_cooldowns.is_empty());
                assert!(actor.media.avatar_hashes.is_empty());

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    #[test]
    fn channel_icon_retry_delay_classifies_transient_vs_permanent_and_enforces_cap() {
        for attempt in 0..MAX_CHANNEL_ICON_RETRIES {
            let expected = CHANNEL_ICON_RETRY_STEP * u32::from(attempt + 1);
            assert_eq!(
                channel_icon_retry_delay(
                    attempt,
                    &ImageFetchError::Transient(ImageTransientReason::QueueFull)
                ),
                Some(expected)
            );
            assert_eq!(
                channel_icon_retry_delay(
                    attempt,
                    &ImageFetchError::Transient(ImageTransientReason::Interrupted)
                ),
                Some(expected)
            );
            assert_eq!(
                channel_icon_retry_delay(
                    attempt,
                    &ImageFetchError::Transient(ImageTransientReason::ServerBusy("flood".into()))
                ),
                Some(expected)
            );
        }
        assert_eq!(
            channel_icon_retry_delay(
                MAX_CHANNEL_ICON_RETRIES,
                &ImageFetchError::Transient(ImageTransientReason::QueueFull)
            ),
            None
        );
        assert_eq!(
            channel_icon_retry_delay(
                0,
                &ImageFetchError::Transient(ImageTransientReason::Timeout)
            ),
            None
        );
        assert_eq!(
            channel_icon_retry_delay(0, &ImageFetchError::NotFound("missing".into())),
            None
        );
        assert_eq!(
            channel_icon_retry_delay(0, &ImageFetchError::PermissionDenied("denied".into())),
            None
        );
        assert_eq!(
            channel_icon_retry_delay(
                0,
                &ImageFetchError::Permanent(SessionError::Transfer("truncated".into()))
            ),
            None
        );
    }

    #[tokio::test]
    async fn channel_icon_retries_transient_errors_with_linear_backoff_and_stops_on_permanent_or_cap()
     {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-icon-backoff-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.active_server_id = Some("a.example:9987".into());

                // 1. Transient queue-full error schedules attempt 1 after 300ms backoff and then succeeds.
                let (reply, mut rx) = oneshot::channel();
                actor.fetch_channel_icon(101, reply);
                let pending = actor.media.pending_images.pop_front().unwrap();
                let _ = pending.reply.send(Err(ImageFetchError::Transient(
                    ImageTransientReason::QueueFull,
                )));
                let signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(signal).await;
                assert!(actor.media.pending_images.is_empty());
                assert!(rx.try_recv().is_err());

                let retry_signal =
                    tokio::time::timeout(Duration::from_millis(800), actor.signal_rx.recv())
                        .await
                        .unwrap()
                        .unwrap();
                assert!(matches!(
                    retry_signal,
                    SessionSignal::RetryChannelIcon {
                        icon_id: 101,
                        attempt: 1,
                        ..
                    }
                ));
                actor.handle_signal(retry_signal).await;
                let pending = actor.media.pending_images.pop_front().unwrap();
                let _ = pending.reply.send(Ok(vec![7, 7, 7]));
                let signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(signal).await;
                assert_eq!(rx.await.unwrap().unwrap(), vec![7, 7, 7]);

                // 2. Permanent errors fail immediately without scheduling retries.
                let (reply_perm, rx_perm) = oneshot::channel();
                actor.fetch_channel_icon(202, reply_perm);
                let pending = actor.media.pending_images.pop_front().unwrap();
                let _ = pending
                    .reply
                    .send(Err(ImageFetchError::PermissionDenied("denied".into())));
                let signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(signal).await;
                assert!(rx_perm.await.unwrap().is_err());
                assert!(actor.signal_rx.try_recv().is_err());

                // 3. Reaching MAX_CHANNEL_ICON_RETRIES surfaces the failure instead of scheduling another retry.
                let (reply_cap, rx_cap) = oneshot::channel();
                actor.media.in_flight_channel_icons.insert(
                    (actor.connection_epoch, "a.example:9987".into(), 303),
                    vec![reply_cap],
                );
                actor.handle_channel_icon_fetched(
                    actor.connection_epoch,
                    "a.example:9987".into(),
                    303,
                    MAX_CHANNEL_ICON_RETRIES,
                    Err(ImageFetchError::Transient(
                        ImageTransientReason::ServerBusy("524 flood".into()),
                    )),
                );
                assert!(matches!(
                    rx_cap.await.unwrap(),
                    Err(SessionError::Protocol(msg)) if msg.contains("524 flood")
                ));

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    #[tokio::test]
    async fn avatar_retries_transient_queue_errors_and_enforces_30s_three_attempt_cooldown_cleared_by_update_or_reconnect()
     {
        tokio::task::LocalSet::new()
            .run_until(async {
                let temp = std::env::temp_dir().join(format!(
                    "flspeak-actor-avatar-cooldown-{:x}",
                    rand::random::<u64>()
                ));
                let _ = std::fs::create_dir_all(&temp);
                let mut actor = audio_actor();
                actor.store_path = temp.join("preferences.json");
                actor.active_server_id = Some("a.example:9987".into());

                let uid_transient = base64::engine::general_purpose::STANDARD.encode([21u8; 20]);
                let uid_cooldown = base64::engine::general_purpose::STANDARD.encode([22u8; 20]);

                // 1. Prompt 500ms retry recovers from QueueFull without recording cooldown failures.
                let (reply, mut rx) = oneshot::channel();
                actor.fetch_avatar(uid_transient.clone(), reply);
                actor.media.avatar_disk.flush().await;
                let disk_signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(disk_signal).await;

                let pending = actor.media.pending_images.pop_front().unwrap();
                let _ = pending.reply.send(Err(ImageFetchError::Transient(
                    ImageTransientReason::QueueFull,
                )));
                let fetched = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(fetched).await;
                assert!(rx.try_recv().is_err());

                let retry_signal =
                    tokio::time::timeout(Duration::from_secs(1), actor.signal_rx.recv())
                        .await
                        .unwrap()
                        .unwrap();
                actor.handle_signal(retry_signal).await;
                let pending = actor.media.pending_images.pop_front().unwrap();
                let _ = pending.reply.send(Ok(vec![11, 22, 33]));
                let fetched = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(fetched).await;
                assert_eq!(rx.await.unwrap().unwrap(), Some(vec![11, 22, 33]));
                assert!(!actor.media.avatar_cooldowns.contains_key(&uid_transient));

                // 2. Three failure attempts trigger ~30s cooldowns and then stop until AvatarUpdated or reconnect.
                for attempt in 1..=MAX_AVATAR_FAILURE_ATTEMPTS {
                    let (reply, rx) = oneshot::channel();
                    actor.fetch_avatar(uid_cooldown.clone(), reply);
                    actor.media.avatar_disk.flush().await;
                    let disk_signal = actor.signal_rx.recv().await.unwrap();
                    actor.handle_signal(disk_signal).await;
                    let pending = actor.media.pending_images.pop_front().unwrap();
                    let _ = pending.reply.send(Err(ImageFetchError::Transient(
                        ImageTransientReason::Timeout,
                    )));
                    let fetched = actor.signal_rx.recv().await.unwrap();
                    actor.handle_signal(fetched).await;
                    assert!(matches!(rx.await.unwrap(), Err(SessionError::Timeout)));

                    {
                        let cooldown = actor.media.avatar_cooldowns.get(&uid_cooldown).unwrap();
                        assert_eq!(cooldown.attempts, attempt);
                        if attempt < MAX_AVATAR_FAILURE_ATTEMPTS {
                            let remaining = cooldown
                                .retry_not_before
                                .unwrap()
                                .saturating_duration_since(tokio::time::Instant::now());
                            assert!(remaining > Duration::from_secs(20));
                        } else {
                            assert!(cooldown.retry_not_before.is_none());
                        }
                    }

                    // During cooldown (or after attempt 3), immediate fetch returns error without disk/network IO.
                    let (reply_blocked, rx_blocked) = oneshot::channel();
                    actor.fetch_avatar(uid_cooldown.clone(), reply_blocked);
                    assert!(actor.media.pending_images.is_empty());
                    assert!(matches!(
                        rx_blocked.await.unwrap(),
                        Err(SessionError::Timeout)
                    ));

                    if attempt < MAX_AVATAR_FAILURE_ATTEMPTS {
                        actor
                            .media
                            .avatar_cooldowns
                            .get_mut(&uid_cooldown)
                            .unwrap()
                            .retry_not_before =
                            Some(tokio::time::Instant::now() - Duration::from_millis(1));
                    }
                }

                // After 3 attempts, cooldown stays locked permanently until update or reconnect.
                let (reply_locked, rx_locked) = oneshot::channel();
                actor.fetch_avatar(uid_cooldown.clone(), reply_locked);
                assert!(actor.media.pending_images.is_empty());
                assert!(matches!(
                    rx_locked.await.unwrap(),
                    Err(SessionError::Timeout)
                ));

                // AvatarUpdated clears cooldown so the next fetch proceeds cleanly.
                actor
                    .handle_signal(SessionSignal::ClientUpdated {
                        epoch: actor.connection_epoch,
                        id: 4,
                        uid: uid_cooldown.clone(),
                        channel_id: 5,
                        input_muted: None,
                        output_muted: None,
                        away: None,
                        away_message: None,
                        server_groups: Vec::new(),
                        avatar_hash: Some("fresh_after_cooldown".into()),
                    })
                    .await;
                assert!(!actor.media.avatar_cooldowns.contains_key(&uid_cooldown));

                let (reply_after_update, rx_after_update) = oneshot::channel();
                actor.fetch_avatar(uid_cooldown.clone(), reply_after_update);
                actor.media.avatar_disk.flush().await;
                let disk_signal = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(disk_signal).await;
                let pending = actor.media.pending_images.pop_front().unwrap();
                let _ = pending.reply.send(Ok(vec![55]));
                let fetched = actor.signal_rx.recv().await.unwrap();
                actor.handle_signal(fetched).await;
                assert_eq!(rx_after_update.await.unwrap().unwrap(), Some(vec![55]));

                // Reconnect / invalidate_handlers also clears cooldowns.
                actor.media.avatar_cooldowns.insert(
                    uid_cooldown.clone(),
                    AvatarCooldown {
                        attempts: 3,
                        retry_not_before: None,
                        last_error: SessionError::Timeout,
                    },
                );
                actor.invalidate_handlers();
                assert!(actor.media.avatar_cooldowns.is_empty());

                let _ = std::fs::remove_dir_all(&temp);
            })
            .await;
    }

    #[tokio::test]
    async fn media_state_reset_on_disconnect_drains_waiters_and_clears_session_state() {
        let mut media = MediaTransferState::new(&PathBuf::new(), &[]);

        let (active_tx, active_rx) = oneshot::channel();
        media.set_active_image(ActiveImage {
            remote_path: "/icon_1".into(),
            negotiation: Box::pin(std::future::pending()),
            reply: active_tx,
            preempt_retries: 1,
        });
        let (pending_tx, pending_rx) = oneshot::channel();
        media.enqueue_image("/icon_2", pending_tx, 0);
        let (chan_tx, chan_rx) = oneshot::channel();
        assert!(media.register_channel_icon_waiter((1, "srv".into(), 10), chan_tx));
        let (avatar_tx, avatar_rx) = oneshot::channel();
        assert!(media.register_avatar_waiter((1, "srv".into(), "u1".into(), 0), avatar_tx));

        media.active_server_icon_id = Some(42);
        media.fetching_server_icon = Some((1, "srv".into(), 42));
        assert!(media.record_avatar_hash("u1", Some("h1".into()), true));
        media.mark_avatar_not_found("u2".into());
        media.avatars_fetched_without_hash.insert("u3".into());
        media.record_avatar_failure_cooldown(
            "u4",
            &SessionError::Timeout,
            tokio::time::Instant::now(),
        );

        media.reset_on_disconnect();

        assert!(matches!(
            active_rx.await.unwrap(),
            Err(ImageFetchError::Permanent(SessionError::NotConnected))
        ));
        assert!(matches!(
            pending_rx.await.unwrap(),
            Err(ImageFetchError::Permanent(SessionError::NotConnected))
        ));
        assert!(matches!(
            chan_rx.await.unwrap(),
            Err(SessionError::NotConnected)
        ));
        assert!(matches!(
            avatar_rx.await.unwrap(),
            Err(SessionError::NotConnected)
        ));
        assert!(media.active_image.is_none());
        assert!(media.pending_images.is_empty());
        assert!(media.in_flight_channel_icons.is_empty());
        assert!(media.in_flight_avatars.is_empty());
        assert!(media.active_server_icon_id.is_none());
        assert!(media.fetching_server_icon.is_none());
        assert!(media.avatar_hashes.is_empty());
        assert!(media.avatar_negative_cache.is_empty());
        assert!(media.avatar_cooldowns.is_empty());
        assert!(media.avatar_revisions.is_empty());
        assert!(media.avatars_fetched_without_hash.is_empty());
    }

    #[tokio::test]
    async fn media_state_image_queue_capacity_and_interrupt_preempt_retries() {
        let mut media = MediaTransferState::new(&PathBuf::new(), &[]);
        let mut rxs = Vec::new();
        for i in 0..IMAGE_QUEUE_CAPACITY {
            let (tx, rx) = oneshot::channel();
            media.enqueue_image(&format!("/img_{i}"), tx, 1);
            rxs.push(rx);
        }
        let (overflow_tx, overflow_rx) = oneshot::channel();
        media.enqueue_image("/img_overflow", overflow_tx, 0);
        assert!(matches!(
            overflow_rx.await.unwrap(),
            Err(ImageFetchError::Transient(ImageTransientReason::QueueFull))
        ));

        let first = media.pop_next_image().unwrap();
        assert_eq!(first.remote_path, "/img_0");
        media.set_active_image(ActiveImage {
            remote_path: first.remote_path,
            negotiation: Box::pin(std::future::pending()),
            reply: first.reply,
            preempt_retries: first.preempt_retries,
        });
        media.interrupt_active_image();
        assert!(media.active_image.is_none());
        assert_eq!(media.pending_images.len(), IMAGE_QUEUE_CAPACITY);

        let requeued = media.pending_images.pop_back().unwrap();
        assert_eq!(requeued.remote_path, "/img_0");
        assert_eq!(requeued.preempt_retries, 0);
        media.set_active_image(ActiveImage {
            remote_path: requeued.remote_path,
            negotiation: Box::pin(std::future::pending()),
            reply: requeued.reply,
            preempt_retries: requeued.preempt_retries,
        });
        media.interrupt_active_image();
        assert!(media.active_image.is_none());
        assert!(matches!(
            rxs.remove(0).await.unwrap(),
            Err(ImageFetchError::Transient(
                ImageTransientReason::Interrupted
            ))
        ));
    }

    #[test]
    fn media_state_avatar_hash_transitions_and_cooldown_progression() {
        let mut media = MediaTransferState::new(&PathBuf::new(), &[]);

        assert!(!media.record_avatar_hash("", Some("h".into()), true));
        assert!(!media.record_avatar_hash("u1", None, true));
        assert_eq!(media.avatar_hash("u1"), Some(&None));
        assert_eq!(media.avatar_revision("u1"), 0);

        assert!(media.record_avatar_hash("u1", Some("h1".into()), false));
        assert_eq!(media.avatar_revision("u1"), 1);
        assert!(!media.record_avatar_hash("u1", Some("h1".into()), true));
        assert_eq!(media.avatar_revision("u1"), 1);

        media.avatars_fetched_without_hash.insert("u2".into());
        assert!(media.record_avatar_hash("u2", None, false));
        assert_eq!(media.avatar_revision("u2"), 1);

        media.mark_avatar_not_found("u3".into());
        assert!(!media.record_avatar_hash("u3", None, false));
        assert!(media.record_avatar_hash("u3", Some("h3".into()), false));
        assert!(!media.avatar_negative_cache.contains("u3"));

        let now = tokio::time::Instant::now();
        media.record_avatar_failure_cooldown("u4", &SessionError::Timeout, now);
        assert!(matches!(
            media.active_avatar_cooldown_error("u4", now + Duration::from_secs(10)),
            Some(SessionError::Timeout)
        ));
        assert!(
            media
                .active_avatar_cooldown_error("u4", now + AVATAR_FAILURE_COOLDOWN)
                .is_none()
        );

        media.record_avatar_failure_cooldown("u4", &SessionError::Timeout, now);
        assert!(matches!(
            media.active_avatar_cooldown_error("u4", now + Duration::from_secs(10)),
            Some(SessionError::Timeout)
        ));

        media.record_avatar_failure_cooldown("u4", &SessionError::Timeout, now);
        assert!(matches!(
            media.active_avatar_cooldown_error("u4", now + Duration::from_secs(3_600)),
            Some(SessionError::Timeout)
        ));
    }
}
