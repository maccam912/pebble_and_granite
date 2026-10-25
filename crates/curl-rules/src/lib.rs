//! Pure rules state machine. Simulation supplies settled positions; remedies
//! restore stones, not the physical ice history of the throw.
use curl_fx::{Fx, V2};
use curl_sim::{FAR_HOG, HOUSE, RADIUS, Stone};
use serde::{Deserialize, Serialize};
pub const RULES_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Format {
    Teams,
    MixedDoubles,
    Wheelchair,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Rules {
    pub guard_mark: u8,
    pub guard_behind: bool,
    pub format: Format,
    pub ends: u8,
    pub guard_count: u8,
    pub no_tick: bool,
    pub thinking_ms: u32,
}
impl Rules {
    pub fn club() -> Self {
        Self {
            guard_mark: 1,
            guard_behind: false,
            format: Format::Teams,
            ends: 6,
            guard_count: 5,
            no_tick: true,
            thinking_ms: 30 * 60 * 1000,
        }
    }
    pub fn mixed() -> Self {
        Self {
            guard_mark: 1,
            guard_behind: false,
            format: Format::MixedDoubles,
            ends: 8,
            guard_count: 3,
            no_tick: false,
            thinking_ms: 22 * 60 * 1000,
        }
    }
    pub fn stones_per_team(&self) -> u8 {
        if self.format == Format::MixedDoubles {
            5
        } else {
            8
        }
    }
    fn valid(&self) -> bool {
        self.guard_mark < 4
            && (1..=10).contains(&self.ends)
            && self.guard_count <= 5
            && self.thinking_ms > 0
            && (self.format != Format::MixedDoubles || (!self.no_tick && self.guard_count == 3))
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Phase {
    Placement,
    Calling,
    InFlight,
    Choice,
    EndComplete,
    GameComplete,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Violation {
    ProtectedRemoval,
    NoTick,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Remedy {
    Accept,
    Restore,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Resolution {
    pub violation: Option<Violation>,
    pub replace_stones: Option<Vec<Stone>>,
    pub choice_team: Option<u8>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Match {
    pub rules: Rules,
    pub phase: Phase,
    pub end: u8,
    pub delivered: u8,
    pub hammer: u8,
    pub placement_team: u8,
    pub power_play_used: [bool; 2],
    pub first_thrower: [u8; 2],
    pub score: [u16; 2],
    pub thinking_ms: [u32; 2],
    pub winner: Option<u8>,
    before: Vec<Stone>,
    pending_after: Vec<Stone>,
    delivered_id: Option<u8>,
}
impl Match {
    pub fn new(rules: Rules, hammer: u8) -> Result<Self, &'static str> {
        if !rules.valid() || hammer > 1 {
            return Err("invalid match configuration");
        }
        let time = rules.thinking_ms;
        let phase = if rules.format == Format::MixedDoubles {
            Phase::Placement
        } else {
            Phase::Calling
        };
        Ok(Self {
            rules,
            phase,
            end: 1,
            delivered: 0,
            hammer,
            placement_team: hammer,
            power_play_used: [false; 2],
            first_thrower: [0; 2],
            score: [0; 2],
            thinking_ms: [time; 2],
            winner: None,
            before: vec![],
            pending_after: vec![],
            delivered_id: None,
        })
    }
    /// End setup belongs to the placement-choice team, independently of hammer.
    pub fn place_mixed(
        &mut self,
        team: u8,
        own_house: bool,
        side: PowerPlay,
    ) -> Result<Vec<Stone>, &'static str> {
        if !self.rules.valid()
            || team > 1
            || self.rules.format != Format::MixedDoubles
            || self.phase != Phase::Placement
            || team != self.placement_team
        {
            return Err("placement unavailable to this team");
        }
        if side != PowerPlay::None
            && (self.end > self.rules.ends || self.power_play_used[team as usize])
        {
            return Err("power play unavailable");
        }
        let hammer = if own_house { team } else { 1 - team };
        let stones = positioned_stones(&self.rules, hammer, side);
        self.hammer = hammer;
        if side != PowerPlay::None {
            self.power_play_used[team as usize] = true;
        }
        self.phase = Phase::Calling;
        Ok(stones)
    }
    pub fn set_first_thrower(&mut self, team: u8, position: u8) -> Result<(), &'static str> {
        if self.rules.format != Format::MixedDoubles
            || team > 1
            || position > 1
            || self.delivered != 0
            || !matches!(self.phase, Phase::Placement | Phase::Calling)
        {
            return Err("throwing order may change only before the end");
        }
        self.first_thrower[team as usize] = position;
        Ok(())
    }
    pub fn delivering_team(&self) -> u8 {
        (1 - self.hammer) ^ (self.delivered % 2)
    }
    /// Seat within the delivering team: mixed doubles 0 throws 1/5, 1 throws 2–4.
    pub fn throwing_seat(&self) -> u8 {
        let n = self.delivered / 2;
        if self.rules.format == Format::MixedDoubles {
            self.first_thrower[self.delivering_team() as usize]
                ^ if n == 0 || n == 4 { 0 } else { 1 }
        } else {
            n / 2
        }
    }
    pub fn next_stone_id(&self) -> u8 {
        self.delivered
            + if self.rules.format == Format::MixedDoubles {
                2
            } else {
                0
            }
    }
    pub fn begin(&mut self, team: u8, stone: u8, positions: &[Stone]) -> Result<(), &'static str> {
        if self.phase != Phase::Calling
            || team != self.delivering_team()
            || stone != self.next_stone_id()
        {
            return Err("not this player's delivery");
        }
        if positions.iter().any(|s| s.active && s.vel != V2::ZERO) {
            return Err("stones still moving");
        }
        self.before = positions.to_vec();
        self.delivered_id = Some(stone);
        self.phase = Phase::InFlight;
        Ok(())
    }
    pub fn settle(&mut self, positions: &[Stone]) -> Result<Resolution, &'static str> {
        if self.phase != Phase::InFlight || positions.iter().any(|s| s.active && s.vel != V2::ZERO)
        {
            return Err("not a settled delivery");
        }
        let team = self.delivering_team();
        let protected = self.delivered < self.rules.guard_count;
        let removal = protected
            && self.before.iter().filter(|s| s.active).any(|old| {
                let applies = if self.rules.format == Format::MixedDoubles {
                    true
                } else {
                    old.team != team && in_guard_zone(old)
                };
                applies && !positions.iter().any(|new| new.id == old.id && new.active)
            });
        if removal {
            let restored = self.restored();
            self.complete_throw(&restored);
            return Ok(Resolution {
                violation: Some(Violation::ProtectedRemoval),
                replace_stones: Some(restored),
                choice_team: None,
            });
        }
        let tick = protected
            && self.rules.no_tick
            && self
                .before
                .iter()
                .filter(|s| {
                    s.active && s.team != team && in_guard_zone(s) && s.pos.x.abs() <= RADIUS
                })
                .any(|old| {
                    positions
                        .iter()
                        .find(|s| s.id == old.id && s.active)
                        .is_some_and(|new| new.pos.x.abs() > RADIUS || !in_guard_zone(new))
                });
        if tick {
            self.pending_after = positions.to_vec();
            self.phase = Phase::Choice;
            return Ok(Resolution {
                violation: Some(Violation::NoTick),
                replace_stones: None,
                choice_team: Some(1 - team),
            });
        }
        self.complete_throw(positions);
        Ok(Resolution {
            violation: None,
            replace_stones: None,
            choice_team: None,
        })
    }
    pub fn choose(&mut self, team: u8, remedy: Remedy) -> Result<Resolution, &'static str> {
        if self.phase != Phase::Choice || team != 1 - self.delivering_team() {
            return Err("choice belongs to opponent");
        }
        let positions = if remedy == Remedy::Restore {
            self.restored()
        } else {
            self.pending_after.clone()
        };
        self.complete_throw(&positions);
        self.pending_after.clear();
        Ok(Resolution {
            violation: Some(Violation::NoTick),
            replace_stones: if remedy == Remedy::Restore {
                Some(positions)
            } else {
                None
            },
            choice_team: None,
        })
    }
    fn restored(&self) -> Vec<Stone> {
        self.before.clone()
    }
    fn complete_throw(&mut self, positions: &[Stone]) {
        self.delivered += 1;
        self.delivered_id = None;
        if self.delivered < self.rules.stones_per_team() * 2 {
            self.phase = Phase::Calling;
            return;
        }
        let (team, points) = score_end(positions);
        if let Some(team) = team {
            self.score[team as usize] += points as u16;
            self.hammer = 1 - team;
            self.placement_team = 1 - team;
        } else if self.rules.format == Format::MixedDoubles && !positions.iter().any(in_house) {
            self.placement_team = 1 - self.hammer;
        }
        self.phase = Phase::EndComplete;
        if self.end >= self.rules.ends && self.score[0] != self.score[1] {
            self.phase = Phase::GameComplete;
            self.winner = Some(if self.score[0] > self.score[1] { 0 } else { 1 });
        }
    }
    pub fn next_end(&mut self) -> Result<(), &'static str> {
        if self.phase != Phase::EndComplete {
            return Err("end not complete");
        }
        self.end = self.end.checked_add(1).ok_or("end limit reached")?;
        self.delivered = 0;
        self.before.clear();
        self.phase = if self.rules.format == Format::MixedDoubles {
            Phase::Placement
        } else {
            Phase::Calling
        };
        if self.end > self.rules.ends {
            self.thinking_ms = [270000; 2];
        }
        Ok(())
    }
    pub fn concede(&mut self, team: u8) -> Result<(), &'static str> {
        if self.phase != Phase::Calling || team != self.delivering_team() {
            return Err("concede only on own delivery turn");
        }
        self.phase = Phase::GameComplete;
        self.winner = Some(1 - team);
        Ok(())
    }
    /// Called only by authority elapsed-time accounting, never from client time.
    pub fn think(&mut self, elapsed_ms: u32) {
        if self.phase != Phase::Calling {
            return;
        }
        let team = self.delivering_team() as usize;
        self.thinking_ms[team] = self.thinking_ms[team].saturating_sub(elapsed_ms);
        if self.thinking_ms[team] == 0 {
            self.phase = Phase::GameComplete;
            self.winner = Some((1 - team) as u8);
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum PowerPlay {
    None,
    Left,
    Right,
}

/// World Curling 2026 R17(f), diagrams pp.29–30. Coordinates in metres.
/// Kept internal: configuration validation precedes every call.
fn positioned_stones(rules: &Rules, hammer: u8, side: PowerPlay) -> Vec<Stone> {
    let mark = rules.guard_mark as usize;
    let y = -HOUSE - Fx::ratio([1372, 1981, 2591, 3200][mark], 1000)
        + if rules.guard_behind { RADIUS } else { -RADIUS };
    let sign = match side {
        PowerPlay::None => 0,
        PowerPlay::Left => -1,
        PowerPlay::Right => 1,
    };
    let guard_x = Fx::ratio([1120, 1100, 1080, 1070][mark] * sign, 1000);
    let house = if side == PowerPlay::None {
        V2::new(Fx::ZERO, Fx::ratio(610, 1000) - RADIUS)
    } else {
        V2::new(Fx::ratio(1219 * sign, 1000), -RADIUS)
    };
    vec![
        Stone::resting(0, 1 - hammer, V2::new(guard_x, y)),
        Stone::resting(1, hammer, house),
    ]
}

pub fn in_house(s: &Stone) -> bool {
    s.active && s.pos.dot(s.pos) <= (HOUSE + RADIUS) * (HOUSE + RADIUS)
}
pub fn in_guard_zone(s: &Stone) -> bool {
    s.active && s.pos.y < Fx::ZERO && s.pos.y - RADIUS > FAR_HOG && !in_house(s)
}
pub fn score_end(stones: &[Stone]) -> (Option<u8>, u8) {
    let mut house: Vec<_> = stones.iter().filter(|s| in_house(s)).collect();
    house.sort_by_key(|s| (s.pos.dot(s.pos), s.id));
    let Some(first) = house.first() else {
        return (None, 0);
    };
    let closest = first.pos.dot(first.pos);
    let team = first.team;
    if house
        .iter()
        .any(|s| s.team != team && s.pos.dot(s.pos) == closest)
    {
        return (None, 0);
    }
    let opposing = house
        .iter()
        .filter(|s| s.team != team)
        .map(|s| s.pos.dot(s.pos))
        .min();
    let points = house
        .iter()
        .filter(|s| s.team == team && opposing.is_none_or(|d| s.pos.dot(s.pos) < d))
        .count();
    (Some(team), points as u8)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn stone(id: u8, team: u8, x: i64, y: i64) -> Stone {
        Stone::resting(id, team, V2::new(Fx::ratio(x, 1000), Fx::ratio(y, 1000)))
    }
    #[test]
    fn scoring_counts_only_closer_and_biting() {
        assert_eq!(
            score_end(&[
                stone(0, 0, 100, 0),
                stone(1, 0, 300, 0),
                stone(2, 1, 400, 0)
            ]),
            (Some(0), 2)
        );
        assert_eq!(score_end(&[stone(0, 0, 1970, 0)]), (Some(0), 1));
        assert_eq!(score_end(&[stone(0, 0, 1972, 0)]), (None, 0));
    }
    #[test]
    fn exact_ties_blank_or_stop_counting() {
        assert_eq!(
            score_end(&[stone(0, 0, 100, 0), stone(1, 1, -100, 0)]),
            (None, 0)
        );
        assert_eq!(
            score_end(&[
                stone(0, 0, 50, 0),
                stone(1, 0, 100, 0),
                stone(2, 1, -100, 0)
            ]),
            (Some(0), 1)
        );
    }
    #[test]
    fn fgz_removal_restores_opponent() {
        let mut m = Match::new(Rules::club(), 1).unwrap();
        let guard = stone(8, 1, 0, -3000);
        m.begin(0, 0, &[guard.clone()]).unwrap();
        let r = m.settle(&[]).unwrap();
        assert_eq!(r.violation, Some(Violation::ProtectedRemoval));
        assert_eq!(r.replace_stones, Some(vec![guard]));
        assert_eq!(m.delivered, 1);
    }
    #[test]
    fn tick_requires_opponents_choice() {
        let mut m = Match::new(Rules::club(), 1).unwrap();
        m.begin(0, 0, &[stone(8, 1, 0, -3000)]).unwrap();
        let r = m.settle(&[stone(8, 1, 400, -3000)]).unwrap();
        assert_eq!(r.choice_team, Some(1));
        assert_eq!(m.delivered, 0);
        assert!(m.choose(0, Remedy::Accept).is_err());
        m.choose(1, Remedy::Restore).unwrap();
        assert_eq!(m.delivered, 1);
    }
    #[test]
    fn sixth_stone_can_remove_guard() {
        let mut m = Match::new(Rules::club(), 1).unwrap();
        m.delivered = 5;
        m.begin(1, 5, &[stone(8, 0, 0, -3000)]).unwrap();
        assert_eq!(m.settle(&[]).unwrap().violation, None);
    }
    #[test]
    fn mixed_protects_own_house_stone_for_three_deliveries() {
        let mut m = Match::new(Rules::mixed(), 1).unwrap();
        m.place_mixed(1, true, PowerPlay::None).unwrap();
        m.begin(0, 2, &[stone(0, 0, 0, 400)]).unwrap();
        assert_eq!(
            m.settle(&[]).unwrap().violation,
            Some(Violation::ProtectedRemoval)
        );
        m.delivered = 3;
        m.begin(1, 5, &[stone(0, 1, 0, 400)]).unwrap();
        assert_eq!(m.settle(&[]).unwrap().violation, None);
    }
    #[test]
    fn mixed_roles_first_and_last_same_player() {
        let mut m = Match::new(Rules::mixed(), 1).unwrap();
        m.place_mixed(1, true, PowerPlay::None).unwrap();
        for (d, seat) in [(0, 0), (1, 0), (2, 1), (5, 1), (6, 1), (8, 0), (9, 0)] {
            m.delivered = d;
            assert_eq!(m.throwing_seat(), seat);
        }
    }
    #[test]
    fn clocks_pause_in_flight_and_expire_authoritatively() {
        let mut m = Match::new(Rules::mixed(), 1).unwrap();
        m.place_mixed(1, true, PowerPlay::None).unwrap();
        m.begin(0, 2, &[]).unwrap();
        m.think(u32::MAX);
        assert_eq!(m.phase, Phase::InFlight);
        m.settle(&[]).unwrap();
        m.think(u32::MAX);
        assert_eq!(m.winner, Some(0));
    }
    #[test]
    fn tied_final_end_requires_extra_end() {
        let mut rules = Rules::club();
        rules.ends = 1;
        let mut m = Match::new(rules, 1).unwrap();
        m.delivered = 15;
        m.begin(1, 15, &[]).unwrap();
        m.settle(&[]).unwrap();
        assert_eq!(m.phase, Phase::EndComplete);
        m.next_end().unwrap();
        assert_eq!(m.end, 2);
        assert_eq!(m.thinking_ms, [270000; 2]);
    }
    #[test]
    fn concede_requires_own_turn() {
        let mut m = Match::new(Rules::club(), 1).unwrap();
        assert!(m.concede(1).is_err());
        m.concede(0).unwrap();
        assert_eq!(m.winner, Some(1));
    }
    #[test]
    fn placement_choice_is_not_automatically_hammer() {
        let mut m = Match::new(Rules::mixed(), 1).unwrap();
        assert!(m.begin(0, 2, &[]).is_err());
        let before = m.clone();
        assert!(m.place_mixed(0, true, PowerPlay::None).is_err());
        assert_eq!(m, before);
        let stones = m.place_mixed(1, false, PowerPlay::None).unwrap();
        assert_eq!(m.hammer, 0);
        assert_eq!(m.delivering_team(), 1);
        assert_eq!(stones[0].team, 1);
        assert_eq!(stones[1].team, 0);
        assert_eq!(stones[1].pos.y + RADIUS, Fx::ratio(610, 1000));
        assert!(in_guard_zone(&stones[0]));
        assert!(in_house(&stones[1]));
        assert!(m.place_mixed(1, true, PowerPlay::None).is_err());
    }
    #[test]
    fn guard_marks_and_power_play_mirror() {
        for mark in 0..4 {
            for behind in [false, true] {
                let mut rules = Rules::mixed();
                rules.guard_mark = mark;
                rules.guard_behind = behind;
                let mut left = Match::new(rules.clone(), 0).unwrap();
                let mut right = Match::new(rules, 0).unwrap();
                let l = left.place_mixed(0, true, PowerPlay::Left).unwrap();
                let r = right.place_mixed(0, true, PowerPlay::Right).unwrap();
                for i in 0..2 {
                    assert_eq!(l[i].pos.x, -r[i].pos.x);
                    assert_eq!(l[i].pos.y, r[i].pos.y);
                }
                assert_eq!(
                    r[0].pos.x,
                    Fx::ratio([1120, 1100, 1080, 1070][mark as usize], 1000)
                );
                assert_eq!(r[1].pos.y + RADIUS, Fx::ZERO);
                assert!(in_guard_zone(&r[0]));
            }
        }
    }
    #[test]
    fn power_play_once_per_team_and_never_extra_end() {
        let mut m = Match::new(Rules::mixed(), 1).unwrap();
        m.place_mixed(1, true, PowerPlay::Left).unwrap();
        m.phase = Phase::EndComplete;
        m.next_end().unwrap();
        let before = m.clone();
        assert!(m.place_mixed(1, true, PowerPlay::Right).is_err());
        assert_eq!(m, before);
        m.placement_team = 0;
        m.place_mixed(0, true, PowerPlay::Right).unwrap();
        assert_eq!(m.power_play_used, [true, true]);
        let mut extra = Match::new(Rules::mixed(), 1).unwrap();
        extra.end = 9;
        assert!(extra.place_mixed(1, true, PowerPlay::Left).is_err());
        assert!(!extra.power_play_used[1]);
        extra.place_mixed(1, true, PowerPlay::None).unwrap();
    }
    #[test]
    fn mixed_empty_blank_and_equal_measure_have_distinct_choice() {
        let mut m = Match::new(Rules::mixed(), 1).unwrap();
        m.place_mixed(1, true, PowerPlay::None).unwrap();
        m.delivered = 9;
        let mut tied = m.clone();
        m.begin(1, 11, &[]).unwrap();
        m.settle(&[]).unwrap();
        assert_eq!(m.placement_team, 0);
        tied.begin(1, 11, &[]).unwrap();
        tied.settle(&[stone(0, 0, 100, 0), stone(1, 1, -100, 0)])
            .unwrap();
        assert_eq!(tied.placement_team, 1);
        assert_eq!(tied.score, [0, 0]);
        m.next_end().unwrap();
        assert_eq!(m.phase, Phase::Placement);
    }
    #[test]
    fn first_thrower_can_change_between_ends_only() {
        let mut m = Match::new(Rules::mixed(), 1).unwrap();
        m.set_first_thrower(0, 1).unwrap();
        m.place_mixed(1, true, PowerPlay::None).unwrap();
        assert_eq!(m.throwing_seat(), 1);
        m.begin(0, 2, &[]).unwrap();
        assert!(m.set_first_thrower(0, 0).is_err());
        m.settle(&[]).unwrap();
        assert!(m.set_first_thrower(0, 0).is_err());
        m.delivered = 2;
        assert_eq!(m.throwing_seat(), 0);
        m.delivered = 8;
        assert_eq!(m.throwing_seat(), 1);
    }
}
