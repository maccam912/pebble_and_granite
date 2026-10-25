//! Versioned replay/command boundary. Never deserialize a remote Sim directly.
use curl_fx::Hash64;
use curl_sim::{MAX_TICKS, MODEL_VERSION, Release, Sim, Stone, Sweep};
use serde::{Deserialize, Serialize};
pub const PROTOCOL_VERSION: u32 = 4;
pub const REPLAY_VERSION: u32 = 1;
pub const MAX_REPLAY_BYTES: usize = 4 * 1024 * 1024;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SweepFrame {
    pub tick: u32,
    pub inputs: Vec<Sweep>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Replay {
    pub schema: u32,
    pub model: u32,
    pub seed: u64,
    pub varied_ice: bool,
    pub initial: Vec<Stone>,
    pub release: Release,
    pub sweeps: Vec<SweepFrame>,
}
impl Replay {
    pub fn draw(seed: u64) -> Self {
        Self {
            schema: REPLAY_VERSION,
            model: MODEL_VERSION,
            seed,
            varied_ice: false,
            initial: vec![],
            release: Release::draw(),
            sweeps: vec![],
        }
    }
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() > MAX_REPLAY_BYTES {
            return Err("replay exceeds byte limit".into());
        }
        let replay: Self = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        replay.start()?;
        Ok(replay)
    }
    pub fn start(&self) -> Result<Sim, String> {
        if self.schema != REPLAY_VERSION || self.model != MODEL_VERSION {
            return Err("incompatible replay version".into());
        }
        if self.initial.len() > 15 || self.sweeps.len() > MAX_TICKS as usize {
            return Err("replay exceeds event limit".into());
        }
        let mut previous = None;
        for frame in &self.sweeps {
            if frame.tick >= MAX_TICKS
                || previous.is_some_and(|p| frame.tick <= p)
                || frame.inputs.len() > 4
            {
                return Err("invalid sweep timeline".into());
            }
            let mut seen = [false; 4];
            for s in &frame.inputs {
                if !s.valid() || seen[s.brush as usize] {
                    return Err("invalid sweep command".into());
                }
                seen[s.brush as usize] = true;
            }
            previous = Some(frame.tick);
        }
        let mut sim = Sim::new(self.seed);
        sim.ice.varied = self.varied_ice;
        for stone in &self.initial {
            sim.add_resting(stone.clone())?;
        }
        sim.release(self.release.clone())?;
        Ok(sim)
    }
    pub fn run(&self) -> Result<Outcome, String> {
        let mut sim = self.start()?;
        let mut next = 0;
        let mut trace = Hash64::default();
        trace.u64(sim.hash());
        while !sim.is_resting() {
            let inputs = if next < self.sweeps.len() && self.sweeps[next].tick == sim.tick {
                let i = next;
                next += 1;
                &self.sweeps[i].inputs[..]
            } else {
                &[]
            };
            sim.step(inputs);
            trace.u64(sim.hash());
        }
        if sim.timed_out {
            return Err("simulation exceeded time budget".into());
        }
        if next != self.sweeps.len() {
            return Err("sweep input after throw ended".into());
        }
        Ok(Outcome {
            trace: format!("{:016x}", trace.finish()),
            state: format!("{:016x}", sim.hash()),
            ticks: sim.tick,
            sim,
        })
    }
}
#[derive(Serialize)]
pub struct Outcome {
    pub trace: String,
    pub state: String,
    pub ticks: u32,
    pub sim: Sim,
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn replay_roundtrip() {
        let r = Replay::draw(7);
        let json = serde_json::to_vec(&r).unwrap();
        let b = Replay::parse(&json).unwrap();
        assert_eq!(r.run().unwrap().trace, b.run().unwrap().trace);
    }
    #[test]
    fn reject_bad_version() {
        let mut r = Replay::draw(0);
        r.model += 1;
        assert!(r.start().is_err());
    }
    #[test]
    fn reject_duplicate_ticks() {
        let mut r = Replay::draw(0);
        r.sweeps = vec![
            SweepFrame {
                tick: 1,
                inputs: vec![],
            },
            SweepFrame {
                tick: 1,
                inputs: vec![],
            },
        ];
        assert!(r.start().is_err());
    }
    #[test]
    fn reject_hostile_initial_state() {
        let mut r = Replay::draw(0);
        let mut s = Stone::resting(1, 1, curl_fx::V2::ZERO);
        s.pos.x = curl_fx::Fx(i64::MIN);
        r.initial.push(s);
        assert!(r.start().is_err());
    }
}

pub mod fixtures;
pub mod session;
