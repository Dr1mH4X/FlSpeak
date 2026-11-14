use super::*;

const MAX_VOICE_QUEUE_DELAY: Duration = Duration::from_millis(100);

impl Actor {
    pub(super) async fn set_muted(&mut self, muted: bool) -> Result<(), SessionError> {
        if self.audio_enabled {
            self.voice.set_muted(muted)?;
        }
        self.voice_state.muted = muted;
        self.audio_since = Instant::now();
        if muted {
            self.emit(SessionEvent::SelfSpeaking { speaking: false });
            self.voice_state.ptt_active = false;
            if self.audio_enabled {
                let _ = self.voice.set_ptt_active(false);
            }
        }
        self.emit_voice_state();
        self.report_voice_flags().await;
        Ok(())
    }

    pub(super) async fn set_deafened(&mut self, deafened: bool) -> Result<(), SessionError> {
        if self.audio_enabled {
            self.voice.set_deafened(deafened)?;
        }
        self.voice_state.deafened = deafened;
        self.audio_since = Instant::now();
        if deafened {
            self.emit(SessionEvent::SelfSpeaking { speaking: false });
            self.voice_state.ptt_active = false;
            if self.audio_enabled {
                let _ = self.voice.set_ptt_active(false);
            }
        }
        self.emit_voice_state();
        self.report_voice_flags().await;
        Ok(())
    }

