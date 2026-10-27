//! Bounded strategic search and rated execution over the exact shared simulation.
//! Plans are derived, disposable state; only the eventual release is journalled.
use crate::Authority;
use curl_fx::{Fx, Rng, V2};
use curl_rules::{Phase, Remedy};
use curl_sim::{HOUSE, MAX_TICKS, RADIUS, Release, Sim};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Difficulty {
    Club,
    Competitive,
    Elite,
}
impl Difficulty {
    /// Maximum centered triangular scatter, in mm/s, mm at the tee, milli-turns/s.
    pub fn scatter(self) -> (i64, i64, i64) {
        match self {
            Self::Club => (100, 360, 45),
            Self::Competitive => (40, 150, 22),
            Self::Elite => (12, 45, 8),
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShotKind {
    Draw,
    Guard,
    Hit,
}
impl ShotKind {
    pub fn name(self) -> &'static str {
        match self {
            Self::Draw => "Draw",
            Self::Guard => "Guard",
            Self::Hit => "Hit",
        }
    }
}
#[derive(Clone, Debug)]
pub struct Plan {
    pub kind: ShotKind,
    pub target: V2,
    pub broom_mm: i64,
    pub speed_mm_s: i64,
    pub turn: i64,
}
impl Plan {
    pub fn release(&self) -> Release {
        let mut release = Release::draw();
        release.vel = V2::new(Fx::ratio(self.broom_mm, 1000), -release.pos.y).unit()
            * Fx::ratio(self.speed_mm_s, 1000);
        release.spin = Fx::ratio(self.turn * 120, 1000);
        release
    }
    /// Same random quantiles across tiers make accuracy comparisons meaningful.
    pub fn execute(&self, difficulty: Difficulty, seed: u64) -> Release {
        let (weight, line, rotation) = difficulty.scatter();
        let mut rng = Rng(seed);
        let mut noisy = self.clone();
        noisy.speed_mm_s = (self.speed_mm_s + noise(&mut rng, weight)).clamp(1400, 4200);
        noisy.broom_mm = (self.broom_mm + noise(&mut rng, line)).clamp(-2200, 2200);
        let mut release = noisy.release();
        release.spin += Fx::ratio(noise(&mut rng, rotation), 1000);
        release
    }
}
fn noise(rng: &mut Rng, amplitude: i64) -> i64 {
    let sample = |rng: &mut Rng| (rng.next_u64() % 2001) as i64 - 1000;
    (sample(rng) + sample(rng) + sample(rng)) * amplitude / 3000
}
fn mm(value: Fx) -> i64 {
    (value * Fx::int(1000)).raw() / Fx::ONE.raw()
}

/// Inverse solve against the current ice without obstacles, then test the whole
/// board through Authority before selecting a shot. No hidden physics changes.
pub fn solve(sim: &Sim, target: V2, kind: ShotKind, turn: i64) -> Plan {
    let mut plan = Plan {
        kind,
        target,
        broom_mm: mm(target.x).clamp(-2200, 2200),
        speed_mm_s: if kind == ShotKind::Hit { 3000 } else { 2050 },
        turn,
    };
    let mut low = 1650;
    let mut high = 2450;
    for _ in 0..12 {
        if kind != ShotKind::Hit {
            plan.speed_mm_s = (low + high) / 2;
        }
        let at = trajectory(sim, &plan);
        // For a hit, measure line at the target's depth instead of at rest.
        let distance = if kind == ShotKind::Hit {
            target.y - Release::draw().pos.y
        } else {
            -Release::draw().pos.y
        };
        let correction = (target.x - at.x) * (-Release::draw().pos.y) / distance;
        plan.broom_mm = (plan.broom_mm + mm(correction)).clamp(-2200, 2200);
        if kind != ShotKind::Hit {
            if at.y < target.y {
                low = plan.speed_mm_s;
            } else {
                high = plan.speed_mm_s;
            }
        }
    }
    plan
}
fn trajectory(source: &Sim, plan: &Plan) -> V2 {
    let mut sim = source.clone();
    sim.stones.clear();
    sim.release(plan.release()).expect("bounded plan release");
    let start = sim.tick;
    let mut last = sim.stones[0].pos;
    while !sim.is_resting() && sim.tick - start < MAX_TICKS {
        sim.step(&[]);
        let pos = sim.stones[0].pos;
        if plan.kind == ShotKind::Hit && pos.y >= plan.target.y {
            let span = pos.y - last.y;
            return if span > Fx::ZERO {
                last + (pos - last) * ((plan.target.y - last.y) / span)
            } else {
                pos
            };
        }
        last = pos;
    }
    last
}
pub fn plan(authority: &Authority) -> Result<Plan, &'static str> {
    plan_at_level(authority, Difficulty::Club)
}

/// The shortlist bounds exact-simulation work, independently of frame rate.
/// Elite also samples execution error using fixed planning seeds, never the
/// eventual executor seed. These utilities are not calibrated probabilities.
pub fn plan_at_level(authority: &Authority, level: Difficulty) -> Result<Plan, &'static str> {
    if authority.game.phase != Phase::Calling || authority.in_hand.is_some() {
        return Err("AI planning requires an unheld calling phase");
    }
    let team = authority.game.delivering_team();
    let mut candidates = ranked_candidates(authority, team)?;
    let width = match level {
        Difficulty::Club => 1,
        Difficulty::Competitive => 2,
        Difficulty::Elite => 4,
    };
    // Keep different tactical intentions in the small reply-search budget;
    // otherwise both turns of the same hit can occupy the whole shortlist.
    let mut intentions = Vec::new();
    candidates.retain(|(plan, _, _)| {
        let key = (plan.kind, plan.target);
        if intentions.contains(&key) {
            return false;
        }
        intentions.push(key);
        true
    });
    candidates.truncate(width);
    let mut best = None;
    for (candidate, next, immediate) in candidates {
        let mut value = immediate;
        if level != Difficulty::Club && next.game.phase == Phase::Calling {
            // The opponent chooses its best legal reply, including remedies.
            let replies = ranked_candidates(&next, 1 - team)?;
            value = replies
                .iter()
                .map(|(_, outcome, _)| position_value(outcome, team))
                .min()
                .unwrap_or(immediate);
        }
        if level == Difficulty::Elite {
            let mut sampled = 0;
            for seed in [0x5151, 0x9292, 0x1373, 0x2464] {
                let outcome = outcome(authority, candidate.execute(level, seed))?;
                sampled += position_value(&outcome, team);
            }
            // Penalize brittle nominal shots. Do not claim these four samples
            // form a probability estimate or allow lucky samples to boost it.
            value -= (immediate - sampled / 4).max(0);
        }
        if best.as_ref().is_none_or(|(_, score)| value > *score) {
            best = Some((candidate, value));
        }
    }
    best.map(|(shot, _)| shot).ok_or("No legal AI candidate")
}

