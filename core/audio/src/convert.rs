//! 设备格式与协议格式之间的声道映射和重采样。
//!
//! 非等采样率路径使用预计算的加窗 sinc 多相 FIR（降采样自动收窄截止频率以抗混叠），
//! 48kHz 同采样率路径直接透传；状态全部由 `FormatConverter` 持有，调用方可以任意切分输入块。

use std::f32::consts::PI;

use crate::format::AudioFormat;

const HALF_TAPS: usize = 8;
const TAPS: usize = HALF_TAPS * 2;
const PHASE_STEPS: usize = 256;

/// 预计算的 `(PHASE_STEPS + 1) * TAPS` 多相滤波系数表。
fn build_polyphase_table(src_rate: u32, dst_rate: u32) -> Vec<f32> {
    let cutoff = (dst_rate as f64 / src_rate as f64).min(1.0) as f32;
    let radius = HALF_TAPS as f32;
    let mut table = Vec::with_capacity((PHASE_STEPS + 1) * TAPS);

    for phase in 0..=PHASE_STEPS {
        let frac = phase as f32 / PHASE_STEPS as f32;
        let start = table.len();
        let mut sum = 0.0f32;
        for tap in 0..TAPS {
            let offset = tap as isize - (HALF_TAPS as isize - 1);
            let x = offset as f32 - frac;
            let sinc = if x.abs() < 1e-6 {
                cutoff
            } else {
                let arg = PI * cutoff * x;
                arg.sin() / (PI * x)
            };
            let window = if x.abs() >= radius {
                0.0
            } else {
                let norm = x / radius;
                0.42 + 0.5 * (PI * norm).cos() + 0.08 * (2.0 * PI * norm).cos()
            };
            let weight = sinc * window;
            table.push(weight);
            sum += weight;
        }
        if sum.abs() > 1e-6 {
            let inv = 1.0 / sum;
            for weight in &mut table[start..] {
                *weight *= inv;
            }
        }
    }
    table
}

/// 交织样本的流式格式转换器。
///
/// 构造函数接受源/目标格式；`process` 可以反复调用，分块边界不会造成断点。
pub struct FormatConverter {
    src: AudioFormat,
    dst: AudioFormat,
    /// 已经映射到目标声道数的待消费源帧。
    buffer: Vec<f32>,
    /// 下一个输出样本在 `buffer` 中的整数源帧位置。
    buf_frame: usize,
    /// 相位分子（`0 <= phase_num < dst.sample_rate_hz`），避免长时运行浮点累加漂移。
    phase_num: u64,
    /// 一帧目标声道数的临时缓冲，避免每个源帧都分配。
    frame: Vec<f32>,
    /// 异采样率时预计算的多相 FIR 系数表；同采样率时为空。
    table: Vec<f32>,
}

impl FormatConverter {
    pub fn new(src: AudioFormat, dst: AudioFormat) -> Self {
        let needs_resample = src.sample_rate_hz != 0
            && dst.sample_rate_hz != 0
            && src.sample_rate_hz != dst.sample_rate_hz
            && dst.channels > 0;
        let (buffer, buf_frame, table) = if needs_resample {
            let pre_history = (HALF_TAPS - 1) * dst.channels as usize;
            (
                vec![0.0; pre_history],
                HALF_TAPS - 1,
                build_polyphase_table(src.sample_rate_hz, dst.sample_rate_hz),
            )
        } else {
            (Vec::new(), 0, Vec::new())
        };
        Self {
            src,
            dst,
            buffer,
            buf_frame,
            phase_num: 0,
            frame: Vec::new(),
            table,
        }
    }

    pub fn src(&self) -> AudioFormat {
        self.src
    }

    pub fn dst(&self) -> AudioFormat {
        self.dst
    }

