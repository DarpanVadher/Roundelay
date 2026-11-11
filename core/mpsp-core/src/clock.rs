//! NTP-style offset estimator: keeps the sample with the lowest RTT in a sliding window.
use std::collections::VecDeque;

#[derive(Default)]
pub struct ClockSync { samples: VecDeque<(i64, i64)> } // (rtt_us, offset_us)

impl ClockSync {
    const WINDOW: usize = 16;
    /// t0 guest send, t1 host recv, t2 host send, t3 guest recv (all microseconds, own clocks).
    pub fn add_sample(&mut self, t0: i64, t1: i64, t2: i64, t3: i64) {
        let rtt = (t3 - t0) - (t2 - t1);
        let offset = ((t1 - t0) + (t2 - t3)) / 2; // host_time - guest_time
        if self.samples.len() == Self::WINDOW { self.samples.pop_front(); }
        self.samples.push_back((rtt, offset));
    }
    pub fn offset_us(&self) -> Option<i64> {
        self.samples.iter().min_by_key(|s| s.0).map(|s| s.1)
    }
    /// Convert a host timestamp to the local clock.
    pub fn host_to_local(&self, host_us: u64) -> Option<i64> {
        self.offset_us().map(|o| host_us as i64 - o)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn picks_low_rtt_sample() {
        let mut c = ClockSync::default();
        // true offset 1000us; symmetric 500us one-way delay
        c.add_sample(0, 1500, 1500, 1000);
        // congested sample with asymmetric delay (bad offset)
        c.add_sample(10_000, 21_000, 21_000, 40_000);
        assert_eq!(c.offset_us(), Some(1000));
    }
}
