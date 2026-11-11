//! Jitter buffer: releases packets when local playout time (host_ts + target delay) is reached.
use std::collections::BTreeMap;

pub struct JitterBuffer { q: BTreeMap<u32, (i64, Vec<u8>)>, next_seq: Option<u32>, max_len: usize }

pub enum Pop { Packet(Vec<u8>), Lost, Empty }

impl JitterBuffer {
    pub fn new(max_len: usize) -> Self { Self { q: BTreeMap::new(), next_seq: None, max_len } }
    /// `play_at_us` = local time at which this packet must be played.
    pub fn push(&mut self, seq: u32, play_at_us: i64, data: Vec<u8>) {
        if let Some(n) = self.next_seq { if seq.wrapping_sub(n) > u32::MAX / 2 { return; } } // too old
        self.q.insert(seq, (play_at_us, data));
        while self.q.len() > self.max_len { self.q.pop_first(); }
    }
    /// Called once per frame period with the local clock.
    pub fn pop(&mut self, now_us: i64) -> Pop {
        let next = match self.next_seq { Some(n) => n, None => match self.q.keys().next() { Some(&k) => k, None => return Pop::Empty } };
        if let Some((t, _)) = self.q.get(&next) {
            if *t > now_us { return Pop::Empty; }
            let (_, d) = self.q.remove(&next).unwrap();
            self.next_seq = Some(next.wrapping_add(1));
            return Pop::Packet(d);
        }
        // Missing packet: declare it lost once a later packet is already due.
        if self.q.values().any(|(t, _)| *t <= now_us) {
            self.next_seq = Some(next.wrapping_add(1));
            return Pop::Lost; // caller runs Opus PLC
        }
        Pop::Empty
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn orders_waits_and_reports_loss() {
        let mut j = JitterBuffer::new(64);
        j.push(1, 1000, vec![1]);
        j.push(0, 900, vec![0]);
        j.push(3, 1200, vec![3]);
        assert!(matches!(j.pop(800), Pop::Empty));
        assert!(matches!(j.pop(900), Pop::Packet(ref d) if d == &vec![0]));
        assert!(matches!(j.pop(1000), Pop::Packet(ref d) if d == &vec![1]));
        assert!(matches!(j.pop(1100), Pop::Empty));
        assert!(matches!(j.pop(1200), Pop::Lost)); // seq 2 missing, seq 3 due
        assert!(matches!(j.pop(1200), Pop::Packet(ref d) if d == &vec![3]));
    }
}
