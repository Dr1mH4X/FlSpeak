use super::*;
use crate::streams;

/// TeamSpeak 的 “command not found”：服务器不支持 TS6 屏幕共享命令。
const COMMAND_NOT_FOUND: &str = "256";
const STREAM_PROBE_TIMEOUT_MS: u64 = 5_000;

impl Actor {
    /// 流目录与本地推流都跟随自己所在的频道。频道变了就作废旧目录、退出观看流并停止推流，再在新频道里发现。
    pub(super) async fn sync_stream_channel(&mut self) {
        let channel = self.self_channel_id;
        if self.streams.channel() == channel {
            return;
        }
        let watched = self.streams.watching().map(|(id, _)| id.to_string());
        let published = self.streams.published_stream_id().map(str::to_string);
        let events = self.streams.reset(channel, StreamEndReason::SelfMoved);
        self.emit_all(events);
        if let Some(stream_id) = watched {
            self.leave_stream_best_effort(&stream_id).await;
        }
        if let Some(stream_id) = published {
            self.stop_stream_best_effort(&stream_id).await;
        }
        if channel != 0 {
            self.discover_streams().await;
        }
    }

    /// 断线时只清本地状态：连接已不可用，服务器会自己回收观看关系。
    pub(super) fn reset_streams(&mut self, reason: StreamEndReason) {
        let events = self.streams.reset(0, reason);
        self.emit_all(events);
    }

