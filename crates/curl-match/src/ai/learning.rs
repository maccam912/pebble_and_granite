//! Bounded, disposable delivery calibration from visible completed shots.
//! No hidden seed, heat, wear or sampled surface values enter this estimate.
use super::{Difficulty, Plan, ShotKind, mm, plan_at_level, solve, trajectory};
use crate::{
    Authority,
    review::{ReviewBook, ShotReview},
};
use curl_fx::{Fx, V2};
use curl_sim::{MAX_TICKS, Release, Sim};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Reading {
    weight: i64,
    curl_milli: i64,
    samples: u8,
}

fn clean(shot: &ShotReview) -> bool {
    shot.in_play
        && shot.finish.is_some()
        && shot.contacts == 0
        && !shot.swept
        && shot.violation.is_none()
        && (1700..=2450).contains(&shot.speed_mm_s)
        && shot.release_spin.abs() >= Fx::ratio(4, 100)
        && shot.release_spin.abs() <= Fx::ratio(25, 100)
}

fn finish(release: Release) -> Option<V2> {
    let mut sim = Sim::new(0);
    sim.release(release).ok()?;
    for _ in 0..MAX_TICKS {
        if sim.is_resting() {
            break;
        }
        sim.step(&[]);
    }
    let stone = sim.stones.first()?;
    (sim.is_resting() && stone.active).then_some(stone.pos)
}

fn curl(release: &Release, end: V2) -> Fx {
    end.x - release.pos.x - (end.y - release.pos.y) * release.vel.x / release.vel.y
}

fn reading(book: &ReviewBook, target: V2, current_end: u8) -> Reading {
    let mut read = Reading::default();
    // Only neighbouring lanes and this/previous end. No history leaks across a
    // new match; the bounded ReviewBook is reconstructed by journal replay.
    for shot in book
        .recent
        .iter()
        .rev()
        .filter(|s| {
            clean(s)
                && s.end <= current_end
                && current_end - s.end <= 1
                && (s.finish.unwrap().x - target.x).abs() <= Fx::ratio(8, 10)
        })
        .take(8)
    {
        let release = Release {
            stone: 0,
            team: 0,
            pos: shot.release_pos,
            vel: shot.release_vel,
            spin: shot.release_spin,
        };
        let Some(expected) = finish(release.clone()) else {
            continue;
        };
        let actual = shot.finish.unwrap();
        let mut faster = release.clone();
        faster.vel = faster.vel * (Fx::ONE + Fx::ratio(10, shot.speed_mm_s));
        let Some(faster_end) = finish(faster) else {
            continue;
        };
        let response = mm(faster_end.y - expected.y);
        if response <= 20 {
            continue;
        }
        // Finite-difference speed response, and signed curl relative to the
        // observed release ray, rather than blaming player aim for ice error.
        let weight = (-mm(actual.y - expected.y) * 10 / response).clamp(-100, 100);
        let expected_curl = mm(curl(&release, expected));
        if expected_curl.abs() < 100 {
            continue;
        }
        let curl_milli =
            ((mm(curl(&release, actual)) - expected_curl) * 1000 / expected_curl).clamp(-300, 300);
        read.weight += weight;
        read.curl_milli += curl_milli;
        read.samples += 1;
    }
    // Two prior-equivalent observations shrink small samples toward standard
    // ice. This is a cautious heuristic, not a calibrated Bayesian posterior.
    let divisor = i64::from(read.samples) + 2;
    read.weight /= divisor;
    read.curl_milli /= divisor;
    read
}