    /// 消费一段交织样本，把转换结果追加到 `output`。
    pub fn process(&mut self, input: &[f32], output: &mut Vec<f32>) {
        let src_channels = self.src.channels as usize;
        let dst_channels = self.dst.channels as usize;
        if src_channels == 0
            || dst_channels == 0
            || self.src.sample_rate_hz == 0
            || self.dst.sample_rate_hz == 0
        {
            return;
        }

        let frames = input.len() / src_channels;
        if frames == 0 {
            return;
        }

        for index in 0..frames {
            let start = index * src_channels;
            self.map_frame(&input[start..start + src_channels], dst_channels);
            self.buffer.extend_from_slice(&self.frame);
        }

        if self.src.sample_rate_hz == self.dst.sample_rate_hz {
            output.extend_from_slice(&self.buffer);
            self.buffer.clear();
            self.buf_frame = 0;
            self.phase_num = 0;
            return;
        }

        let src_rate = self.src.sample_rate_hz as u64;
        let dst_rate = self.dst.sample_rate_hz as u64;
        let total_frames = self.buffer.len() / dst_channels;

        loop {
            let base = self.buf_frame;
            if base + HALF_TAPS >= total_frames {
                break;
            }
            let frac = self.phase_num as f32 / dst_rate as f32;
            let scaled = (frac * PHASE_STEPS as f32).clamp(0.0, PHASE_STEPS as f32);
            let phase_lo = (scaled.floor() as usize).min(PHASE_STEPS);
            let phase_hi = (phase_lo + 1).min(PHASE_STEPS);
            let alpha = scaled - phase_lo as f32;
            let row_lo = &self.table[phase_lo * TAPS..(phase_lo + 1) * TAPS];
            let row_hi = &self.table[phase_hi * TAPS..(phase_hi + 1) * TAPS];
            let first_frame = base - (HALF_TAPS - 1);

            for channel in 0..dst_channels {
                let mut acc = 0.0f32;
                for tap in 0..TAPS {
                    let weight = row_lo[tap] + (row_hi[tap] - row_lo[tap]) * alpha;
                    let sample = self.buffer[(first_frame + tap) * dst_channels + channel];
                    acc += sample * weight;
                }
                output.push(acc.clamp(-1.0, 1.0));
            }
            let next_phase = self.phase_num + src_rate;
            self.buf_frame += (next_phase / dst_rate) as usize;
            self.phase_num = next_phase % dst_rate;
        }

        let keep_from = self.buf_frame.saturating_sub(HALF_TAPS - 1);
        if keep_from > 0 {
            self.buffer.drain(..keep_from * dst_channels);
            self.buf_frame -= keep_from;
        }
    }

