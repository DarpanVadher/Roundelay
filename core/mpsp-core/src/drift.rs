//! Clock-drift correction for the guest's output.
//!
//! The host's capture clock and the guest's DAC clock never run at exactly the same rate (typically
//! +-50 ppm, sometimes far more on phones), so a fixed-rate player slowly over/under-runs. We hold the
//! playout queue near a target fill level by nudging a linear-interpolation resampler's ratio by at
//! most +-0.5% (inaudible), which also keeps all guests aligned to the same host timeline.
use std::collections::VecDeque;

/// Stereo (interleaved) linear-interpolation resampler pulling from a queue.
#[derive(Default)]
pub struct Resampler { frac: f64, prev: [f32; 2] }

impl Resampler {
    /// Fill `out` (interleaved stereo), consuming about `ratio` input frames per output frame.
    pub fn pull(&mut self, q: &mut VecDeque<f32>, ratio: f64, out: &mut [f32]) {
        for o in out.chunks_exact_mut(2) {
            if q.len() < 2 { o[0] = self.prev[0]; o[1] = self.prev[1]; continue; } // hold on underrun
            let f = self.frac as f32;
            o[0] = self.prev[0] + (q[0] - self.prev[0]) * f;
            o[1] = self.prev[1] + (q[1] - self.prev[1]) * f;
            self.frac += ratio;
            while self.frac >= 1.0 && q.len() >= 2 {
                self.frac -= 1.0;
                self.prev = [q.pop_front().unwrap(), q.pop_front().unwrap()];
            }
        }
    }
}

/// Converts interleaved stereo captured at the sound card's rate to 48 kHz in fixed-size chunks (the Opus encoder
/// needs 48 kHz). Used by the host when the device being captured is not a 48 kHz one (e.g. Bluetooth at 44.1 kHz).
pub struct RateConverter { ratio: f64, rs: Resampler, q: VecDeque<f32> }

impl RateConverter {
    pub fn new(input_hz: u32) -> Self { Self { ratio: input_hz as f64 / 48_000.0, rs: Resampler::default(), q: VecDeque::new() } }

    /// Feed captured samples; `emit` is called with each ready chunk of `chunk_frames` stereo frames at 48 kHz.
    pub fn push(&mut self, input: &[f32], chunk_frames: usize, mut emit: impl FnMut(&[f32])) {
        self.q.extend(input);
        let need = (chunk_frames as f64 * self.ratio).ceil() as usize + 2;
        let mut out = vec![0f32; chunk_frames * 2];
        while self.q.len() / 2 >= need {
            self.rs.pull(&mut self.q, self.ratio, &mut out);
            emit(&out);
        }
    }
}

/// Smooths the queue fill level and maps its error to a resampling ratio.
pub struct DriftController { target: f64, smooth: f64 }

impl DriftController {
    const ALPHA: f64 = 0.05;       // fill-level low-pass (callbacks are bursty)
    const GAIN: f64 = 2e-5;        // ratio change per frame of error
    const MAX_OFFSET: f64 = 0.005; // +-0.5%
    pub fn new(target_frames: usize) -> Self { Self { target: target_frames as f64, smooth: target_frames as f64 } }
    pub fn reset(&mut self) { self.smooth = self.target; }
    /// Fill above target -> consume faster (ratio > 1); below -> slower.
    pub fn update(&mut self, fill_frames: usize) -> f64 {
        self.smooth += Self::ALPHA * (fill_frames as f64 - self.smooth);
        1.0 + ((self.smooth - self.target) * Self::GAIN).clamp(-Self::MAX_OFFSET, Self::MAX_OFFSET)
    }
}

/// Playout queue + resampler + controller. `push` from the decoder, `render` from the audio callback.
pub struct Playout {
    q: VecDeque<f32>, rs: Resampler, ctl: DriftController,
    target: usize, started: bool,
    /// Input (48 kHz) frames consumed per output frame at the sound card's own rate: 48000 / device_rate.
    rate_ratio: f64,
    pub underruns: u64, pub ratio: f64, pub fill: usize,
}

