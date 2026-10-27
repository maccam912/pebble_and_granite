//! Disposable observations rebuilt from accepted commands. Never hashed or saved.
use crate::{Authority, Seat};
use curl_fx::{Fx, V2, isqrt};
use curl_rules::{Phase, Violation};
use curl_sim::{NEAR_HOG, RADIUS, Sim};
use std::{collections::VecDeque, sync::Arc};

fn mm(n: Fx) -> i64 {
    ((n.raw() as i128 * 1000) / (1_i128 << 32)) as i64
}
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PlayerStats {
    pub shots: u32,
    pub hog_faults: u32,
    speed_sum: u64,
    speed_squared: u64,
    moving_releases: u32,
}
impl PlayerStats {
    pub fn mean_speed_mm_s(&self) -> u64 {
        self.speed_sum / u64::from(self.moving_releases.max(1))
    }
    pub fn spread_mm_s(&self) -> u64 {
        let n = u128::from(self.moving_releases.max(1));
        isqrt((n * self.speed_squared as u128 - (self.speed_sum as u128).pow(2)) / (n * n)) as u64
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShotReview {
    pub ordinal: u32,
    pub end: u8,
    pub seat: Seat,
    pub stone: u8,
    pub speed_mm_s: i64,
    pub release_tick: u32,
    pub release_pos: V2,
    pub release_vel: V2,
    pub hog_split_ms: Option<u32>,
    pub travel_ms: u32,
    pub finish: Option<V2>,
    pub curl_mm: Option<i64>,
    pub turns_milli: i64,
    pub contacts: u32,
    pub in_play: bool,
    pub violation: Option<Violation>,
    pub path: Arc<Vec<V2>>,
}
impl ShotReview {
    pub fn key(&self) -> u64 {
        let mut hash = curl_fx::Hash64::default();
        for value in [
            self.ordinal as u64,
            self.end as u64,
            self.seat.team as u64,
            self.seat.position as u64,
            self.release_tick as u64,
            self.speed_mm_s as u64,
            self.in_play as u64,
        ] {
            hash.u64(value);
        }
        for point in self.path.iter() {
            hash.u64(point.x.raw() as u64);
            hash.u64(point.y.raw() as u64);
        }
        hash.finish()
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
struct Active {
    review: ShotReview,
    near_hog: Option<u32>,
    changed_past: bool,
}
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ReviewBook {
    pub recent: Arc<VecDeque<ShotReview>>,
    pub stats: [PlayerStats; 8],
    active: Option<Active>,
    next_ordinal: u32,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SplitClock {
    Waiting,
    Running(u32),
    Complete(u32),
    Incomplete,
}
impl ReviewBook {
    pub fn begin(&mut self, sim: &Sim, seat: Seat, end: u8) {
        let Some(stone) = sim.stones.iter().find(|s| Some(s.id) == sim.delivered) else {
            return;
        };
        self.next_ordinal += 1;
        self.active = Some(Active {
            near_hog: None,
            changed_past: false,
            review: ShotReview {
                ordinal: self.next_ordinal,
                end,
                seat,
                stone: stone.id,
                speed_mm_s: mm(stone.vel.length()),
                release_tick: sim.release_tick,
                release_pos: stone.pos,
                release_vel: stone.vel,
                hog_split_ms: None,
                travel_ms: 0,
                finish: None,
                curl_mm: None,
                turns_milli: 0,
                contacts: 0,
                in_play: false,
                violation: None,
                path: Arc::new(vec![stone.pos]),
            },
        });
    }
    pub fn tick(&mut self, sim: &Sim) {
        let Some(active) = &mut self.active else {
            return;
        };
        let Some(stone) = sim.stones.iter().find(|s| s.id == active.review.stone) else {
            return;
        };
        if active.near_hog.is_none() && stone.pos.y - RADIUS > NEAR_HOG {
            active.near_hog = Some(sim.tick);
        }
        active.review.hog_split_ms = sim
            .hog_tick
            .zip(active.near_hog)
            .map(|(far, near)| far.saturating_sub(near) * 1000 / 240);
        if (sim.tick - active.review.release_tick).is_multiple_of(12)
            && active.review.path.last() != Some(&stone.pos)
            && active.review.path.len() < 1201
        {
            Arc::make_mut(&mut active.review.path).push(stone.pos);
        }
    }
    pub fn split_ms(&self, sim: &Sim) -> Option<u32> {
        if let Some(active) = &self.active {
            return active.review.hog_split_ms;
        }
        self.recent
            .back()
            .filter(|r| Some(r.stone) == sim.delivered && r.release_tick == sim.release_tick)
            .and_then(|r| r.hog_split_ms)
    }
    /// A stopwatch driven by observed whole-stone crossings, never wall time.
    pub fn split_clock(&self, sim: &Sim) -> SplitClock {
        if let Some(ms) = self.split_ms(sim) {
            return SplitClock::Complete(ms);
        }
        let Some(active) = &self.active else {
            return SplitClock::Incomplete;
        };
        let moving = sim
            .stones
            .iter()
            .any(|stone| stone.id == active.review.stone && stone.active && stone.vel != V2::ZERO);
        if !moving {
            return SplitClock::Incomplete;
        }
        active.near_hog.map_or(SplitClock::Waiting, |near| {
            SplitClock::Running(sim.tick.saturating_sub(near) * 1000 / 240)
        })
    }
    pub fn finish(&mut self, sim: &Sim, violation: Option<Violation>) {
        let Some(active) = self.active.take() else {
            return;
        };
        let mut review = active.review;
        let stone = sim.stones.iter().find(|s| s.id == review.stone);
        review.travel_ms = (sim.tick - review.release_tick) * 1000 / 240;
        review.contacts = sim.contacts;
        review.violation = violation;
        if let Some(stone) = stone {
            review.finish = Some(stone.pos);
            review.turns_milli = mm(stone.turns);
            review.in_play = stone.active;
            if review.release_vel.y > Fx::ZERO {
                let straight = review.release_pos.x
                    + (stone.pos.y - review.release_pos.y) * review.release_vel.x
                        / review.release_vel.y;
                review.curl_mm = Some(mm(stone.pos.x - straight));
            }
            if review.path.last() != Some(&stone.pos) {
                Arc::make_mut(&mut review.path).push(stone.pos);
            }
        }
        let stats = &mut self.stats[(review.seat.team * 4 + review.seat.position) as usize];
        stats.shots += 1;
        stats.hog_faults += u32::from(violation == Some(Violation::HogRelease));
        if review.speed_mm_s > 0 {
            stats.moving_releases += 1;
            stats.speed_sum += review.speed_mm_s as u64;
            stats.speed_squared += (review.speed_mm_s as u64).pow(2);
        }
        let recent = Arc::make_mut(&mut self.recent);
        if recent.len() == 32 {
            recent.pop_front();
        }
        recent.push_back(review);
    }
    pub fn changed_past(&mut self) {
        if let Some(active) = &mut self.active {
            active.changed_past = true;
        }
    }
    fn reconcile(&mut self, after: &Authority) {
        let Some(active) = &mut self.active else {
            return;
        };
        if !active.changed_past
            && after
                .last_resolution
                .as_ref()
                .is_none_or(|r| r.violation.is_none())
        {
            return;
        }
        active.changed_past = false;
        active.near_hog = None;
        active.review.path = Arc::new(vec![active.review.release_pos]);
        let team = active.review.seat.team;
        after.replay_for_review(team, |sim| self.tick(sim));
    }
    pub fn transition(&mut self, before: &Authority, after: &Authority) {
        if before.game.phase == Phase::Calling && after.game.phase == Phase::InFlight {
            self.begin(
                &after.sim,
                Seat {
                    team: before.game.delivering_team(),
                    position: before.game.throwing_seat(),
                },
                before.game.end,
            );
        }
        if self.active.is_none() && after.game.delivered > before.game.delivered {
            self.begin(
                &after.sim,
                Seat {
                    team: before.game.delivering_team(),
                    position: before.game.throwing_seat(),
                },
                before.game.end,
            );
        }
        if self.active.is_some()
            && after.sim.is_resting()
            && !matches!(after.game.phase, Phase::InFlight | Phase::Choice)
        {
            self.reconcile(after);
            self.finish(
                &after.sim,
                after.last_resolution.as_ref().and_then(|r| r.violation),
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{practice::Practice, recorded::RecordedMatch};
    use curl_rules::Rules;
    use curl_sim::Release;
    #[test]
    fn live_split_waits_for_near_hog_freezes_at_far_hog_and_rebuilds() {
        let mut practice = Practice::new(42);
        let mut release = Release::draw();
        release.pos.y = Fx::int(-36);
        release.vel.y = Fx::ratio(27, 10);
        practice.release(release).unwrap();
        assert_eq!(
            practice.reviews.split_clock(&practice.sim),
            SplitClock::Waiting
        );
        let mut near = None;
        let mut rebuilt = false;
        while !practice.sim.is_resting() {
            practice.step(&[]).unwrap();
            if near.is_none() && practice.sim.stones[0].pos.y - RADIUS > NEAR_HOG {
                near = Some(practice.sim.tick);
            }
            let clock = practice.reviews.split_clock(&practice.sim);
            if let Some(far) = practice.sim.hog_tick {
                assert_eq!(
                    clock,
                    SplitClock::Complete((far - near.unwrap()) * 1000 / 240)
                );
            } else if let Some(near) = near {
                assert_eq!(
                    clock,
                    SplitClock::Running((practice.sim.tick - near) * 1000 / 240)
                );
                if !rebuilt && practice.sim.tick > near + 120 {
                    let restored = Practice::from_log(practice.log.clone()).unwrap();
                    assert_eq!(restored.reviews.split_clock(&restored.sim), clock);
                    assert_eq!(restored.sim.hash(), practice.sim.hash());
                    rebuilt = true;
                }
            } else {
                assert_eq!(clock, SplitClock::Waiting);
            }
        }
        assert!(rebuilt);
        let mut short = Practice::new(42);
        let mut release = Release::draw();
        release.vel.y = Fx::ratio(1, 10);
        short.release(release).unwrap();
        while !short.sim.is_resting() {
            short.step(&[]).unwrap();
        }
        assert_eq!(
            short.reviews.split_clock(&short.sim),
            SplitClock::Incomplete
        );
    }
    #[test]
    fn early_release_split_is_true_hog_to_hog_and_practice_rebuilds_paths() {
        let mut practice = Practice::new(42);
        let mut release = Release::draw();
        release.pos.y = Fx::int(-36);
        release.vel.y = Fx::ratio(27, 10);
        practice.release(release).unwrap();
        let mut near = None;
        while !practice.sim.is_resting() {
            practice.step(&[]).unwrap();
            if near.is_none() && practice.sim.stones[0].pos.y - RADIUS > NEAR_HOG {
                near = Some(practice.sim.tick);
            }
        }
        let review = practice.reviews.recent.back().unwrap();
        let expected = (practice.sim.hog_tick.unwrap() - near.unwrap()) * 1000 / 240;
        assert_eq!(review.hog_split_ms, Some(expected));
        assert!(
            expected + 2000
                < (practice.sim.hog_tick.unwrap() - practice.sim.release_tick) * 1000 / 240
        );
        assert!(review.path.len() > 20);
        let restored = Practice::from_log(practice.log.clone()).unwrap();
        assert_eq!(restored.sim.hash(), practice.sim.hash());
        assert_eq!(restored.reviews, practice.reviews);
    }
    #[test]
    fn match_reviews_rebuild_for_both_positions_and_do_not_change_hashes() {
        let mut game = RecordedMatch::new(42, Rules::club(), 1).unwrap();
        for _ in 0..8 {
            let seat = Seat {
                team: game.game.delivering_team(),
                position: game.game.throwing_seat(),
            };
            let mut release = Release::draw();
            release.vel = V2::new(Fx::ratio(2, 10), Fx::int(4));
            game.release(seat, release).unwrap();
            while game.game.phase == Phase::InFlight {
                game.advance(64, None).unwrap();
            }
        }
        assert_eq!(game.reviews.recent.len(), 8);
        for seat in [0, 1, 4, 5] {
            assert_eq!(game.reviews.stats[seat].shots, 2);
        }
        let before = game.hash();
        assert_eq!(game.reviews.stats[0].spread_mm_s(), 0);
        assert_eq!(before, game.hash());
        let restored = RecordedMatch::parse(game.json().unwrap().as_bytes()).unwrap();
        assert_eq!(restored.hash(), before);
        assert_eq!(restored.reviews, game.reviews);
    }
    #[test]
    fn late_sweep_review_reconciles_to_the_accepted_physical_path() {
        use crate::recorded::Record;
        let mut late = RecordedMatch::new(42, Rules::club(), 1).unwrap();
        let seat = Seat {
            team: 0,
            position: 0,
        };
        late.release(seat, Release::draw()).unwrap();
        let mut early = late.clone();
        let tick = late.sim.release_tick + 40;
        let record = Record::Sweep {
            seat,
            tick,
            input: curl_sim::Sweep::centered(0, 255),
        };
        early.advance(28, None).unwrap();
        early.apply(record.clone()).unwrap();
        early.advance(24, None).unwrap();
        late.advance(52, None).unwrap();
        late.apply(record).unwrap();
        assert_eq!(late.sim.hash(), early.sim.hash());
        for game in [&mut late, &mut early] {
            while game.game.phase == Phase::InFlight {
                game.advance(64, None).unwrap();
            }
        }
        assert_eq!(late.hash(), early.hash());
        assert_eq!(late.reviews, early.reviews);
    }
    #[test]
    fn protected_remedy_keeps_the_physical_path_and_records_the_removed_delivery() {
        let mut rules = Rules::club();
        rules.no_tick = false;
        let mut game = RecordedMatch::new(42, rules, 1).unwrap();
        let guard = crate::ai::solve(
            &game.sim,
            V2::new(Fx::ZERO, Fx::int(-3)),
            crate::ai::ShotKind::Guard,
            1,
        );
        game.release(
            Seat {
                team: 0,
                position: 0,
            },
            guard.release(),
        )
        .unwrap();
        while game.game.phase == Phase::InFlight {
            game.advance(64, None).unwrap();
        }
        let target = game.sim.stones.iter().find(|s| s.active).unwrap().pos;
        let hit = crate::ai::solve(&game.sim, target, crate::ai::ShotKind::Hit, 1);
        game.release(
            Seat {
                team: 1,
                position: 0,
            },
            hit.release(),
        )
        .unwrap();
        while game.game.phase == Phase::InFlight {
            game.advance(64, None).unwrap();
        }
        let shot = game.reviews.recent.back().unwrap();
        assert_eq!(shot.violation, Some(Violation::ProtectedRemoval));
        assert!(!shot.in_play && shot.finish.is_none());
        assert!(shot.path.len() > 20);
        assert_eq!(game.reviews.recent.len(), 2);
        let restored = RecordedMatch::parse(game.json().unwrap().as_bytes()).unwrap();
        assert_eq!(restored.reviews, game.reviews);
    }
    #[test]
    fn hog_fault_and_recent_history_bound_preserve_all_stats() {
        let mut p = Practice::new(42);
        for _ in 0..40 {
            p.hog_violation().unwrap();
            p.clear_stones().unwrap();
        }
        assert_eq!(p.reviews.recent.len(), 32);
        assert_eq!(p.reviews.stats[0].shots, 40);
        assert_eq!(p.reviews.stats[0].hog_faults, 40);
        assert_eq!(p.reviews.stats[0].mean_speed_mm_s(), 0);
        let restored = Practice::from_log(p.log.clone()).unwrap();
        assert_eq!(restored.reviews, p.reviews);
    }
}
