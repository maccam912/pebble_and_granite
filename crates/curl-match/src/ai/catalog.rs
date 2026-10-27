//! A bounded catalogue of contact intentions, checked against actual outcomes.
use super::{Authority, Fx, HOUSE, Plan, RADIUS, ShotKind, V2, solve};
use curl_sim::Stone;

pub(super) struct Candidate {
    pub plan: Plan,
    first: Option<u8>,
    second: Option<u8>,
}

fn stone(game: &Authority, id: u8) -> Option<&Stone> {
    game.sim.stones.iter().find(|s| s.id == id && s.active)
}

impl Candidate {
    pub fn accepts(
        &self,
        before: &Authority,
        after: &Authority,
        contacts: &[curl_sim::Event],
    ) -> bool {
        if self.plan.kind == ShotKind::CornerGuard {
            return stone(after, before.game.next_stone_id()).is_some_and(|s| {
                s.pos.y < -HOUSE - RADIUS
                    && s.pos.x.abs() > Fx::ratio(5, 10)
                    && (s.pos - self.plan.target).length() < Fx::ratio(5, 10)
            });
        }
        let Some(id) = self.first else {
            return true;
        };
        let Some(original) = stone(before, id) else {
            return false;
        };
        let target = stone(after, id);
        let delivered = stone(after, before.game.next_stone_id());
        match self.plan.kind {
            ShotKind::Freeze => target.zip(delivered).is_some_and(|(target, delivered)| {
                (target.pos - original.pos).length() < Fx::ratio(8, 100)
                    && (delivered.pos - target.pos).length() <= RADIUS * Fx::int(2) + Fx::ratio(15, 1000)
            }),
            ShotKind::Tap => target.is_some_and(|target| {
                let moved = (target.pos - original.pos).length();
                moved >= Fx::ratio(15, 100) && moved <= Fx::ratio(15, 10)
                    && target.pos.y > original.pos.y
            }),
            ShotKind::HitRoll => target.is_none() && delivered.is_some_and(|delivered| {
                delivered.pos.length() <= HOUSE + RADIUS
                    && (delivered.pos.x - original.pos.x).abs() >= Fx::ratio(30, 100)
            }),
            ShotKind::Peel => target.is_none() && delivered.is_none(),
            ShotKind::Double => target.is_none() && self.second.is_some_and(|id| stone(after, id).is_none()),
            ShotKind::Runback => self.second.is_some_and(|id| {
                let Some(original_second) = stone(before, id) else { return false; };
                let struck = contacts.iter().any(|e| matches!(e, curl_sim::Event::Contact(a, b, _) if (*a == original.id && *b == id) || (*b == original.id && *a == id)));
                struck && stone(after, id).is_none_or(|s| (s.pos - original_second.pos).length() >= Fx::ratio(30, 100))
            }),
            _ => true,
        }
    }
}

fn add(
    plans: &mut Vec<Candidate>,
    game: &Authority,
    kind: ShotKind,
    target: V2,
    first: Option<u8>,
    second: Option<u8>,
) {
    if target.x.abs() > Fx::ratio(22, 10) || target.y < Fx::int(-5) || target.y > Fx::int(2) {
        return;
    }
    for turn in [-1, 1] {
        plans.push(Candidate {
            plan: solve(&game.sim, target, kind, turn),
            first,
            second,
        });
    }
}

pub(super) fn generate(game: &Authority) -> Vec<Candidate> {
    let mut plans = Vec::new();
    for x in [-800, 0, 800] {
        add(
            &mut plans,
            game,
            ShotKind::Draw,
            V2::new(
                Fx::ratio(x, 1000),
                if x == 0 { Fx::ZERO } else { Fx::ratio(-4, 10) },
            ),
            None,
            None,
        );
    }
    for x in [0, -1150, 1150] {
        add(
            &mut plans,
            game,
            if x == 0 {
                ShotKind::Guard
            } else {
                ShotKind::CornerGuard
            },
            V2::new(Fx::ratio(x, 1000), Fx::int(-3)),
            None,
            None,
        );
    }
    let team = game.game.delivering_team();
    let mut house: Vec<_> = game
        .sim
        .stones
        .iter()
        .filter(|s| s.active && s.pos.length() <= HOUSE + RADIUS)
        .collect();
    house.sort_by_key(|s| (s.pos.length(), s.id));
    let opponents: Vec<_> = house
        .iter()
        .copied()
        .filter(|s| s.team != team)
        .take(2)
        .collect();
    for target in &opponents {
        add(
            &mut plans,
            game,
            ShotKind::Hit,
            target.pos,
            Some(target.id),
            None,
        );
    }
    if let Some(target) = house.first() {
        add(
            &mut plans,
            game,
            ShotKind::Freeze,
            target.pos - V2::new(Fx::ZERO, RADIUS * Fx::int(2) - Fx::ratio(5, 1000)),
            Some(target.id),
            None,
        );
        add(
            &mut plans,
            game,
            ShotKind::Tap,
            target.pos + V2::new(Fx::ZERO, Fx::ratio(6, 10)),
            Some(target.id),
            None,
        );
    }
    // Peel the nearest opposing guard, or the leading house threat if no guard.
    let mut guards: Vec<_> = game
        .sim
        .stones
        .iter()
        .filter(|s| s.active && s.pos.y < -HOUSE && s.pos.y >= Fx::int(-5))
        .collect();
    guards.sort_by_key(|s| (s.pos.y, s.id));
    if let Some(target) = guards
        .iter()
        .copied()
        .find(|s| s.team != team)
        .or_else(|| opponents.first().copied())
    {
        add(
            &mut plans,
            game,
            ShotKind::Peel,
            target.pos + V2::new(RADIUS * Fx::ratio(8, 10), Fx::ZERO),
            Some(target.id),
            None,
        );
    }
    if let Some(target) = opponents.first() {
        for side in [-1, 1] {
            add(
                &mut plans,
                game,
                ShotKind::HitRoll,
                target.pos + V2::new(RADIUS * Fx::ratio(side * 4, 10), Fx::ZERO),
                Some(target.id),
                None,
            );
        }
    }
    if opponents.len() == 2 {
        let (front, back) = if opponents[0].pos.y < opponents[1].pos.y {
            (opponents[0], opponents[1])
        } else {
            (opponents[1], opponents[0])
        };
        for side in [-1, 1] {
            let mut glance = back.clone();
            glance.pos.x += RADIUS * Fx::ratio(side * 12, 10);
            contact_pair(&mut plans, game, ShotKind::Double, front, &glance);
        }
    }
    if let Some(target) = opponents.first()
        && let Some(guard) = guards
            .iter()
            .copied()
            .filter(|s| s.team == team)
            .min_by_key(|s| ((s.pos - target.pos).length(), s.id))
    {
        contact_pair(&mut plans, game, ShotKind::Runback, guard, target);
    }
    debug_assert!(plans.len() <= 32);
    plans
}