    /// 把自己的静音/聋听/离开状态上报给服务器，其他客户端才能看到标志。
    /// 本地门控已经生效，上报失败只记日志不回滚。
    pub(super) async fn report_voice_flags(&self) {
        let Some(client) = self.client.clone() else {
            return;
        };
        let (input, output) = mute_flags(self.voice_state.muted, self.voice_state.deafened);
        let params = vec![
            ("client_input_muted", input),
            ("client_output_muted", output),
            ("client_away", if self.voice_state.away { "1" } else { "0" }),
        ];
        if let Err(err) = tsclient_rs::clientUpdate(&client, &params).await {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("状态上报失败: {err}"),
            });
        }
    }

    /// 离开只是服务器上的标志，不影响本地音频采集与播放。
    pub(super) async fn set_away(&mut self, away: bool) -> Result<(), SessionError> {
        self.voice_state.away = away;
        self.emit_voice_state();
        self.report_voice_flags().await;
        Ok(())
    }

    pub(super) fn set_ptt_mode(&mut self, enabled: bool) -> Result<(), SessionError> {
        if self.audio_enabled {
            self.voice.set_ptt_mode(enabled)?;
        }
        self.voice_state.ptt_mode = enabled;
        self.audio_since = Instant::now();
        if enabled && !self.voice_state.ptt_active {
            self.emit(SessionEvent::SelfSpeaking { speaking: false });
        }
        if !enabled {
            self.voice_state.ptt_active = false;
        }
        self.emit_voice_state();
        Ok(())
    }

    pub(super) fn set_ptt_active(&mut self, active: bool) -> Result<(), SessionError> {
        if !self.voice_state.ptt_mode {
            return Ok(());
        }
        let active = active && !self.voice_state.muted && !self.voice_state.deafened;
        if self.audio_enabled {
            self.voice.set_ptt_active(active)?;
        }
        self.voice_state.ptt_active = active;
        self.audio_since = Instant::now();
        if !active {
            self.emit(SessionEvent::SelfSpeaking { speaking: false });
        }
        self.emit_voice_state();
        Ok(())
    }

    pub(super) fn set_audio_devices(
        &mut self,
        input: Option<String>,
        output: Option<String>,
    ) -> Result<(), SessionError> {
        if !self.audio_enabled {
            return Ok(());
        }
        if self.input_device == input && self.output_device == output {
            return Ok(());
        }
        self.input_device = input;
        self.output_device = output;
        if self.client.is_some() {
            self.voice.set_input_device(self.input_device.clone())?;
            self.voice.set_output_device(self.output_device.clone())?;
        }
        Ok(())
    }

    pub(super) fn apply_self_channel(&mut self, channel_id: u64, codec: Option<i32>) {
        if self.self_channel_id == channel_id {
            self.apply_channel_codec(codec);
            return;
        }
        self.self_channel_id = channel_id;
        self.audio_since = Instant::now();
        if let SessionState::Connected { client_id, .. } = self.state.clone() {
            self.set_state(SessionState::Connected {
                client_id,
                channel_id,
            });
        }
        if channel_id == 0 {
            if self.capture_active {
                let _ = self.voice.stop_capture();
                self.capture_active = false;
            }
            return;
        }
        self.apply_channel_codec(codec);
    }

    pub(super) fn apply_channel_codec(&mut self, codec: Option<i32>) {
        if !self.audio_enabled {
            return;
        }
        let Some(codec) = codec else {
            self.stop_capture_with_message("无法读取当前频道的 codec");
            return;
        };
        if !is_supported_codec(codec) {
            self.stop_capture_with_message(&format!("频道 codec {codec} 不受支持（仅 Opus 4/5）"));
            return;
        }
        self.current_codec = codec;
        if let Err(err) = self.voice.set_channel_codec(codec) {
            self.voice_state.message = Some(err.to_string());
            self.emit_voice_state();
            return;
        }
        self.voice_state.message = None;
        if self.client.is_some() && self.self_channel_id != 0 && !self.capture_active {
            let _ = self.voice.set_muted(self.voice_state.muted);
            let _ = self.voice.set_deafened(self.voice_state.deafened);
            let _ = self.voice.set_ptt_mode(self.voice_state.ptt_mode);
            let _ = self.voice.set_ptt_active(self.voice_state.ptt_active);
            if let Err(err) = self.voice.start_capture(self.input_device.clone()) {
                self.voice_state.message = Some(err.to_string());
            } else {
                self.capture_active = true;
            }
        }
        self.emit_voice_state();
    }

    fn stop_capture_with_message(&mut self, message: &str) {
        if self.capture_active {
            let _ = self.voice.stop_capture();
            self.capture_active = false;
        }
        self.voice_state.message = Some(message.to_string());
        self.emit_voice_state();
    }
    pub(super) fn handle_audio(&mut self, event: AudioEvent) {
        match event {
            AudioEvent::Outbound {
                codec,
                data,
                produced_at,
            } => {
                if !self.can_send_voice(codec, produced_at, Instant::now()) {
                    return;
                }
                if data.len() > MAX_PACKET_BYTES {
                    crate::log_error!(
                        size = data.len(),
                        max = MAX_PACKET_BYTES;
                        "encoding layer constraint violated: packet exceeds budget"
                    );
                    return;
                }
                if let Some(client) = &self.client {
                    client.send_voice(data, codec);
                }
            }
            AudioEvent::Talkers { client_ids } => {
                self.emit(SessionEvent::Speaking { client_ids });
            }
            AudioEvent::SelfSpeaking { speaking } => {
                self.emit(SessionEvent::SelfSpeaking {
                    speaking: speaking && self.voice_gate_open(),
                });
            }
            AudioEvent::CaptureState { ready } => {
                self.voice_state.input_ready = ready;
                if ready {
                    self.voice_state.message = None;
                }
                self.capture_active = ready;
                self.emit_voice_state();
            }
            AudioEvent::PlaybackState { ready } => {
                self.voice_state.output_ready = ready;
                if ready {
                    self.voice_state.message = None;
                }
                self.emit_voice_state();
            }
            AudioEvent::Error { stage, message } => {
                let stage = match stage {
                    AudioStage::Capture => "采集",
                    AudioStage::Playback => "播放",
                    AudioStage::Codec => "编解码",
                };
                self.voice_state.message = Some(format!("{stage}失败: {message}"));
                self.emit_voice_state();
            }
        }
    }

    fn voice_gate_open(&self) -> bool {
        matches!(self.state, SessionState::Connected { .. })
            && self.self_channel_id != 0
            && self.capture_active
            && !self.voice_state.muted
            && !self.voice_state.deafened
            && (!self.voice_state.ptt_mode || self.voice_state.ptt_active)
    }

    pub(super) fn can_send_voice(&self, codec: i32, produced_at: Instant, now: Instant) -> bool {
        self.voice_gate_open()
            && codec == self.current_codec
            && produced_at >= self.audio_since
            && now.saturating_duration_since(produced_at) <= MAX_VOICE_QUEUE_DELAY
    }

    pub(super) fn start_voice(&mut self) {
        if !self.audio_enabled {
            return;
        }
        let _ = self.voice.set_muted(self.voice_state.muted);
        let _ = self.voice.set_deafened(self.voice_state.deafened);
        let _ = self.voice.set_ptt_mode(self.voice_state.ptt_mode);
        let _ = self.voice.set_ptt_active(self.voice_state.ptt_active);
        if let Err(err) = self.voice.start_playback(self.output_device.clone()) {
            self.voice_state.message = Some(err.to_string());
        }
        if self.self_channel_id != 0 && is_supported_codec(self.current_codec) {
            if let Err(err) = self.voice.start_capture(self.input_device.clone()) {
                self.voice_state.message = Some(err.to_string());
                self.capture_active = false;
            } else {
                self.capture_active = true;
            }
        } else {
            self.capture_active = false;
        }
    }

    pub(super) fn stop_voice(&mut self) {
        if self.audio_enabled {
            let _ = self.voice.stop();
        }
        self.capture_active = false;
    }
}