    /// TS6 进频道时不重放已有的流，逐个问本频道成员。
    ///
    /// 第一条用带回执的命令探测服务器是否认识 `requeststreaminfo`；其余不等回执，
    /// 避免成员多时每人一个往返地卡住 actor。结果经 `notifystreaminfo` 回来。
    pub(super) async fn discover_streams(&mut self) {
        if !self.streams_supported {
            return;
        }
        let Some(client) = self.client.clone() else {
            return;
        };
        let targets = self.channel_peers(self.streams.channel());
        for (index, clid) in targets.into_iter().enumerate() {
            let command = format!("requeststreaminfo clid={clid}");
            if index == 0 {
                match client.exec_command(&command, STREAM_PROBE_TIMEOUT_MS).await {
                    Ok(()) => {}
                    Err(tsclient_rs::Error::ServerError { id, .. }) if id == COMMAND_NOT_FOUND => {
                        self.streams_supported = false;
                        self.emit(SessionEvent::Log {
                            level: "info".into(),
                            message: "服务器不支持 TS6 屏幕共享".into(),
                        });
                        return;
                    }
                    Err(err) => self.emit(SessionEvent::Log {
                        level: "debug".into(),
                        message: format!("查询客户端 {clid} 的屏幕共享失败: {err}"),
                    }),
                }
            } else if let Err(err) = client.send_command_no_wait(&command).await {
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("屏幕共享发现中断: {err}"),
                });
                return;
            }
        }
    }

    pub(super) async fn query_stream_info(&self, clid: i32) {
        if !self.streams_supported {
            return;
        }
        let Some(client) = self.client.clone() else {
            return;
        };
        if let Err(err) = client
            .send_command_no_wait(&format!("requeststreaminfo clid={clid}"))
            .await
        {
            self.emit(SessionEvent::Log {
                level: "debug".into(),
                message: format!("查询客户端 {clid} 的屏幕共享失败: {err}"),
            });
        }
    }

    pub(super) async fn join_stream(
        &mut self,
        stream_id: String,
        source_clid: i32,
    ) -> Result<(), SessionError> {
        self.connected()?;
        let (previous, events) = self.streams.begin_join(&stream_id, source_clid)?;
        self.emit_all(events);
        if let Some(previous) = previous {
            self.leave_stream_best_effort(&previous).await;
        }
        let result = self
            .stream_command(
                "joinstreamrequest",
                &streams::join_request(&stream_id, source_clid),
            )
            .await;
        if result.is_err() {
            let events = self.streams.abandon_join(&stream_id);
            self.emit_all(events);
        }
        result
    }

    /// 本地状态先清掉再通知服务器，命令失败也不会留下悬空的观看状态。
    pub(super) async fn leave_stream(&mut self, stream_id: String) -> Result<(), SessionError> {
        let events = self.streams.leave(&stream_id)?;
        self.emit_all(events);
        self.send_stream_leave(&stream_id).await
    }

    async fn leave_stream_best_effort(&self, stream_id: &str) {
        if let Err(err) = self.send_stream_leave(stream_id).await {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("退出屏幕共享 {stream_id} 失败: {err}"),
            });
        }
    }

    async fn send_stream_leave(&self, stream_id: &str) -> Result<(), SessionError> {
        let self_clid = self.self_client_id.ok_or(SessionError::NotConnected)?;
        self.stream_command(
            "removeclientfromstream",
            &streams::leave_request(stream_id, self_clid),
        )
        .await
    }

    pub(super) async fn start_screen_share(
        &mut self,
        name: String,
        audio: bool,
        bitrate: u32,
        viewer_limit: u32,
    ) -> Result<(), SessionError> {
        self.connected()?;
        if self.self_channel_id == 0 {
            return Err(SessionError::NotInChannel);
        }
        let params = self
            .streams
            .start_publish(&name, audio, bitrate, viewer_limit)?;
        let result = self.stream_command("setupstream", &params).await;
        if result.is_err() {
            self.streams.rollback_publish();
        }
        result
    }

    pub(super) async fn stop_screen_share(&mut self) -> Result<(), SessionError> {
        let (active_stream_id, events) = self.streams.stop_publish();
        self.emit_all(events);
        if let Some(stream_id) = active_stream_id
            && self.client.is_some()
        {
            self.stream_command("stopstream", &streams::stop_stream_request(&stream_id))
                .await?;
        }
        Ok(())
    }

    pub(super) async fn stop_stream_best_effort(&self, stream_id: &str) {
        if let Err(err) = self
            .stream_command("stopstream", &streams::stop_stream_request(stream_id))
            .await
        {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("停止屏幕共享 {stream_id} 失败: {err}"),
            });
        }
    }

    pub(super) async fn respond_stream_join_request(
        &mut self,
        viewer_clid: i32,
        accept: bool,
        offer_sdp: String,
    ) -> Result<(), SessionError> {
        self.connected()?;
        let params = self
            .streams
            .respond_viewer_join(viewer_clid, accept, &offer_sdp)?;
        self.emit(SessionEvent::Log {
            level: "debug".into(),
            message: format!(
                "发送 respondjoinstreamrequest: 观众={viewer_clid}, accept={accept}, offer_sdp_len={}",
                offer_sdp.len()
            ),
        });
        let result = self
            .stream_command("respondjoinstreamrequest", &params)
            .await;
        if result.is_err() {
            self.streams.remove_viewer(viewer_clid);
        }
        result
    }

    pub(super) async fn send_publisher_ice_candidate(
        &self,
        viewer_clid: i32,
        sdp: String,
        mid: Option<String>,
        m_line: Option<i32>,
    ) -> Result<(), SessionError> {
        self.connected()?;
        let stream_id = self
            .streams
            .check_publisher_signal_target(viewer_clid)?
            .to_string();
        let payload = streams::ice_payload(&sdp, mid.as_deref(), m_line);
        self.stream_signaling(&stream_id, viewer_clid, payload)
            .await
    }

    pub(super) async fn kick_stream_viewer(
        &mut self,
        viewer_clid: i32,
    ) -> Result<(), SessionError> {
        self.connected()?;
        let (params, event) = self.streams.kick_viewer(viewer_clid)?;
        self.emit(event);
        self.stream_command("removeclientfromstream", &params).await
    }

    pub(super) async fn stream_signaling(
        &self,
        stream_id: &str,
        target_clid: i32,
        payload: String,
    ) -> Result<(), SessionError> {
        self.stream_command(
            "streamsignaling",
            &[
                ("id", stream_id.to_string()),
                ("clid", target_clid.to_string()),
                ("json", payload),
            ],
        )
        .await
    }

    async fn stream_command(
        &self,
        command: &str,
        params: &[(&'static str, String)],
    ) -> Result<(), SessionError> {
        let client = self.connected()?;
        let params: Vec<(&str, &str)> = params.iter().map(|(k, v)| (*k, v.as_str())).collect();
        client
            .send_raw_command(command, &params)
            .await
            .map_err(protocol_error)
    }

    fn channel_peers(&self, channel: u64) -> Vec<i32> {
        let mut peers = Vec::new();
        let mut seen = HashSet::new();
        if let Some(snapshot) = self
            .client
            .as_ref()
            .and_then(|client| client.directory_snapshot())
        {
            for row in snapshot.clients {
                if row.channel_id == channel
                    && Some(row.id) != self.self_client_id
                    && seen.insert(row.id)
                {
                    peers.push(row.id);
                }
            }
        }
        if let Some((_, clients)) = &self.last_snapshot {
            for row in clients {
                if row.channel_id == channel
                    && Some(row.id) != self.self_client_id
                    && seen.insert(row.id)
                {
                    peers.push(row.id);
                }
            }
        }
        peers
    }
}