fn contact_pair(
    plans: &mut Vec<Candidate>,
    game: &Authority,
    kind: ShotKind,
    front: &Stone,
    back: &Stone,
) {
    let direction = (back.pos - front.pos).unit();
    if direction.y < Fx::ratio(4, 10) {
        return;
    }
    // The impact normal points from the first stone toward the second.
    add(
        plans,
        game,
        kind,
        front.pos - direction * RADIUS * Fx::int(2),
        Some(front.id),
        Some(back.id),
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::outcome_with_contacts;
    use curl_rules::Rules;

    fn board(stones: &[(u8, i64, i64)]) -> Authority {
        let mut game = Authority::new(42, Rules::club(), 1).unwrap();
        game.game.delivered = 6; // Guard protection has expired; Gold throws.
        for (id, &(team, x, y)) in stones.iter().enumerate() {
            game.sim
                .add_resting(Stone::resting(
                    id as u8,
                    team,
                    V2::new(Fx::ratio(x, 1000), Fx::ratio(y, 1000)),
                ))
                .unwrap();
        }
        game
    }

    #[test]
    fn contact_catalogue_has_physically_distinct_successes() {
        let fixtures = [
            (ShotKind::Freeze, vec![(1, 0, 0)]),
            (ShotKind::Tap, vec![(1, 0, 0)]),
            (ShotKind::HitRoll, vec![(1, 0, 0)]),
            (ShotKind::Peel, vec![(1, 0, -3000)]),
            (ShotKind::Double, vec![(1, 0, -500), (1, 0, 500)]),
            (ShotKind::Runback, vec![(0, 0, -3000), (1, 0, 0)]),
        ];
        let mut missing = Vec::new();
        for (kind, stones) in fixtures {
            let game = board(&stones);
            let before = game.hash();
            let mut successes = 0;
            for candidate in generate(&game).into_iter().filter(|c| c.plan.kind == kind) {
                let (next, contacts) =
                    outcome_with_contacts(&game, candidate.plan.release()).unwrap();
                let accepted = candidate.accepts(&game, &next, &contacts);
                assert!(
                    !candidate.accepts(&game, &game, &[]),
                    "Unplayed {kind:?} accepted"
                );
                if kind == ShotKind::Runback {
                    assert!(
                        !candidate.accepts(&game, &next, &[]),
                        "Runback requires the actual contact chain"
                    );
                }
                successes += usize::from(accepted);
            }
            if successes == 0 {
                missing.push(kind);
            }
            assert_eq!(game.hash(), before);
        }
        assert!(
            missing.is_empty(),
            "No successful candidate for {missing:?}"
        );
    }
    #[test]
    fn corner_guards_and_protected_peels_are_checked_on_the_legal_board() {
        let mut game = board(&[(1, 0, -3000), (1, 800, 0), (0, -800, -3000)]);
        let candidates = generate(&game);
        assert!(candidates.len() <= 32);
        let corners: Vec<_> = candidates
            .iter()
            .filter(|c| c.plan.kind == ShotKind::CornerGuard)
            .collect();
        assert_eq!(corners.len(), 4);
        for candidate in corners {
            let (next, _) = outcome_with_contacts(&game, candidate.plan.release()).unwrap();
            let shooter = stone(&next, game.game.next_stone_id()).unwrap();
            assert!((shooter.pos - candidate.plan.target).length() < Fx::ratio(8, 100));
        }
        game.game.delivered = 4;
        for candidate in generate(&game)
            .iter()
            .filter(|c| c.plan.kind == ShotKind::Peel)
        {
            let (next, contacts) = outcome_with_contacts(&game, candidate.plan.release()).unwrap();
            assert!(
                !candidate.accepts(&game, &next, &contacts),
                "Protected peel survived remedy"
            );
        }
    }
}