fn candidate_plans(authority: &Authority) -> Vec<Plan> {
    let mut targets = vec![
        (ShotKind::Draw, V2::ZERO),
        (
            ShotKind::Draw,
            V2::new(Fx::ratio(-8, 10), Fx::ratio(-4, 10)),
        ),
        (ShotKind::Draw, V2::new(Fx::ratio(8, 10), Fx::ratio(-4, 10))),
        (ShotKind::Guard, V2::new(Fx::ZERO, Fx::int(-3))),
    ];
    let team = authority.game.delivering_team();
    let mut opponents: Vec<_> = authority
        .sim
        .stones
        .iter()
        .filter(|s| s.active && s.team != team && s.pos.length() <= HOUSE + RADIUS)
        .collect();
    opponents.sort_by_key(|s| s.pos.length());
    for stone in opponents.into_iter().take(2) {
        targets.push((ShotKind::Hit, stone.pos));
    }
    let mut plans = Vec::new();
    for (kind, target) in targets {
        for turn in [-1, 1] {
            plans.push(solve(&authority.sim, target, kind, turn));
        }
    }
    plans
}

fn ranked_candidates(
    authority: &Authority,
    team: u8,
) -> Result<Vec<(Plan, Authority, i64)>, &'static str> {
    let mut candidates = Vec::new();
    for candidate in candidate_plans(authority) {
        let next = outcome(authority, candidate.release())?;
        let value = position_value(&next, team);
        candidates.push((candidate, next, value));
    }
    // Stable sorting preserves the deterministic catalogue order on ties.
    candidates.sort_by_key(|(_, _, value)| std::cmp::Reverse(*value));
    Ok(candidates)
}

