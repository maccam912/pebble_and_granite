//! Two independently accepted brushes for the local four-player team mode.
use crate::{Authority, Seat, recorded::RecordedMatch};
use curl_rules::Format;
use curl_sim::Sweep;

/// The vice calls when the skip throws; otherwise the skip calls.
pub fn regular_pair(thrower: u8) -> [u8; 2] {
    let caller = if thrower == 3 { 2 } else { 3 };
    let mut pair = [0; 2];
    let mut index = 0;
    for position in 0..4 {
        if position != thrower && position != caller {
            pair[index] = position;
            index += 1;
        }
    }
    pair
}

fn participants(game: &Authority, human_position: i8) -> [u8; 2] {
    let mut pair = regular_pair(game.game.throwing_seat());
    let caller = if game.game.throwing_seat() == 3 { 2 } else { 3 };
    if game.game.delivering_team() == 0
        && (0..4).contains(&human_position)
        && human_position as u8 != caller
    {
        // Preserve manual brushing after a human delivery: the human can follow
        // their own stone, while one of the regular sweepers partners them.
        let human = human_position as u8;
        let partner = pair
            .into_iter()
            .filter(|p| *p != human)
            .min_by_key(|p| (game.brush_fatigue_at_release()[*p as usize], *p))
            .unwrap();
        pair = [human, partner];
    }
    pair
}

pub fn advance(
    game: &mut RecordedMatch,
    count: u32,
    human_position: i8,
    human: Sweep,
    ai_effort: u8,
) -> Result<(), &'static str> {
    if game.sim.version < 4
        || game.game.rules.format != Format::Teams
        || !(-1..=5).contains(&human_position)
        || count > 64
        || !human.valid()
    {
        return Err("independent team sweeping unavailable");
    }
    let inputs = player_inputs(game, human_position, human, ai_effort);
    game.advance_players(count, &inputs)
}

