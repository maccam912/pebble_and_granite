use super::*;
use curl_fx::{Fx, V2};
const A: Seat = Seat {
    team: 0,
    position: 0,
};
const B: Seat = Seat {
    team: 0,
    position: 1,
};
fn game() -> Authority {
    let mut a = Authority::new(42, Rules::mixed(), 1).unwrap();
    a.place_mixed(
        Seat {
            team: 1,
            position: 0,
        },
        true,
        PowerPlay::None,
    )
    .unwrap();
    a.release(A, Release::draw()).unwrap();
    a
}
#[test]
fn independent_players_and_future_tee_crossing_ignore_packet_order() {
    let mut a = game();
    let stone = a.sim.stones.iter_mut().find(|s| s.id == 2).unwrap();
    stone.pos.y = Fx::ratio(-1, 1000);
    stone.vel = V2::new(Fx::ZERO, Fx::int(2));
    let mut b = a.clone();
    let mut input = Sweep::centered(2, 255);
    input.brush = 3; // A client cannot choose the fatigue identity.
    for (game, seats) in [(&mut a, [A, B]), (&mut b, [B, A])] {
        for seat in seats {
            game.sweep_span(seat, 0, input, 8).unwrap();
        }
        assert_eq!(
            game.inputs(&game.sim)
                .iter()
                .map(|s| s.brush)
                .collect::<Vec<_>>(),
            vec![0, 1]
        );
        assert!(game.sweep(A, 0, Sweep::centered(2, 100)).is_err());
        game.step().unwrap();
        assert!(game.sim.stones.iter().find(|s| s.id == 2).unwrap().pos.y >= Fx::ZERO);
        assert_eq!(game.sim.brush_fatigue[..2], [3, 3]);
        assert_eq!(
            game.inputs(&game.sim)
                .iter()
                .map(|s| s.brush)
                .collect::<Vec<_>>(),
            vec![0]
        );
        game.step().unwrap();
        assert_eq!(game.sim.brush_fatigue[..2], [6, 1]);
        for _ in 0..6 {
            game.step().unwrap();
        }
        // Player two can take over when player one is not sweeping.
        game.sweep(B, 8, input).unwrap();
        assert_eq!(game.inputs(&game.sim)[0].brush, 1);
    }
    assert_eq!(a.hash(), b.hash());
}
#[test]
fn moving_own_stones_and_defending_tee_permissions_are_tick_based() {
    let mut a = game();
    let target = a.sim.stones.iter_mut().find(|s| s.team == 1).unwrap();
    let id = target.id;
    target.pos = V2::new(Fx::ratio(15, 10), Fx::ratio(-1, 1000));
    target.vel = V2::new(Fx::ZERO, Fx::int(1));
    let input = Sweep::centered(id, 255);
    assert!(a.sweep(A, 0, input).is_err()); // Opponent's stone before tee.
    for position in [0, 1] {
        a.sweep_span(Seat { team: 1, position }, 0, input, 8)
            .unwrap();
    }
    assert_eq!(
        a.inputs(&a.sim).iter().map(|s| s.brush).collect::<Vec<_>>(),
        vec![2, 3]
    );
    a.step().unwrap();
    assert_eq!(
        a.inputs(&a.sim).iter().map(|s| s.brush).collect::<Vec<_>>(),
        vec![3]
    );
    assert!(
        a.sweep(
            Seat {
                team: 1,
                position: 0
            },
            8,
            input
        )
        .is_err()
    );
    a.sweep(A, 1, input).unwrap(); // Delivering team may now sweep opponent behind tee.
    assert_eq!(
        a.inputs(&a.sim).iter().map(|s| s.brush).collect::<Vec<_>>(),
        vec![0, 3]
    );
}
#[test]
fn both_brushes_rewind_across_tee_like_full_release_replay() {
    // Fresh legal release, clear from the positioned stones.
    let mut release = Release::draw();
    release.vel = V2::new(Fx::ratio(2, 10), Fx::int(5));
    let mut a = Authority::new(42, Rules::mixed(), 1).unwrap();
    a.place_mixed(
        Seat {
            team: 1,
            position: 0,
        },
        true,
        PowerPlay::None,
    )
    .unwrap();
    a.release(A, release).unwrap();
    for _ in 0..4000 {
        if a.sim.stones.iter().find(|s| s.id == 2).unwrap().pos.y >= Fx::ratio(-5, 100) {
            break;
        }
        a.step().unwrap();
    }
    assert_eq!(a.game.phase, Phase::InFlight);
    let mut reference = a.clone();
    for _ in 0..32 {
        let tick = a.sim.tick - 8;
        for seat in [B, A] {
            let input = Sweep::centered(2, 220);
            a.sweep(seat, tick, input).unwrap();
            reference.rewind.clear();
            reference.sweep(seat, tick, input).unwrap();
        }
        a.step().unwrap();
        reference.step().unwrap();
        assert_eq!(a.hash(), reference.hash());
    }
    assert!(a.sim.stones.iter().find(|s| s.id == 2).unwrap().pos.y > Fx::ZERO);
}
#[test]
fn player_brush_journal_restores_and_old_rules_are_not_reinterpreted() {
    use crate::recorded::{Record, RecordedMatch};
    let mut m = RecordedMatch::new(42, Rules::mixed(), 1).unwrap();
    m.place_mixed(
        Seat {
            team: 1,
            position: 0,
        },
        true,
        PowerPlay::None,
    )
    .unwrap();
    m.release(A, Release::draw()).unwrap();
    for seat in [A, B] {
        m.apply(Record::BrushSpan {
            seat,
            tick: 0,
            input: Sweep::centered(2, 200),
            count: 12,
        })
        .unwrap();
    }
    m.advance(24, None).unwrap();
    let json = m.json().unwrap();
    assert_eq!(
        RecordedMatch::parse(json.as_bytes()).unwrap().hash(),
        m.hash()
    );
    let old = json.replace("\"rules_version\":4", "\"rules_version\":3");
    assert_ne!(old, json);
    assert!(RecordedMatch::parse(old.as_bytes()).is_err());
}

