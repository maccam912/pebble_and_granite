//! Session files record commands, including time spent between throws. Sweep
//! spans compress held inputs without losing tick precision or cooling history.
use curl_sim::{MAX_TICKS, MODEL_VERSION, Release, Sweep};
use serde::{Deserialize, Serialize};
pub const SESSION_SCHEMA: u32 = 2;
pub const MAX_SESSION_BYTES: usize = 16 * 1024 * 1024;
pub const MAX_RECORDS: usize = 1024;
pub const MAX_SPANS: usize = 100_000;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SweepSpan {
    pub start: u32,
    pub end: u32,
    pub input: Sweep,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RecordedShot {
    pub release: Release,
    pub ticks: u32,
    pub sweeps: Vec<SweepSpan>,
    pub final_hash: Option<String>,
}
impl RecordedShot {
    pub fn validate(&self) -> Result<(), &'static str> {
        self.release.validate()?;
        if self.ticks > MAX_TICKS || self.sweeps.len() > MAX_TICKS as usize * 4 {
            return Err("shot limit exceeded");
        }
        let mut ends = [0; 4];
        let mut previous = None;
        for span in &self.sweeps {
            if !span.input.valid() || span.start >= span.end || span.end > self.ticks {
                return Err("invalid sweep span");
            }
            let key = (span.start, span.input.brush);
            if previous.is_some_and(|p| key <= p) || span.start < ends[span.input.brush as usize] {
                return Err("overlapping or unordered sweep spans");
            }
            ends[span.input.brush as usize] = span.end;
            previous = Some(key);
        }
        if self
            .final_hash
            .as_ref()
            .is_some_and(|h| h.len() != 16 || !h.bytes().all(|b| b.is_ascii_hexdigit()))
        {
            return Err("invalid recorded hash");
        }
        Ok(())
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", deny_unknown_fields)]
pub enum Record {
    HogViolation { stone: u8, team: u8 },
    Shot(RecordedShot),
    Idle(u32),
    ClearStones,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SessionLog {
    pub schema: u32,
    pub model: u32,
    pub seed: u64,
    pub varied_ice: bool,
    pub records: Vec<Record>,
}
impl SessionLog {
    pub fn new(seed: u64) -> Self {
        Self {
            schema: SESSION_SCHEMA,
            model: MODEL_VERSION,
            seed,
            varied_ice: false,
            records: vec![],
        }
    }
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() > MAX_SESSION_BYTES {
            return Err("session byte limit exceeded".into());
        }
        let log: Self = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        log.validate()?;
        Ok(log)
    }
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.schema != SESSION_SCHEMA || self.model != MODEL_VERSION {
            return Err("incompatible session version");
        }
        if self.records.len() > MAX_RECORDS {
            return Err("session record limit exceeded");
        }
        let mut count = 0;
        let mut spans = 0;
        for (i, record) in self.records.iter().enumerate() {
            match record {
                Record::HogViolation { stone, team } => {
                    if *stone as usize >= curl_sim::MAX_STONES || *team > 1 {
                        return Err("invalid hog violation identity");
                    }
                    count += 1;
                }
                Record::Shot(shot) => {
                    shot.validate()?;
                    count += 1;
                    spans += shot.sweeps.len();
                    if shot.final_hash.is_none() && i + 1 != self.records.len() {
                        return Err("unfinished shot must be last");
                    }
                }
                Record::Idle(ticks) if *ticks > curl_sim::HZ * 3600 => {
                    return Err("idle limit exceeded");
                }
                _ => {}
            }
        }
        if count > 256 || spans > MAX_SPANS {
            return Err("session simulation budget exceeded");
        }
        Ok(())
    }
}