fn player_inputs(
    game: &Authority,
    human_position: i8,
    human: Sweep,
    ai_effort: u8,
) -> Vec<(Seat, Sweep)> {
    let team = game.game.delivering_team();
    let pair = participants(game, human_position);
    pair.into_iter()
        .enumerate()
        .map(|(index, position)| {
            let manual = team == 0
                && (human_position == position as i8
                    || human_position == 4 && human.effort > 0 && index == 0);
            let input = if manual {
                human
            } else {
                Sweep {
                    stone: game.sim.delivered.unwrap_or(human.stone),
                    brush: 0,
                    effort: ai_effort,
                    lateral_mm: if index == 0 { -60 } else { 60 },
                    ahead_mm: if index == 0 { 180 } else { 420 },
                }
            };
            (Seat { team, position }, input)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use curl_rules::{Phase, Rules};
    use curl_sim::Release;

    #[test]
    fn roles_rotate_and_human_delivery_keeps_manual_brushing() {
        assert_eq!(regular_pair(0), [1, 2]);
        assert_eq!(regular_pair(1), [0, 2]);
        assert_eq!(regular_pair(2), [0, 1]);
        assert_eq!(regular_pair(3), [0, 1]);
        let mut game = Authority::new(42, Rules::club(), 1).unwrap();
        assert_eq!(participants(&game, 0), [0, 1]);
        game.sim.brush_fatigue[1] = 10000;
        assert_eq!(participants(&game, 0), [0, 2]);
        assert_eq!(participants(&game, 3), [1, 2]);
        assert_eq!(participants(&game, 4), [1, 2]);
        game.game.delivered = 1; // Cyan has two AI sweepers regardless of Gold role.
        assert_eq!(participants(&game, 1), [1, 2]);
    }

    #[test]
    fn one_human_and_one_ai_have_separate_fatigue_and_replay() {
        let mut game = RecordedMatch::new(42, Rules::club(), 1).unwrap();
        game.release(
            Seat {
                team: 0,
                position: 0,
            },
            Release::draw(),
        )
        .unwrap();
        let mut human = Sweep::centered(0, 255);
        human.brush = 7;
        advance(&mut game, 64, 0, human, 255).unwrap();
        assert_eq!(game.sim.brush_fatigue[..4], [192, 192, 0, 0]);
        let fatigue = game.sim.brush_fatigue;
        human.effort = 0;
        advance(&mut game, 64, 0, human, 255).unwrap();
        // The partner is fixed for the whole delivery, including after reload.
        assert!(game.sim.brush_fatigue[0] < fatigue[0]);
        assert_eq!(game.sim.brush_fatigue[1], 384);
        assert_eq!(game.sim.brush_fatigue[2], 0);
        assert_eq!(
            game.sim.brush_fatigue[7], 0,
            "Client chose a fresh identity"
        );
        let restored = RecordedMatch::parse(game.json().unwrap().as_bytes()).unwrap();
        assert_eq!(restored.hash(), game.hash());
        assert_eq!(restored.sim.brush_fatigue, game.sim.brush_fatigue);
        while game.game.phase == Phase::InFlight {
            game.advance(64, None).unwrap();
        }
        game.release(
            Seat {
                team: 1,
                position: 0,
            },
            Release::draw(),
        )
        .unwrap();
        advance(&mut game, 64, 0, Sweep::centered(1, 0), 255).unwrap();
        assert_eq!(game.sim.brush_fatigue[5..7], [192, 192]);
        assert_eq!(
            RecordedMatch::parse(game.json().unwrap().as_bytes())
                .unwrap()
                .hash(),
            game.hash()
        );
    }

    #[test]
    fn human_can_brush_a_contact_stone_while_partner_tracks_delivery() {
        use curl_fx::{Fx, V2};
        let mut game = Authority::new(42, Rules::club(), 1).unwrap();
        game.release(
            Seat {
                team: 0,
                position: 0,
            },
            Release::draw(),
        )
        .unwrap();
        // A second own stone is moving after contact. Each player keeps their
        // intended target, instead of applying the human gesture to the shooter.
        let mut contact = game.sim.stones[0].clone();
        contact.id = 2;
        contact.pos = V2::new(Fx::int(1), Fx::int(-5));
        contact.vel = V2::new(Fx::ZERO, Fx::int(1));
        game.sim.stones.push(contact);
        for (seat, input) in player_inputs(&game, 1, Sweep::centered(2, 255), 255) {
            game.sweep(seat, game.sim.tick, input).unwrap();
        }
        game.step().unwrap();
        let accepted = game.active_brushes();
        assert_eq!(accepted.len(), 2);
        assert_eq!((accepted[0].brush, accepted[0].stone), (1, 2));
        assert_eq!((accepted[1].brush, accepted[1].stone), (2, 0));
        assert_eq!(game.sim.brush_fatigue[1..3], [3, 3]);
    }

    #[test]
    fn caller_off_and_full_manual_have_no_hidden_partner_input() {
        let mut game = RecordedMatch::new(42, Rules::club(), 1).unwrap();
        game.release(
            Seat {
                team: 0,
                position: 0,
            },
            Release::draw(),
        )
        .unwrap();
        let mut reference = game.clone();
        reference.advance(64, None).unwrap();
        for role in [3, 4, 5] {
            let mut trial = game.clone();
            advance(&mut trial, 64, role, Sweep::centered(0, 0), 0).unwrap();
            assert_eq!(trial.hash(), reference.hash());
        }
        let mut full = game.clone();
        advance(&mut full, 64, 4, Sweep::centered(0, 255), 0).unwrap();
        assert_eq!(
            full.sim.brush_fatigue[1..3],
            [192, 0],
            "Full-team manual brush was ignored"
        );
        let before = game.hash();
        assert!(advance(&mut game, 65, 0, Sweep::centered(0, 255), 255).is_err());
        assert_eq!(game.hash(), before);
    }

    #[test]
    fn a_second_brush_changes_the_physical_result() {
        let mut both = RecordedMatch::new(42, Rules::club(), 1).unwrap();
        let mut release = Release::draw();
        release.vel.y = curl_fx::Fx::ratio(19, 10);
        both.release(
            Seat {
                team: 0,
                position: 0,
            },
            release,
        )
        .unwrap();
        let mut one = both.clone();
        while both.game.phase == Phase::InFlight {
            advance(&mut both, 64, 3, Sweep::centered(0, 0), 255).unwrap();
        }
        while one.game.phase == Phase::InFlight {
            advance(&mut one, 64, 1, Sweep::centered(0, 0), 255).unwrap();
        }
        assert!(both.sim.stones[0].pos.y > one.sim.stones[0].pos.y + curl_fx::Fx::ratio(1, 10));
    }

    #[test]
    fn behind_tee_keeps_one_brush_per_team_in_stable_player_order() {
        use curl_fx::{Fx, V2};
        let mut game = Authority::new(42, Rules::club(), 1).unwrap();
        game.release(
            Seat {
                team: 0,
                position: 0,
            },
            Release::draw(),
        )
        .unwrap();
        game.sim.stones[0].pos.y = Fx::ratio(-1, 1000);
        game.sim.stones[0].vel = V2::new(Fx::ZERO, Fx::int(2));
        for position in [2, 1] {
            game.sweep_span(
                Seat { team: 0, position },
                game.sim.tick,
                Sweep::centered(0, 255),
                8,
            )
            .unwrap();
        }
        game.step().unwrap(); // crosses tee; both were legal before it
        let fatigue = game.sim.brush_fatigue;
        game.sweep_span(
            Seat {
                team: 1,
                position: 3,
            },
            game.sim.tick,
            Sweep::centered(0, 255),
            4,
        )
        .unwrap();
        game.step().unwrap();
        assert!(game.sim.brush_fatigue[1] > fatigue[1]);
        assert!(game.sim.brush_fatigue[2] < fatigue[2]);
        assert_eq!(game.sim.brush_fatigue[7], 3);
        assert_eq!(game.active_brushes().len(), 2);
    }
}