fn calibrate(mut plan: Plan, book: &ReviewBook, end: u8) -> Plan {
    let read = reading(book, plan.target, end);
    plan.ice_samples = read.samples;
    if read.samples == 0 {
        return plan;
    }
    let release = plan.release();
    let at = trajectory(&Sim::new(0), &plan);
    let correction = (mm(curl(&release, at)) * read.curl_milli / 1000).clamp(-250, 250);
    let distance = mm(at.y - release.pos.y).max(1000);
    let tee_distance = mm(-release.pos.y);
    plan.broom_mm = (plan.broom_mm - correction * tee_distance / distance).clamp(-2200, 2200);
    if plan.kind.weight_kind() != 2 {
        plan.speed_mm_s = (plan.speed_mm_s + read.weight).clamp(1650, 2450);
    }
    plan
}

pub fn plan(
    authority: &Authority,
    book: &ReviewBook,
    level: Difficulty,
) -> Result<Plan, &'static str> {
    // Tactical outcomes are forecasts on the standard-sheet model. Delivery
    // corrections come only from observations, after selecting the intention.
    Ok(calibrate(
        plan_at_level(authority, level)?,
        book,
        authority.game.end,
    ))
}

pub fn called(
    authority: &Authority,
    book: &ReviewBook,
    target: V2,
    kind: ShotKind,
    turn: i64,
) -> Plan {
    calibrate(
        solve(&Sim::new(0), target, kind, turn),
        book,
        authority.game.end,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        Seat,
        recorded::{Brush, Record, RecordedMatch},
    };
    use curl_rules::{Phase, Rules};
    use curl_sim::{Cell, Ice, Sweep};
    use std::sync::Arc;

    fn warm_sheet() -> Sim {
        let mut sim = Sim::new(991);
        sim.ice.varied = true;
        for x in -25..=25 {
            for y in -680..=40 {
                let p = V2::new(Fx::ratio(x, 20), Fx::ratio(y, 20));
                if let Some(cell) = Ice::cell(p) {
                    sim.ice.cells.insert(
                        cell,
                        Cell {
                            heat: 1500,
                            updated: 0,
                            wear: 80,
                        },
                    );
                }
            }
        }
        sim
    }

    fn observe(mut sim: Sim, release: Release) -> ReviewBook {
        sim.release(release).unwrap();
        let mut book = ReviewBook::default();
        book.begin(
            &sim,
            Seat {
                team: 0,
                position: 0,
            },
            1,
        );
        for _ in 0..MAX_TICKS {
            if sim.is_resting() {
                break;
            }
            sim.step(&[]);
            book.tick(&sim);
        }
        book.finish(&sim, None);
        book
    }

    #[test]
    fn unseen_ice_cannot_change_plan_call_or_live_advice() {
        let a = Authority::new(42, Rules::club(), 1).unwrap();
        let mut b = a.clone();
        b.sim.ice = warm_sheet().ice;
        let book = ReviewBook::default();
        let before = b.hash();
        for level in [Difficulty::Club, Difficulty::Competitive, Difficulty::Elite] {
            assert_eq!(
                plan(&a, &book, level).unwrap().release(),
                plan(&b, &book, level).unwrap().release()
            );
        }
        assert_eq!(
            called(&a, &book, V2::ZERO, ShotKind::Draw, 1).release(),
            called(&b, &book, V2::ZERO, ShotKind::Draw, 1).release()
        );
        assert_eq!(before, b.hash());
        let mut moving = Sim::new(0);
        moving.release(Release::draw()).unwrap();
        let mut hidden = moving.clone();
        hidden.ice = b.sim.ice;
        assert_eq!(
            super::super::advice(&moving, V2::ZERO, Difficulty::Club),
            super::super::advice(&hidden, V2::ZERO, Difficulty::Club)
        );
    }

    #[test]
    fn clean_observations_improve_weight_without_reading_the_surface() {
        let game = Authority::new(42, Rules::club(), 1).unwrap();
        let baseline = called(&game, &ReviewBook::default(), V2::ZERO, ShotKind::Draw, 1);
        let mut observations = observe(warm_sheet(), baseline.release());
        let observed = observations.recent[0].clone();
        assert!(clean(&observed));
        for _ in 0..3 {
            Arc::make_mut(&mut observations.recent).push_back(observed.clone());
        }
        let adjusted = called(&game, &observations, V2::ZERO, ShotKind::Draw, 1);
        assert_eq!(adjusted.ice_samples, 4);
        assert!(adjusted.speed_mm_s < baseline.speed_mm_s);
        let before = observed.finish.unwrap().length();
        let after = observe(warm_sheet(), adjusted.release()).recent[0]
            .finish
            .unwrap()
            .length();
        eprintln!(
            "learning: baseline={}mm corrected={}mm speeds={},{}",
            mm(before),
            mm(after),
            baseline.speed_mm_s,
            adjusted.speed_mm_s
        );
        assert!(
            after < before * Fx::ratio(8, 10),
            "Calibration failed to reduce actual error"
        );
        let distant = called(
            &game,
            &observations,
            V2::new(Fx::ratio(15, 10), Fx::ZERO),
            ShotKind::Draw,
            1,
        );
        assert_eq!(
            distant.ice_samples, 0,
            "Unknown lane borrowed confident ice"
        );
        let mut later = game.clone();
        later.game.end = 3;
        assert_eq!(
            called(&later, &observations, V2::ZERO, ShotKind::Draw, 1).ice_samples,
            0
        );
        for variant in 0..3 {
            let mut rejected = observed.clone();
            match variant {
                0 => rejected.contacts = 1,
                1 => rejected.swept = true,
                _ => rejected.violation = Some(curl_rules::Violation::HogRelease),
            }
            let mut book = ReviewBook::default();
            Arc::make_mut(&mut book.recent).push_back(rejected);
            assert_eq!(
                called(&game, &book, V2::ZERO, ShotKind::Draw, 1).ice_samples,
                0
            );
        }
        let mut misplaced = baseline.clone();
        misplaced.broom_mm += 500;
        let neutral = observe(Sim::new(0), misplaced.release());
        let read = reading(&neutral, neutral.recent[0].finish.unwrap(), 1);
        assert_eq!(
            read,
            Reading {
                samples: 1,
                weight: 0,
                curl_milli: 0
            },
            "Player line error was learned as ice error"
        );
    }

    #[test]
    fn observation_flags_and_learning_rebuild_from_accepted_journal() {
        for swept in [false, true] {
            let mut game = RecordedMatch::new(42, Rules::club(), 1).unwrap();
            let shot = solve(&Sim::new(0), V2::ZERO, ShotKind::Draw, 1);
            game.release(
                Seat {
                    team: 0,
                    position: 0,
                },
                shot.release(),
            )
            .unwrap();
            game.advance(32, None).unwrap();
            if swept {
                // Accepted late brush evidence excludes the shot after rewind.
                game.apply(Record::BrushSpan {
                    seat: Seat {
                        team: 0,
                        position: 0,
                    },
                    tick: game.sim.tick - 12,
                    input: Sweep::centered(0, 255),
                    count: 12,
                })
                .unwrap();
            }
            while game.game.phase == Phase::InFlight {
                game.advance(
                    64,
                    Some(Brush {
                        effort: 0,
                        lateral_mm: 0,
                        ahead_mm: 180,
                    }),
                )
                .unwrap();
            }
            assert_eq!(game.reviews.recent[0].swept, swept);
            let restored = RecordedMatch::parse(game.json().unwrap().as_bytes()).unwrap();
            assert_eq!(game.reviews, restored.reviews);
            assert_eq!(game.hash(), restored.hash());
            let before = reading(&game.reviews, V2::ZERO, 1);
            assert_eq!(before.samples, u8::from(!swept));
            assert_eq!(before, reading(&restored.reviews, V2::ZERO, 1));
            assert_eq!(
                plan(&game, &game.reviews, Difficulty::Club)
                    .unwrap()
                    .release(),
                plan(&restored, &restored.reviews, Difficulty::Club)
                    .unwrap()
                    .release()
            );
        }
    }
}
