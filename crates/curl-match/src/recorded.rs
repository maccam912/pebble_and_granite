//! Command-only match journal. Restores validate by replaying the shared authority.
use crate::{Authority, Seat};
use base64::prelude::*;
use curl_rules::{Phase, PowerPlay, RULES_VERSION, Remedy, Rules};
use curl_sim::{MAX_TICKS, MODEL_VERSION, Release, Sweep};
use serde::{Deserialize, Serialize};
use std::ops::Deref;
use std::sync::Arc;
pub const MATCH_SCHEMA: u32 = 2;
const MAX_BYTES: usize = 16 * 1024 * 1024;
const MAX_RECORDS: usize = 2_000_000;
const BLOCK_RECORDS: usize = 256;
const BLOCK_BYTES: usize = 128 * 1024;
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
    BeginAnalogDelivery {
        seat: Seat,
        target_mm_s: i64,
        broom_mm: i64,
        line: curl_proto::session::DeliveryLine,
    },
    BeginDelivery {
        seat: Seat,
        target_mm_s: i64,
        broom_mm: i64,
    },
    ReleaseDelivery {
        seat: Seat,
        trim_mm_s: i64,
        line_mm: i64,
        turn: i64,
    },
    SuspendDelivery {
        seat: Seat,
        suspended: bool,
    },
    CancelDelivery {
        seat: Seat,
    },
    HogViolation {
        seat: Seat,
    },
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
    BrushSpan {
        seat: Seat,
        tick: u32,
        input: Sweep,
        count: u8,
    },
    Think {
        ms: u32,
    },
    Choose {
        seat: Seat,
        remedy: Remedy,
    },
    NextEnd {},
    Concede {
        team: u8,
    },
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct MatchLog {
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
    blocks: Arc<Vec<Arc<str>>>,
    sealed_records: usize,
    sealed_bytes: usize,
    last_speed: curl_fx::Fx,
    pub reviews: crate::review::ReviewBook,
}
type PreparedJournal = (MatchLog, Arc<Vec<Arc<str>>>, usize, usize);
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Archive {
    schema: u32,
    model: u32,
    rules_version: u32,
    seed: u64,
    rules: Rules,
    hammer: u8,
    blocks: Vec<String>,
    tail: Vec<Record>,
    hash: u64,
}
#[derive(Serialize)]
struct ArchiveView<'a> {
    schema: u32,
    model: u32,
    rules_version: u32,
    seed: u64,
    rules: &'a Rules,
    hammer: u8,
    blocks: Vec<&'a str>,
    tail: &'a [Record],
    hash: u64,
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
            blocks: Arc::new(Vec::new()),
            sealed_records: 0,
            sealed_bytes: 0,
            last_speed: curl_fx::Fx::ZERO,
            reviews: crate::review::ReviewBook::default(),
        })
    }
    pub fn json(&self) -> Result<String, String> {
        let archive = ArchiveView {
            schema: MATCH_SCHEMA,
            model: MODEL_VERSION,
            rules_version: RULES_VERSION,
            seed: self.log.seed,
            rules: &self.log.rules,
            hammer: self.log.hammer,
            blocks: self.blocks.iter().map(|b| b.as_ref()).collect(),
            tail: &self.log.records,
            hash: self.authority.hash(),
        };
        let json = serde_json::to_string(&archive).map_err(|e| e.to_string())?;
        if json.len() > MAX_BYTES {
            return Err("match save exceeds byte limit".into());
        }
        Ok(json)
    }
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        Self::parse_controlled(bytes, |_, _| true)
    }
    /// Called before decoding and between bounded records/blocks. Returning false
    /// cancels without publishing any partially reconstructed authority.
    pub fn parse_controlled(
        bytes: &[u8],
        mut progress: impl FnMut(usize, usize) -> bool,
    ) -> Result<Self, String> {
        let mut checkpoint = |done, total| {
            if progress(done, total) {
                Ok(())
            } else {
                Err("match restore cancelled")
            }
        };
        checkpoint(0, 0)?;
        if bytes.len() > MAX_BYTES {
            return Err("match save exceeds byte limit".into());
        }
        #[derive(Deserialize)]
        struct Version {
            schema: u32,
        }
        let version: Version = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        if version.schema == 1 {
            let log: MatchLog = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
            if log.model != MODEL_VERSION
                || log.rules_version != RULES_VERSION
                || log.records.len() > 20000
            {
                return Err("incompatible legacy match log".into());
            }
            let mut restored = Self::new(log.seed, log.rules, log.hammer)?;
            let total = log.records.len();
            for (done, record) in log.records.into_iter().enumerate() {
                checkpoint(done, total)?;
                restored.apply(record)?;
            }
            checkpoint(total, total)?;
            if restored.hash() != log.hash {
                return Err("match state verification failed".into());
            }
            return Ok(restored);
        }
        let archive: Archive = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        if archive.schema != MATCH_SCHEMA
            || archive.model != MODEL_VERSION
            || archive.rules_version != RULES_VERSION
            || archive.blocks.len() > MAX_RECORDS / BLOCK_RECORDS
            || archive.tail.len() > BLOCK_RECORDS
        {
            return Err("incompatible or oversized match log".into());
        }
        let mut restored = Self::new(archive.seed, archive.rules, archive.hammer)?;
        let total = archive.blocks.len() * BLOCK_RECORDS + archive.tail.len();
        let mut done = 0;
        for block in archive.blocks {
            checkpoint(done, total)?;
            let compressed = BASE64_STANDARD
                .decode(block)
                .map_err(|_| "invalid journal block encoding")?;
            let raw =
                miniz_oxide::inflate::decompress_to_vec_zlib_with_limit(&compressed, BLOCK_BYTES)
                    .map_err(|_| "invalid or oversized journal block")?;
            let records: Vec<Record> = serde_json::from_slice(&raw).map_err(|e| e.to_string())?;
            if records.len() != BLOCK_RECORDS {
                return Err("invalid journal block count".into());
            }
            for record in records {
                checkpoint(done, total)?;
                restored.apply(record)?;
                done += 1;
            }
        }
        for record in archive.tail {
            checkpoint(done, total)?;
            restored.apply(record)?;
            done += 1;
        }
        checkpoint(done, total)?;
        if restored.hash() != archive.hash {
            return Err("match state verification failed".into());
        }
        Ok(restored)
    }
    fn execute(
        a: &mut Authority,
        r: &Record,
        reviews: &mut crate::review::ReviewBook,
    ) -> Result<(), &'static str> {
        match r {
            Record::BeginAnalogDelivery {
                seat,
                target_mm_s,
                broom_mm,
                line,
            } => a.begin_analog_delivery(*seat, *target_mm_s, *broom_mm, line.clone()),
            Record::HogViolation { seat } => a.hog_violation(*seat),
            Record::Place {
                seat,
                own_house,
                side,
            } => a.place_mixed(*seat, *own_house, *side),
            Record::Order { team, first } => {
                if a.in_hand.is_some() {
                    return Err("delivery already started");
                }
                a.game.set_first_thrower(*team, *first)
            }
            Record::BeginDelivery {
                seat,
                target_mm_s,
                broom_mm,
            } => a.begin_delivery(*seat, *target_mm_s, *broom_mm),
            Record::ReleaseDelivery {
                seat,
                trim_mm_s,
                line_mm,
                turn,
            } => a.release_delivery(*seat, *trim_mm_s, *line_mm, *turn),
            Record::SuspendDelivery { seat, suspended } => a.suspend_delivery(*seat, *suspended),
            Record::CancelDelivery { seat } => a.cancel_delivery(*seat),
            Record::Release { seat, release } => a.release(*seat, release.clone()),
            Record::Sweep { seat, tick, input } => a.sweep(*seat, *tick, *input).map(|_| ()),
            Record::BrushSpan {
                seat,
                tick,
                input,
                count,
            } => a.sweep_span(*seat, *tick, *input, *count),
            Record::Think { ms } => a.think(*ms),
            Record::Choose { seat, remedy } => a.choose(*seat, *remedy),
            Record::NextEnd {} => a.next_end(),
            Record::Concede { team } => {
                a.game.concede(*team)?;
                a.in_hand = None;
                Ok(())
            }
            Record::Step { ticks, brush } => {
                if *ticks == 0 || *ticks > MAX_TICKS {
                    return Err("invalid match step span");
                }
                for _ in 0..*ticks {
                    Self::tick(a, *brush, reviews)?;
                }
                Ok(())
            }
        }
    }
    fn tick(
        a: &mut Authority,
        brush: Option<Brush>,
        reviews: &mut crate::review::ReviewBook,
    ) -> Result<(), &'static str> {
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
            if a.sim
                .stones
                .iter()
                .any(|s| s.id == input.stone && s.active && s.vel != curl_fx::V2::ZERO)
            {
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
        a.step()?;
        reviews.tick(&a.sim);
        Ok(())
    }
    fn prepare_append(&self, r: Record) -> Result<PreparedJournal, &'static str> {
        if self.sealed_records + self.log.records.len() >= MAX_RECORDS {
            return Err("match record limit reached");
        }
        let mut log = self.log.clone();
        let mut blocks = self.blocks.clone();
        let mut sealed_records = self.sealed_records;
        let mut sealed_bytes = self.sealed_bytes;
        if log.records.len() == BLOCK_RECORDS {
            let raw = serde_json::to_vec(&log.records).map_err(|_| "journal encoding failed")?;
            if raw.len() > BLOCK_BYTES {
                return Err("journal block too large");
            }
            let encoded =
                BASE64_STANDARD.encode(miniz_oxide::deflate::compress_to_vec_zlib(&raw, 3));
            // Reserve room for the bounded tail and JSON metadata/commas.
            if sealed_bytes + encoded.len() + blocks.len() * 4 > MAX_BYTES - BLOCK_BYTES {
                return Err("match byte limit reached");
            }
            sealed_bytes += encoded.len();
            sealed_records += log.records.len();
            Arc::make_mut(&mut blocks).push(Arc::from(encoded));
            log.records.clear();
        }
        Self::append(&mut log, r);
        Ok((log, blocks, sealed_records, sealed_bytes))
    }
    fn append(log: &mut MatchLog, r: Record) {
        if let Some(previous) = log.records.last_mut() {
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
        log.records.push(r);
    }
    pub fn apply(&mut self, r: Record) -> Result<(), &'static str> {
        let ticks = if let Record::Step { ticks, .. } = &r {
            *ticks as u64
        } else {
            0
        };
        if self.replay_ticks + ticks > MAX_REPLAY_TICKS {
            return Err("match journal limit reached");
        }
        let journal = self.prepare_append(r.clone())?;
        let mut next = self.authority.clone();
        let mut reviews = self.reviews.clone();
        Self::execute(&mut next, &r, &mut reviews)?;
        if matches!(&r, Record::Sweep { tick, .. } | Record::BrushSpan { tick, .. } if *tick < self.sim.tick)
        {
            reviews.changed_past();
        }
        reviews.transition(&self.authority, &next);
        if let Record::Release { release, .. } = &r {
            self.last_speed = release.vel.length();
        }
        if matches!(&r, Record::ReleaseDelivery { .. }) {
            self.last_speed = next
                .sim
                .stones
                .iter()
                .find(|s| Some(s.id) == next.sim.delivered)
                .map_or(curl_fx::Fx::ZERO, |s| s.vel.length());
        }
        if matches!(&r, Record::HogViolation { .. })
            || next
                .last_resolution
                .as_ref()
                .is_some_and(|r| r.violation == Some(curl_rules::Violation::HogRelease))
        {
            self.last_speed = curl_fx::Fx::ZERO;
        }
        self.authority = next;
        self.reviews = reviews;
        self.replay_ticks += ticks;
        (
            self.log,
            self.blocks,
            self.sealed_records,
            self.sealed_bytes,
        ) = journal;
        Ok(())
    }
    pub fn advance(&mut self, count: u32, brush: Option<Brush>) -> Result<(), &'static str> {
        if count > 64 {
            return Err("too many live ticks");
        }
        if self.game.phase != Phase::InFlight || count == 0 {
            return Ok(());
        }
        if self.replay_ticks + count as u64 > MAX_REPLAY_TICKS {
            return Err("match journal limit reached");
        }
        let mut next = self.authority.clone();
        let mut reviews = self.reviews.clone();
        let mut ticks = 0;
        while ticks < count && next.game.phase == Phase::InFlight {
            Self::tick(&mut next, brush, &mut reviews)?;
            ticks += 1;
        }
        let journal = self.prepare_append(Record::Step { ticks, brush })?;
        reviews.transition(&self.authority, &next);
        self.authority = next;
        self.reviews = reviews;
        self.replay_ticks += ticks as u64;
        (
            self.log,
            self.blocks,
            self.sealed_records,
            self.sealed_bytes,
        ) = journal;
        Ok(())
    }
    /// Local spatial input uses the same bounded, seat-owned spans as online
    /// play. Existing Step/BrushSpan records retain their original semantics.
    pub fn advance_targeted(
        &mut self,
        count: u32,
        seat: Seat,
        input: Option<Sweep>,
    ) -> Result<(), &'static str> {
        if count > 64 || input.is_some_and(|s| !s.valid()) {
            return Err("invalid targeted step");
        }
        let input = input.filter(|s| s.effort > 0);
        if input.is_none() {
            return self.advance(count, None);
        }
        let mut next = self.clone();
        let mut remaining = count;
        while remaining > 0 && next.game.phase == Phase::InFlight {
            let ticks = remaining.min(12);
            if let Some(input) = input
                && next
                    .sim
                    .stones
                    .iter()
                    .any(|s| s.id == input.stone && s.active && s.vel != curl_fx::V2::ZERO)
            {
                next.apply(Record::BrushSpan {
                    seat,
                    tick: next.sim.tick,
                    input,
                    count: ticks as u8,
                })?;
            }
            next.advance(ticks, None)?;
            remaining -= ticks;
        }
        *self = next;
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
        if self.in_hand.is_some() {
            return self.apply(Record::Think { ms });
        }
        let journal = self.prepare_append(Record::Think { ms })?;
        // Authority::think checks before mutating; it needs no copy of the last
        // throw's sweep history on each idle render frame.
        self.authority.think(ms)?;
        (
            self.log,
            self.blocks,
            self.sealed_records,
            self.sealed_bytes,
        ) = journal;
        Ok(())
    }
    pub fn next_end(&mut self) -> Result<(), &'static str> {
        self.apply(Record::NextEnd {})
    }
    pub fn last_release_speed(&self) -> curl_fx::Fx {
        self.last_speed
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
    fn controlled_restore_progress_and_cancellation_cross_blocks() {
        let mut m = game();
        release(&mut m);
        // Alternating efforts prevent adjacent records from being coalesced.
        for i in 0..300 {
            m.advance(
                1,
                Some(Brush {
                    effort: 180 + (i % 2) as u8,
                    lateral_mm: 0,
                    ahead_mm: 180,
                }),
            )
            .unwrap();
        }
        assert!(!m.blocks.is_empty());
        let json = m.json().unwrap();
        let mut previous = 0;
        let mut final_total = 0;
        let restored = RecordedMatch::parse_controlled(json.as_bytes(), |done, total| {
            assert!(done >= previous && done <= total);
            previous = done;
            final_total = total;
            true
        })
        .unwrap();
        assert!(final_total > BLOCK_RECORDS);
        assert_eq!(previous, final_total);
        assert_eq!(restored.hash(), m.hash());
        for stop_at in [0, 1, 256, 270] {
            let mut last = 0;
            let error = RecordedMatch::parse_controlled(json.as_bytes(), |done, _| {
                last = done;
                done < stop_at
            })
            .err()
            .unwrap();
            assert_eq!(error, "match restore cancelled");
            assert_eq!(last, stop_at);
        }
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
        let mut log: serde_json::Value = serde_json::from_str(&json).unwrap();
        log["hash"] = (log["hash"].as_u64().unwrap() ^ 1).into();
        assert!(RecordedMatch::parse(&serde_json::to_vec(&log).unwrap()).is_err());
        log["hash"] = (log["hash"].as_u64().unwrap() ^ 1).into();
        log["tail"].as_array_mut().unwrap().push(
            serde_json::to_value(Record::Step {
                ticks: u32::MAX,
                brush: None,
            })
            .unwrap(),
        );
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
    #[test]
    fn sealed_sweep_history_restores_and_clones_share_blocks() {
        let mut m = game();
        release(&mut m);
        for i in 0..400 {
            m.apply(Record::Sweep {
                seat: Seat {
                    team: 0,
                    position: 0,
                },
                tick: m.sim.tick,
                input: Sweep::centered(2, (i % 255) as u8),
            })
            .unwrap();
            m.advance(4, None).unwrap();
        }
        assert!(m.blocks.len() >= 3);
        let copy = m.clone();
        assert!(Arc::ptr_eq(&copy.blocks, &m.blocks));
        let json = m.json().unwrap();
        assert!(
            json.len() < 16000,
            "sampled sweeps must compact: {}",
            json.len()
        );
        let restored = RecordedMatch::parse(json.as_bytes()).unwrap();
        assert_eq!(restored.hash(), m.hash());
        assert_eq!(restored.last_release_speed(), m.last_release_speed());
        assert_eq!(copy.hash(), m.hash());
    }
    #[test]
    fn brush_spans_match_tick_samples_and_preserve_consumed_overlap() {
        let mut span = game();
        release(&mut span);
        span.advance(20, None).unwrap();
        let mut individual = span.clone();
        let seat = Seat {
            team: 0,
            position: 1,
        };
        let input = Sweep::centered(2, 220);
        span.apply(Record::BrushSpan {
            seat,
            tick: 8,
            input,
            count: 12,
        })
        .unwrap();
        for tick in 8..20 {
            individual
                .apply(Record::Sweep { seat, tick, input })
                .unwrap();
        }
        assert_eq!(span.hash(), individual.hash());
        span.apply(Record::BrushSpan {
            seat,
            tick: 5,
            input,
            count: 12,
        })
        .unwrap();
        for tick in 5..8 {
            individual
                .apply(Record::Sweep { seat, tick, input })
                .unwrap();
        }
        assert_eq!(span.hash(), individual.hash());
        assert!(
            span.apply(Record::BrushSpan {
                seat,
                tick: 20,
                input,
                count: 13
            })
            .is_err()
        );
        span.advance(40, None).unwrap();
        individual.advance(40, None).unwrap();
        // Old spans retime their starting tick once, then keep their duration.
        span.apply(Record::BrushSpan {
            seat,
            tick: 0,
            input,
            count: 12,
        })
        .unwrap();
        for tick in 60..72 {
            individual
                .apply(Record::Sweep { seat, tick, input })
                .unwrap();
        }
        assert_eq!(span.hash(), individual.hash());
        let restored = RecordedMatch::parse(span.json().unwrap().as_bytes()).unwrap();
        assert_eq!(restored.hash(), span.hash());
    }
    #[test]
    fn legacy_saves_migrate_and_expansion_bombs_are_bounded() {
        let mut m = game();
        m.think(137).unwrap();
        let mut legacy = m.log.clone();
        legacy.schema = 1;
        legacy.hash = m.hash();
        let restored = RecordedMatch::parse(&serde_json::to_vec(&legacy).unwrap()).unwrap();
        assert_eq!(restored.hash(), m.hash());
        assert!(restored.json().unwrap().contains("\"schema\":2"));
        let mut archive: serde_json::Value = serde_json::from_str(&m.json().unwrap()).unwrap();
        let bomb = BASE64_STANDARD.encode(miniz_oxide::deflate::compress_to_vec_zlib(
            &vec![0; BLOCK_BYTES + 1],
            3,
        ));
        archive["blocks"] = serde_json::json!([bomb]);
        assert!(RecordedMatch::parse(&serde_json::to_vec(&archive).unwrap()).is_err());
        archive["blocks"] = serde_json::json!(["invalid!"]);
        assert!(RecordedMatch::parse(&serde_json::to_vec(&archive).unwrap()).is_err());
    }
    #[test]
    fn full_match_sample_capacity_stays_below_transfer_limit() {
        // Storage-capacity fixture, not a physics/calibration claim: 80 throws,
        // 30 s each, two varying brush streams sampled at 60 Hz, plus step spans.
        let mut m = game();
        let mut random = curl_fx::Rng(7);
        for tick in (0..80 * 30 * 240).step_by(4) {
            for team in 0..2 {
                let value = random.next_u64();
                let record = Record::Sweep {
                    seat: Seat {
                        team,
                        position: (value % 2) as u8,
                    },
                    tick,
                    input: Sweep {
                        stone: 2,
                        brush: 0,
                        effort: value as u8,
                        lateral_mm: ((value >> 8) % 701) as i16 - 350,
                        ahead_mm: 80 + ((value >> 20) % 621) as u16,
                    },
                };
                let prepared = m.prepare_append(record).unwrap();
                (m.log, m.blocks, m.sealed_records, m.sealed_bytes) = prepared;
            }
            let prepared = m
                .prepare_append(Record::Step {
                    ticks: 4,
                    brush: None,
                })
                .unwrap();
            (m.log, m.blocks, m.sealed_records, m.sealed_bytes) = prepared;
        }
        let json = m.json().unwrap();
        assert!(m.sealed_records > 400_000);
        assert!(
            json.len() < 8 * 1024 * 1024,
            "capacity fixture bytes={}",
            json.len()
        );
        eprintln!(
            "80-throw two-brush capacity fixture: {} bytes, {} records",
            json.len(),
            m.sealed_records + m.log.records.len()
        );
    }
    #[test]
    #[ignore = "manual release-profile latency measurement"]
    fn profile_continuous_late_sweeping() {
        let mut m = game();
        release(&mut m);
        let start = std::time::Instant::now();
        let mut spans = 0;
        let mut slowest = std::time::Duration::ZERO;
        while m.game.phase == Phase::InFlight {
            m.advance(12, None).unwrap();
            if m.game.phase != Phase::InFlight {
                break;
            }
            let began = std::time::Instant::now();
            m.apply(Record::BrushSpan {
                seat: Seat {
                    team: 0,
                    position: 1,
                },
                tick: m.sim.tick - 12,
                input: Sweep::centered(2, 255),
                count: 12,
            })
            .unwrap();
            slowest = slowest.max(began.elapsed());
            spans += 1;
        }
        assert_eq!(
            m.hash(),
            0x654eaff0d4d4fb1d,
            "model-3 profile trajectory changed"
        );
        eprintln!(
            "LATE_SWEEP_PROFILE spans={spans} simulated_seconds={:.3} wall_ms={:.3} worst_span_ms={:.3} hash={:016x}",
            (m.sim.tick - m.sim.release_tick) as f64 / 240.0,
            start.elapsed().as_secs_f64() * 1000.0,
            slowest.as_secs_f64() * 1000.0,
            m.hash()
        );
    }
}
