//! Session files record commands, including time spent between throws. Sweep
//! spans compress held inputs without losing tick precision or cooling history.
use curl_sim::{MAX_TICKS, MODEL_VERSION, Release, Sweep};
use serde::{Deserialize, Serialize};
pub const SESSION_SCHEMA: u32 = 3;
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
pub struct DeliveryLine {
    pub x_mm: i64,
    pub aim_mm: i64,
}
impl DeliveryLine {
    pub fn validate(&self) -> Result<(), &'static str> {
        if !(-450..=450).contains(&self.x_mm) || !(-1500..=1500).contains(&self.aim_mm) {
            return Err("invalid analog delivery line");
        }
        Ok(())
    }
    pub fn target_mm(&self, broom_mm: i64) -> i64 {
        (broom_mm + self.aim_mm).clamp(-2200, 2200)
    }
    pub fn x_um(&self, broom_mm: i64, y_um: i64) -> i64 {
        let start = curl_input::delivery::START_Y_UM;
        let x = self.x_mm * 1000;
        x + (y_um - start) * (self.target_mm(broom_mm) * 1000 - x) / -start
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PendingDelivery {
    pub target_mm_s: i64,
    pub broom_mm: i64,
    pub elapsed_ms: u32,
    // None retains the exact behavior and serialized bytes of old held saves.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub line: Option<DeliveryLine>,
}
impl PendingDelivery {
    pub fn validate(&self) -> Result<(), &'static str> {
        if let Some(line) = &self.line {
            line.validate()?;
        }
        if !(1500..=5000).contains(&self.target_mm_s)
            || !(-2200..=2200).contains(&self.broom_mm)
            || self.elapsed_ms >= curl_input::delivery::crossing_ms(self.target_mm_s, true)
        {
            return Err("invalid pending delivery");
        }
        Ok(())
    }
    pub fn pose(&self) -> curl_input::delivery::Pose {
        curl_input::delivery::slide_pose(self.target_mm_s, self.elapsed_ms as u64 * 240 / 1000)
    }
    pub fn x_um(&self) -> i64 {
        self.line
            .as_ref()
            .map_or(0, |line| line.x_um(self.broom_mm, self.pose().y_um))
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SessionLog {
    pub schema: u32,
    pub model: u32,
    pub seed: u64,
    pub varied_ice: bool,
    pub records: Vec<Record>,
    #[serde(default)]
    pub pending_delivery: Option<PendingDelivery>,
}
impl SessionLog {
    pub fn new(seed: u64) -> Self {
        Self {
            schema: SESSION_SCHEMA,
            model: MODEL_VERSION,
            seed,
            varied_ice: false,
            records: vec![],
            pending_delivery: None,
        }
    }
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() > MAX_SESSION_BYTES {
            return Err("session byte limit exceeded".into());
        }
        let mut log: Self = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        // Schema 2 used the same model-3 shot records and had no held delivery.
        if log.schema == 2 && log.pending_delivery.is_none() {
            log.schema = SESSION_SCHEMA;
        }
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
        if let Some(pending) = &self.pending_delivery {
            pending.validate()?;
            if self.records.len() >= MAX_RECORDS - 1 {
                return Err("no room to finish pending delivery");
            }
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
