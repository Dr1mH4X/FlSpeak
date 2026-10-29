use crate::{SessionError, SessionEvent};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
};
use std::task::{Context, Poll};
use std::time::{Duration, Instant};
use tokio::io::AsyncWrite;
use tokio::sync::broadcast;
use tsclient_rs::FileDownloadInfo;
const TRANSFER_PROGRESS_BYTES: u64 = 256 * 1024;
const TRANSFER_PROGRESS_INTERVAL: Duration = Duration::from_millis(200);

pub(crate) async fn receive(
    host: String,
    info: FileDownloadInfo,
    destination: PathBuf,
    id: u64,
    events: broadcast::Sender<SessionEvent>,
    epoch: u64,
    current: Arc<AtomicU64>,
) -> Result<(), SessionError> {
    if destination
        .try_exists()
        .map_err(|error| SessionError::Transfer(error.to_string()))?
    {
        return Err(SessionError::Transfer("destination already exists".into()));
    }
    let staging =
        destination.with_file_name(format!(".flspeak-{:032x}.part", rand::random::<u128>()));
    let file = tokio::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&staging)
        .await
        .map_err(|error| SessionError::Transfer(error.to_string()))?;
    let transfer = async {
        let mut writer = ProgressWriter::new(file, id, info.size, events);
        tsclient_rs::downloadFileData(&host, &info, &mut writer)
            .await
            .map_err(crate::channel_tools::protocol_error)?;
        writer
            .inner
            .sync_all()
            .await
            .map_err(|error| SessionError::Transfer(error.to_string()))?;
        drop(writer);
        let link_result = tokio::fs::hard_link(&staging, &destination).await;
        finish_staging(&staging, &destination, link_result).await
    };
    let cancelled = async {
        while current.load(Ordering::SeqCst) == epoch {
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    };
    let outcome =
        tokio::select! {result=transfer=>result, ()=cancelled=>Err(SessionError::NotConnected)};
    let cleanup = match tokio::fs::remove_file(&staging).await {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(SessionError::Transfer(error.to_string())),
    };
    outcome.and(cleanup)
}

async fn finish_staging(
    staging: &Path,
    destination: &Path,
    link_result: std::io::Result<()>,
) -> Result<(), SessionError> {
    match link_result {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            Err(SessionError::Transfer(error.to_string()))
        }
        Err(_) => {
            if destination
                .try_exists()
                .map_err(|error| SessionError::Transfer(error.to_string()))?
            {
                return Err(SessionError::Transfer("destination already exists".into()));
            }
            tokio::fs::rename(staging, destination)
                .await
                .map_err(|error| SessionError::Transfer(error.to_string()))
        }
    }
}

/// 下载进度写入器。
struct ProgressWriter {
    inner: tokio::fs::File,
    id: u64,
    total: u64,
    transferred: u64,
    last_emit_bytes: u64,
    last_emit_at: Instant,
    events: broadcast::Sender<SessionEvent>,
}

