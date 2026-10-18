//! 混音后的软削波。
//!
//! 多人同时说话时硬 clamp 会产生刺耳的削顶失真。这里用带连续一阶导数的三段曲线：
//! `|x| <= KNEE` 线性，超过后按 `tanh` 压缩，最大输出接近 1 但不会硬切。

pub const KNEE: f32 = 0.5;

pub fn soft_clip(sample: f32) -> f32 {
    let magnitude = sample.abs();
    if magnitude <= KNEE {
        return sample;
    }
    let compressed = KNEE + (1.0 - KNEE) * ((magnitude - KNEE) / (1.0 - KNEE)).tanh();
    compressed.copysign(sample)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn passes_small_samples_through() {
        assert_eq!(soft_clip(0.0), 0.0);
        assert_eq!(soft_clip(0.25), 0.25);
        assert_eq!(soft_clip(-0.5), -0.5);
    }

    #[test]
    fn compresses_without_hard_clipping() {
        let high = soft_clip(1.0);
        assert!(high > 0.5 && high < 1.0, "{high}");
        let very_high = soft_clip(10.0);
        assert!(very_high >= high && very_high <= 1.0, "{very_high}");
    }

    #[test]
    fn is_symmetric_and_monotonic() {
        let mut previous = -1.0;
        for step in 0..=200 {
            let x = step as f32 / 100.0 - 1.0;
            let y = soft_clip(x);
            assert!(y >= previous - 1e-6, "{x} {y} {previous}");
            assert!((soft_clip(-x) + y).abs() < 1e-6);
            previous = y;
        }
    }
}