fn outcome(authority: &Authority, release: Release) -> Result<Authority, &'static str> {
    let mut next = authority.clone();
    let team = authority.game.delivering_team();
    next.release(
        crate::Seat {
            team,
            position: authority.game.throwing_seat(),
        },
        release,
    )?;
    for _ in 0..MAX_TICKS {
        if next.game.phase != Phase::InFlight {
            break;
        }
        next.step()?;
    }
    if next.game.phase == Phase::InFlight {
        return Err("AI rollout did not settle");
    }
    if next.game.phase == Phase::Choice {
        let remedy = best_remedy(&next)?;
        next.choose(
            crate::Seat {
                team: 1 - team,
                position: 0,
            },
            remedy,
        )?;
    }
    Ok(next)
}
/// The non-offending team chooses its better legal board; ties restore the guard.
pub fn best_remedy(authority: &Authority) -> Result<Remedy, &'static str> {
    if authority.game.phase != Phase::Choice {
        return Err("No remedy is pending");
    }
    let team = 1 - authority.game.delivering_team();
    let mut best = None;
    for remedy in [Remedy::Restore, Remedy::Accept] {
        let mut next = authority.clone();
        next.choose(crate::Seat { team, position: 0 }, remedy)?;
        let value = position_value(&next, team);
        if best.as_ref().is_none_or(|(_, score)| value > *score) {
            best = Some((remedy, value));
        }
    }
    Ok(best.expect("two legal remedies").0)
}

/// A noisy weight estimate for the skip. The forecast is a disposable unswept
/// rollout; it does not alter the real ice or move any authoritative stone.
pub fn advice(sim: &Sim, target: V2, difficulty: Difficulty) -> (u8, u8) {
    let Some(id) = sim.delivered else {
        return (0, 0);
    };
    let Some(stone) = sim
        .stones
        .iter()
        .find(|s| s.id == id && s.active && s.vel != V2::ZERO)
    else {
        return (0, 0);
    };
    let mut forecast = sim.clone();
    let start = forecast.tick;
    while !forecast.is_resting() && forecast.tick - start < MAX_TICKS {
        forecast.step(&[]);
    }
    let stop = forecast
        .stones
        .iter()
        .find(|s| s.id == id)
        .map_or(stone.pos, |s| s.pos);
    let mut rng = Rng(sim.ice.seed ^ (id as u64 + 1).wrapping_mul(0x9e3779b97f4a7c15));
    let uncertainty = noise(&mut rng, difficulty.scatter().1 * 2);
    let short = mm(target.y - stop.y) + uncertainty;
    let effort = if short > 180 {
        255
    } else if short > -80 {
        80
    } else {
        0
    };
    // Guard zones 1–3, front rings 4–6, tee 7, back rings 8–10.
    let zone = weight_zone(mm(stop.y) + uncertainty);
    (effort, zone)
}

fn weight_zone(y_mm: i64) -> u8 {
    [-4200, -3000, -1829, -1220, -610, -150, 150, 610, 1220]
        .iter()
        .position(|boundary| y_mm < *boundary)
        .map_or(10, |index| index as u8 + 1)
}