impl Playout {
    pub fn new(target_frames: usize) -> Self {
        Self { q: VecDeque::new(), rs: Resampler::default(), ctl: DriftController::new(target_frames),
               target: target_frames, started: false, rate_ratio: 1.0, underruns: 0, ratio: 1.0, fill: 0 }
    }
    /// Tell the playout the sound card runs at `hz` instead of 48 kHz (many Bluetooth devices only do 44.1 kHz);
    /// `render` then converts as it plays. Call before the first `render` on a (re)opened stream.
    pub fn set_output_rate(&mut self, hz: u32) {
        self.rate_ratio = 48_000.0 / hz.max(1) as f64;
    }

    /// Frames waiting in the queue right now.
    pub fn queued_frames(&self) -> usize { self.q.len() / 2 }
    /// Whether playback has begun (false while (re)buffering).
    pub fn is_started(&self) -> bool { self.started }
    /// Current queue target in frames (the base target, grown to fit the sound card's callback size).
    pub fn target_frames(&self) -> usize { self.target }

    /// Forget everything queued and re-buffer from scratch. Used after the output device changed (the old stream
    /// died), so we do not play seconds-old audio or carry a stale fill estimate into the new stream.
    pub fn reset(&mut self) {
        self.q.clear();
        self.rs = Resampler::default();
        self.ctl.reset();
        self.started = false;
        self.ratio = 1.0;
    }
    /// Interleaved stereo samples.
    pub fn push(&mut self, pcm: &[f32]) {
        self.q.extend(pcm);
        while self.q.len() / 2 > self.target * 4 { self.q.pop_front(); self.q.pop_front(); } // after a stall
    }
    /// Fill interleaved stereo `out`. Outputs silence until the queue reaches the target, and re-buffers
    /// after an underrun so latency stays constant.
    pub fn render(&mut self, out: &mut [f32]) {
        let fill = self.q.len() / 2;
        self.fill = fill;
        if !self.started {
            if fill >= self.target { self.started = true; } else { out.fill(0.0); return; }
        }
        self.ratio = self.ctl.update(fill); // drift correction alone (what the UI shows as ppm)
        let step = self.ratio * self.rate_ratio; // input frames per output frame, drift and device rate combined
        let need = (out.len() / 2) as f64 * step + 2.0;
        if (fill as f64) < need {
            self.started = false; self.underruns += 1; self.ctl.reset(); out.fill(0.0); return;
        }
        self.rs.pull(&mut self.q, step, out);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ramp(n: usize) -> VecDeque<f32> { (0..n).flat_map(|i| [i as f32, i as f32]).collect() }

    #[test]
    fn unity_ratio_is_one_frame_delayed_passthrough() {
        let (mut r, mut q, mut out) = (Resampler::default(), ramp(20), vec![0f32; 20]);
        r.pull(&mut q, 1.0, &mut out);
        for k in 1..10 { assert_eq!(out[k * 2], (k - 1) as f32); }
    }

    #[test]
    fn higher_ratio_consumes_proportionally_more() {
        let (mut r, mut q, mut out) = (Resampler::default(), ramp(20_000), vec![0f32; 2 * 10_000]);
        r.pull(&mut q, 1.01, &mut out);
        let consumed = 20_000 - q.len() / 2;
        assert!((consumed as i64 - 10_100).abs() <= 2, "consumed {consumed}");
    }

    // Target must exceed one packet (480) + one callback (480) + margin: fill is only observed in
    // whole-packet steps, so one step down must still leave enough to render.
    const TARGET: usize = 1920;

    #[test]
    fn reset_discards_queue_and_rebuffers_before_playing_again() {
        let mut p = Playout::new(TARGET);
        p.push(&vec![0.5f32; 2 * (TARGET + 100)]);
        let mut out = vec![0f32; 960];
        p.render(&mut out);
        assert!(out.iter().any(|&x| x != 0.0), "plays once the target is buffered");
        p.reset();
        out.fill(1.0);
        p.render(&mut out);
        assert!(out.iter().all(|&x| x == 0.0), "silent after reset until refilled");
        assert_eq!((p.fill, p.underruns), (0, 0));
        p.push(&vec![0.5f32; 2 * (TARGET + 100)]);
        p.render(&mut out);
        assert!(out.iter().any(|&x| x != 0.0), "plays again after refilling");
    }

    /// Simulates producer/consumer clocks differing by `ppm`, 480-frame chunks, for 120 s.
    fn simulate(prod_period_us: u64) -> Playout {
        let mut p = Playout::new(TARGET);
        let (mut next_prod, mut next_cons) = (0u64, 0u64);
        let mut out = vec![0f32; 960];
        while next_prod.min(next_cons) < 120_000_000 {
            if next_prod <= next_cons { p.push(&vec![0.1f32; 960]); next_prod += prod_period_us; }
            else { p.render(&mut out); next_cons += 10_000; }
        }
        p
    }

    #[test]
    fn fast_producer_fill_stays_bounded() { // producer +0.1%: uncorrected fill would grow ~5760 frames
        let p = simulate(9_990);
        assert_eq!(p.underruns, 0);
        assert!((p.fill as i64 - TARGET as i64).abs() <= 600, "fill {}", p.fill);
    }

    #[test]
    fn slow_producer_no_underruns_and_bounded() { // producer -0.1%: uncorrected would underrun repeatedly
        let p = simulate(10_010);
        assert_eq!(p.underruns, 0);
        assert!((p.fill as i64 - TARGET as i64).abs() <= 600, "fill {}", p.fill);
    }

    /// Zero crossings per second of the loud part of a mono-from-left signal sampled at `rate`.
    fn tone_hz(samples: &[f32], rate: f64) -> f64 {
        let crossings = samples.windows(2).filter(|w| (w[0] < 0.0) != (w[1] < 0.0)).count();
        crossings as f64 / 2.0 / (samples.len() as f64 / rate)
    }

    fn sine_48k(hz: f64, seconds: f64) -> Vec<f32> {
        (0..(48_000.0 * seconds) as usize).flat_map(|i| { let v = (2.0 * std::f64::consts::PI * hz * i as f64 / 48_000.0).sin() as f32 * 0.5; [v, v] }).collect()
    }

    #[test]
    fn playing_at_44100_keeps_the_pitch() {
        let mut p = Playout::new(TARGET);
        p.set_output_rate(44_100);
        let tone = sine_48k(1000.0, 3.0);
        let mut out = vec![0f32; 441 * 2]; // 10 ms at 44.1 kHz
        let mut left = Vec::new();
        // Audio arrives 10 ms at a time (480 frames), exactly as the network delivers it, and is consumed 10 ms at a time.
        for chunk in tone.chunks(480 * 2).take(250) {
            p.push(chunk);
            p.render(&mut out);
            left.extend(out.iter().step_by(2));
        }
        let steady = &left[44_100 / 2..]; // skip the initial buffering silence (~0.5 s is generous)
        let hz = tone_hz(steady, 44_100.0);
        assert!((hz - 1000.0).abs() < 20.0, "1 kHz tone came out at {hz:.0} Hz");
        assert_eq!(p.underruns, 0);
    }

    #[test]
    fn a_44100_sound_card_does_not_starve_or_overfill_the_queue() {
        let mut p = Playout::new(TARGET);
        p.set_output_rate(44_100);
        let (mut next_prod, mut next_cons) = (0u64, 0u64);
        let mut out = vec![0f32; 441 * 2];
        while next_prod.min(next_cons) < 60_000_000 {
            if next_prod <= next_cons { p.push(&vec![0.1f32; 960]); next_prod += 10_000; }
            else { p.render(&mut out); next_cons += 10_000; }
        }
        assert_eq!(p.underruns, 0, "underruns at 44.1 kHz");
        assert!((p.fill as i64 - TARGET as i64).abs() <= 600, "fill {} should stay near {TARGET}", p.fill);
    }

    #[test]
    fn capturing_at_44100_converts_to_48k_with_the_right_pitch() {
        let mut conv = RateConverter::new(44_100);
        let input: Vec<f32> = (0..44_100 * 2).flat_map(|i| { let v = (2.0 * std::f64::consts::PI * 1000.0 * i as f64 / 44_100.0).sin() as f32 * 0.5; [v, v] }).collect();
        let mut left = Vec::new();
        for chunk in input.chunks(441 * 2) { conv.push(chunk, 480, |c| left.extend(c.iter().step_by(2))); }
        assert!(left.len() > 48_000, "got {} output frames for 2 s of input", left.len()); // ~96000
        let hz = tone_hz(&left[480..], 48_000.0);
        assert!((hz - 1000.0).abs() < 20.0, "1 kHz tone came out at {hz:.0} Hz");
        let expected = 2 * 48_000;
        assert!((left.len() as i64 - expected as i64).abs() < 2 * 480 + 200, "length {} vs {}", left.len(), expected);
    }
}
