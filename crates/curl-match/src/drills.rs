//! Target drills score actual settled sim positions, including misses and hogs.
use crate::{practice::Practice, review::ShotReview};
use curl_fx::{Fx, V2};
use curl_sim::{HOUSE, Sim};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Weight,
    Guard,
    Line,
    Sweeping,
    Takeout,
    Split,
}
impl Kind {
    pub fn from_index(index: i64) -> Option<Self> {
        match index {
            0 => Some(Self::Weight),
            1 => Some(Self::Guard),
            2 => Some(Self::Line),
            3 => Some(Self::Sweeping),
            4 => Some(Self::Takeout),
            5 => Some(Self::Split),
            _ => None,
        }
    }
    pub fn target(self, attempt: u8) -> V2 {
        match self {
            Self::Guard => V2::new(Fx::ZERO, Fx::int(-3)),
            Self::Line | Self::Takeout => V2::new(
                Fx::ratio(if attempt.is_multiple_of(2) { -8 } else { 8 }, 10),
                Fx::ZERO,
            ),
            _ => V2::ZERO,
        }
    }
    /// Targets are training goals on this model, not claims of calibrated ice.
    pub fn split_target_ms(attempt: u8) -> u32 {
        [14_000, 15_000, 16_000, 14_500, 15_500][usize::from(attempt % 5)]
    }
    /// The target is placed by an ordinary recorded draw. No hidden state edits
    /// or new replay records are needed, and the setup survives normal restore.
    pub fn prepare(self, practice: &mut Practice, attempt: u8) -> Result<(), &'static str> {
        if self != Self::Takeout {
            return Ok(());
        }
        if !practice.sim.stones.is_empty() || practice.log.pending_delivery.is_some() {
            return Err("Takeout setup needs an empty sheet");
        }
        let mut next = practice.clone();
        let plan = crate::ai::solve(
            &next.sim,
            self.target(attempt),
            crate::ai::ShotKind::Draw,
            if attempt.is_multiple_of(2) { 1 } else { -1 },
        );
        next.release(plan.release())?;
        while !next.sim.is_resting() {
            next.step(&[])?;
        }
        if !next.sim.stones[0].active || next.sim.stones[0].pos.length() > HOUSE {
            return Err("Takeout target did not reach the house");
        }
        *practice = next;
        Ok(())
    }
    pub fn observed_target(self, practice: &Practice, attempt: u8) -> V2 {
        if self == Self::Takeout
            && let Some(at) = practice
                .reviews
                .recent
                .iter()
                .rev()
                .find(|r| r.stone == 0)
                .and_then(|r| r.finish)
        {
            return at;
        }
        self.target(attempt)
    }
    pub fn grade(self, practice: &Practice, attempt: u8) -> Option<Grade> {
        if self != Self::Split {
            return self.result_at(&practice.sim, self.observed_target(practice, attempt));
        }
        let review = practice.reviews.recent.back()?;
        if practice.sim.delivered != Some(review.stone) || !practice.sim.is_resting() {
            return None;
        }
        Some(Self::split_result(review, attempt))
    }
    fn split_result(review: &ShotReview, attempt: u8) -> Grade {
        let error = review
            .hog_split_ms
            .map(|ms| ms.abs_diff(Self::split_target_ms(attempt)));
        let stars = match error {
            Some(ms) if ms <= 200 => 3,
            Some(ms) if ms <= 500 => 2,
            Some(ms) if ms <= 1000 => 1,
            _ => 0,
        };
        Grade {
            stars,
            error_mm: 0,
            in_play: review.in_play,
            split_ms: review.hog_split_ms,
            error_ms: error,
            target_removed: false,
            target_moved_mm: 0,
        }
    }
    /// Weight isolates depth. The other drills measure distance to the target.
    pub fn result(self, sim: &Sim, attempt: u8) -> Option<Grade> {
        self.result_at(sim, self.target(attempt))
    }
    fn result_at(self, sim: &Sim, target: V2) -> Option<Grade> {
        let id = sim.delivered?;
        if self == Self::Takeout && (id != 1 || !sim.stones.iter().any(|s| s.id == 0)) {
            return None;
        }
        if !sim.is_resting() {
            return None;
        }
        let stone = sim.stones.iter().find(|s| s.id == id)?;
        let offset = stone.pos - target;
        let error = if self == Self::Weight {
            offset.y.abs()
        } else {
            offset.length()
        };
        let error_mm = (error.raw() as i128 * 1000 / (1_i128 << 32)) as i64;
        let stars = if !stone.active {
            0
        } else if error <= Fx::ratio(15, 100) {
            3
        } else if error <= Fx::ratio(45, 100) {
            2
        } else if error <= Fx::ratio(9, 10) {
            1
        } else {
            0
        };
        let victim = sim.stones.iter().find(|s| s.id == 0);
        let target_removed = self == Self::Takeout && victim.is_some_and(|s| !s.active);
        let moved = victim.map_or(0, |s| {
            ((s.pos - target).length().raw() as i128 * 1000 / (1_i128 << 32)) as i64
        });
        let stars = if self == Self::Takeout {
            if target_removed {
                if stone.active && stone.pos.length() <= HOUSE + curl_sim::RADIUS {
                    3
                } else {
                    2
                }
            } else if moved >= 450 {
                1
            } else {
                0
            }
        } else {
            stars
        };
        Some(Grade {
            stars,
            error_mm,
            in_play: stone.active,
            split_ms: None,
            error_ms: None,
            target_removed,
            target_moved_mm: moved,
        })
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Grade {
    pub stars: u8,
    pub error_mm: i64,
    pub in_play: bool,
    pub split_ms: Option<u32>,
    pub error_ms: Option<u32>,
    pub target_removed: bool,
    pub target_moved_mm: i64,
}
#[cfg(test)]
mod tests {
    use super::*;
    use curl_sim::{Release, Stone};
    fn settle(practice: &mut Practice) {
        while !practice.sim.is_resting() {
            practice.step(&[]).unwrap();
        }
    }
    #[test]
    fn real_takeouts_preserve_recorded_setup_and_grade_contact_outcomes() {
        for attempt in 0..5 {
            let mut practice = Practice::new(42);
            Kind::Takeout.prepare(&mut practice, attempt).unwrap();
            assert!(
                Kind::Takeout.grade(&practice, attempt).is_none(),
                "setup must not count as a player attempt"
            );
            let before = practice.hash();
            assert!(Kind::Takeout.prepare(&mut practice, attempt).is_err());
            assert_eq!(before, practice.hash());
            let restored = Practice::from_log(practice.log.clone()).unwrap();
            assert_eq!(restored.sim, practice.sim);
            let target = Kind::Takeout.observed_target(&practice, attempt);
            let plan = crate::ai::solve(
                &practice.sim,
                target,
                crate::ai::ShotKind::Hit,
                if attempt.is_multiple_of(2) { 1 } else { -1 },
            );
            let mut release = plan.release();
            release.stone = 1;
            release.team = 1;
            practice.release(release).unwrap();
            assert!(Kind::Takeout.grade(&practice, attempt).is_none());
            settle(&mut practice);
            let grade = Kind::Takeout.grade(&practice, attempt).unwrap();
            assert!(
                grade.target_removed && grade.stars >= 2,
                "{attempt}: {grade:?}"
            );
            let restored = Practice::from_log(practice.log.clone()).unwrap();
            assert_eq!(Kind::Takeout.grade(&restored, attempt), Some(grade));
            assert_eq!(practice.hash(), restored.hash());
            practice.clear_stones().unwrap();
            Kind::Takeout.prepare(&mut practice, attempt).unwrap();
            practice.hog_violation().unwrap();
            assert_eq!(Kind::Takeout.grade(&practice, attempt).unwrap().stars, 0);
        }
    }
    #[test]
    fn timing_goals_are_reachable_on_seeded_ice() {
        for attempt in 0..5 {
            let target = Kind::split_target_ms(attempt);
            let (mut low, mut high) = (1700, 3000);
            let mut best = u32::MAX;
            for _ in 0..12 {
                let speed = (low + high) / 2;
                let mut practice = Practice::new(42);
                let mut release = Release::draw();
                release.vel.y = Fx::ratio(speed, 1000);
                practice.release(release).unwrap();
                settle(&mut practice);
                match Kind::Split.grade(&practice, attempt).unwrap().split_ms {
                    Some(ms) => {
                        best = best.min(ms.abs_diff(target));
                        if ms > target {
                            low = speed;
                        } else {
                            high = speed;
                        }
                    }
                    None => low = speed,
                }
            }
            assert!(
                best <= 200,
                "training target {target} ms is unreachable: nearest {best} ms"
            );
        }
    }
    #[test]
    fn split_grades_true_crossings_including_fast_stones_out_the_back() {
        let mut practice = Practice::new(42);
        let mut release = Release::draw();
        release.pos.y = Fx::int(-36);
        release.vel.y = Fx::ratio(27, 10);
        practice.release(release).unwrap();
        assert!(Kind::Split.grade(&practice, 0).is_none());
        settle(&mut practice);
        let grade = Kind::Split.grade(&practice, 0).unwrap();
        let review = practice.reviews.recent.back().unwrap();
        assert_eq!(grade.split_ms, review.hog_split_ms);
        assert!(grade.split_ms.is_some());
        assert!(grade.split_ms.unwrap() < review.travel_ms);
        let mut crossing = review.clone();
        crossing.in_play = false;
        for (error, stars) in [
            (0, 3),
            (200, 3),
            (201, 2),
            (500, 2),
            (501, 1),
            (1000, 1),
            (1001, 0),
        ] {
            crossing.hog_split_ms = Some(Kind::split_target_ms(0) + error);
            assert_eq!(Kind::split_result(&crossing, 0).stars, stars);
        }
        crossing.hog_split_ms = None;
        assert_eq!(Kind::split_result(&crossing, 0).stars, 0);
        practice.clear_stones().unwrap();
        practice.hog_violation().unwrap();
        assert_eq!(Kind::Split.grade(&practice, 0).unwrap().split_ms, None);
        assert_eq!(Kind::Split.grade(&practice, 0).unwrap().stars, 0);
    }
    #[test]
    fn targets_and_scoring_use_actual_positions_and_count_misses() {
        assert!(Kind::from_index(-1).is_none() && Kind::from_index(6).is_none());
        assert_eq!(Kind::Line.target(0).x, -Kind::Line.target(1).x);
        let mut sim = Sim::new(42);
        assert!(Kind::Weight.result(&sim, 0).is_none());
        sim.release(Release::draw()).unwrap();
        assert!(Kind::Weight.result(&sim, 0).is_none());
        sim.stones = vec![Stone::resting(0, 0, V2::new(Fx::ONE, Fx::ratio(1, 10)))];
        assert_eq!(Kind::Weight.result(&sim, 0).unwrap().stars, 3);
        assert_eq!(Kind::Sweeping.result(&sim, 0).unwrap().stars, 0);
        sim.stones[0].pos = V2::new(Fx::ratio(3, 10), Fx::ZERO);
        assert_eq!(Kind::Line.result(&sim, 1).unwrap().stars, 1);
        sim.stones[0].active = false;
        sim.stones[0].pos = V2::ZERO;
        assert_eq!(Kind::Weight.result(&sim, 0).unwrap().stars, 0);
    }
}
