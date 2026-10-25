//! Device-neutral stroke mapping. Positions are millionths of logical viewport
//! height, and time is monotonic microseconds. No render-frame delta enters weight.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Idle,
    Grip,
    Pull,
    Drive,
    Slide,
    Released,
    Cancelled,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Sample {
    pub us: u64,
    pub x: i64,
    pub y: i64,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Report {
    pub speed_mm_s: i64,
    pub line_mm: i64,
    pub push_mm_s: i64,
    pub drive_us: u64,
    pub valid: bool,
}
pub struct Stroke {
    pub phase: Phase,
    pub one_push: bool,
    pub gain: i64,
    start: Sample,
    last: Sample,
    drive: Sample,
    drive_end: Option<Sample>,
    speed: i64,
}
impl Default for Stroke {
    fn default() -> Self {
        Self {
            phase: Phase::Idle,
            one_push: false,
            gain: 1000,
            start: Sample { us: 0, x: 0, y: 0 },
            last: Sample { us: 0, x: 0, y: 0 },
            drive: Sample { us: 0, x: 0, y: 0 },
            drive_end: None,
            speed: 0,
        }
    }
}
impl Stroke {
    pub fn grip(&mut self, s: Sample) {
        self.start = s;
        self.last = s;
        self.drive = s;
        self.drive_end = None;
        self.speed = 0;
        self.phase = Phase::Grip;
    }
    pub fn cancel(&mut self) {
        self.phase = Phase::Cancelled;
    }
    pub fn sample(&mut self, s: Sample) {
        if s.us <= self.last.us || s.x.abs() > 4_000_000 || s.y.abs() > 4_000_000 {
            return;
        }
        match self.phase {
            Phase::Grip if s.y - self.start.y > 5000 => self.phase = Phase::Pull,
            Phase::Grip if self.one_push && self.start.y - s.y > 3000 => {
                self.drive = self.last;
                self.phase = Phase::Drive;
            }
            Phase::Pull if self.last.y - s.y > 2000 => {
                self.drive = self.last;
                self.phase = Phase::Drive;
            }
            _ => {}
        }
        if self.phase == Phase::Drive && s.us - self.drive.us >= 120_000 {
            // Interpolate the crossing event to a fixed 120 ms measurement window.
            let end_us = self.drive.us + 120_000;
            let span = s.us - self.last.us;
            let part = end_us.saturating_sub(self.last.us).min(span);
            let end = Sample {
                us: end_us,
                x: self.last.x + (s.x - self.last.x) * part as i64 / span as i64,
                y: self.last.y + (s.y - self.last.y) * part as i64 / span as i64,
            };
            self.finish_drive(end);
            self.phase = Phase::Slide;
        }
        self.last = s;
    }
    fn finish_drive(&mut self, end: Sample) {
        let duration = end.us.saturating_sub(self.drive.us).max(1);
        let velocity =
            ((self.drive.y - end.y).max(0) * 1_000_000 / duration as i64) * self.gain / 1000;
        // Broad comfortable stroke range for draw weights, with hits at the top.
        self.speed = if velocity < 350_000 {
            1600 + velocity * 600 / 350_000
        } else {
            2200 + (velocity - 350_000) * 1800 / 650_000
        };
        self.speed = self.speed.clamp(1500, 5000);
        self.drive_end = Some(end);
    }
    pub fn release(&mut self, s: Sample) -> Report {
        self.sample(s);
        if self.phase == Phase::Drive && s.us - self.drive.us >= 30_000 {
            self.finish_drive(s);
            self.phase = Phase::Slide;
        }
        let valid = self.phase == Phase::Slide && s.us.saturating_sub(self.drive.us) < 4_000_000;
        let end = self.drive_end.unwrap_or(s);
        let trim = ((end.y - s.y) * 300 / 100_000).clamp(-70, 70);
        let lateral = s.x - self.start.x;
        let line = if lateral.abs() < 8000 {
            0
        } else {
            lateral.signum() * (lateral.abs() - 8000) * 1000 / 1_000_000
        };
        self.phase = Phase::Released;
        Report {
            speed_mm_s: (self.speed + trim).clamp(1500, 5000),
            line_mm: line.clamp(-120, 120),
            push_mm_s: trim.max(0),
            drive_us: end.us.saturating_sub(self.drive.us),
            valid,
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn s(us: u64, y: i64) -> Sample {
        Sample { us, x: 0, y }
    }
    #[test]
    fn stroke_requires_pull_then_drive() {
        let mut a = Stroke::default();
        a.grip(s(0, 0));
        a.sample(s(100000, 30000));
        a.sample(s(120000, 24000));
        a.sample(s(240000, -12000));
        let r = a.release(s(500000, -12000));
        assert!(r.valid);
        assert!((2000..=2200).contains(&r.speed_mm_s));
        assert_eq!(r.line_mm, 0);
    }
    #[test]
    fn click_is_not_throw() {
        let mut a = Stroke::default();
        a.grip(s(0, 0));
        assert!(!a.release(s(100000, 0)).valid);
    }
    #[test]
    fn cancellation_is_not_throw() {
        let mut a = Stroke::default();
        a.grip(s(0, 0));
        a.cancel();
        assert!(!a.release(s(100000, 0)).valid);
    }
    #[test]
    fn one_push_accessibility() {
        let mut a = Stroke {
            one_push: true,
            ..Default::default()
        };
        a.grip(s(0, 0));
        a.sample(s(100000, -30000));
        assert!(a.release(s(200000, -60000)).valid);
    }
    #[test]
    fn same_continuous_motion_with_different_event_rates() {
        fn run(step: u64) -> Report {
            let mut a = Stroke {
                one_push: true,
                ..Default::default()
            };
            a.grip(s(0, 0));
            for t in (step..=240000).step_by(step as usize) {
                a.sample(s(t, -(t as i64) * 3 / 10));
            }
            a.release(s(300000, -72000))
        }
        let a = run(10000);
        let b = run(20000);
        assert_eq!(a.speed_mm_s, b.speed_mm_s);
    }
}