#[test]
fn match_release_preserves_player_fatigue_and_idle_time_recovers_it() {
    let mut a = Authority::new(42, Rules::mixed(), 1).unwrap();
    a.place_mixed(
        Seat {
            team: 1,
            position: 0,
        },
        true,
        PowerPlay::None,
    )
    .unwrap();
    a.sim.brush_fatigue = [4000, 5000, 6000, 7000, 0, 0, 0, 0];
    a.think(1000).unwrap();
    let recovered = a.sim.brush_fatigue;
    assert!(recovered[0] < 4000 && recovered[3] < 7000);
    a.release(A, Release::draw()).unwrap();
    assert_eq!(a.sim.brush_fatigue, recovered);
}

#[test]
fn retimed_spans_replace_only_unconsumed_player_intent() {
    use crate::recorded::{Record, RecordedMatch};
    let mut m = RecordedMatch::new(42, Rules::mixed(), 1).unwrap();
    m.place_mixed(
        Seat {
            team: 1,
            position: 0,
        },
        true,
        PowerPlay::None,
    )
    .unwrap();
    m.release(A, Release::draw()).unwrap();
    m.advance(50, None).unwrap();
    m.advance(50, None).unwrap();
    for (tick, effort) in [(0, 200), (12, 100)] {
        m.apply(Record::BrushSpan {
            seat: A,
            tick,
            input: Sweep::centered(2, effort),
            count: 12,
        })
        .unwrap();
    }
    assert_eq!(m.accepted_sweeps().len(), 12);
    assert!(
        m.accepted_sweeps()
            .iter()
            .all(|(tick, s)| *tick >= 100 && s.effort == 100)
    );
    m.advance(5, None).unwrap();
    m.apply(Record::BrushSpan {
        seat: A,
        tick: 24,
        input: Sweep::centered(2, 50),
        count: 12,
    })
    .unwrap();
    let accepted = m.accepted_sweeps();
    assert_eq!(accepted.len(), 17);
    assert!(
        accepted
            .iter()
            .all(|(tick, s)| s.effort == if *tick < 105 { 100 } else { 50 })
    );
    m.apply(Record::BrushSpan {
        seat: A,
        tick: 100,
        input: Sweep::centered(2, 255),
        count: 12,
    })
    .unwrap();
    let overlap = m.accepted_sweeps();
    assert_eq!(overlap.len(), 17);
    assert!(overlap.iter().all(|(tick, s)| s.effort
        == if *tick < 105 {
            100
        } else if *tick < 112 {
            255
        } else {
            50
        }));
    assert!(
        m.apply(Record::Sweep {
            seat: A,
            tick: 100,
            input: Sweep::centered(2, 255)
        })
        .is_err()
    );
    m.advance(30, None).unwrap();
    assert_eq!(
        RecordedMatch::parse(m.json().unwrap().as_bytes())
            .unwrap()
            .hash(),
        m.hash()
    );
}

#[test]
fn targeted_local_steps_replay_a_contact_stone_and_reject_opponent_atomically() {
    use crate::recorded::RecordedMatch;
    let mut m = RecordedMatch::new(42, Rules::mixed(), 1).unwrap();
    m.place_mixed(
        Seat {
            team: 1,
            position: 0,
        },
        true,
        PowerPlay::None,
    )
    .unwrap();
    let mut release = Release::draw();
    release.vel.y = Fx::int(3);
    release.spin = Fx::ZERO;
    m.release(A, release).unwrap();
    let mut target = None;
    for _ in 0..10_000 {
        target = m
            .sim
            .stones
            .iter()
            .find(|s| s.id != m.sim.delivered.unwrap() && s.active && s.vel != V2::ZERO)
            .cloned();
        if target.is_some() || m.game.phase != Phase::InFlight {
            break;
        }
        m.advance(1, None).unwrap();
    }
    let target = target.expect("fixture should move a positioned stone");
    let owner = Seat {
        team: target.team,
        position: 1,
    };
    let mut input = Sweep::centered(target.id, 220);
    input.lateral_mm = 75;
    input.ahead_mm = 240;
    let before = m.hash();
    let json = m.json().unwrap();
    assert!(m.advance_targeted(65, owner, Some(input)).is_err());
    assert_eq!(m.hash(), before);
    if target.pos.y < Fx::ZERO {
        assert!(
            m.advance_targeted(
                24,
                Seat {
                    team: 1 - target.team,
                    position: 1
                },
                Some(input)
            )
            .is_err()
        );
        assert_eq!(m.json().unwrap(), json);
    }
    m.advance_targeted(64, owner, Some(input)).unwrap();
    assert!(
        m.accepted_sweeps()
            .iter()
            .any(|(_, s)| { s.stone == target.id && s.lateral_mm == 75 && s.ahead_mm == 240 })
    );
    let mut restored = RecordedMatch::parse(m.json().unwrap().as_bytes()).unwrap();
    assert_eq!(restored.hash(), m.hash());
    while m.game.phase == Phase::InFlight {
        m.advance_targeted(64, owner, Some(input)).unwrap();
        restored.advance_targeted(64, owner, Some(input)).unwrap();
    }
    assert_eq!(restored.hash(), m.hash());
    assert_eq!(
        RecordedMatch::parse(m.json().unwrap().as_bytes())
            .unwrap()
            .hash(),
        m.hash()
    );
}
