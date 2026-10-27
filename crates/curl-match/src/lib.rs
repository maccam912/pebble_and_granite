//! Transport-independent host authority. Only validated commands reach the sim.
use curl_rules::{Format, Match, Phase, PowerPlay, Remedy, Resolution, Rules};
use curl_sim::{Release, Sim, Sweep};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, VecDeque};
use std::sync::Arc;

pub mod ai;
#[cfg(test)]
mod brushing_tests;
pub mod delivery;
pub mod drills;

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
    pub in_hand: Option<delivery::InHand>,
    flight_clock: Option<delivery::FlightClock>,
    release_snapshot: Option<Arc<Sim>>,
    // Derived acceleration cache: never part of save data or canonical hashes.
    rewind: VecDeque<Arc<Sim>>,
    idle_remainder: u32,
    sweeps: BTreeMap<(u32, u8), Sweep>,
    pub last_resolution: Option<Resolution>,
}
impl Authority {
    pub fn new(seed: u64, rules: Rules, hammer: u8) -> Result<Self, &'static str> {
        Ok(Self {
            sim: Sim::new(seed),
            in_hand: None,
            flight_clock: None,
            game: Match::new(rules, hammer)?,
            release_snapshot: None,
            rewind: VecDeque::new(),
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
        self.in_hand = None;
        self.flight_clock = None;
        self.release_snapshot = None;
        self.rewind.clear();
        self.sweeps.clear();
        self.last_resolution = None;
        Ok(())
    }
    pub fn release(&mut self, seat: Seat, mut release: Release) -> Result<(), &'static str> {
        if self.in_hand.is_some() {
            return Err("release the active slide instead");
        }
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
        let fatigue = sim.brush_fatigue;
        sim.release(release.clone())?;
        // Match players carry fatigue between deliveries; accepted idle time
        // provides recovery. The standalone single-shot sim keeps its reset API.
        sim.brush_fatigue = fatigue;
        let mut game = self.game.clone();
        game.begin(seat.team, release.stone, &self.sim.stones)?;
        self.game = game;
        self.sim = sim;
        self.flight_clock = if release.pos.y + curl_sim::RADIUS < delivery::DELIVERY_TEE {
            Some(delivery::FlightClock {
                remainder: 0,
                stop_tick: None,
            })
        } else {
            None
        };
        let snapshot = Arc::new(self.sim.clone());
        self.release_snapshot = Some(snapshot.clone());
        self.rewind = VecDeque::from([snapshot]);
        self.sweeps.clear();
        self.last_resolution = None;
        Ok(())
    }
    pub fn hog_violation(&mut self, seat: Seat) -> Result<(), &'static str> {
        if !self.valid_seat(seat)
            || seat.team != self.game.delivering_team()
            || seat.position != self.game.throwing_seat()
            || self.game.phase != Phase::Calling
        {
            return Err("seat does not own this delivery");
        }
        let id = self.game.next_stone_id();
        let mut game = self.game.clone();
        let resolution = game.hog_violation(seat.team, id, &self.sim.stones)?;
        let mut sim = self.sim.clone();
        sim.hog_violation(id, seat.team)?;
        self.game = game;
        self.sim = sim;
        self.in_hand = None;
        self.flight_clock = None;
        self.release_snapshot = None;
        self.rewind.clear();
        self.sweeps.clear();
        self.last_resolution = Some(resolution);
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
        tick: u32,
        input: Sweep,
    ) -> Result<AcceptedSweep, &'static str> {
        self.accept_sweep(seat, tick, input, true, false)
    }
    pub fn sweep_span(
        &mut self,
        seat: Seat,
        tick: u32,
        input: Sweep,
        count: u8,
    ) -> Result<(), &'static str> {
        if count == 0 || count > 12 {
            return Err("invalid brush span");
        }
        if tick < self.sim.release_tick {
            return Err("sweep predates delivery");
        }
        let mut next = self.clone();
        // Defending sweep authorization begins at receipt after the tee, never
        // retroactively at the client's older rendered tick.
        let start = if seat.team != next.game.delivering_team() {
            tick.max(next.sim.tick)
        } else {
            tick
        };
        let first = next.accept_sweep(seat, start, input, false, true)?;
        for offset in 1..count as u32 {
            next.accept_sweep(
                seat,
                first
                    .tick
                    .checked_add(offset)
                    .ok_or("brush tick overflow")?,
                input,
                false,
                true,
            )?;
        }
        if first.tick < next.sim.tick {
            next.resimulate(first.tick)?;
        }
        *self = next;
        Ok(())
    }
    fn accept_sweep(
        &mut self,
        seat: Seat,
        requested_tick: u32,
        mut input: Sweep,
        resimulate: bool,
        replace_future: bool,
    ) -> Result<AcceptedSweep, &'static str> {
        if !self.valid_seat(seat) || self.game.phase != Phase::InFlight || !input.valid() {
            return Err("sweep unavailable");
        }
        if self.game.rules.format == Format::Wheelchair {
            return Err("wheelchair curling has no sweeping");
        }
        if requested_tick < self.sim.release_tick {
            return Err("sweep predates delivery");
        }
        if requested_tick > self.sim.tick.saturating_add(FUTURE_WINDOW) {
            return Err("sweep too far in future");
        }
        // A past brush may not retroactively move the clock's tee crossing.
        let protected_clock = self
            .flight_clock
            .as_ref()
            .is_some_and(|clock| clock.stop_tick.is_none_or(|stop| requested_tick < stop));
        let tick = if protected_clock || requested_tick.saturating_add(LATE_WINDOW) < self.sim.tick
        {
            requested_tick.max(self.sim.tick)
        } else {
            requested_tick.max(self.sim.release_tick)
        };
        let delivered = self.sim.delivered.ok_or("no delivered stone")?;
        let mixed = self.game.rules.format == Format::MixedDoubles;
        if !mixed && input.stone != delivered {
            return Err("only delivered-stone sweeping supported in this format");
        }
        let stone = self
            .sim
            .stones
            .iter()
            .find(|s| s.id == input.stone && s.active)
            .ok_or("stone out of play")?;
        if mixed {
            if stone.vel == curl_fx::V2::ZERO {
                return Err("stone is not moving");
            }
            if stone.team != seat.team && stone.pos.y < curl_fx::Fx::ZERO {
                return Err("opponent cannot sweep here");
            }
            if stone.pos.y >= curl_fx::Fx::ZERO
                && seat.team != self.game.delivering_team()
                && seat.position != 1
            {
                return Err("only defending skip may sweep behind tee");
            }
        } else if seat.team != self.game.delivering_team()
            && (seat.position != 3 || stone.pos.y < curl_fx::Fx::ZERO)
        {
            return Err("opponent cannot sweep here");
        }
        if stone.team != seat.team && tick < self.sim.tick {
            return Err("opponent sweep may not predate tee authorization");
        }
        // Mixed doubles has one fatigue identity per player, fixed across throws
        // and ends. The client cannot select a fresher brush identity.
        input.brush = if mixed {
            seat.team * 2 + seat.position
        } else {
            seat.team
        };
        if let Some(existing) = self.sweeps.get(&(tick, input.brush)) {
            if !replace_future {
                return Err("duplicate player sweep tick");
            }
            if tick < self.sim.tick {
                // Network retiming may make a later span overlap a consumed
                // tail. Retain that accepted sample; never replay its heat twice.
                return Ok(AcceptedSweep {
                    tick,
                    input: *existing,
                    retimed: tick != requested_tick,
                });
            }
        }
        // Retimed spans can overlap the unconsumed tail of a prior span. The
        // latest accepted effort replaces future intent for this player; it
        // never stacks heat or rewrites already simulated duplicate samples.
        self.sweeps.insert((tick, input.brush), input);
        if resimulate && tick < self.sim.tick {
            self.resimulate(tick)?;
        }
        Ok(AcceptedSweep {
            tick,
            input,
            retimed: tick != requested_tick,
        })
    }
    fn inputs(&self, sim: &Sim) -> Vec<Sweep> {
        let mut behind = [false; 2];
        self.sweeps
            .range((sim.tick, 0)..=(sim.tick, u8::MAX))
            .filter_map(|(_, input)| {
                if self.game.rules.format != Format::MixedDoubles {
                    return Some(*input);
                }
                let stone = sim
                    .stones
                    .iter()
                    .find(|s| s.id == input.stone && s.active)?;
                if input.effort == 0 || stone.vel == curl_fx::V2::ZERO {
                    return None;
                }
                let team = input.brush / 2;
                if stone.pos.y < curl_fx::Fx::ZERO {
                    return (stone.team == team).then_some(*input);
                }
                // Evaluate against THIS tick's state, including resimulation and
                // spans scheduled before crossing. Stable player order resolves
                // simultaneous behind-tee requests, independent of packet order.
                if team != self.game.delivering_team() && input.brush % 2 != 1 {
                    return None;
                }
                if std::mem::replace(&mut behind[team as usize], true) {
                    return None;
                }
                Some(*input)
            })
            .collect()
    }
    fn checkpoint_needed(&self, tick: u32, release_tick: u32) -> bool {
        (tick - release_tick).is_multiple_of(12)
            && self.rewind.back().is_none_or(|s| s.tick != tick)
    }
    fn remember(&mut self, snapshot: Arc<Sim>) {
        let oldest = snapshot.tick.saturating_sub(LATE_WINDOW);
        self.rewind.push_back(snapshot);
        // Keep one checkpoint at or before the oldest acceptable late tick.
        while self.rewind.len() > 1 && self.rewind[1].tick <= oldest {
            self.rewind.pop_front();
        }
    }
    fn resimulate(&mut self, changed_tick: u32) -> Result<(), &'static str> {
        let target = self.sim.tick;
        let base = self
            .rewind
            .iter()
            .rev()
            .find(|s| s.tick <= changed_tick)
            .or(self.release_snapshot.as_ref())
            .ok_or("missing release snapshot")?;
        let mut restored = base.as_ref().clone();
        self.rewind.retain(|s| s.tick <= restored.tick);
        while restored.tick < target && !restored.is_resting() {
            if self.checkpoint_needed(restored.tick, restored.release_tick) {
                self.remember(Arc::new(restored.clone()));
            }
            restored.step(&self.inputs(&restored));
        }
        self.sim = restored;
        Ok(())
    }
    pub fn step(&mut self) -> Result<(), &'static str> {
        if self.game.phase != Phase::InFlight {
            return Ok(());
        }
        if self.checkpoint_needed(self.sim.tick, self.sim.release_tick) {
            self.remember(Arc::new(self.sim.clone()));
        }
        self.sim.step(&self.inputs(&self.sim));
        if self.sim.timed_out {
            return Err("physics time budget exhausted");
        }
        self.advance_flight_clock();
        if self.game.phase == Phase::GameComplete {
            return Ok(());
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
        if self.in_hand.is_some() {
            return self.advance_delivery(elapsed_ms);
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
        if let Some(delivery) = &self.in_hand {
            h.bytes(b"in-hand-v1");
            h.bytes(&serde_json::to_vec(delivery).expect("delivery serialize"));
        }
        if let Some(clock) = &self.flight_clock {
            h.bytes(b"flight-clock-v1");
            h.bytes(&serde_json::to_vec(clock).expect("clock serialize"));
        }
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
    fn defending_brush_span_starts_at_authorized_receipt_tick() {
        let mut a = authority();
        a.release(THROWER, Release::draw()).unwrap();
        for _ in 0..20 {
            a.step().unwrap();
        }
        let defender = Seat {
            team: 1,
            position: 1,
        };
        let input = Sweep::centered(2, 200);
        assert!(a.sweep_span(defender, 0, input, 12).is_err());
        a.sim.stones.iter_mut().find(|s| s.id == 2).unwrap().pos.y = curl_fx::Fx::ratio(1, 10);
        a.sweep_span(defender, 0, input, 12).unwrap();
        let accepted = a.accepted_sweeps();
        assert_eq!(accepted.len(), 12);
        assert_eq!(accepted[0].0, 20);
        assert_eq!(accepted[11].0, 31);
    }
    #[test]
    fn bounded_rewind_matches_full_release_replay() {
        let mut cached = authority();
        cached.release(THROWER, Release::draw()).unwrap();
        let mut reference = cached.clone();
        for batch in 0..160 {
            for _ in 0..12 {
                cached.step().unwrap();
                reference.step().unwrap();
            }
            let tick = cached.sim.tick.saturating_sub(batch % 25);
            let input = Sweep::centered(2, (batch % 255) as u8);
            // Force the reference to replay the whole release, independently
            // of the acceleration cache, across every accepted late offset.
            reference.rewind.clear();
            cached.sweep(THROWER, tick, input).unwrap();
            reference.sweep(THROWER, tick, input).unwrap();
            assert_eq!(cached.hash(), reference.hash(), "batch {batch}");
            assert!(cached.rewind.len() <= 4);
        }
    }
    #[test]
    fn previous_delivery_brush_cannot_retime_into_new_delivery() {
        let mut a = authority();
        a.think(1000).unwrap();
        a.release(THROWER, Release::draw()).unwrap();
        let before = a.hash();
        assert!(a.sweep(THROWER, 0, Sweep::centered(2, 255)).is_err());
        assert!(
            a.sweep_span(THROWER, 0, Sweep::centered(2, 255), 12)
                .is_err()
        );
        assert_eq!(a.hash(), before);
        a.sweep_span(THROWER, a.sim.release_tick, Sweep::centered(2, 255), 12)
            .unwrap();
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
        assert_eq!(
            a.sweep(
                Seat {
                    team: 0,
                    position: 1
                },
                0,
                input
            )
            .unwrap()
            .input
            .brush,
            1
        );
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
