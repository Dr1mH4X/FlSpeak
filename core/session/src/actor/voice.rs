use super::*;

const MAX_VOICE_QUEUE_DELAY: Duration = Duration::from_millis(100);
pub(super) const VOICE_REPORT_BASE_WINDOW: Duration = Duration::from_millis(600);
pub(super) const VOICE_REPORT_MAX_BACKOFF: Duration = Duration::from_secs(8);
pub(super) const VOICE_REPORT_MAX_FLOOD_RETRIES: u32 = 10;
pub(super) const VOICE_REPORT_MAX_DIRTY_DURATION: Duration = Duration::from_secs(10);

pub(super) type ReportInstant = tokio::time::Instant;

pub(super) const DIRTY_INPUT_MUTED: u8 = 1 << 0;
pub(super) const DIRTY_OUTPUT_MUTED: u8 = 1 << 1;
pub(super) const DIRTY_AWAY: u8 = 1 << 2;
pub(super) const DIRTY_ALL: u8 = DIRTY_INPUT_MUTED | DIRTY_OUTPUT_MUTED | DIRTY_AWAY;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(super) struct VoiceFlagsSnapshot {
    pub input_muted: bool,
    pub output_muted: bool,
    pub away: bool,
}

impl VoiceFlagsSnapshot {
    pub(super) fn from_voice_state(state: &VoiceStateView) -> Self {
        let (input, output) = mute_flags(state.muted, state.deafened);
        Self {
            input_muted: input == "1",
            output_muted: output == "1",
            away: state.away,
        }
    }

