//! Command-only match journal. Restores validate by replaying the shared authority.
use crate::{Authority, Seat};
use curl_rules::{Phase, PowerPlay, RULES_VERSION, Remedy, Rules};
use curl_sim::{MAX_TICKS, MODEL_VERSION, Release, Sweep};
use serde::{Deserialize, Serialize};
use std::ops::Deref;
pub const MATCH_SCHEMA: u32 = 1;
const MAX_BYTES: usize = 16 * 1024 * 1024;
const MAX_RECORDS: usize = 20000;
const MAX_REPLAY_TICKS: u64 = 4_000_000;
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Brush {
    pub effort: u8,
    pub lateral_mm: i16,
    pub ahead_mm: u16,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", deny_unknown_fields)]
pub enum Record {
    Place {
        seat: Seat,
        own_house: bool,
        side: PowerPlay,
    },
    Order {
        team: u8,
        first: u8,
    },
    Release {
        seat: Seat,
        release: Release,
    },
    Step {
        ticks: u32,
        brush: Option<Brush>,
    },
    Sweep {
        seat: Seat,
        tick: u32,
        input: Sweep,
    },
    Think {
        ms: u32,
    },
    Choose {
        seat: Seat,
        remedy: Remedy,
    },
    NextEnd {},
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MatchLog {
    pub schema: u32,
    pub model: u32,
    pub rules_version: u32,
    pub seed: u64,
    pub rules: Rules,
    pub hammer: u8,
    pub records: Vec<Record>,
    pub hash: u64,
}
#[derive(Clone)]
pub struct RecordedMatch {
    authority: Authority,
    log: MatchLog,
    replay_ticks: u64,
}
impl Deref for RecordedMatch {
    type Target = Authority;
    fn deref(&self) -> &Authority {
        &self.authority
    }
}
impl RecordedMatch {
    pub fn new(seed: u64, rules: Rules, hammer: u8) -> Result<Self, &'static str> {
        let authority = Authority::new(seed, rules.clone(), hammer)?;
        Ok(Self {
            authority,
            log: MatchLog {
                schema: MATCH_SCHEMA,
                model: MODEL_VERSION,
                rules_version: RULES_VERSION,
                seed,
                rules,
                hammer,
                records: vec![],
                hash: 0,
            },
            replay_ticks: 0,
        })
    }
    pub fn json(&self) -> Result<String, String> {
        let mut log = self.log.clone();
        log.hash = self.authority.hash();
        let json = serde_json::to_string(&log).map_err(|e| e.to_string())?;
        if json.len() > MAX_BYTES {
            return Err("match save exceeds byte limit".into());
        }
        Ok(json)
    }
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() > MAX_BYTES {
            return Err("match save exceeds byte limit".into());
        }
        let log: MatchLog = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        if log.schema != MATCH_SCHEMA
            || log.model != MODEL_VERSION
            || log.rules_version != RULES_VERSION
            || log.records.len() > MAX_RECORDS
        {
            return Err("incompatible or oversized match log".into());
        }
        let budget: u64 = log
            .records
            .iter()
            .map(|r| {
                if let Record::Step { ticks, .. } = r {
                    *ticks as u64
                } else {
                    0
                }
            })
            .sum();
        if budget > MAX_REPLAY_TICKS {
            return Err("match replay tick limit exceeded".into());
        }
        let mut restored = Self::new(log.seed, log.rules, log.hammer)?;
        for record in log.records {
            restored.apply(record)?;
        }
        if restored.authority.hash() != log.hash {
            return Err("match state verification failed".into());
        }
        Ok(restored)
    }
    fn execute(a: &mut Authority, r: &Record) -> Result<(), &'static str> {
        match r {
            Record::Place {
                seat,
                own_house,
                side,
            } => a.place_mixed(*seat, *own_house, *side),
            Record::Order { team, first } => a.game.set_first_thrower(*team, *first),
            Record::Release { seat, release } => a.release(*seat, release.clone()),
            Record::Sweep { seat, tick, input } => a.sweep(*seat, *tick, *input).map(|_| ()),
            Record::Think { ms } => a.think(*ms),
            Record::Choose { seat, remedy } => a.choose(*seat, *remedy),
            Record::NextEnd {} => a.next_end(),
            Record::Step { ticks, brush } => {
                if *ticks == 0 || *ticks > MAX_TICKS {
                    return Err("invalid match step span");
                }
                for _ in 0..*ticks {
                    Self::tick(a, *brush)?;
                }
                Ok(())
            }
        }
    }
    fn tick(a: &mut Authority, brush: Option<Brush>) -> Result<(), &'static str> {
        if a.game.phase != Phase::InFlight {
            return Err("cannot step settled match");
        }
        if let Some(b) = brush {
            let input = Sweep {
                stone: a.sim.delivered.ok_or("no delivered stone")?,
                brush: 0,
                effort: b.effort,
                lateral_mm: b.lateral_mm,
                ahead_mm: b.ahead_mm,
            };
            if !input.valid() {
                return Err("invalid brush sample");
            }
            if a.sim.stones.iter().any(|s| s.id == input.stone && s.active) {
                a.sweep(
                    Seat {
                        team: a.game.delivering_team(),
                        position: a.game.throwing_seat(),
                    },
                    a.sim.tick,
                    input,
                )?;
            }
        }
        a.step()
    }
    fn append(&mut self, r: Record) {
        if let Some(previous) = self.log.records.last_mut() {
            match (previous, &r) {
                (Record::Step { ticks, brush }, Record::Step { ticks: n, brush: b })
                    if brush == b && *ticks + *n <= MAX_TICKS =>
                {
                    *ticks += *n;
                    return;
                }
                (Record::Think { ms }, Record::Think { ms: n }) if *ms + *n <= 60000 => {
                    *ms += *n;
                    return;
                }
                _ => {}
            }
        }
        self.log.records.push(r);
    }
    pub fn apply(&mut self, r: Record) -> Result<(), &'static str> {
        let ticks = if let Record::Step { ticks, .. } = &r {
            *ticks as u64
        } else {
            0
        };
        if self.log.records.len() >= MAX_RECORDS || self.replay_ticks + ticks > MAX_REPLAY_TICKS {
            return Err("match journal limit reached");
        }
        let mut next = self.authority.clone();
        Self::execute(&mut next, &r)?;
        self.authority = next;
        self.replay_ticks += ticks;
        self.append(r);
        Ok(())
    }
    pub fn advance(&mut self, count: u32, brush: Option<Brush>) -> Result<(), &'static str> {
        if count > 64 {
            return Err("too many live ticks");
        }
        if self.game.phase != Phase::InFlight || count == 0 {
            return Ok(());
        }
        if self.log.records.len() >= MAX_RECORDS
            || self.replay_ticks + count as u64 > MAX_REPLAY_TICKS
        {
            return Err("match journal limit reached");
        }
        let mut next = self.authority.clone();
        let mut ticks = 0;
        while ticks < count && next.game.phase == Phase::InFlight {
            Self::tick(&mut next, brush)?;
            ticks += 1;
        }
        self.authority = next;
        self.replay_ticks += ticks as u64;
        self.append(Record::Step { ticks, brush });
        Ok(())
    }
    pub fn release(&mut self, seat: Seat, release: Release) -> Result<(), &'static str> {
        self.apply(Record::Release { seat, release })
    }
    pub fn place_mixed(
        &mut self,
        seat: Seat,
        own_house: bool,
        side: PowerPlay,
    ) -> Result<(), &'static str> {
        self.apply(Record::Place {
            seat,
            own_house,
            side,
        })
    }
    pub fn order(&mut self, team: u8, first: u8) -> Result<(), &'static str> {
        self.apply(Record::Order { team, first })
    }
    pub fn think(&mut self, ms: u32) -> Result<(), &'static str> {
        if ms == 0 || self.game.phase != Phase::Calling {
            return Ok(());
        }
        if self.log.records.len() >= MAX_RECORDS {
            return Err("match journal limit reached");
        }
        // Authority::think checks before mutating; it needs no copy of the last
        // throw's sweep history on each idle render frame.
        self.authority.think(ms)?;
        self.append(Record::Think { ms });
        Ok(())
    }
    pub fn next_end(&mut self) -> Result<(), &'static str> {
        self.apply(Record::NextEnd {})
    }
    pub fn last_release_speed(&self) -> curl_fx::Fx {
        self.log
            .records
            .iter()
            .rev()
            .find_map(|r| {
                if let Record::Release { release, .. } = r {
                    Some(release.vel.length())
                } else {
                    None
                }
            })
            .unwrap_or(curl_fx::Fx::ZERO)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn game() -> RecordedMatch {
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
        m
    }
    fn release(m: &mut RecordedMatch) {
        m.release(
            Seat {
                team: m.game.delivering_team(),
                position: m.game.throwing_seat(),
            },
            Release::draw(),
        )
        .unwrap();
    }
    #[test]
    fn interrupted_swept_shot_continues_identically() {
        let mut m = game();
        m.order(0, 1).unwrap();
        m.think(1001).unwrap();
        release(&mut m);
        let brush = Some(Brush {
            effort: 200,
            lateral_mm: 0,
            ahead_mm: 180,
        });
        for _ in 0..20 {
            m.advance(64, brush).unwrap();
        }
        let json = m.json().unwrap();
        assert!(json.len() < 3000, "constant sweep must compress");
        let mut restored = RecordedMatch::parse(json.as_bytes()).unwrap();
        assert_eq!(restored.hash(), m.hash());
        while m.game.phase == Phase::InFlight {
            m.advance(64, None).unwrap();
            restored.advance(64, None).unwrap();
        }
        assert_eq!(restored.hash(), m.hash());
        assert_eq!(restored.game, m.game);
    }
    #[test]
    fn full_end_and_next_placement_restore() {
        let mut m = game();
        for _ in 0..10 {
            m.think(123).unwrap();
            release(&mut m);
            while m.game.phase == Phase::InFlight {
                m.advance(64, None).unwrap();
            }
        }
        m.next_end().unwrap();
        m.order(1, 1).unwrap();
        let seat = Seat {
            team: m.game.placement_team,
            position: 0,
        };
        m.place_mixed(seat, false, PowerPlay::Right).unwrap();
        let restored = RecordedMatch::parse(m.json().unwrap().as_bytes()).unwrap();
        assert_eq!(restored.hash(), m.hash());
        assert_eq!(restored.game, m.game);
        assert_eq!(restored.sim.ice, m.sim.ice);
    }
    #[test]
    fn invalid_command_and_tampered_save_do_not_mutate() {
        let mut m = game();
        let hash = m.hash();
        let json = m.json().unwrap();
        assert!(m.advance(65, None).is_err());
        assert!(
            m.apply(Record::Step {
                ticks: 100,
                brush: None
            })
            .is_err()
        );
        assert_eq!(m.hash(), hash);
        assert_eq!(m.json().unwrap(), json);
        let mut log: MatchLog = serde_json::from_str(&json).unwrap();
        log.hash ^= 1;
        assert!(RecordedMatch::parse(&serde_json::to_vec(&log).unwrap()).is_err());
        log.hash ^= 1;
        log.records.push(Record::Step {
            ticks: u32::MAX,
            brush: None,
        });
        assert!(RecordedMatch::parse(&serde_json::to_vec(&log).unwrap()).is_err());
        assert_eq!(m.hash(), hash);
    }
    #[test]
    fn late_sweep_replay_preserves_release_snapshot() {
        let mut m = game();
        release(&mut m);
        m.advance(20, None).unwrap();
        m.apply(Record::Sweep {
            seat: Seat {
                team: 0,
                position: 0,
            },
            tick: 10,
            input: Sweep::centered(2, 255),
        })
        .unwrap();
        let mut restored = RecordedMatch::parse(m.json().unwrap().as_bytes()).unwrap();
        m.advance(64, None).unwrap();
        restored.advance(64, None).unwrap();
        assert_eq!(m.hash(), restored.hash());
    }
}
