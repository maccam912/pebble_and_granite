//! Transport-independent host authority. Only validated commands reach the sim.
use curl_rules::{Format, Match, Phase, PowerPlay, Remedy, Resolution, Rules};
use curl_sim::{Release, Sim, Sweep};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const LATE_WINDOW: u32 = 24; // 100 ms; older samples apply at authority arrival.
pub const FUTURE_WINDOW: u32 = 12;
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Seat {
    pub team: u8,
    pub position: u8,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AcceptedSweep {
    pub tick: u32,
    pub input: Sweep,
    pub retimed: bool,
}
#[derive(Clone)]
pub struct Authority {
    pub sim: Sim,
    pub game: Match,
    release_snapshot: Option<Sim>,
    idle_remainder: u32,
    sweeps: BTreeMap<(u32, u8), Sweep>,
    pub last_resolution: Option<Resolution>,
}
impl Authority {
    pub fn new(seed: u64, rules: Rules, hammer: u8) -> Result<Self, &'static str> {
        Ok(Self {
            sim: Sim::new(seed),
            game: Match::new(rules, hammer)?,
            release_snapshot: None,
            idle_remainder: 0,
            sweeps: BTreeMap::new(),
            last_resolution: None,
        })
    }
    pub fn place_mixed(
        &mut self,
        seat: Seat,
        own_house: bool,
        side: PowerPlay,
    ) -> Result<(), &'static str> {
        if !self.valid_seat(seat) {
            return Err("invalid seat");
        }
        let mut game = self.game.clone();
        let stones = game.place_mixed(seat.team, own_house, side)?;
        let mut sim = self.sim.clone();
        sim.clear_stones()?;
        for stone in stones {
            sim.add_resting(stone)?;
        }
        self.game = game;
        self.sim = sim;
        Ok(())
    }
    pub fn next_end(&mut self) -> Result<(), &'static str> {
        let mut game = self.game.clone();
        game.next_end()?;
        let mut sim = self.sim.clone();
        sim.clear_stones()?;
        sim.advance_idle(60 * 240)?;
        self.game = game;
        self.sim = sim;
        self.release_snapshot = None;
        self.sweeps.clear();
        self.last_resolution = None;
        Ok(())
    }
    pub fn release(&mut self, seat: Seat, mut release: Release) -> Result<(), &'static str> {
        if !self.valid_seat(seat)
            || seat.team != self.game.delivering_team()
            || seat.position != self.game.throwing_seat()
            || self.game.phase != Phase::Calling
        {
            return Err("seat does not own this delivery");
        }
        // Ignore client-provided identity: the authority assigns team and stone id.
        release.team = seat.team;
        release.stone = self.game.next_stone_id();
        release.validate()?;
        // Validate both state transitions on clones so failure cannot partially mutate.
        let mut sim = self.sim.clone();
        sim.release(release.clone())?;
        let mut game = self.game.clone();
        game.begin(seat.team, release.stone, &self.sim.stones)?;
        self.game = game;
        self.sim = sim;
        self.release_snapshot = Some(self.sim.clone());
        self.sweeps.clear();
        self.last_resolution = None;
        Ok(())
    }
    fn valid_seat(&self, seat: Seat) -> bool {
        seat.team < 2
            && seat.position
                < if self.game.rules.format == Format::MixedDoubles {
                    2
                } else {
                    4
                }
    }
    pub fn sweep(
        &mut self,
        seat: Seat,
        requested_tick: u32,
        mut input: Sweep,
    ) -> Result<AcceptedSweep, &'static str> {
        if !self.valid_seat(seat) || self.game.phase != Phase::InFlight || !input.valid() {
            return Err("sweep unavailable");
        }
        if self.game.rules.format == Format::Wheelchair {
            return Err("wheelchair curling has no sweeping");
        }
        if requested_tick > self.sim.tick.saturating_add(FUTURE_WINDOW) {
            return Err("sweep too far in future");
        }
        let tick = if requested_tick.saturating_add(LATE_WINDOW) < self.sim.tick {
            self.sim.tick
        } else {
            requested_tick.max(self.sim.release_tick)
        };
        let delivered = self.sim.delivered.ok_or("no delivered stone")?;
        if input.stone != delivered {
            return Err("only delivered-stone sweeping supported in this slice");
        }
        // Behind the tee: one sweeper per side. A defending skip (seat 1 in mixed,
        // 3 in teams) may sweep only after the stone reaches the far tee.
        let stone = self
            .sim
            .stones
            .iter()
            .find(|s| s.id == delivered && s.active)
            .ok_or("stone out of play")?;
        if seat.team != self.game.delivering_team() {
            let skip = if self.game.rules.format == Format::MixedDoubles {
                1
            } else {
                3
            };
            if seat.position != skip || stone.pos.y < curl_fx::Fx::ZERO {
                return Err("opponent cannot sweep here");
            }
            // Do not retroactively authorize a command using the stone's later position.
            if tick < self.sim.tick {
                return Err("opponent sweep may not predate tee authorization");
            }
        }
        // One tracked brush stream per team in first slice, no client-selected fatigue id.
        input.brush = seat.team;
        if self.sweeps.contains_key(&(tick, input.brush)) {
            return Err("duplicate team sweep tick");
        }
        self.sweeps.insert((tick, input.brush), input);
        if tick < self.sim.tick {
            self.resimulate()?;
        }
        Ok(AcceptedSweep {
            tick,
            input,
            retimed: tick != requested_tick,
        })
    }
    fn inputs(&self, tick: u32) -> Vec<Sweep> {
        self.sweeps
            .range((tick, 0)..=(tick, u8::MAX))
            .map(|(_, s)| *s)
            .collect()
    }
    fn resimulate(&mut self) -> Result<(), &'static str> {
        let target = self.sim.tick;
        let mut restored = self
            .release_snapshot
            .clone()
            .ok_or("missing release snapshot")?;
        while restored.tick < target && !restored.is_resting() {
            restored.step(&self.inputs(restored.tick));
        }
        self.sim = restored;
        Ok(())
    }
    pub fn step(&mut self) -> Result<(), &'static str> {
        if self.game.phase != Phase::InFlight {
            return Ok(());
        }
        self.sim.step(&self.inputs(self.sim.tick));
        if self.sim.timed_out {
            return Err("physics time budget exhausted");
        }
        if self.sim.is_resting() {
            let resolution = self.game.settle(&self.sim.stones)?;
            if let Some(stones) = &resolution.replace_stones {
                self.sim.stones = stones.clone();
            }
            self.last_resolution = Some(resolution);
        }
        Ok(())
    }
    pub fn choose(&mut self, seat: Seat, remedy: Remedy) -> Result<(), &'static str> {
        if !self.valid_seat(seat) {
            return Err("invalid seat");
        }
        let resolution = self.game.choose(seat.team, remedy)?;
        if let Some(stones) = &resolution.replace_stones {
            self.sim.stones = stones.clone();
        }
        self.last_resolution = Some(resolution);
        Ok(())
    }
    /// Authority wall time affects both the thinking clock and cooling ice.
    pub fn think(&mut self, elapsed_ms: u32) -> Result<(), &'static str> {
        if elapsed_ms > 60000 {
            return Err("elapsed interval too large");
        }
        if self.game.phase != Phase::Calling {
            return Ok(());
        }
        let total = elapsed_ms * 240 + self.idle_remainder;
        self.sim.advance_idle(total / 1000)?;
        self.idle_remainder = total % 1000;
        self.game.think(elapsed_ms);
        Ok(())
    }
    pub fn hash(&self) -> u64 {
        let mut h = curl_fx::Hash64::default();
        h.u64(self.sim.hash());
        h.u64(self.idle_remainder as u64);
        h.bytes(&serde_json::to_vec(&self.game).expect("rules serialize"));
        h.u64(self.release_snapshot.as_ref().map_or(0, |sim| sim.hash()));
        h.bytes(&serde_json::to_vec(&self.accepted_sweeps()).expect("sweeps serialize"));
        h.finish()
    }
    pub fn accepted_sweeps(&self) -> Vec<(u32, Sweep)> {
        self.sweeps
            .iter()
            .map(|((tick, _), s)| (*tick, *s))
            .collect()
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    const THROWER: Seat = Seat {
        team: 0,
        position: 0,
    };
    fn authority() -> Authority {
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
        a
    }
    #[test]
    fn release_ownership_and_identity() {
        let mut a = authority();
        assert!(
            a.release(
                Seat {
                    team: 1,
                    position: 0
                },
                Release::draw()
            )
            .is_err()
        );
        assert_eq!(a.game.phase, Phase::Calling);
        a.release(THROWER, Release::draw()).unwrap();
        assert_eq!(a.sim.delivered, Some(2));
        assert_eq!(a.sim.stones[0].team, 0);
        assert!(a.release(THROWER, Release::draw()).is_err());
    }
    #[test]
    fn rejected_release_is_atomic() {
        let mut a = authority();
        let before = a.sim.hash();
        let mut r = Release::draw();
        r.vel.y = curl_fx::Fx(i64::MAX);
        assert!(a.release(THROWER, r).is_err());
        assert_eq!(before, a.sim.hash());
        assert_eq!(a.game.phase, Phase::Calling);
    }
    #[test]
    fn delayed_inputs_match_on_time_exactly() {
        let mut a = authority();
        a.release(THROWER, Release::draw()).unwrap();
        let mut b = a.clone();
        let input = Sweep::centered(2, 255);
        a.sweep(THROWER, 10, input).unwrap();
        for _ in 0..20 {
            a.step().unwrap();
            b.step().unwrap();
        }
        b.sweep(THROWER, 10, input).unwrap();
        assert_eq!(a.sim.hash(), b.sim.hash());
        for _ in 0..50 {
            a.step().unwrap();
            b.step().unwrap();
        }
        assert_eq!(a.sim.hash(), b.sim.hash());
    }
    #[test]
    fn stale_sweep_cannot_rewrite_past() {
        let mut a = authority();
        a.release(THROWER, Release::draw()).unwrap();
        for _ in 0..100 {
            a.step().unwrap();
        }
        let before = a.sim.hash();
        let accepted = a.sweep(THROWER, 0, Sweep::centered(2, 255)).unwrap();
        assert_eq!(accepted.tick, 100);
        assert!(accepted.retimed);
        assert_eq!(before, a.sim.hash());
    }
    #[test]
    fn deny_opponent_before_tee_and_duplicate_fatigue_stream() {
        let mut a = authority();
        a.release(THROWER, Release::draw()).unwrap();
        let input = Sweep::centered(2, 255);
        assert!(
            a.sweep(
                Seat {
                    team: 1,
                    position: 1
                },
                0,
                input
            )
            .is_err()
        );
        a.sweep(THROWER, 0, input).unwrap();
        assert!(
            a.sweep(
                Seat {
                    team: 0,
                    position: 1
                },
                0,
                input
            )
            .is_err()
        );
        assert!(a.sweep(THROWER, 500, input).is_err());
    }
    #[test]
    fn mixed_match_end_transition_preserves_ice_and_requires_new_placement() {
        let mut a = authority();
        assert_eq!(a.sim.stones.len(), 2);
        assert!(a.place_mixed(THROWER, true, PowerPlay::None).is_err());
        for _ in 0..10 {
            let seat = Seat {
                team: a.game.delivering_team(),
                position: a.game.throwing_seat(),
            };
            a.release(seat, Release::draw()).unwrap();
            for _ in 0..curl_sim::MAX_TICKS {
                if a.game.phase != Phase::InFlight {
                    break;
                }
                a.step().unwrap();
            }
            assert_ne!(a.game.phase, Phase::InFlight);
        }
        assert_eq!(a.game.phase, Phase::EndComplete);
        let tick = a.sim.tick;
        let ice = a.sim.ice.clone();
        a.next_end().unwrap();
        assert_eq!(a.game.end, 2);
        assert_eq!(a.game.phase, Phase::Placement);
        assert!(a.sim.stones.is_empty());
        assert_eq!(a.sim.tick, tick + 60 * 240);
        assert_eq!(a.sim.ice, ice);
        assert!(a.release(THROWER, Release::draw()).is_err());
        let seat = Seat {
            team: a.game.placement_team,
            position: 0,
        };
        a.place_mixed(seat, true, PowerPlay::None).unwrap();
        assert_eq!(a.sim.stones.len(), 2);
        assert_eq!(a.sim.stones[0].id, 0);
        assert_eq!(a.game.next_stone_id(), 2);
    }
    #[test]
    fn thinking_time_cools_ice_independent_of_frame_partition() {
        let mut a = authority();
        let mut b = a.clone();
        a.think(1001).unwrap();
        for _ in 0..1001 {
            b.think(1).unwrap();
        }
        assert_eq!(a.sim.hash(), b.sim.hash());
        assert_eq!(a.game.thinking_ms, b.game.thinking_ms);
        assert_eq!(a.idle_remainder, b.idle_remainder);
        assert_eq!(a.sim.tick, 240);
        let tick = a.sim.tick;
        a.release(THROWER, Release::draw()).unwrap();
        a.think(1000).unwrap();
        assert_eq!(a.sim.tick, tick);
    }
}

pub mod practice;

pub mod room;

pub mod recorded;

pub mod sync;