pub(super) fn list_audio_devices() -> Result<AudioDevicesView, SessionError> {
    let inputs = audio::device::input_devices()
        .map_err(SessionError::Audio)?
        .into_iter()
        .map(AudioDeviceView::from)
        .collect();
    let outputs = audio::device::output_devices()
        .map_err(SessionError::Audio)?
        .into_iter()
        .map(AudioDeviceView::from)
        .collect();
    Ok(AudioDevicesView { inputs, outputs })
}
impl From<audio::device::DeviceInfo> for AudioDeviceView {
    fn from(info: audio::device::DeviceInfo) -> Self {
        Self {
            id: info.id,
            name: info.name,
            is_default: info.is_default,
        }
    }
}
/// 官方客户端的标志语义：deafen 同时置 input 与 output，解除 deafen 后
/// input 恢复用户自己的静音选择。
pub(super) fn mute_flags(muted: bool, deafened: bool) -> (&'static str, &'static str) {
    (
        if muted || deafened { "1" } else { "0" },
        if deafened { "1" } else { "0" },
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actor::test_support::*;

    #[test]
    fn queued_voice_requires_fresh_data_and_an_open_gate() {
        let mut actor = audio_actor();
        let at = actor.audio_since;
        let now = at + Duration::from_millis(20);
        assert!(actor.can_send_voice(VOICE_CODEC, at, now));
        assert!(!actor.can_send_voice(
            VOICE_CODEC,
            at,
            at + MAX_VOICE_QUEUE_DELAY + Duration::from_millis(1)
        ));
        actor.audio_since = at + Duration::from_millis(1);
        assert!(!actor.can_send_voice(VOICE_CODEC, at, now));
        actor.audio_since = at;
        actor.voice_state.muted = true;
        assert!(!actor.can_send_voice(VOICE_CODEC, at, now));
        actor.voice_state.muted = false;
        actor.voice_state.ptt_mode = true;
        assert!(!actor.can_send_voice(VOICE_CODEC, at, now));
        actor.voice_state.ptt_active = true;
        assert!(actor.can_send_voice(VOICE_CODEC, at, now));
        actor.voice_state.deafened = true;
        assert!(!actor.can_send_voice(VOICE_CODEC, at, now));
        actor.voice_state.deafened = false;
        actor.capture_active = false;
        assert!(!actor.can_send_voice(VOICE_CODEC, at, now));
    }

    #[test]
    fn outbound_voice_guard_uses_the_encoder_budget() {
        let mut actor = audio_actor();
        let mut events = actor.events.subscribe();
        actor.handle_audio(AudioEvent::Outbound {
            codec: VOICE_CODEC,
            data: vec![0; MAX_PACKET_BYTES],
            produced_at: Instant::now(),
        });
        assert!(events.try_recv().is_err());
        assert!(actor.voice_state.message.is_none());

        actor.handle_audio(AudioEvent::Outbound {
            codec: VOICE_CODEC,
            data: vec![0; MAX_PACKET_BYTES + 1],
            produced_at: Instant::now(),
        });
        // 防御性拦截超限包：断言未发出且未污染 UI message 状态
        assert!(events.try_recv().is_err());
        assert!(actor.voice_state.message.is_none());
    }

    #[tokio::test]
    async fn mute_cycle_discards_already_queued_voice_and_readiness_preserves_ptt_intent() {
        let mut actor = audio_actor();
        let queued = Instant::now();
        actor.set_muted(true).await.unwrap();
        actor.set_muted(false).await.unwrap();
        assert!(!actor.can_send_voice(VOICE_CODEC, queued, Instant::now()));
        actor.voice_state.ptt_mode = true;
        actor.voice_state.ptt_active = false;
        actor.handle_audio(AudioEvent::CaptureState { ready: true });
        assert!(actor.voice_state.input_ready);
        assert!(actor.voice_state.ptt_mode);
        assert!(!actor.voice_state.ptt_active);
        let mut events = actor.events.subscribe();
        actor.handle_audio(AudioEvent::SelfSpeaking { speaking: true });
        assert!(matches!(
            events.try_recv(),
            Ok(SessionEvent::SelfSpeaking { speaking: false })
        ));
    }

    #[test]
    fn mute_flags_follow_official_deafen_semantics() {
        assert_eq!(mute_flags(false, false), ("0", "0"));
        assert_eq!(mute_flags(true, false), ("1", "0"));
        // deafen 同时置两个标志，覆盖用户当前的静音选择。
        assert_eq!(mute_flags(false, true), ("1", "1"));
        assert_eq!(mute_flags(true, true), ("1", "1"));
    }
}
