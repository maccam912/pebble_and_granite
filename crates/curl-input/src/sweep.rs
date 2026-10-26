//! Timestamped scrub effort, shared by mouse, held-click trackpad and touch.
//! Positions use the same logical-height units as delivery. Camera movement and
//! render polling cannot create motion. Gains are provisional feel parameters.
use crate::{Sample, valid_sample};
use std::collections::VecDeque;

const WINDOW_US: u64 = 200_000;
const MIN_TRAVEL: i64 = 7_500; // Six logical pixels on the 800-high surface.
const MAX_SAMPLES: usize = 256;

#[derive(Default)]
pub struct Scrub {
    samples: VecDeque<Sample>,
}
impl Scrub {
    pub fn begin(&mut self, sample: Sample) {
        self.cancel();
        if valid_sample(sample) {
            self.samples.push_back(sample);
        }
    }
    pub fn cancel(&mut self) {
        self.samples.clear();
    }
    pub fn motion(&mut self, sample: Sample) {
        let Some(last) = self.samples.back() else {
            return;
        };
        if !valid_sample(sample) || sample.us <= last.us {
            return;
        }
        if sample.us - last.us >= WINDOW_US {
            self.begin(sample);
            return;
        }
        self.samples.push_back(sample);
        // Retain the segment that straddles the window for exact clipping.
        while self.samples.len() > 2 && self.samples[1].us <= sample.us.saturating_sub(WINDOW_US) {
            self.samples.pop_front();
        }
        while self.samples.len() > MAX_SAMPLES {
            self.samples.pop_front();
        }
    }
    pub fn effort(&self, us: u64) -> u8 {
        let Some(last) = self.samples.back() else {
            return 0;
        };
        if us < last.us || us.saturating_sub(last.us) >= WINDOW_US {
            return 0;
        }
        let start = us.saturating_sub(WINDOW_US);
        let mut distance = 0_u64;
        let mut low = (last.x, last.y);
        let mut high = low;
        for (a, b) in self.samples.iter().zip(self.samples.iter().skip(1)) {
            if b.us <= start {
                continue;
            }
            let span = b.us - a.us;
            let overlap = b.us - a.us.max(start);
            let dx = (b.x - a.x) * overlap as i64 / span as i64;
            let dy = (b.y - a.y) * overlap as i64 / span as i64;
            distance +=
                ((dx as i128 * dx as i128 + dy as i128 * dy as i128) as u128).isqrt() as u64;
            for (x, y) in [(b.x - dx, b.y - dy), (b.x, b.y)] {
                low = (low.0.min(x), low.1.min(y));
                high = (high.0.max(x), high.1.max(y));
            }
        }
        if (high.0 - low.0).max(high.1 - low.1) < MIN_TRAVEL {
            return 0;
        }
        // Average over a fixed window: short/light scrubs clean with little
        // heat; sustained faster strokes approach the accessible hold effort.
        let speed = distance * 1_000_000 / WINDOW_US;
        (speed.saturating_sub(20_000) * 255 / 430_000).min(255) as u8
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn s(us: u64, x: i64) -> Sample {
        Sample { us, x, y: 0 }
    }
    #[test]
    fn light_and_hard_scrubs_decay_without_motion() {
        let mut scrub = Scrub::default();
        scrub.begin(s(0, 0));
        scrub.motion(s(100_000, 10_000));
        let light = scrub.effort(100_000);
        assert!((1..100).contains(&light));
        scrub.motion(s(200_000, -40_000));
        let hard = scrub.effort(200_000);
        assert!(hard > light);
        assert!(scrub.effort(300_000) < hard);
        assert_eq!(scrub.effort(400_000), 0);
        scrub.cancel();
        assert_eq!(scrub.effort(200_000), 0);
    }
    #[test]
    fn stationary_pointer_jitter_and_hostile_samples_do_not_sweep() {
        let mut scrub = Scrub::default();
        scrub.begin(s(0, 0));
        for t in 1..=200 {
            scrub.motion(s(t * 1000, if t % 2 == 0 { 1000 } else { -1000 }));
        }
        assert_eq!(scrub.effort(200_000), 0);
        scrub.motion(s(100_000, 100_000));
        scrub.motion(s(200_000, 100_000));
        scrub.motion(s(201_000, i64::MAX));
        assert_eq!(scrub.effort(201_000), 0);
        scrub.begin(s(300_000, 0));
        assert_eq!(scrub.effort(350_000), 0);
    }
    #[test]
    fn polling_does_not_change_effort_or_remember_old_motion() {
        let mut a = Scrub::default();
        let mut b = Scrub::default();
        for scrub in [&mut a, &mut b] {
            scrub.begin(s(0, 0));
        }
        for t in 1..=100 {
            let sample = s(t * 10_000, if t % 20 < 10 { 40_000 } else { 0 });
            a.motion(sample);
            b.motion(sample);
            for offset in [0, 1000, 4000, 8000] {
                let _ = a.effort(sample.us + offset);
            }
            assert_eq!(a.effort(sample.us), b.effort(sample.us));
        }
        assert_eq!(a.effort(900_000), 0); // Backward clock query.
        a.motion(s(2_000_000, 0));
        assert_eq!(a.effort(2_000_000), 0);
        assert!(a.samples.len() <= MAX_SAMPLES);
    }
}