impl ProgressWriter {
    fn new(
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

    fn record(&mut self, written: usize) {
        self.transferred += written as u64;
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

impl AsyncWrite for ProgressWriter {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        let this = self.get_mut();
        let poll = Pin::new(&mut this.inner).poll_write(cx, buf);
        if let Poll::Ready(Ok(written)) = &poll {
            this.record(*written);
        }
        poll
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_flush(cx)
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_shutdown(cx)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    async fn root() -> PathBuf {
        let path =
            std::env::temp_dir().join(format!("fls-download-test-{}", rand::random::<u64>()));
        tokio::fs::create_dir_all(&path).await.unwrap();
        path
    }
    async fn server(bytes: &'static [u8], size: u64) -> FileDownloadInfo {
        let socket = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = socket.local_addr().unwrap().port();
        tokio::spawn(async move {
            let (mut peer, _) = socket.accept().await.unwrap();
            let mut key = [0; 3];
            peer.read_exact(&mut key).await.unwrap();
            assert_eq!(&key, b"key");
            peer.write_all(bytes).await.unwrap();
        });
        FileDownloadInfo {
            client_file_transfer_id: 1,
            server_file_transfer_id: 1,
            file_transfer_key: "key".into(),
            port: port.into(),
            size,
        }
    }
    #[tokio::test]
    async fn complete_download_is_published_and_existing_file_is_preserved() {
        let root = root().await;
        let path = root.join("file.txt");
        let (events, _) = broadcast::channel(8);
        let current = Arc::new(AtomicU64::new(1));
        let info = server(b"verified bytes", 14).await;
        receive(
            "127.0.0.1".into(),
            info.clone(),
            path.clone(),
            1,
            events.clone(),
            1,
            current.clone(),
        )
        .await
        .unwrap();
        assert_eq!(tokio::fs::read(&path).await.unwrap(), b"verified bytes");
        assert!(
            receive(
                "127.0.0.1".into(),
                info,
                path.clone(),
                2,
                events,
                1,
                current
            )
            .await
            .is_err()
        );
        assert_eq!(tokio::fs::read(&path).await.unwrap(), b"verified bytes");
        let mut entries = tokio::fs::read_dir(&root).await.unwrap();
        assert!(entries.next_entry().await.unwrap().is_some());
        assert!(entries.next_entry().await.unwrap().is_none());
        tokio::fs::remove_dir_all(root).await.unwrap();
    }
    #[tokio::test]
    async fn truncated_download_leaves_no_destination_or_partial_file() {
        let root = root().await;
        let (events, _) = broadcast::channel(8);
        let info = server(b"short", 20).await;
        assert!(
            receive(
                "127.0.0.1".into(),
                info,
                root.join("file"),
                1,
                events,
                1,
                Arc::new(AtomicU64::new(1))
            )
            .await
            .is_err()
        );
        assert!(
            tokio::fs::read_dir(&root)
                .await
                .unwrap()
                .next_entry()
                .await
                .unwrap()
                .is_none()
        );
        tokio::fs::remove_dir_all(root).await.unwrap();
    }
    #[tokio::test]
    async fn changing_connection_epoch_cancels_and_removes_staging_file() {
        let root = root().await;
        let socket = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = socket.local_addr().unwrap().port();
        let current = Arc::new(AtomicU64::new(1));
        let update = current.clone();
        let peer = tokio::spawn(async move {
            let (mut peer, _) = socket.accept().await.unwrap();
            let mut key = [0; 3];
            peer.read_exact(&mut key).await.unwrap();
            update.store(2, Ordering::SeqCst);
            let mut end = [0; 1];
            assert_eq!(peer.read(&mut end).await.unwrap(), 0);
        });
        let info = FileDownloadInfo {
            client_file_transfer_id: 1,
            server_file_transfer_id: 1,
            file_transfer_key: "key".into(),
            port: port.into(),
            size: 100,
        };
        let (events, _) = broadcast::channel(8);
        assert!(matches!(
            receive(
                "127.0.0.1".into(),
                info,
                root.join("file"),
                1,
                events,
                1,
                current
            )
            .await,
            Err(SessionError::NotConnected)
        ));
        peer.await.unwrap();
        assert!(
            tokio::fs::read_dir(&root)
                .await
                .unwrap()
                .next_entry()
                .await
                .unwrap()
                .is_none()
        );
        tokio::fs::remove_dir_all(root).await.unwrap();
    }
    #[tokio::test]
    async fn finish_staging_falls_back_to_rename_when_hard_link_is_blocked() {
        let root = root().await;
        let staging = root.join(".flspeak-fallback.part");
        let destination = root.join("file.txt");
        tokio::fs::write(&staging, b"android fallback")
            .await
            .unwrap();
        finish_staging(
            &staging,
            &destination,
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)),
        )
        .await
        .unwrap();
        assert!(!staging.try_exists().unwrap());
        assert_eq!(
            tokio::fs::read(&destination).await.unwrap(),
            b"android fallback"
        );

        let second_staging = root.join(".flspeak-second.part");
        tokio::fs::write(&second_staging, b"overwrite attempt")
            .await
            .unwrap();
        assert!(
            finish_staging(
                &second_staging,
                &destination,
                Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)),
            )
            .await
            .is_err()
        );
        assert_eq!(
            tokio::fs::read(&destination).await.unwrap(),
            b"android fallback"
        );
        tokio::fs::remove_dir_all(root).await.unwrap();
    }
}
