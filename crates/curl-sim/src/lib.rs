//! Authoritative 240 Hz curling model. No floats, wall clocks or engine types.
use curl_fx::{Fx, Hash64, Rng, V2};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const MODEL_VERSION: u32 = 2;
pub const HZ: u32 = 240;
pub const DT: Fx = Fx::ratio(1, HZ as i64);
pub const RADIUS: Fx = Fx::ratio(142, 1000);
pub const HALF_WIDTH: Fx = Fx::ratio(2375, 1000);
pub const NEAR_HOG: Fx = Fx::ratio(-28349, 1000);
pub const FAR_HOG: Fx = Fx::ratio(-6401, 1000);
pub const BACK: Fx = Fx::ratio(1829, 1000);
pub const HOUSE: Fx = Fx::ratio(1829, 1000);
pub const MAX_STONES: usize = 16;
pub const MAX_TICKS: u32 = HZ * 60;
const REST: Fx = Fx::ratio(5, 1000);
const DIAMETER: Fx = Fx::ratio(284, 1000);

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Stone {
    pub id: u8,
    pub team: u8,
    pub pos: V2,
    pub vel: V2,
    /// Revolutions / second, clockwise positive.
    pub spin: Fx,
    pub turns: Fx,
    pub active: bool,
    pub touched: bool,
}
impl Stone {
    pub fn resting(id: u8, team: u8, pos: V2) -> Self {
        Self {
            id,
            team,
            pos,
            vel: V2::ZERO,
            spin: Fx::ZERO,
            turns: Fx::ZERO,
            active: true,
            touched: false,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Release {
    pub stone: u8,
    pub team: u8,
    pub pos: V2,
    pub vel: V2,
    pub spin: Fx,
}
impl Release {
    pub fn draw() -> Self {
        Self {
            stone: 0,
            team: 0,
            pos: V2::new(Fx::ZERO, NEAR_HOG - Fx::ratio(1, 100)),
            vel: V2::new(Fx::ZERO, Fx::ratio(205, 100)),
            spin: Fx::ratio(12, 100),
        }
    }
    pub fn validate(&self) -> Result<(), &'static str> {
        // Compare components before products: hostile integer payloads must not overflow.
        if self.stone as usize >= MAX_STONES
            || self.team > 1
            || self.pos.x < -HALF_WIDTH + RADIUS
            || self.pos.x > HALF_WIDTH - RADIUS
            || self.pos.y < Fx::int(-35)
            || self.pos.y >= NEAR_HOG
            || self.vel.x < Fx::int(-2)
            || self.vel.x > Fx::int(2)
            || self.vel.y < Fx::ratio(1, 10)
            || self.vel.y > Fx::int(6)
            || self.spin < Fx::int(-3)
            || self.spin > Fx::int(3)
        {
            return Err("release outside physical bounds");
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Sweep {
    pub stone: u8,
    pub brush: u8,
    pub effort: u8,
    pub lateral_mm: i16,
    pub ahead_mm: u16,
}
impl Sweep {
    pub fn centered(stone: u8, effort: u8) -> Self {
        Self {
            stone,
            brush: 0,
            effort,
            lateral_mm: 0,
            ahead_mm: 180,
        }
    }
    pub fn valid(&self) -> bool {
        self.brush < 4
            && self.stone < 16
            && (-350..=350).contains(&self.lateral_mm)
            && (80..=700).contains(&self.ahead_mm)
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Cell {
    pub heat: u16,
    pub updated: u32,
    pub wear: u16,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ice {
    pub seed: u64,
    pub cells: BTreeMap<u32, Cell>,
    pub varied: bool,
}
impl Ice {
    pub fn new(seed: u64) -> Self {
        Self {
            seed,
            cells: BTreeMap::new(),
            varied: false,
        }
    }
    pub fn cell(pos: V2) -> Option<u32> {
        let x = ((pos.x + HALF_WIDTH) / Fx::ratio(5, 100)).raw() >> 32;
        let y = ((pos.y + Fx::int(40)) / Fx::ratio(5, 100)).raw() >> 32;
        if !(0..95).contains(&x) || !(0..914).contains(&y) {
            None
        } else {
            Some(y as u32 * 95 + x as u32)
        }
    }
    fn heat_at(c: Cell, tick: u32) -> u16 {
        // Linear cooling, 1.5 C cap, 3 seconds from full heat. Lazy and exact.
        c.heat.saturating_sub(
            tick.saturating_sub(c.updated)
                .saturating_mul(3)
                .min(u16::MAX as u32) as u16,
        )
    }
    pub fn sample(&self, pos: V2, tick: u32) -> (Fx, Fx) {
        let Some(index) = Self::cell(pos) else {
            return (Fx::ONE, Fx::ZERO);
        };
        let cell = self.cells.get(&index).copied().unwrap_or_default();
        let variation = if self.varied {
            (Rng(self.seed ^ index as u64).next_u64() % 101) as i64 - 50
        } else {
            0
        };
        let drag =
            Fx::ONE + Fx::ratio(variation, 10000) - Fx::ratio(cell.wear.min(100) as i64, 100000);
        (drag, Fx::ratio(Self::heat_at(cell, tick) as i64, 1500))
    }
    fn brush(&mut self, pos: V2, effort: u8, tick: u32) {
        // Brush footprint 30 cm across, 10 cm along sheet; only cells touched warm.
        for dx in -3..=3 {
            for dy in -1..=1 {
                let p = pos + V2::new(Fx::ratio(dx, 20), Fx::ratio(dy, 20));
                if let Some(i) = Self::cell(p) {
                    let c = self.cells.entry(i).or_default();
                    c.heat = (Self::heat_at(*c, tick) + (effort as u16 * 30 / 255)).min(1500);
                    c.updated = tick;
                }
            }
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Event {
    Contact(u8, u8, Fx),
    HogCrossed(u8, u32),
    Removed(u8),
    Rest(u8),
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Sim {
    pub version: u32,
    pub tick: u32,
    pub stones: Vec<Stone>,
    pub ice: Ice,
    pub delivered: Option<u8>,
    pub release_tick: u32,
    pub hog_tick: Option<u32>,
    pub contacts: u32,
    pub timed_out: bool,
    pub brush_fatigue: [u16; 4],
    last_cells: [Option<u32>; MAX_STONES],
}
impl Sim {
    pub fn new(seed: u64) -> Self {
        Self {
            version: MODEL_VERSION,
            tick: 0,
            stones: vec![],
            ice: Ice::new(seed),
            delivered: None,
            release_tick: 0,
            hog_tick: None,
            contacts: 0,
            timed_out: false,
            brush_fatigue: [0; 4],
            last_cells: [None; MAX_STONES],
        }
    }
    pub fn add_resting(&mut self, stone: Stone) -> Result<(), &'static str> {
        if !self.is_resting()
            || self.stones.len() >= MAX_STONES
            || self.stones.iter().any(|s| s.id == stone.id)
            || stone.id as usize >= MAX_STONES
            || stone.team > 1
            || stone.vel != V2::ZERO
            || stone.spin != Fx::ZERO
            || stone.turns != Fx::ZERO
            || stone.touched
            || !stone.active
            || stone.pos.x < -HALF_WIDTH + RADIUS
            || stone.pos.x > HALF_WIDTH - RADIUS
            || stone.pos.y < FAR_HOG
            || stone.pos.y > BACK + RADIUS
            || self
                .stones
                .iter()
                .any(|s| s.active && (s.pos - stone.pos).length() < DIAMETER)
        {
            return Err("invalid starting stone");
        }
        self.stones.push(stone);
        self.stones.sort_by_key(|s| s.id);
        Ok(())
    }
    pub fn release(&mut self, r: Release) -> Result<(), &'static str> {
        r.validate()?;
        if !self.is_resting()
            || self.stones.iter().any(|s| s.id == r.stone)
            || self.stones.len() >= MAX_STONES
        {
            return Err("release unavailable");
        }
        let mut s = Stone::resting(r.stone, r.team, r.pos);
        s.vel = r.vel;
        s.spin = r.spin;
        self.delivered = Some(r.stone);
        self.release_tick = self.tick;
        self.hog_tick = None;
        self.timed_out = false;
        self.brush_fatigue = [0; 4];
        self.last_cells = [None; MAX_STONES];
        self.stones.push(s);
        self.stones.sort_by_key(|s| s.id);
        Ok(())
    }
    /// Advance deterministic ice time while no stones move. Heat cools lazily.
    pub fn advance_idle(&mut self, ticks: u32) -> Result<(), &'static str> {
        if !self.is_resting() || ticks > HZ * 3600 {
            return Err("invalid idle interval");
        }
        self.tick = self
            .tick
            .checked_add(ticks)
            .ok_or("simulation clock exhausted")?;
        for f in &mut self.brush_fatigue {
            *f = f.saturating_sub(ticks.saturating_mul(2).min(u16::MAX as u32) as u16);
        }
        Ok(())
    }
    /// Remove practice stones without re-pebbling or rewinding the ice clock.
    pub fn clear_stones(&mut self) -> Result<(), &'static str> {
        if !self.is_resting() {
            return Err("stones still moving");
        }
        self.stones.clear();
        self.delivered = None;
        self.release_tick = self.tick;
        self.hog_tick = None;
        self.contacts = 0;
        self.timed_out = false;
        self.last_cells = [None; MAX_STONES];
        Ok(())
    }
    pub fn is_resting(&self) -> bool {
        self.stones.iter().all(|s| !s.active || s.vel == V2::ZERO)
    }
    pub fn step(&mut self, sweeps: &[Sweep]) -> Vec<Event> {
        if self.is_resting() {
            return vec![];
        }
        let mut events = vec![];
        let mut used = [false; 4];
        for sweep in sweeps.iter().filter(|s| s.valid()) {
            let brush = sweep.brush as usize;
            if used[brush] {
                continue;
            }
            used[brush] = true;
            if let Some(s) = self
                .stones
                .iter()
                .find(|s| s.id == sweep.stone && s.active && s.vel != V2::ZERO)
            {
                let dir = s.vel.unit();
                let p = s.pos
                    + dir * Fx::ratio(sweep.ahead_mm as i64, 1000)
                    + dir.right() * Fx::ratio(sweep.lateral_mm as i64, 1000);
                let fatigue = self.brush_fatigue[brush];
                let effort = (sweep.effort as u32 * (20000 - fatigue as u32) / 20000) as u8;
                self.ice.brush(p, effort, self.tick);
                self.brush_fatigue[brush] = (fatigue + sweep.effort as u16 / 64).min(12000);
            }
        }
        for (i, active) in used.iter().enumerate() {
            if !active {
                self.brush_fatigue[i] = self.brush_fatigue[i].saturating_sub(2);
            }
        }
        for s in &mut self.stones {
            if !s.active || s.vel == V2::ZERO {
                continue;
            }
            let speed = s.vel.length();
            let dir = s.vel.unit();
            // Rational low-speed friction, provisional empirical calibration.
            let (ice, heat) = self.ice.sample(s.pos, self.tick);
            let decel = Fx::ratio(61, 1000)
                * (Fx::ONE + Fx::ratio(35, 100) / (speed + Fx::ratio(2, 10)))
                * ice
                * (Fx::ONE - heat * Fx::ratio(18, 100));
            let next = (speed - decel * DT).max(Fx::ZERO);
            if next < REST {
                s.vel = V2::ZERO;
                s.spin = Fx::ZERO;
                events.push(Event::Rest(s.id));
                continue;
            }
            let spin_factor = (s.spin.abs() / Fx::ratio(4, 100)).min(Fx::ONE)
                / (Fx::ONE + (s.spin.abs() / Fx::ratio(6, 10)) * (s.spin.abs() / Fx::ratio(6, 10)));
            let lateral = Fx::ratio(90, 10000) / (speed + Fx::ratio(3, 10))
                * s.spin.sign()
                * spin_factor
                * (Fx::ONE - heat * Fx::ratio(70, 100));
            s.vel = (dir * next + dir.right() * (lateral * DT)).unit() * next;
            s.turns += s.spin * DT;
            s.spin = s.spin * Fx::ratio(99998, 100000);
            if let Some(cell) = Ice::cell(s.pos)
                && self.last_cells[s.id as usize] != Some(cell)
            {
                let c = self.ice.cells.entry(cell).or_default();
                c.wear = c.wear.saturating_add(1);
                self.last_cells[s.id as usize] = Some(cell);
            }
        }
        self.move_contacts(&mut events);
        self.tick += 1;
        for s in &mut self.stones {
            if !s.active {
                continue;
            }
            if Some(s.id) == self.delivered && self.hog_tick.is_none() && s.pos.y - RADIUS > FAR_HOG
            {
                self.hog_tick = Some(self.tick);
                events.push(Event::HogCrossed(s.id, self.tick));
            }
            if s.pos.x.abs() + RADIUS >= HALF_WIDTH || s.pos.y - RADIUS > BACK {
                s.active = false;
                s.vel = V2::ZERO;
                s.spin = Fx::ZERO;
                events.push(Event::Removed(s.id));
            }
        }
        if self.tick - self.release_tick >= MAX_TICKS {
            self.timed_out = true;
            for s in &mut self.stones {
                s.vel = V2::ZERO;
                s.spin = Fx::ZERO;
            }
        }
        if self.is_resting()
            && let Some(s) = self
                .stones
                .iter_mut()
                .find(|s| Some(s.id) == self.delivered)
            && s.active
            && s.pos.y - RADIUS <= FAR_HOG
            && !s.touched
        {
            s.active = false;
            events.push(Event::Removed(s.id));
        }
        events
    }
    fn move_contacts(&mut self, events: &mut Vec<Event>) {
        let mut remaining = DT;
        for _ in 0..64 {
            let mut hit = None;
            for i in 0..self.stones.len() {
                for j in i + 1..self.stones.len() {
                    let (a, b) = (&self.stones[i], &self.stones[j]);
                    if !a.active || !b.active {
                        continue;
                    }
                    let p = b.pos - a.pos;
                    let v = b.vel - a.vel;
                    let aa = v.dot(v);
                    let bb = p.dot(v);
                    let cc = p.dot(p) - DIAMETER * DIAMETER;
                    if aa <= Fx::EPSILON || bb >= Fx::ZERO {
                        continue;
                    }
                    let time = if cc <= Fx::ZERO {
                        Fx::ZERO
                    } else {
                        let disc = bb * bb - aa * cc;
                        if disc < Fx::ZERO {
                            continue;
                        }
                        (-bb - disc.sqrt()) / aa
                    };
                    if time < Fx::ZERO || time > remaining {
                        continue;
                    }
                    if hit.is_none_or(|(t, _, _)| time < t) {
                        hit = Some((time, i, j));
                    }
                }
            }
            let travel = hit.map_or(remaining, |(t, _, _)| t);
            for s in &mut self.stones {
                if s.active {
                    s.pos = s.pos + s.vel * travel;
                }
            }
            remaining -= travel;
            let Some((_, i, j)) = hit else {
                break;
            };
            let (left, right) = self.stones.split_at_mut(j);
            let a = &mut left[i];
            let b = &mut right[0];
            let normal = (b.pos - a.pos).unit();
            let closing = (a.vel - b.vel).dot(normal);
            if closing > Fx::ZERO {
                let impulse = closing * Fx::ratio(185, 200); // e=0.85 provisional, equal matched mass
                a.vel = a.vel - normal * impulse;
                b.vel = b.vel + normal * impulse;
                // Tangential surface impulse includes spin; solid disc inertia m*r²/2.
                let tangent = normal.right();
                let tau = Fx::ratio(6283185307, 1000000000);
                let slip = (a.vel - b.vel).dot(tangent) + (a.spin + b.spin) * tau * RADIUS;
                let jt = (slip / Fx::int(6))
                    .clamp(-impulse * Fx::ratio(1, 10), impulse * Fx::ratio(1, 10));
                a.vel = a.vel - tangent * jt;
                b.vel = b.vel + tangent * jt;
                let spin_delta = jt * Fx::int(2) / (tau * RADIUS);
                a.spin -= spin_delta;
                b.spin -= spin_delta;
                a.touched = true;
                b.touched = true;
                self.contacts += 1;
                events.push(Event::Contact(a.id, b.id, impulse));
            }
            let gap = (DIAMETER - (b.pos - a.pos).length()).max(Fx::ZERO) + Fx::ratio(1, 1000000);
            a.pos = a.pos - normal * (gap / Fx::int(2));
            b.pos = b.pos + normal * (gap / Fx::int(2));
            if remaining <= Fx::ZERO {
                break;
            }
        }
        // Fixed passes remove residual overlaps in touching chains deterministically.
        for _ in 0..16 {
            for i in 0..self.stones.len() {
                for j in i + 1..self.stones.len() {
                    let (left, right) = self.stones.split_at_mut(j);
                    let a = &mut left[i];
                    let b = &mut right[0];
                    if !a.active || !b.active {
                        continue;
                    }
                    let p = b.pos - a.pos;
                    let len = p.length();
                    if len < DIAMETER {
                        let n = if len == Fx::ZERO {
                            V2::new(Fx::ONE, Fx::ZERO)
                        } else {
                            p.unit()
                        };
                        let d = (DIAMETER - len) / Fx::int(2) + Fx::ratio(1, 1000000);
                        a.pos = a.pos - n * d;
                        b.pos = b.pos + n * d;
                    }
                }
            }
        }
    }
    pub fn hash(&self) -> u64 {
        let mut h = Hash64::default();
        h.u64(self.version as u64);
        h.u64(self.tick as u64);
        h.u64(self.ice.seed);
        h.u64(self.ice.varied as u64);
        h.u64(self.delivered.map_or(256, |id| id as u64));
        h.u64(self.release_tick as u64);
        h.u64(self.hog_tick.map_or(u64::MAX, |t| t as u64));
        h.u64(self.contacts as u64);
        h.u64(self.timed_out as u64);
        for f in self.brush_fatigue {
            h.u64(f as u64);
        }
        for c in self.last_cells {
            h.u64(c.map_or(u64::MAX, |i| i as u64));
        }
        h.u64(self.stones.len() as u64);
        for s in &self.stones {
            h.u64(s.id as u64);
            h.u64(s.team as u64);
            for v in [s.pos.x, s.pos.y, s.vel.x, s.vel.y, s.spin, s.turns] {
                h.fx(v);
            }
            h.u64(s.active as u64);
            h.u64(s.touched as u64);
        }
        h.u64(self.ice.cells.len() as u64);
        for (i, c) in &self.ice.cells {
            h.u64(*i as u64);
            h.u64(c.heat as u64);
            h.u64(c.updated as u64);
            h.u64(c.wear as u64);
        }
        h.finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn run(mut s: Sim, effort: u8) -> Sim {
        while !s.is_resting() {
            s.step(&[Sweep::centered(0, effort)]);
        }
        assert!(!s.timed_out);
        s
    }
    #[test]
    fn draw_curls_clockwise_and_stops() {
        let mut s = Sim::new(1);
        s.release(Release::draw()).unwrap();
        let s = run(s, 0);
        let a = &s.stones[0];
        assert!(a.pos.x > Fx::ratio(5, 10));
        assert!(s.tick > 4000 && s.tick < 9000);
        assert!(a.turns > Fx::int(2) && a.turns < Fx::int(4));
    }
    #[test]
    fn mirror_turn() {
        let mut a = Sim::new(2);
        let mut b = a.clone();
        let r = Release::draw();
        let mut l = r.clone();
        l.spin = -r.spin;
        a.release(r).unwrap();
        b.release(l).unwrap();
        let a = run(a, 0);
        let b = run(b, 0);
        assert_eq!(a.stones[0].pos.x, -b.stones[0].pos.x);
        assert_eq!(a.stones[0].pos.y, b.stones[0].pos.y);
    }
    #[test]
    fn sweeping_adds_distance() {
        let mut s = Sim::new(3);
        s.release(Release::draw()).unwrap();
        let a = run(s.clone(), 0);
        let b = run(s, 255);
        assert!(b.stones[0].pos.y > a.stones[0].pos.y + Fx::ratio(1, 10));
        assert!(b.stones[0].pos.x < a.stones[0].pos.x);
    }
    #[test]
    fn snapshot_resumes_exactly() {
        let mut a = Sim::new(4);
        a.ice.varied = true;
        a.release(Release::draw()).unwrap();
        for _ in 0..2000 {
            a.step(&[Sweep::centered(0, 255)]);
        }
        let mut b = a.clone();
        while !a.is_resting() {
            a.step(&[]);
            b.step(&[]);
            assert_eq!(a.hash(), b.hash());
        }
        assert_eq!(a, b);
    }
    #[test]
    fn rejects_hostile_release_without_overflow() {
        for raw in [i64::MIN, i64::MAX] {
            let mut r = Release::draw();
            r.vel.x = Fx(raw);
            assert!(r.validate().is_err());
        }
    }
    #[test]
    fn contact_conserves_linear_momentum_and_does_not_tunnel() {
        let mut s = Sim::new(0);
        s.stones = vec![
            Stone::resting(0, 0, V2::new(Fx::ZERO, Fx::ratio(-30, 100))),
            Stone::resting(1, 1, V2::ZERO),
        ];
        s.stones[0].vel = V2::new(Fx::ZERO, Fx::int(6));
        let before = s.stones[0].vel;
        let mut events = vec![];
        s.move_contacts(&mut events);
        assert_eq!(s.stones[0].vel + s.stones[1].vel, before);
        assert!(s.stones[1].vel.y > Fx::int(5));
        assert!((s.stones[1].pos - s.stones[0].pos).length() >= DIAMETER);
        assert_eq!(events.len(), 1);
    }
    #[test]
    fn spun_contact_reduces_energy_and_deflects_in_physical_direction() {
        let mut s = Sim::new(0);
        s.stones = vec![
            Stone::resting(0, 0, V2::new(Fx::ZERO, Fx::ratio(-30, 100))),
            Stone::resting(1, 1, V2::ZERO),
        ];
        s.stones[0].vel = V2::new(Fx::ZERO, Fx::int(6));
        s.stones[0].spin = Fx::ratio(1, 2);
        fn energy(stones: &[Stone]) -> Fx {
            let tau = Fx::ratio(6283185307, 1000000000);
            stones.iter().fold(Fx::ZERO, |sum, s| {
                sum + s.vel.dot(s.vel) / Fx::int(2)
                    + RADIUS * RADIUS * s.spin * s.spin * tau * tau / Fx::int(4)
            })
        }
        let before = energy(&s.stones);
        let mut events = vec![];
        s.move_contacts(&mut events);
        assert!(energy(&s.stones) <= before);
        // Clockwise running surface at the front moves right; friction transfers
        // rightward momentum to the struck stone and leftward reaction to shooter.
        assert!(s.stones[1].vel.x > Fx::ZERO);
        assert!(s.stones[0].spin < Fx::ratio(1, 2));
    }
    #[test]
    fn packed_chain_separates_after_each_tick() {
        let mut s = Sim::new(0);
        for id in 0..12 {
            s.stones.push(Stone::resting(
                id,
                id % 2,
                V2::new(Fx::ZERO, Fx::int(-4) + DIAMETER * Fx::int(id as i32)),
            ));
        }
        s.stones[0].vel = V2::new(Fx::ZERO, Fx::int(6));
        for _ in 0..120 {
            s.step(&[]);
            for (i, a) in s.stones.iter().enumerate() {
                for b in &s.stones[i + 1..] {
                    if a.active && b.active {
                        assert!(
                            (a.pos - b.pos).length() + Fx::ratio(5, 1000000) >= DIAMETER,
                            "overlap in packed chain"
                        );
                    }
                }
            }
        }
    }
    #[test]
    fn hash_includes_ice() {
        let a = Sim::new(1);
        let mut b = a.clone();
        b.ice.brush(V2::ZERO, 255, 0);
        assert_ne!(a.hash(), b.hash());
    }
}