    fn map_frame(&mut self, source: &[f32], dst_channels: usize) {
        self.frame.clear();
        let src_channels = source.len();
        match (src_channels, dst_channels) {
            (1, _) => {
                self.frame.resize(dst_channels, source[0]);
            }
            (_, 1) => {
                let sum: f32 = source.iter().sum();
                self.frame.push(sum / src_channels as f32);
            }
            _ => {
                for channel in 0..dst_channels {
                    self.frame.push(source.get(channel).copied().unwrap_or(0.0));
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PCM: AudioFormat = AudioFormat {
        sample_rate_hz: 48_000,
        channels: 2,
    };

    fn format(sample_rate_hz: u32, channels: u16) -> AudioFormat {
        AudioFormat {
            sample_rate_hz,
            channels,
        }
    }

    #[test]
    fn same_format_passes_through() {
        let mut converter = FormatConverter::new(PCM, PCM);
        let mut output = Vec::new();
        converter.process(&[0.0, 1.0, 2.0, 3.0], &mut output);
        assert_eq!(output, vec![0.0, 1.0, 2.0, 3.0]);

        converter.process(&[4.0, 5.0], &mut output);
        assert_eq!(output, vec![0.0, 1.0, 2.0, 3.0, 4.0, 5.0]);
    }

    #[test]
    fn mono_is_duplicated_to_stereo() {
        let mut converter = FormatConverter::new(format(48_000, 1), PCM);
        let mut output = Vec::new();
        converter.process(&[0.25, -0.5], &mut output);
        assert_eq!(output, vec![0.25, 0.25, -0.5, -0.5]);
    }

    #[test]
    fn stereo_is_averaged_to_mono() {
        let mut converter = FormatConverter::new(PCM, format(48_000, 1));
        let mut output = Vec::new();
        converter.process(&[1.0, 0.0, 0.5, -0.5], &mut output);
        assert_eq!(output, vec![0.5, 0.0]);
    }

    #[test]
    fn upsampling_doubles_the_frame_count() {
        let mut converter = FormatConverter::new(format(24_000, 2), PCM);
        let mut output = Vec::new();
        converter.process(&[0.0; 960], &mut output);
        let lookahead = HALF_TAPS * 4;
        assert!(
            output.len() >= 1920 - lookahead && output.len() <= 1920,
            "{}",
            output.len()
        );

        // 下一块继续输出，不丢连续性。
        converter.process(&[0.0; 960], &mut output);
        assert!(
            output.len() >= 3840 - lookahead && output.len() <= 3840,
            "{}",
            output.len()
        );
    }

    #[test]
    fn downsampling_halves_the_frame_count() {
        let mut converter = FormatConverter::new(PCM, format(24_000, 2));
        let mut output = Vec::new();
        converter.process(&[0.0; 1920], &mut output);
        let lookahead = HALF_TAPS * 2;
        assert!(
            output.len() >= 960 - lookahead && output.len() <= 960,
            "{}",
            output.len()
        );
    }

    #[test]
    fn dc_and_passband_sine_preserve_unity_gain_across_rates() {
        for src_rate in [16_000, 44_100, 96_000] {
            let mut dc = FormatConverter::new(format(src_rate, 1), format(48_000, 1));
            let mut dc_out = Vec::new();
            dc.process(&vec![0.75; 4000], &mut dc_out);
            let tail = &dc_out[dc_out.len() / 2..];
            for &sample in tail {
                assert!(
                    (sample - 0.75).abs() < 1e-4,
                    "src_rate={src_rate} dc drift: {sample}"
                );
            }

            let mut sine = FormatConverter::new(format(src_rate, 1), format(48_000, 1));
            let input: Vec<f32> = (0..4000)
                .map(|i| (2.0 * PI * 1000.0 * i as f32 / src_rate as f32).sin())
                .collect();
            let mut sine_out = Vec::new();
            sine.process(&input, &mut sine_out);
            let peak = sine_out[sine_out.len() / 2..]
                .iter()
                .map(|s| s.abs())
                .fold(0.0f32, f32::max);
            assert!(
                (peak - 1.0).abs() < 0.02,
                "src_rate={src_rate} 1kHz peak={peak}"
            );
        }
    }

    #[test]
    fn downsampling_attenuates_aliasing_above_nyquist() {
        // 96kHz -> 48kHz 时，36kHz（高于目标 Nyquist 24kHz）应被显著抑制，而不是混叠成 12kHz。
        let mut converter = FormatConverter::new(format(96_000, 1), format(48_000, 1));
        let input: Vec<f32> = (0..4800)
            .map(|i| (2.0 * PI * 36_000.0 * i as f32 / 96_000.0).sin())
            .collect();
        let mut output = Vec::new();
        converter.process(&input, &mut output);
        let rms_out = (output[output.len() / 2..]
            .iter()
            .map(|s| s * s)
            .sum::<f32>()
            / (output.len() / 2) as f32)
            .sqrt();
        assert!(rms_out < 0.05, "alias leakage too high: rms={rms_out}");
    }

    #[test]
    fn chunk_boundaries_do_not_change_the_output() {
        let source_rate = format(44_100, 2);
        let samples: Vec<f32> = (0..4410)
            .flat_map(|index| {
                let value = (index as f32 * 0.01).sin();
                [value, -value]
            })
            .collect();

        let mut whole = FormatConverter::new(source_rate, PCM);
        let mut whole_output = Vec::new();
        whole.process(&samples, &mut whole_output);

        let mut chunked = FormatConverter::new(source_rate, PCM);
        let mut chunked_output = Vec::new();
        for chunk in samples.chunks(882) {
            chunked.process(chunk, &mut chunked_output);
        }

        assert_eq!(whole_output.len(), chunked_output.len());
        assert_eq!(whole_output, chunked_output);
    }

    #[test]
    fn resampling_clamps_sinc_overshoot_within_unit_bounds() {
        // 48kHz -> 44.1kHz 下对全幅阶跃信号做 Sinc 重采样，输出必须严格钳位在 [-1.0, 1.0]。
        let mut converter = FormatConverter::new(PCM, format(44_100, 2));
        let mut input = vec![-1.0f32; 480];
        input.extend(vec![1.0f32; 480]);
        let mut output = Vec::new();
        converter.process(&input, &mut output);
        assert!(!output.is_empty());
        assert!(output.iter().all(|s| (-1.0..=1.0).contains(s)));
    }

    #[test]
    fn invalid_formats_are_ignored() {
        let mut converter = FormatConverter::new(format(0, 0), PCM);
        let mut output = Vec::new();
        converter.process(&[1.0, 2.0], &mut output);
        assert!(output.is_empty());
    }
}
