//! 跨 FFI 的稳定提示码。UI 文案由 Dart 的 `arb/` 映射，Rust 只传代码。

pub const VOICE_INPUT_UNAVAILABLE: &str = "voice.input_unavailable";
pub const VOICE_OUTPUT_UNAVAILABLE: &str = "voice.output_unavailable";
pub const VOICE_CODEC_UNAVAILABLE: &str = "voice.codec_unavailable";
pub const VOICE_CODEC_UNSUPPORTED: &str = "voice.codec_unsupported";
pub const VOICE_CAPTURE_FAILED: &str = "voice.capture_failed";
pub const VOICE_PLAYBACK_FAILED: &str = "voice.playback_failed";
pub const VOICE_CODEC_FAILED: &str = "voice.codec_failed";
pub const VOICE_SYNC_FAILED: &str = "voice.sync_failed";

pub const SESSION_CONNECTION_LOST: &str = "session.connection_lost";
pub const SESSION_KICKED: &str = "session.kicked";
pub const SESSION_CONNECT_FAILED: &str = "session.connect_failed";
pub const SESSION_CONNECT_TIMEOUT: &str = "session.connect_timeout";
pub const SESSION_CONNECT_DENIED: &str = "session.connect_denied";
pub const SESSION_RECONNECT_EXHAUSTED: &str = "session.reconnect_exhausted";
pub const SESSION_IDENTITY_READ_FAILED: &str = "session.identity_read_failed";
pub const SESSION_IDENTITY_UPGRADE_FAILED: &str = "session.identity_upgrade_failed";
pub const SESSION_IDENTITY_THREAD_FAILED: &str = "session.identity_thread_failed";
pub const SESSION_HISTORY_WRITE_FAILED: &str = "session.history_write_failed";
pub const SESSION_HISTORY_COMPACT_FAILED: &str = "session.history_compact_failed";
pub const SESSION_SETTINGS_LOAD_FAILED: &str = "session.settings_load_failed";
pub const SESSION_ACTOR_START_FAILED: &str = "session.actor_start_failed";
