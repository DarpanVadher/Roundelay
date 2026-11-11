use anyhow::{anyhow, Result};
use cpal::traits::{DeviceTrait, HostTrait};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

pub type Key = [u8; 32];
pub const STREAM_ID: u32 = 1; // AEAD stream ids: audio=1, ping=2, pong=3 (a (key, seq, stream) nonce is never reused)
pub const PING_ID: u32 = 2;
pub const PONG_ID: u32 = 3;
pub const RATE: u32 = 48_000;
pub const FRAME: usize = 480; // 10 ms per channel
/// Playout queue target (frames). Must exceed one packet + one callback + margin; see mpsp-core drift tests.
pub const PLAYOUT_TARGET: usize = 1920;
pub const PLAYOUT_TARGET_US: i64 = 40_000;

/// Cooperative shutdown flag shared by every worker thread of a session.
#[derive(Clone, Default)]
pub struct Stop(Arc<AtomicBool>);
impl Stop {
    pub fn set(&self) { self.0.store(true, Ordering::SeqCst) }
    pub fn is_set(&self) -> bool { self.0.load(Ordering::SeqCst) }
}

/// Picks a 32-bit float stream config for a device and returns it with the sample rate it runs at: 48 kHz when
/// the device offers it, otherwise the device's own rate. Many Bluetooth headphones only do 44.1 kHz; the caller
/// converts between that and the engine's 48 kHz (`Playout::set_output_rate`, `RateConverter`).
pub fn output_config(dev: &cpal::Device) -> Result<(cpal::StreamConfig, u32)> {
    let ranges: Vec<_> = dev.supported_output_configs()?.filter(|r| r.sample_format() == cpal::SampleFormat::F32).collect();
    if let Some(r) = ranges.iter().find(|r| r.min_sample_rate().0 <= RATE && r.max_sample_rate().0 >= RATE) {
        return Ok((r.clone().with_sample_rate(cpal::SampleRate(RATE)).config(), RATE));
    }
    let r = ranges.first().ok_or_else(|| anyhow!("audio device has no 32-bit float mode"))?;
    let rate = r.max_sample_rate().0;
    Ok((r.clone().with_sample_rate(cpal::SampleRate(rate)).config(), rate))
}

/// Name of the system's current default output device, if there is one. Desktop audio streams stay bound to the
/// device they were opened on, so the engine polls this to notice when the user connects/disconnects Bluetooth
/// headphones or switches outputs, and then reopens its stream on the new default.
pub fn default_output_name() -> Option<String> {
    cpal::default_host().default_output_device().and_then(|d| d.name().ok())
}

/// Should an open stream move to a different device? Only when a default exists and differs from where we are.
/// (No default at all, e.g. every device just vanished, keeps the current stream rather than churning.)
pub fn output_device_changed(opened_on: &str, current_default: Option<&str>) -> bool {
    matches!(current_default, Some(now) if now != opened_on)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_change_is_detected_only_for_a_different_existing_default() {
        assert!(!output_device_changed("Speakers (Realtek)", Some("Speakers (Realtek)")));
        assert!(output_device_changed("Speakers (Realtek)", Some("Headphones (Bluetooth)")));
        assert!(output_device_changed("Headphones (Bluetooth)", Some("Speakers (Realtek)"))); // and back
        assert!(!output_device_changed("Speakers (Realtek)", None), "no default at all: keep what we have");
    }

    #[test]
    fn default_output_name_is_stable_between_calls() {
        // Whatever this machine has (or nothing on a CI box), two consecutive lookups must agree, otherwise the
        // watcher would reopen the stream in a loop.
        assert_eq!(default_output_name(), default_output_name());
    }
}
