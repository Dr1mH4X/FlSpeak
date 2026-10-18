//! 设备格式与协议格式之间的声道映射和重采样。
//!
//! 语音只用流式线性插值：48kHz 立体声是统一中间格式，设备给什么就转什么。
//! 状态全部由 `FormatConverter` 持有，调用方可以任意切分输入块。

use crate::format::AudioFormat;

/// 交织样本的流式格式转换器。
///
/// 构造函数接受源/目标格式；`process` 可以反复调用，分块边界不会造成断点。
pub struct FormatConverter {
    src: AudioFormat,
    dst: AudioFormat,
    /// 已经映射到目标声道数的待消费源帧。
    buffer: Vec<f32>,
    /// 下一个输出样本在 `buffer` 中的位置（以源帧为单位）。
    position: f64,
    /// 一帧目标声道数的临时缓冲，避免每个源帧都分配。
    frame: Vec<f32>,
}

impl FormatConverter {
    pub fn new(src: AudioFormat, dst: AudioFormat) -> Self {
        Self {
            src,
            dst,
            buffer: Vec::new(),
            position: 0.0,
            frame: Vec::new(),
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
            self.position = 0.0;
            return;
        }

        let ratio = self.src.sample_rate_hz as f64 / self.dst.sample_rate_hz as f64;
        let total_frames = self.buffer.len() / dst_channels;

        loop {
            let index = self.position.floor() as usize;
            if index + 1 >= total_frames {
                break;
            }
            let fraction = (self.position - index as f64) as f32;
            let left = index * dst_channels;
            let right = left + dst_channels;
            for channel in 0..dst_channels {
                let a = self.buffer[left + channel];
                let b = self.buffer[right + channel];
                output.push(a + (b - a) * fraction);
            }
            self.position += ratio;
        }

        // 至少留一帧，下一块才能和这一块插值衔接。
        let consumed = (self.position.floor() as usize).min(total_frames.saturating_sub(1));
        if consumed > 0 {
            self.buffer.drain(..consumed * dst_channels);
            self.position -= consumed as f64;
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
        assert!(
            output.len() >= 1916 && output.len() <= 1920,
            "{}",
            output.len()
        );

        // 下一块继续输出，不丢连续性。
        converter.process(&[0.0; 960], &mut output);
        assert!(
            output.len() >= 3836 && output.len() <= 3840,
            "{}",
            output.len()
        );
    }

    #[test]
    fn downsampling_halves_the_frame_count() {
        let mut converter = FormatConverter::new(PCM, format(24_000, 2));
        let mut output = Vec::new();
        converter.process(&[0.0; 1920], &mut output);
        assert!(
            output.len() >= 958 && output.len() <= 960,
            "{}",
            output.len()
        );
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
    fn invalid_formats_are_ignored() {
        let mut converter = FormatConverter::new(format(0, 0), PCM);
        let mut output = Vec::new();
        converter.process(&[1.0, 2.0], &mut output);
        assert!(output.is_empty());
    }
}
