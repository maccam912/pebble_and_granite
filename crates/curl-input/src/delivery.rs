//! Provisional delivery biomechanics, independent of rendering frequency.
//!
//! The stroke chooses a target speed at the near hog. A fixed deceleration model
//! derives the drive speed and subsequent release position/speed. It is not a
//! second stone simulator: after release the shared stone/ice core takes over.
use crate::{Phase, Report, Sample, Stroke, valid_sample};
use std::collections::VecDeque;

pub const DELIVERY_VERSION: u32 = 2;
pub const HZ: u64 = 240;
pub const START_Y_UM: i64 = -37_800_000;
pub const RADIUS_UM: i64 = 142_000;
pub const NEAR_TEE_UM: i64 = -34_750_000;
pub const NEAR_HOG_INSIDE_UM: i64 = -28_349_000;
pub const HOG_WIDTH_UM: i64 = 102_000;
// Conservative R5(e) boundary: leading edge must not touch the near edge of
// the painted line while the handle remains held. Equality is a violation.
pub const HOG_CENTER_UM: i64 = NEAR_HOG_INSIDE_UM - HOG_WIDTH_UM - RADIUS_UM;
pub const SLIDE_DECEL_UM_S2: i64 = 70_000;
const MAX_SLIDE_TICKS: u64 = 20 * HZ;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Pose {
    pub slide_tick: u64,
    pub y_um: i64,
    pub speed_um_s: i64,
    pub in_play: bool,
    pub hog_warning: bool,
    pub hog_violation: bool,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Outcome {
    Cancelled,
    Released,
    HogViolation,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DeliveryReport {
    pub turn: i64,
    pub trim_mm_s: i64,
    pub outcome: Outcome,
    pub stroke: Report,
    pub pose: Pose,
    pub speed_um_s: i64,
}
#[derive(Default)]
pub struct Delivery {
    stroke: Stroke,
    final_report: Option<DeliveryReport>,
    finish_samples: VecDeque<Sample>,
}
impl Delivery {
    pub fn phase(&self) -> Phase {
        self.stroke.phase
    }
    pub fn grip(&mut self, sample: Sample, one_push: bool, gain: i64) {
        self.final_report = None;
        self.finish_samples.clear();
        self.remember(sample);
        self.stroke.one_push = one_push;
        self.stroke.gain = gain.clamp(250, 4000);
        self.stroke.grip(sample);
    }
    pub fn motion(&mut self, sample: Sample) {
        if self.final_report.is_none() {
            self.remember(sample);
            self.stroke.sample(sample);
        }
    }
    fn remember(&mut self, sample: Sample) {
        if !valid_sample(sample)
            || self
                .finish_samples
                .back()
                .is_some_and(|s| sample.us <= s.us)
        {
            return;
        }
        self.finish_samples.push_back(sample);
        while self.finish_samples.len() > 2 && self.finish_samples[1].us + 160_000 < sample.us {
            self.finish_samples.pop_front();
        }
        while self.finish_samples.len() > 256 {
            self.finish_samples.pop_front();
        }
    }
    pub fn target_mm_s(&self) -> i64 {
        self.stroke.speed
    }
    fn finish_velocity(&self, sample: Sample) -> (i64, i64) {
        let start = sample.us.saturating_sub(120_000);
        let mut previous = *self.finish_samples.front().unwrap_or(&sample);
        let mut origin = previous;
        for point in &self.finish_samples {
            if point.us >= start {
                let duration = point.us.saturating_sub(previous.us).max(1);
                let offset = start.saturating_sub(previous.us).min(duration);
                origin = Sample {
                    us: start.max(previous.us),
                    x: previous.x
                        + ((point.x - previous.x) as i128 * offset as i128 / duration as i128)
                            as i64,
                    y: previous.y
                        + ((point.y - previous.y) as i128 * offset as i128 / duration as i128)
                            as i64,
                };
                break;
            }
            previous = *point;
        }
        let duration = sample.us.saturating_sub(origin.us);
        if duration < 20_000 {
            return (0, 0);
        }
        (
            (sample.x - origin.x) * 1_000_000 / duration as i64,
            (origin.y - sample.y) * 1_000_000 / duration as i64,
        )
    }
    pub fn cancel(&mut self) {
        self.stroke.cancel();
        self.final_report = None;
    }
    /// Read-only; 30, 60 and 144 Hz callers receive the same pose at a given time.
    /// Quantize elapsed time once to 240 Hz rather than integrating render deltas.
    pub fn pose(&self, us: u64) -> Pose {
        if let Some(report) = self.final_report {
            return report.pose;
        }
        self.moving_pose(us)
    }
    fn moving_pose(&self, us: u64) -> Pose {
        if matches!(self.stroke.phase, Phase::Idle | Phase::Cancelled) {
            return idle_pose();
        }
        // A stationary hand still completes the fixed drive window. Derive this
        // on a copy so render queries never become input samples or alter weight.
        let mut stroke = self.stroke.clone();
        let now = us.max(stroke.last.us);
        if stroke.phase == Phase::Drive {
            stroke.sample(Sample {
                us: now,
                ..stroke.last
            });
        }
        let Some(end) = stroke.drive_end else {
            return idle_pose();
        };
        let ticks = ((us.max(self.stroke.last.us).saturating_sub(end.us) as u128 * HZ as u128)
            / 1_000_000)
            .min(MAX_SLIDE_TICKS as u128) as u64;
        slide_pose(stroke.speed, ticks)
    }

    pub fn release(&mut self, sample: Sample) -> DeliveryReport {
        if let Some(report) = self.final_report {
            return report;
        }
        self.remember(sample);
        let (side_velocity, forward_velocity) = if valid_sample(sample) {
            self.finish_velocity(sample)
        } else {
            (0, 0)
        };
        let admissible = valid_sample(sample) && sample.us >= self.stroke.last.us;
        let began_drive = matches!(self.stroke.phase, Phase::Drive | Phase::Slide);
        let stroke = self.stroke.release_with_limit(sample, 20_000_000);
        let pose = if admissible && began_drive {
            self.moving_pose(sample.us)
        } else {
            idle_pose()
        };
        let outcome = if admissible && began_drive && pose.hog_violation {
            Outcome::HogViolation
        } else if admissible && stroke.valid {
            Outcome::Released
        } else {
            Outcome::Cancelled
        };
        // Arm extension is a bounded adjustment; it cannot retroactively move
        // the slide or change the time at which the stone touches the hog line.
        let trim = (forward_velocity / 4000).clamp(-70, 70) * 1000;
        let turn = if side_velocity.abs() >= 80_000 {
            side_velocity.signum()
        } else {
            0
        };
        let report = DeliveryReport {
            turn,
            trim_mm_s: trim / 1000,
            outcome,
            stroke,
            pose,
            speed_um_s: (pose.speed_um_s + trim).clamp(100_000, 6_000_000),
        };
        self.final_report = Some(report);
        report
    }
}

/// Shared immutable trajectory for the input preview and host-owned delivery.
/// Callers validate the target in 1500..=5000 mm/s before persisting a plan.
pub fn slide_pose(target_mm_s: i64, ticks: u64) -> Pose {
    let ticks = ticks.min(MAX_SLIDE_TICKS);
    let target_speed = target_mm_s.clamp(1500, 5000) * 1000;
    let v0 = curl_fx::isqrt(
        (target_speed as i128 * target_speed as i128
            + 2 * SLIDE_DECEL_UM_S2 as i128 * (HOG_CENTER_UM - START_Y_UM) as i128) as u128,
    ) as i64;
    let t = ticks as i128;
    let hz = HZ as i128;
    let distance = v0 as i128 * t / hz - SLIDE_DECEL_UM_S2 as i128 * t * t / (2 * hz * hz);
    let y = START_Y_UM + distance as i64;
    Pose {
        slide_tick: ticks,
        y_um: y.min(HOG_CENTER_UM),
        speed_um_s: v0 - SLIDE_DECEL_UM_S2 * ticks as i64 / HZ as i64,
        in_play: y + RADIUS_UM >= NEAR_TEE_UM,
        hog_warning: y >= HOG_CENTER_UM - 800_000,
        hog_violation: y >= HOG_CENTER_UM,
    }
}

/// First whole authority millisecond at which a geometric boundary is reached.
pub fn crossing_ms(target_mm_s: i64, hog: bool) -> u32 {
    for tick in 0..=MAX_SLIDE_TICKS {
        let pose = slide_pose(target_mm_s, tick);
        if if hog {
            pose.hog_violation
        } else {
            pose.in_play
        } {
            return (tick * 1000).div_ceil(HZ) as u32;
        }
    }
    unreachable!("bounded delivery always reaches the hog line")
}

fn idle_pose() -> Pose {
    Pose {
        slide_tick: 0,
        y_um: START_Y_UM,
        speed_um_s: 0,
        in_play: false,
        hog_warning: false,
        hog_violation: false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn sample(us: u64, y: i64) -> Sample {
        Sample { us, x: 0, y }
    }
    fn draw() -> Delivery {
        let mut delivery = Delivery::default();
        delivery.grip(sample(0, 0), true, 1000);
        delivery.motion(sample(20_000, -5250));
        delivery.motion(sample(120_000, -31_500));
        assert_eq!(delivery.stroke.speed, 2050);
        delivery
    }
    #[test]
    fn release_flick_sets_rotation_and_bounded_weight_trim() {
        for direction in [-1, 1] {
            let mut d = draw();
            d.motion(Sample {
                us: 2_880_000,
                x: 0,
                y: -31_500,
            });
            let r = d.release(Sample {
                us: 3_000_000,
                x: direction * 24_000,
                y: -55_500,
            });
            assert_eq!(r.turn, direction);
            assert_eq!(r.trim_mm_s, 50);
            assert_eq!(r.outcome, Outcome::Released);
        }
        let mut d = draw();
        d.motion(sample(2_880_000, -31_500));
        let r = d.release(sample(3_000_000, 100_000));
        assert_eq!(r.trim_mm_s, -70);
        assert_eq!(r.turn, 0);
        let mut d = draw();
        d.motion(Sample {
            us: 2_000_000,
            x: 24_000,
            y: -31_500,
        });
        let r = d.release(Sample {
            us: 3_000_000,
            x: 24_000,
            y: -31_500,
        });
        assert_eq!(r.turn, 0, "old sideways movement is not a release flick");
        assert_eq!(r.trim_mm_s, 0);
    }
    #[test]
    fn drive_target_becomes_position_dependent_release_speed() {
        let mut early = draw();
        let mut late = draw();
        let first = early.release(sample(500_000, -31_500));
        let second = late.release(sample(3_000_000, -31_500));
        assert_eq!(first.outcome, Outcome::Released);
        assert_eq!(second.outcome, Outcome::Released);
        assert!(first.pose.y_um < second.pose.y_um);
        assert!(first.speed_um_s > second.speed_um_s);
        assert!(!first.pose.in_play);
        assert!(second.pose.in_play);
        assert!(second.pose.y_um < HOG_CENTER_UM);
    }
    #[test]
    fn render_query_frequency_never_changes_release() {
        let mut reference = draw();
        let expected = reference.release(sample(3_200_000, -31_500));
        for rate in [30, 60, 144] {
            let mut delivery = draw();
            for n in 0..rate * 3 {
                let _ = delivery.pose(120_000 + n * 1_000_000 / rate);
            }
            assert_eq!(delivery.release(sample(3_200_000, -31_500)), expected);
        }
    }
    #[test]
    fn near_hog_boundary_and_warning_are_tick_exact() {
        let delivery = draw();
        let mut crossing = 0;
        let mut warned = false;
        for tick in 0..MAX_SLIDE_TICKS {
            // Ceiling ensures the requested integer microsecond maps to tick.
            let us = 120_000 + (tick * 1_000_000).div_ceil(HZ);
            let pose = delivery.pose(us);
            assert_eq!(pose.slide_tick, tick);
            if pose.hog_warning && !pose.hog_violation {
                warned = true;
            }
            if pose.hog_violation {
                crossing = us;
                break;
            }
        }
        assert!(warned && crossing > 4_000_000 && crossing < 6_000_000);
        let mut before = draw();
        let mut at = draw();
        assert_eq!(
            before.release(sample(crossing - 1, -31_500)).outcome,
            Outcome::Released
        );
        assert_eq!(
            at.release(sample(crossing, -31_500)).outcome,
            Outcome::HogViolation
        );
        assert_eq!(at.pose(u64::MAX).y_um, HOG_CENTER_UM);
    }
    #[test]
    fn cancelled_and_invalid_strokes_cannot_release() {
        let mut delivery = draw();
        delivery.cancel();
        assert_eq!(
            delivery.release(sample(500_000, -31_500)).outcome,
            Outcome::Cancelled
        );
        let mut delivery = draw();
        assert_eq!(delivery.release(sample(1, 0)).outcome, Outcome::Cancelled);
        let mut delivery = draw();
        assert_eq!(
            delivery.release(sample(u64::MAX, i64::MIN)).outcome,
            Outcome::Cancelled
        );
        let mut delivery = Delivery::default();
        delivery.grip(sample(0, 0), false, 1000);
        assert_eq!(
            delivery.release(sample(100_000, 0)).outcome,
            Outcome::Cancelled
        );
    }
    #[test]
    fn holding_still_finishes_drive_without_render_mutation() {
        let mut delivery = Delivery::default();
        delivery.grip(sample(0, 0), true, 1000);
        delivery.motion(sample(40_000, -12_000));
        let pose = delivery.pose(500_000);
        assert!(pose.slide_tick > 0 && pose.y_um > START_Y_UM);
        assert_eq!(delivery.phase(), Phase::Drive);
        let report = delivery.release(sample(500_000, -12_000));
        assert_eq!(report.pose, pose);
        assert_eq!(report.outcome, Outcome::Released);
        let mut abandoned = draw();
        assert_eq!(
            abandoned.release(sample(60_000_000, -31_500)).outcome,
            Outcome::HogViolation
        );
    }
    #[test]
    fn finished_delivery_is_immutable_until_new_grip() {
        let mut delivery = draw();
        let report = delivery.release(sample(500_000, -31_500));
        delivery.motion(sample(600_000, 20_000));
        assert_eq!(delivery.release(sample(700_000, 20_000)), report);
        assert_eq!(delivery.pose(900_000), report.pose);
        delivery.grip(sample(1_000_000, 0), false, 1000);
        assert_eq!(delivery.pose(1_000_000).y_um, START_Y_UM);
        assert_eq!(delivery.phase(), Phase::Grip);
    }
}