    fn params(self) -> Vec<(&'static str, &'static str)> {
        vec![
            (
                "client_input_muted",
                if self.input_muted { "1" } else { "0" },
            ),
            (
                "client_output_muted",
                if self.output_muted { "1" } else { "0" },
            ),
            ("client_away", if self.away { "1" } else { "0" }),
        ]
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum VoiceReportMode {
    Leading,
    Timer { seq: u64 },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum VoiceReportDecision {
    SendNow {
        coalesced: u32,
        window: Duration,
    },
    ScheduleTrailing {
        wait: Duration,
        seq: u64,
        coalesced: u32,
        window: Duration,
    },
    AlreadyScheduled {
        coalesced: u32,
        window: Duration,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum VoiceFailureOutcome {
    FloodBackoff {
        wait: Duration,
        seq: u64,
        retry: u32,
        coalesced: u32,
    },
    GiveUp {
        notify_ui: bool,
        retries: u32,
    },
}

/// 自身静音/聋听/离开标志上报状态机：Leading + Trailing 快照合并与 524 指数退避。
pub(super) struct VoiceReportState {
    pub(super) window: Duration,
    pub(super) last_attempt: Option<ReportInstant>,
    pub(super) trailing_scheduled: bool,
    pub(super) timer_seq: u64,
    pub(super) coalesced_count: u32,
    pub(super) flood_retries: u32,
    pub(super) dirty_mask: u8,
    pub(super) dirty_since: Option<ReportInstant>,
    pub(super) unconfirmed: bool,
    pub(super) notified_unconfirmed: bool,
    pub(super) server_confirmed: VoiceFlagsSnapshot,
}

impl Default for VoiceReportState {
    fn default() -> Self {
        Self::new()
    }
}

impl VoiceReportState {
    pub(super) fn new() -> Self {
        Self {
            window: VOICE_REPORT_BASE_WINDOW,
            last_attempt: None,
            trailing_scheduled: false,
            timer_seq: 0,
            coalesced_count: 0,
            flood_retries: 0,
            dirty_mask: 0,
            dirty_since: None,
            unconfirmed: false,
            notified_unconfirmed: false,
            server_confirmed: VoiceFlagsSnapshot::default(),
        }
    }

    pub(super) fn mark_dirty(&mut self, mask: u8, now: ReportInstant) {
        if self.dirty_mask == 0 || self.unconfirmed {
            self.dirty_since = Some(now);
        }
        self.dirty_mask |= mask;
        if self.unconfirmed {
            self.unconfirmed = false;
            self.notified_unconfirmed = false;
            self.flood_retries = 0;
        }
    }

    pub(super) fn try_begin(
        &mut self,
        mode: VoiceReportMode,
        now: ReportInstant,
    ) -> Option<VoiceReportDecision> {
        match mode {
            VoiceReportMode::Timer { seq } => {
                if !self.trailing_scheduled || self.timer_seq != seq {
                    return None;
                }
                self.trailing_scheduled = false;
                let coalesced = std::mem::take(&mut self.coalesced_count);
                self.last_attempt = Some(now);
                Some(VoiceReportDecision::SendNow {
                    coalesced,
                    window: self.window,
                })
            }
            VoiceReportMode::Leading => {
                if self.trailing_scheduled {
                    self.coalesced_count = self.coalesced_count.saturating_add(1);
                    return Some(VoiceReportDecision::AlreadyScheduled {
                        coalesced: self.coalesced_count,
                        window: self.window,
                    });
                }
                if let Some(last) = self.last_attempt {
                    let elapsed = now.saturating_duration_since(last);
                    if elapsed < self.window {
                        self.trailing_scheduled = true;
                        self.timer_seq = self.timer_seq.wrapping_add(1);
                        self.coalesced_count = self.coalesced_count.saturating_add(1);
                        return Some(VoiceReportDecision::ScheduleTrailing {
                            wait: self.window - elapsed,
                            seq: self.timer_seq,
                            coalesced: self.coalesced_count,
                            window: self.window,
                        });
                    }
                }
                let coalesced = std::mem::take(&mut self.coalesced_count);
                self.last_attempt = Some(now);
                Some(VoiceReportDecision::SendNow {
                    coalesced,
                    window: self.window,
                })
            }
        }
    }

    pub(super) fn record_success(
        &mut self,
        sent: VoiceFlagsSnapshot,
        current_local: VoiceFlagsSnapshot,
    ) {
        self.server_confirmed = sent;
        self.window = VOICE_REPORT_BASE_WINDOW;
        self.flood_retries = 0;
        self.unconfirmed = false;
        self.notified_unconfirmed = false;
        if !self.trailing_scheduled {
            if sent.input_muted == current_local.input_muted {
                self.dirty_mask &= !DIRTY_INPUT_MUTED;
            }
            if sent.output_muted == current_local.output_muted {
                self.dirty_mask &= !DIRTY_OUTPUT_MUTED;
            }
            if sent.away == current_local.away {
                self.dirty_mask &= !DIRTY_AWAY;
            }
            if self.dirty_mask == 0 {
                self.dirty_since = None;
            }
        }
    }

    pub(super) fn record_failure(
        &mut self,
        is_flood: bool,
        now: ReportInstant,
    ) -> VoiceFailureOutcome {
        if is_flood {
            self.flood_retries = self.flood_retries.saturating_add(1);
            let dirty_elapsed = self
                .dirty_since
                .map_or(Duration::ZERO, |t| now.saturating_duration_since(t));
            if self.flood_retries >= VOICE_REPORT_MAX_FLOOD_RETRIES
                || dirty_elapsed >= VOICE_REPORT_MAX_DIRTY_DURATION
            {
                self.trailing_scheduled = false;
                self.timer_seq = self.timer_seq.wrapping_add(1);
                self.unconfirmed = true;
                let notify_ui = !std::mem::replace(&mut self.notified_unconfirmed, true);
                return VoiceFailureOutcome::GiveUp {
                    notify_ui,
                    retries: self.flood_retries,
                };
            }
            self.window = (self.window * 2).min(VOICE_REPORT_MAX_BACKOFF);
            self.last_attempt = Some(now);
            self.trailing_scheduled = true;
            self.timer_seq = self.timer_seq.wrapping_add(1);
            return VoiceFailureOutcome::FloodBackoff {
                wait: self.window,
                seq: self.timer_seq,
                retry: self.flood_retries,
                coalesced: self.coalesced_count,
            };
        }

        self.trailing_scheduled = false;
        self.timer_seq = self.timer_seq.wrapping_add(1);
        self.unconfirmed = true;
        let notify_ui = !std::mem::replace(&mut self.notified_unconfirmed, true);
        VoiceFailureOutcome::GiveUp {
            notify_ui,
            retries: self.flood_retries,
        }
    }

    pub(super) fn resolve_self_flags(
        &mut self,
        local: VoiceFlagsSnapshot,
        server_input: Option<bool>,
        server_output: Option<bool>,
        server_away: Option<bool>,
    ) -> VoiceFlagsSnapshot {
        if let Some(v) = server_input {
            self.server_confirmed.input_muted = v;
            if !self.trailing_scheduled && v == local.input_muted {
                self.dirty_mask &= !DIRTY_INPUT_MUTED;
            }
        }
        if let Some(v) = server_output {
            self.server_confirmed.output_muted = v;
            if !self.trailing_scheduled && v == local.output_muted {
                self.dirty_mask &= !DIRTY_OUTPUT_MUTED;
            }
        }
        if let Some(v) = server_away {
            self.server_confirmed.away = v;
            if !self.trailing_scheduled && v == local.away {
                self.dirty_mask &= !DIRTY_AWAY;
            }
        }
        if self.dirty_mask == 0 {
            self.dirty_since = None;
            self.unconfirmed = false;
            self.notified_unconfirmed = false;
        }
        VoiceFlagsSnapshot {
            input_muted: if (self.dirty_mask & DIRTY_INPUT_MUTED) != 0 {
                local.input_muted
            } else {
                self.server_confirmed.input_muted
            },
            output_muted: if (self.dirty_mask & DIRTY_OUTPUT_MUTED) != 0 {
                local.output_muted
            } else {
                self.server_confirmed.output_muted
            },
            away: if (self.dirty_mask & DIRTY_AWAY) != 0 {
                local.away
            } else {
                self.server_confirmed.away
            },
        }
    }

    pub(super) fn reset(&mut self) {
        self.window = VOICE_REPORT_BASE_WINDOW;
        self.last_attempt = None;
        self.trailing_scheduled = false;
        self.timer_seq = self.timer_seq.wrapping_add(1);
        self.coalesced_count = 0;
        self.flood_retries = 0;
        self.dirty_mask = 0;
        self.dirty_since = None;
        self.unconfirmed = false;
        self.notified_unconfirmed = false;
        self.server_confirmed = VoiceFlagsSnapshot::default();
    }
}

fn is_flood_error(err: &tsclient_rs::Error) -> bool {
    matches!(err, tsclient_rs::Error::ServerError { id, .. } if id == "524")
}

impl Actor {
    pub(super) fn apply_muted(&mut self, muted: bool) -> Result<(), SessionError> {
        if self.audio_enabled {
            self.voice.set_muted(muted)?;
        }
        self.voice_state.muted = muted;
        self.finish_local_voice_change(DIRTY_INPUT_MUTED, muted);
        Ok(())
    }

    pub(super) fn apply_deafened(&mut self, deafened: bool) -> Result<(), SessionError> {
        if self.audio_enabled {
            self.voice.set_deafened(deafened)?;
        }
        self.voice_state.deafened = deafened;
        self.finish_local_voice_change(DIRTY_INPUT_MUTED | DIRTY_OUTPUT_MUTED, deafened);
        Ok(())
    }

    /// 离开只是服务器上的标志，不影响本地音频采集与播放。
    pub(super) fn apply_away(&mut self, away: bool) {
        self.voice_state.away = away;
        self.voice_report
            .mark_dirty(DIRTY_AWAY, ReportInstant::now());
        self.emit_voice_state();
        self.sync_self_voice_to_snapshot();
    }

    fn finish_local_voice_change(&mut self, dirty_mask: u8, close_ptt: bool) {
        self.audio_since = Instant::now();
        if close_ptt {
            self.emit(SessionEvent::SelfSpeaking { speaking: false });
            self.voice_state.ptt_active = false;
            if self.audio_enabled {
                let _ = self.voice.set_ptt_active(false);
            }
        }
        self.voice_report
            .mark_dirty(dirty_mask, ReportInstant::now());
        self.emit_voice_state();
        self.sync_self_voice_to_snapshot();
    }

    fn sync_self_voice_to_snapshot(&mut self) {
        let Some(self_id) = self.self_client_id else {
            return;
        };
        let flags = VoiceFlagsSnapshot::from_voice_state(&self.voice_state);
        if let Some((_, clients)) = &mut self.last_snapshot
            && let Some(row) = clients.iter_mut().find(|client| client.id == self_id)
        {
            row.input_muted = Some(flags.input_muted);
            row.output_muted = Some(flags.output_muted);
            row.away = Some(flags.away);
        }
        self.emit(SessionEvent::ClientUpdated {
            id: self_id,
            input_muted: Some(flags.input_muted),
            output_muted: Some(flags.output_muted),
            away: Some(flags.away),
            away_message: None,
        });
    }

    fn schedule_voice_report_signal(&self, delay: Duration, seq: u64) {
        let epoch = self.connection_epoch;
        let signals = self.signals.clone();
        tokio::spawn(async move {
            tokio::time::sleep(delay).await;
            let _ = signals.send(SessionSignal::ReportVoiceFlags { epoch, seq });
        });
    }

    /// 把自己的静音/聋听/离开状态经节流合并后上报给服务器，其他客户端才能看到标志。
    /// 本地门控已经生效，上报失败只记日志并在彻底失败时提示用户，不回滚本地状态。
    pub(super) async fn request_state_update(&mut self) {
        self.report_voice_flags_step(VoiceReportMode::Leading).await;
    }

    pub(super) async fn report_voice_flags_step(&mut self, mode: VoiceReportMode) {
        let Some(client) = self.client.clone() else {
            return;
        };
        let now = ReportInstant::now();
        match self.voice_report.try_begin(mode, now) {
            None => return,
            Some(VoiceReportDecision::ScheduleTrailing {
                wait,
                seq,
                coalesced,
                window,
            }) => {
                self.emit(SessionEvent::Log {
                    level: "debug".into(),
                    message: format!(
                        "状态上报进入节流窗口，已调度尾随合并: coalesced={coalesced}, wait_ms={}, window_ms={}",
                        wait.as_millis(),
                        window.as_millis()
                    ),
                });
                self.schedule_voice_report_signal(wait, seq);
                return;
            }
            Some(VoiceReportDecision::AlreadyScheduled { coalesced, window }) => {
                self.emit(SessionEvent::Log {
                    level: "debug".into(),
                    message: format!(
                        "状态上报已合并至挂起窗口: coalesced={coalesced}, window_ms={}",
                        window.as_millis()
                    ),
                });
                return;
            }
            Some(VoiceReportDecision::SendNow { coalesced, window }) => {
                if coalesced > 0 {
                    self.emit(SessionEvent::Log {
                        level: "debug".into(),
                        message: format!(
                            "发送合并后的状态快照: coalesced={coalesced}, window_ms={}",
                            window.as_millis()
                        ),
                    });
                }
            }
        }

        let sent = VoiceFlagsSnapshot::from_voice_state(&self.voice_state);
        let params = sent.params();
        let result = match tsclient_rs::clientUpdate(&client, &params).await {
            Ok(()) => Ok(()),
            Err(tsclient_rs::Error::ServerError { ref id, .. }) if id == "0" => Ok(()),
            Err(err) => Err(err),
        };
        match result {
            Ok(()) => {
                let current_local = VoiceFlagsSnapshot::from_voice_state(&self.voice_state);
                let was_backed_off = self.voice_report.flood_retries > 0;
                self.voice_report.record_success(sent, current_local);
                if was_backed_off {
                    self.emit(SessionEvent::Log {
                        level: "debug".into(),
                        message: format!(
                            "状态上报恢复正常，退避窗口已重置为 {}ms",
                            VOICE_REPORT_BASE_WINDOW.as_millis()
                        ),
                    });
                }
            }
            Err(err) => {
                let is_flood = is_flood_error(&err);
                match self
                    .voice_report
                    .record_failure(is_flood, ReportInstant::now())
                {
                    VoiceFailureOutcome::FloodBackoff {
                        wait,
                        seq,
                        retry,
                        coalesced,
                    } => {
                        self.emit(SessionEvent::Log {
                            level: "debug".into(),
                            message: format!(
                                "状态上报触发 524 退避重试: retry={retry}, backoff_ms={}, coalesced={coalesced}, error={err}",
                                wait.as_millis()
                            ),
                        });
                        self.schedule_voice_report_signal(wait, seq);
                    }
                    VoiceFailureOutcome::GiveUp { notify_ui, retries } => {
                        self.emit(SessionEvent::Log {
                            level: "warn".into(),
                            message: format!(
                                "状态上报失败 (retries={retries}, unconfirmed=true): {err}"
                            ),
                        });
                        if notify_ui {
                            self.emit(SessionEvent::Failed {
                                message: "状态同步失败，稍后切换状态或重连时将重新同步".into(),
                            });
                        }
                    }
                }
            }
        }
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

    #[test]
    fn mute_cycle_discards_already_queued_voice_and_readiness_preserves_ptt_intent() {
        let mut actor = audio_actor();
        let queued = Instant::now();
        actor.apply_muted(true).unwrap();
        actor.apply_muted(false).unwrap();
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

    #[test]
    fn voice_report_state_coalesces_burst_and_fires_trailing_idempotently() {
        let mut state = VoiceReportState::new();
        let t0 = ReportInstant::now();

        state.mark_dirty(DIRTY_INPUT_MUTED, t0);
        assert_eq!(
            state.try_begin(VoiceReportMode::Leading, t0),
            Some(VoiceReportDecision::SendNow {
                coalesced: 0,
                window: VOICE_REPORT_BASE_WINDOW,
            })
        );

        // 窗口内连续切换 9 次（含切回原状态），仅首次调度尾随，后续合并计数递增。
        for i in 1..=9 {
            let at = t0 + Duration::from_millis(i * 50);
            state.mark_dirty(DIRTY_INPUT_MUTED, at);
            let decision = state.try_begin(VoiceReportMode::Leading, at);
            if i == 1 {
                assert_eq!(
                    decision,
                    Some(VoiceReportDecision::ScheduleTrailing {
                        wait: VOICE_REPORT_BASE_WINDOW - Duration::from_millis(50),
                        seq: 1,
                        coalesced: 1,
                        window: VOICE_REPORT_BASE_WINDOW,
                    })
                );
            } else {
                assert_eq!(
                    decision,
                    Some(VoiceReportDecision::AlreadyScheduled {
                        coalesced: i as u32,
                        window: VOICE_REPORT_BASE_WINDOW,
                    })
                );
            }
        }

        // 过期序号定时器被忽略；匹配序号在窗口末发送合并后的最终状态。
        let t_end = t0 + VOICE_REPORT_BASE_WINDOW;
        assert_eq!(
            state.try_begin(VoiceReportMode::Timer { seq: 99 }, t_end),
            None
        );
        assert_eq!(
            state.try_begin(VoiceReportMode::Timer { seq: 1 }, t_end),
            Some(VoiceReportDecision::SendNow {
                coalesced: 9,
                window: VOICE_REPORT_BASE_WINDOW,
            })
        );
    }

    #[test]
    fn voice_report_state_backs_off_on_524_and_resets_on_success_or_stops_at_cap() {
        let mut state = VoiceReportState::new();
        let t0 = ReportInstant::now();
        state.mark_dirty(DIRTY_INPUT_MUTED, t0);
        assert!(state.try_begin(VoiceReportMode::Leading, t0).is_some());

        let expected_waits = [
            Duration::from_millis(1200),
            Duration::from_millis(2400),
            Duration::from_millis(4800),
            Duration::from_secs(8),
            Duration::from_secs(8),
        ];
        let mut now = t0;
        for (idx, expected_wait) in expected_waits.iter().enumerate() {
            let outcome = state.record_failure(true, now);
            assert_eq!(
                outcome,
                VoiceFailureOutcome::FloodBackoff {
                    wait: *expected_wait,
                    seq: (idx + 1) as u64,
                    retry: (idx + 1) as u32,
                    coalesced: 0,
                }
            );
            now += Duration::from_millis(500);
            assert!(
                state
                    .try_begin(
                        VoiceReportMode::Timer {
                            seq: (idx + 1) as u64
                        },
                        now
                    )
                    .is_some()
            );
        }

        // 成功一次后退避窗口立刻回到 600ms，失败计数归零。
        let ok_snap = VoiceFlagsSnapshot {
            input_muted: true,
            output_muted: false,
            away: false,
        };
        state.record_success(ok_snap, ok_snap);
        assert_eq!(state.window, VOICE_REPORT_BASE_WINDOW);
        assert_eq!(state.flood_retries, 0);
        assert_eq!(state.dirty_mask, 0);
        assert!(!state.unconfirmed);

        // 连续 524 达到次数上限时放弃重试并仅通知一次，后续再操作时重新激活。
        let t_retry = now + Duration::from_secs(1);
        state.mark_dirty(DIRTY_AWAY, t_retry);
        for attempt in 1..=VOICE_REPORT_MAX_FLOOD_RETRIES {
            let outcome = state.record_failure(true, t_retry);
            if attempt < VOICE_REPORT_MAX_FLOOD_RETRIES {
                assert!(matches!(outcome, VoiceFailureOutcome::FloodBackoff { .. }));
            } else {
                assert_eq!(
                    outcome,
                    VoiceFailureOutcome::GiveUp {
                        notify_ui: true,
                        retries: VOICE_REPORT_MAX_FLOOD_RETRIES,
                    }
                );
            }
        }
        assert!(state.unconfirmed);
        assert!(!state.trailing_scheduled);
        // 非 524 错误在同一失败串内不重复弹通知。
        assert_eq!(
            state.record_failure(false, t_retry),
            VoiceFailureOutcome::GiveUp {
                notify_ui: false,
                retries: VOICE_REPORT_MAX_FLOOD_RETRIES,
            }
        );

        // 下一次用户操作清除 unconfirmed 并允许重新调度。
        let t_next = t_retry + Duration::from_secs(20);
        state.mark_dirty(DIRTY_AWAY, t_next);
        assert!(!state.unconfirmed);
        assert_eq!(
            state.record_failure(false, t_next),
            VoiceFailureOutcome::GiveUp {
                notify_ui: true,
                retries: 0,
            }
        );
    }

    #[test]
    fn voice_report_state_resolve_self_flags_respects_dirty_bits_and_server_updates() {
        let mut state = VoiceReportState::new();
        let t0 = ReportInstant::now();
        let local_muted = VoiceFlagsSnapshot {
            input_muted: true,
            output_muted: false,
            away: false,
        };
        state.mark_dirty(DIRTY_INPUT_MUTED, t0);
        assert!(state.try_begin(VoiceReportMode::Leading, t0).is_some());
        state.mark_dirty(DIRTY_INPUT_MUTED, t0 + Duration::from_millis(50));
        assert!(matches!(
            state.try_begin(VoiceReportMode::Leading, t0 + Duration::from_millis(50)),
            Some(VoiceReportDecision::ScheduleTrailing { .. })
        ));

        // 尾随调度仍在挂起时，旧回显不能覆盖本地 dirty 字段，但可更新非 dirty 的 away 字段。
        let resolved_pending = state.resolve_self_flags(
            VoiceFlagsSnapshot::default(),
            Some(true),
            Some(false),
            Some(true),
        );
        assert!(!resolved_pending.input_muted);
        assert!(resolved_pending.away);
        assert_ne!(state.dirty_mask & DIRTY_INPUT_MUTED, 0);

        // 尾随定时触发并上报成功后，dirty 位清除。
        assert!(
            state
                .try_begin(
                    VoiceReportMode::Timer { seq: 1 },
                    t0 + VOICE_REPORT_BASE_WINDOW
                )
                .is_some()
        );
        state.record_success(local_muted, local_muted);
        assert_eq!(state.dirty_mask, 0);
        let settled = state.resolve_self_flags(local_muted, Some(true), Some(false), Some(false));
        assert_eq!(settled, local_muted);
    }

    struct RecordingClientUpdateMiddleware {
        calls: Arc<std::sync::Mutex<Vec<String>>>,
        next_result: Arc<std::sync::Mutex<VecDeque<Result<(), tsclient_rs::Error>>>>,
    }

    impl tsclient_rs::CommandMiddleware for RecordingClientUpdateMiddleware {
        fn wrap(&self, _: TestCommandHandler) -> TestCommandHandler {
            let calls = Arc::clone(&self.calls);
            let next_result = Arc::clone(&self.next_result);
            Arc::new(move |command| {
                let calls = Arc::clone(&calls);
                let next_result = Arc::clone(&next_result);
                Box::pin(async move {
                    if command.starts_with("clientupdate") {
                        calls.lock().unwrap().push(command);
                        return next_result.lock().unwrap().pop_front().unwrap_or_else(|| {
                            Err(tsclient_rs::Error::ServerError {
                                id: "0".into(),
                                server_message: "ok".into(),
                                extra_message: None,
                            })
                        });
                    }
                    Err(tsclient_rs::Error::ServerError {
                        id: "0".into(),
                        server_message: "ok".into(),
                        extra_message: None,
                    })
                })
            })
        }
    }

    #[tokio::test]
    async fn rapid_mute_toggles_coalesce_client_update_calls_and_keep_local_voice_instant() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let calls = Arc::new(std::sync::Mutex::new(Vec::new()));
                let client = Client::new(
                    tsclient_rs::generateIdentity(0),
                    "127.0.0.1:9987".into(),
                    "test".into(),
                    tsclient_rs::ClientOptions {
                        command_middleware: vec![Box::new(RecordingClientUpdateMiddleware {
                            calls: Arc::clone(&calls),
                            next_result: Arc::new(std::sync::Mutex::new(VecDeque::new())),
                        })],
                        ..Default::default()
                    },
                );
                client.mark_connected();

                let mut actor = audio_actor();
                actor.self_client_id = Some(1);
                actor.client = Some(Arc::new(client));
                let mut events = actor.events.subscribe();

                let mut voice_events = Vec::new();
                for i in 0..10 {
                    actor.apply_muted(i % 2 == 0).unwrap();
                    actor.request_state_update().await;
                    while let Ok(ev) = events.try_recv() {
                        if let SessionEvent::Voice(v) = ev {
                            voice_events.push(v.muted);
                        }
                    }
                }

                // 本地 Voice 事件 10 次切换均有即时输出，但期间仅发了 1 次 Leading clientupdate。
                assert_eq!(voice_events.len(), 10);
                assert!(!actor.voice_state.muted);
                assert_eq!(calls.lock().unwrap().len(), 1);
                assert!(calls.lock().unwrap()[0].contains("client_input_muted=1"));

                // 到达基础窗口末后，尾随合并再发 1 次最终状态（共计 2 次）。
                let signal = tokio::time::timeout(Duration::from_secs(2), actor.signal_rx.recv())
                    .await
                    .expect("trailing report timer")
                    .expect("trailing report signal");
                actor.handle_signal(signal).await;

                let recorded = calls.lock().unwrap().clone();
                assert_eq!(recorded.len(), 2);
                assert!(recorded[1].contains("client_input_muted=0"));
            })
            .await;
    }

    #[tokio::test]
    async fn flood_524_triggers_backoff_without_warn_and_non_524_notifies_once() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let calls = Arc::new(std::sync::Mutex::new(Vec::new()));
                let results = Arc::new(std::sync::Mutex::new(VecDeque::from([
                    Err(tsclient_rs::Error::ServerError {
                        id: "524".into(),
                        server_message: "client is flooding".into(),
                        extra_message: None,
                    }),
                    Err(tsclient_rs::Error::ServerError {
                        id: "0".into(),
                        server_message: "ok".into(),
                        extra_message: None,
                    }),
                    Err(tsclient_rs::Error::ServerError {
                        id: "2568".into(),
                        server_message: "insufficient client permissions".into(),
                        extra_message: None,
                    }),
                ])));
                let client = Client::new(
                    tsclient_rs::generateIdentity(0),
                    "127.0.0.1:9987".into(),
                    "test".into(),
                    tsclient_rs::ClientOptions {
                        command_middleware: vec![Box::new(RecordingClientUpdateMiddleware {
                            calls: Arc::clone(&calls),
                            next_result: results,
                        })],
                        ..Default::default()
                    },
                );
                client.mark_connected();

                let mut actor = audio_actor();
                actor.self_client_id = Some(1);
                actor.client = Some(Arc::new(client));
                let mut events = actor.events.subscribe();

                actor.apply_muted(true).unwrap();
                actor.request_state_update().await;

                // 524 进入退避（debug 日志直通 tracing 而不入广播通道），不发 warn 或 Failed 弹窗。
                assert_eq!(actor.voice_report.flood_retries, 1);
                assert_eq!(actor.voice_report.window, Duration::from_millis(1200));
                assert!(actor.voice_report.trailing_scheduled);
                let first_round: Vec<SessionEvent> =
                    std::iter::from_fn(|| events.try_recv().ok()).collect();
                assert!(!first_round.iter().any(|ev| matches!(
                    ev,
                    SessionEvent::Log { level, .. } if level == "warn"
                ) || matches!(
                    ev,
                    SessionEvent::Failed { .. }
                )));

                // 1200ms 退避后重试成功，基础窗口恢复为 600ms。
                let signal = tokio::time::timeout(Duration::from_secs(3), actor.signal_rx.recv())
                    .await
                    .expect("backoff timer")
                    .expect("backoff signal");
                actor.handle_signal(signal).await;
                assert_eq!(actor.voice_report.window, VOICE_REPORT_BASE_WINDOW);
                assert_eq!(calls.lock().unwrap().len(), 2);

                // 模拟冷却窗口已过后新操作遇非 524 错误：停重试、记 warn、触发一次 Failed 提示，本地仍保持状态。
                actor.voice_report.last_attempt =
                    Some(ReportInstant::now() - VOICE_REPORT_BASE_WINDOW);
                actor.apply_away(true);
                actor.request_state_update().await;
                assert!(actor.voice_state.away);
                assert!(actor.voice_report.unconfirmed);

                let second_round: Vec<SessionEvent> =
                    std::iter::from_fn(|| events.try_recv().ok()).collect();
                assert!(second_round.iter().any(|ev| matches!(
                    ev,
                    SessionEvent::Log { level, .. } if level == "warn"
                )));
                assert_eq!(
                    second_round
                        .iter()
                        .filter(|ev| matches!(ev, SessionEvent::Failed { .. }))
                        .count(),
                    1
                );
            })
            .await;
    }
}