fn position_value(authority: &Authority, team: u8) -> i64 {
    let game = &authority.game;
    let sim = &authority.sim;
    let score_lead =
        i64::from(game.score[team as usize]) - i64::from(game.score[(1 - team) as usize]);
    if game.phase == Phase::GameComplete {
        return if game.winner == Some(team) {
            10_000_000
        } else {
            -10_000_000
        };
    }
    let completed = game.phase == Phase::EndComplete;
    let (counting, points) = curl_rules::score_end(&sim.stones);
    // Settled end points have already been added by the rules engine.
    let lead = score_lead
        + if completed {
            0
        } else {
            i64::from(points) * if counting == Some(team) { 1 } else { -1 }
        };
    let ends_left = i64::from(game.rules.ends.saturating_sub(game.end));
    let mut value = lead * 100_000 + lead.signum() * 50_000 / (ends_left + 1);
    let next_hammer = if completed {
        game.hammer
    } else {
        counting.map_or(game.hammer, |scorer| 1 - scorer)
    };
    // A heuristic option value for the next end: it allows early blanks with
    // hammer. A real last-end win always dominates it through the terminal gate.
    value += if next_hammer == team { 55_000 } else { -55_000 };
    if completed {
        return value;
    }
    for stone in sim.stones.iter().filter(|s| s.active) {
        let sign = if stone.team == team { 1 } else { -1 };
        let distance = stone.pos.length();
        if distance <= HOUSE + RADIUS {
            value += sign * (5000 - mm(distance));
        } else if game.delivered < game.rules.stones_per_team() * 2 - 4
            && stone.pos.y < -HOUSE
            && stone.pos.y > Fx::int(-5)
        {
            let aggressive =
                game.score[stone.team as usize] <= game.score[(1 - stone.team) as usize];
            value += sign * (1200 - mm(stone.pos.x.abs()) / 2) * if aggressive { 1 } else { -1 };
        }
    }
    value
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::recorded::RecordedMatch;
    use curl_rules::Rules;
    #[test]
    fn last_stone_uses_end_score_and_hammer_instead_of_always_drawing() {
        let mut early = Authority::new(42, Rules::club(), 1).unwrap();
        early.game.delivered = 15;
        let early_hash = early.hash();
        let blank = plan_at_level(&early, Difficulty::Competitive).unwrap();
        let blanked = outcome(&early, blank.release()).unwrap();
        assert_eq!(blanked.game.phase, Phase::EndComplete);
        assert_eq!(blanked.game.score, [0, 0]);
        assert_eq!(blanked.game.hammer, 1);
        assert_eq!(early.hash(), early_hash);

        let mut final_end = early.clone();
        final_end.game.end = final_end.game.rules.ends;
        for level in [Difficulty::Club, Difficulty::Competitive, Difficulty::Elite] {
            let winning = plan_at_level(&final_end, level).unwrap();
            let won = outcome(&final_end, winning.release()).unwrap();
            assert_eq!(
                won.game.winner,
                Some(1),
                "{level:?} blanked instead of winning"
            );
        }
        // Trailing with hammer, a single point saves the match in the final end.
        final_end.game.score = [1, 0];
        let tying = plan_at_level(&final_end, Difficulty::Competitive).unwrap();
        let tied = outcome(&final_end, tying.release()).unwrap();
        assert_eq!(tied.game.score, [1, 1]);
        assert_eq!(tied.game.phase, Phase::EndComplete);
    }

    #[test]
    fn strategic_evaluation_is_zero_sum_and_does_not_double_count_end_points() {
        let mut game = Authority::new(42, Rules::club(), 1).unwrap();
        game.game.score = [2, 0];
        game.sim
            .add_resting(curl_sim::Stone::resting(
                0,
                0,
                V2::new(Fx::ZERO, Fx::int(-3)),
            ))
            .unwrap();
        game.sim
            .add_resting(curl_sim::Stone::resting(1, 1, V2::ZERO))
            .unwrap();
        assert_eq!(position_value(&game, 0), -position_value(&game, 1));
        game.game.phase = Phase::EndComplete;
        game.game.score = [2, 1];
        game.game.hammer = 0;
        let settled = position_value(&game, 0);
        game.sim.stones.clear();
        assert_eq!(position_value(&game, 0), settled);
    }

    #[test]
    fn reply_search_keeps_a_guarded_scoring_position() {
        let mut game = Authority::new(42, Rules::club(), 1).unwrap();
        game.game.delivered = 6;
        // Gold has shot rock behind its centre guard; Cyan sits front-right.
        for (id, team, x, y) in [(0, 0, 0, 0), (1, 1, 800, -400), (2, 0, 0, -3000)] {
            game.sim
                .add_resting(curl_sim::Stone::resting(
                    id,
                    team,
                    V2::new(Fx::ratio(x, 1000), Fx::ratio(y, 1000)),
                ))
                .unwrap();
        }
        let before = game.hash();
        let club = plan_at_level(&game, Difficulty::Club).unwrap();
        let competitive = plan_at_level(&game, Difficulty::Competitive).unwrap();
        let reply_value = |plan: &Plan| {
            let next = outcome(&game, plan.release()).unwrap();
            ranked_candidates(&next, 1)
                .unwrap()
                .iter()
                .map(|(_, end, _)| position_value(end, 0))
                .min()
                .unwrap()
        };
        assert_eq!(club.kind, ShotKind::Hit);
        assert_eq!(competitive.kind, ShotKind::Draw);
        assert!(reply_value(&competitive) > reply_value(&club) + 50_000);
        assert_eq!(game.hash(), before);
        let repeated = plan_at_level(&game, Difficulty::Competitive).unwrap();
        assert_eq!(competitive.release(), repeated.release());
    }
    #[test]
    fn weight_zones_match_the_accessible_legend() {
        for (index, y) in [-5000, -3500, -2400, -1500, -900, -400, 0, 400, 900, 1500]
            .into_iter()
            .enumerate()
        {
            assert_eq!(weight_zone(y), index as u8 + 1);
        }
    }
    #[test]
    fn physical_no_tick_fixture_and_ai_remedy() {
        let mut game = RecordedMatch::new(42, Rules::club(), 1).unwrap();
        for (team, speed, broom) in [(0, 1981, -963), (1, 2016, -803)] {
            let shot = Plan {
                kind: ShotKind::Draw,
                target: V2::ZERO,
                speed_mm_s: speed,
                broom_mm: broom,
                turn: 1,
            };
            game.release(crate::Seat { team, position: 0 }, shot.release())
                .unwrap();
            while game.game.phase == Phase::InFlight {
                game.advance(64, None).unwrap();
            }
        }
        assert_eq!(game.game.phase, Phase::Choice);
        let before = game.hash();
        // This glancing tick promotes the non-offender's guard into the house.
        assert_eq!(best_remedy(&game).unwrap(), Remedy::Accept);
        assert_eq!(game.hash(), before);
        let pending = game.json().unwrap();
        for remedy in [Remedy::Accept, Remedy::Restore] {
            let mut restored = RecordedMatch::parse(pending.as_bytes()).unwrap();
            assert_eq!(restored.game.phase, Phase::Choice);
            restored
                .apply(crate::recorded::Record::Choose {
                    seat: crate::Seat {
                        team: 0,
                        position: 0,
                    },
                    remedy,
                })
                .unwrap();
            assert_eq!(restored.game.phase, Phase::Calling);
            assert_eq!(restored.game.delivered, 2);
            let final_copy = RecordedMatch::parse(restored.json().unwrap().as_bytes()).unwrap();
            assert_eq!(final_copy.hash(), restored.hash());
            assert_eq!(final_copy.reviews, restored.reviews);
        }
    }
    #[test]
    fn inverse_draw_reaches_both_sides_on_shared_ice() {
        for x in [-800, 0, 800] {
            let sim = Sim::new(42);
            let target = V2::new(Fx::ratio(x, 1000), Fx::ZERO);
            let plan = solve(&sim, target, ShotKind::Draw, 1);
            let at = trajectory(&sim, &plan);
            assert!((at - target).length() < Fx::ratio(8, 100), "{x}: {at:?}");
        }
    }
    #[test]
    fn called_guards_and_hits_solve_both_turns_and_target_sides() {
        let sim = Sim::new(42);
        for kind in [ShotKind::Guard, ShotKind::Hit] {
            for turn in [-1, 1] {
                for x in [-800, 800] {
                    let target = V2::new(
                        Fx::ratio(x, 1000),
                        if kind == ShotKind::Guard {
                            Fx::int(-3)
                        } else {
                            Fx::ZERO
                        },
                    );
                    let plan = solve(&sim, target, kind, turn);
                    assert!((trajectory(&sim, &plan) - target).length() < Fx::ratio(8, 100));
                }
            }
        }
    }
    #[test]
    fn accuracy_tiers_reduce_release_scatter_without_changing_the_plan() {
        let plan = solve(&Sim::new(42), V2::ZERO, ShotKind::Draw, 1);
        let ideal = plan.release();
        let mut error = [Fx::ZERO; 3];
        for seed in 1..=100 {
            for (i, level) in [Difficulty::Club, Difficulty::Competitive, Difficulty::Elite]
                .into_iter()
                .enumerate()
            {
                let release = plan.execute(level, seed);
                release.validate().unwrap();
                assert_eq!(release, plan.execute(level, seed));
                error[i] += (release.vel - ideal.vel).length();
            }
        }
        assert!(error[0] > error[1] * Fx::int(2));
        assert!(error[1] > error[2] * Fx::int(2));
    }
    #[test]
    fn accuracy_tiers_reduce_actual_landing_scatter() {
        let source = Sim::new(42);
        let plan = solve(&source, V2::ZERO, ShotKind::Draw, 1);
        let mut errors = [Fx::ZERO; 3];
        for seed in 1..=16 {
            for (index, tier) in [Difficulty::Club, Difficulty::Competitive, Difficulty::Elite]
                .into_iter()
                .enumerate()
            {
                let mut sim = source.clone();
                sim.release(plan.execute(tier, seed)).unwrap();
                while !sim.is_resting() {
                    sim.step(&[]);
                }
                errors[index] += sim.stones[0].pos.length();
            }
        }
        assert!(errors[0] > errors[1] * Fx::ratio(15, 10), "{errors:?}");
        assert!(errors[1] > errors[2] * Fx::ratio(15, 10), "{errors:?}");
    }
    #[test]
    fn planner_is_read_only_and_release_replays_through_team_end() {
        let mut game = RecordedMatch::new(42, Rules::club(), 1).unwrap();
        let before = game.hash();
        let shot = plan(&game).unwrap();
        assert_eq!(game.hash(), before);
        for _ in 0..16 {
            let seat = crate::Seat {
                team: game.game.delivering_team(),
                position: game.game.throwing_seat(),
            };
            let mut release = shot.execute(Difficulty::Competitive, game.game.delivered as u64 + 1);
            release.stone = game.game.next_stone_id();
            game.release(seat, release).unwrap();
            while game.game.phase == Phase::InFlight {
                game.advance(64, None).unwrap();
            }
            assert!(game.game.phase != Phase::Choice);
        }
        assert_eq!(game.game.phase, Phase::EndComplete);
        let restored = RecordedMatch::parse(game.json().unwrap().as_bytes()).unwrap();
        assert_eq!(restored.hash(), game.hash());
        game.next_end().unwrap();
        assert_eq!(game.game.end, 2);
        assert!(game.sim.stones.is_empty());
    }
}
