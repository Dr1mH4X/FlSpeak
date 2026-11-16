//! 音频流错误分类、退避恢复状态机与虚拟默认设备推断。
//!
//! 纯逻辑不依赖 `cpal`，确保无 `audio` feature 时也可完整编译与单测。

use std::time::{Duration, Instant};

pub const RECOVERY_BACKOFF: [Duration; 4] = [
    Duration::from_millis(200),
    Duration::from_millis(500),
    Duration::from_millis(1_000),
    Duration::from_millis(2_000),
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StreamErrorKind {
    /// 后端已自动重路由到新的默认设备，现有流仍有效，无需重建。
    DeviceChanged,
    /// 设备断开或流已失效，必须关闭并重建。
    Disconnected,
    /// 系统拒绝权限，不应自动重试。
    PermissionDenied,
    /// 欠载/过载或实时调度提示等非致命信息，忽略即可。
    NonFatal,
    /// 其他错误，按断流做有限次重建尝试。
    Other,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StreamError {
    pub kind: StreamErrorKind,
    pub message: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryFailure {
    Scheduled { next_at: Instant, attempt: u32 },
    Exhausted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum RecoveryState {
    #[default]
    Idle,
    Active,
    RetryPending {
        next_at: Instant,
        attempt: u32,
    },
    Failed,
}

impl RecoveryState {
    pub fn reset(&mut self) {
        *self = Self::Idle;
    }

    pub fn on_open_succeeded(&mut self) {
        *self = Self::Active;
    }

    pub fn on_open_failed(&mut self, now: Instant, retryable: bool) -> RecoveryFailure {
        if !retryable {
            *self = Self::Failed;
            return RecoveryFailure::Exhausted;
        }
        let attempt = match *self {
            Self::RetryPending { attempt, .. } => attempt,
            Self::Idle | Self::Active | Self::Failed => 0,
        };
        let Some(&delay) = RECOVERY_BACKOFF.get(attempt as usize) else {
            *self = Self::Failed;
            return RecoveryFailure::Exhausted;
        };
        let next_attempt = attempt + 1;
        let next_at = now + delay;
        *self = Self::RetryPending {
            next_at,
            attempt: next_attempt,
        };
        RecoveryFailure::Scheduled {
            next_at,
            attempt: next_attempt,
        }
    }

    pub fn next_deadline(&self) -> Option<Instant> {
        match *self {
            Self::RetryPending { next_at, .. } => Some(next_at),
            Self::Idle | Self::Active | Self::Failed => None,
        }
    }

    pub fn due_for_retry(&self, now: Instant) -> bool {
        matches!(*self, Self::RetryPending { next_at, .. } if now >= next_at)
    }
}

/// 判断设备 ID 是否指向虚拟默认设备占位（如 Android AAudio 的 `-1` / `aaudio:-1`）。
pub fn is_virtual_default_device_id(id: &str) -> bool {
    let device_part = id.split_once(':').map_or(id, |(_, rest)| rest);
    device_part == "-1"
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DeviceCandidate {
    pub is_builtin: bool,
    pub is_speaker: bool,
    pub is_microphone: bool,
}

/// 当系统的 `default_*_device()` 返回虚拟占位 ID、无法在具体设备列表里直接匹配时，
/// 根据设备描述推断默认的内置扬声器或内置麦克风索引。
pub fn pick_fallback_default_index(input: bool, candidates: &[DeviceCandidate]) -> Option<usize> {
    if input {
        candidates
            .iter()
            .position(|c| c.is_builtin && c.is_microphone)
            .or_else(|| candidates.iter().position(|c| c.is_microphone))
            .or_else(|| candidates.iter().position(|c| c.is_builtin))
    } else {
        candidates
            .iter()
            .position(|c| c.is_builtin && c.is_speaker)
            .or_else(|| candidates.iter().position(|c| c.is_speaker))
            .or_else(|| candidates.iter().position(|c| c.is_builtin))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recovery_schedules_backoff_then_exhausts() {
        let mut state = RecoveryState::default();
        let t0 = Instant::now();

        for (idx, expected_delay) in RECOVERY_BACKOFF.iter().enumerate() {
            let outcome = state.on_open_failed(t0, true);
            assert_eq!(
                outcome,
                RecoveryFailure::Scheduled {
                    next_at: t0 + *expected_delay,
                    attempt: (idx + 1) as u32,
                }
            );
            assert!(!state.due_for_retry(t0 + *expected_delay - Duration::from_millis(1)));
            assert!(state.due_for_retry(t0 + *expected_delay));
        }

        assert_eq!(state.on_open_failed(t0, true), RecoveryFailure::Exhausted);
        assert_eq!(state, RecoveryState::Failed);
        assert_eq!(state.next_deadline(), None);
    }

    #[test]
    fn non_retryable_error_fails_immediately_and_open_resets() {
        let mut state = RecoveryState::default();
        let t0 = Instant::now();
        assert_eq!(state.on_open_failed(t0, false), RecoveryFailure::Exhausted);
        assert_eq!(state, RecoveryState::Failed);

        state.on_open_succeeded();
        assert_eq!(state, RecoveryState::Active);
        assert_eq!(
            state.on_open_failed(t0, true),
            RecoveryFailure::Scheduled {
                next_at: t0 + RECOVERY_BACKOFF[0],
                attempt: 1,
            }
        );

        state.reset();
        assert_eq!(state, RecoveryState::Idle);
    }

    #[test]
    fn virtual_default_id_and_builtin_fallback_heuristics() {
        assert!(is_virtual_default_device_id("-1"));
        assert!(is_virtual_default_device_id("aaudio:-1"));
        assert!(!is_virtual_default_device_id("aaudio:2"));
        assert!(!is_virtual_default_device_id(
            "coreaudio:BuiltInSpeakerDevice"
        ));

        let outputs = [
            DeviceCandidate {
                is_builtin: true,
                is_speaker: false,
                is_microphone: false,
            },
            DeviceCandidate {
                is_builtin: true,
                is_speaker: true,
                is_microphone: false,
            },
            DeviceCandidate {
                is_builtin: false,
                is_speaker: true,
                is_microphone: false,
            },
        ];
        assert_eq!(pick_fallback_default_index(false, &outputs), Some(1));

        let inputs = [
            DeviceCandidate {
                is_builtin: false,
                is_speaker: false,
                is_microphone: true,
            },
            DeviceCandidate {
                is_builtin: true,
                is_speaker: false,
                is_microphone: true,
            },
        ];
        assert_eq!(pick_fallback_default_index(true, &inputs), Some(1));
    }
}
