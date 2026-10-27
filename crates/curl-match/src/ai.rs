//! Bounded one-ply planner and rated execution over the exact shared simulation.
//! Plans are derived, disposable state; only the eventual release is journalled.
use crate::Authority;
use curl_fx::{Fx, Rng, V2};
use curl_rules::Phase;
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
    if authority.game.phase != Phase::Calling || authority.in_hand.is_some() {
        return Err("AI planning requires an unheld calling phase");
    }
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
    let mut best = None;
    for (kind, target) in targets {
        for turn in [-1, 1] {
            let candidate = solve(&authority.sim, target, kind, turn);
            let mut next = authority.clone();
            let seat = crate::Seat {
                team,
                position: authority.game.throwing_seat(),
            };
            if next.release(seat, candidate.release()).is_err() {
                continue;
            }
            for _ in 0..MAX_TICKS {
                if next.game.phase != Phase::InFlight {
                    break;
                }
                next.step()?;
            }
            // Team rules have already applied protected-stone remedies here.
            let value = board_value(&next.sim, team, authority.game.delivered);
            if best.as_ref().is_none_or(|(_, score)| value > *score) {
                best = Some((candidate, value));
            }
        }
    }
    best.map(|(shot, _)| shot).ok_or("No legal AI candidate")
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
    let zone = ((mm(stop.y) + uncertainty + 6000) / 850 + 1).clamp(1, 10) as u8;
    (effort, zone)
}

fn board_value(sim: &Sim, team: u8, delivered: u8) -> i64 {
    let mut house: Vec<_> = sim
        .stones
        .iter()
        .filter(|s| s.active && s.pos.length() <= HOUSE + RADIUS)
        .collect();
    house.sort_by_key(|s| s.pos.length());
    let mut value = 0;
    if let Some(first) = house.first() {
        let points = house.iter().take_while(|s| s.team == first.team).count() as i64;
        value += points
            * if first.team == team {
                100_000
            } else {
                -100_000
            };
    }
    for stone in sim.stones.iter().filter(|s| s.active) {
        let sign = if stone.team == team { 1 } else { -1 };
        let distance = stone.pos.length();
        if distance <= HOUSE + RADIUS {
            value += sign * (5000 - mm(distance));
        } else if delivered < 10 && stone.pos.y < -HOUSE && stone.pos.y > Fx::int(-5) {
            value += sign * (1200 - mm(stone.pos.x.abs()) / 2);
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
