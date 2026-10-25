use curl_proto::session::{MAX_RECORDS, MAX_SPANS, Record, RecordedShot, SessionLog, SweepSpan};
use curl_sim::{MAX_STONES, Release, Sim, Sweep};

/// Recorder shared by native client and headless tools. No UI or filesystem IO.
#[derive(Clone)]
pub struct Practice {
    pub sim: Sim,
    pub log: SessionLog,
    active: Option<usize>,
    span_count: usize,
}
impl Practice {
    pub fn new(seed: u64) -> Self {
        Self {
            sim: Sim::new(seed),
            log: SessionLog::new(seed),
            active: None,
            span_count: 0,
        }
    }
    pub fn next_id(&self) -> Option<u8> {
        let id = self
            .sim
            .stones
            .iter()
            .map(|s| s.id)
            .max()
            .map_or(0, |id| id + 1);
        if (id as usize) < MAX_STONES {
            Some(id)
        } else {
            None
        }
    }
    pub fn release(&mut self, release: Release) -> Result<(), &'static str> {
        if self.log.records.len() >= MAX_RECORDS
            || self
                .log
                .records
                .iter()
                .filter(|r| matches!(r, Record::Shot(_)))
                .count()
                >= 256
        {
            return Err("practice log is full; start a new session");
        }
        if self.active.is_some() {
            return Err("shot still active");
        }
        self.sim.release(release.clone())?;
        self.active = Some(self.log.records.len());
        self.log.records.push(Record::Shot(RecordedShot {
            release,
            ticks: 0,
            sweeps: vec![],
            final_hash: None,
        }));
        Ok(())
    }
    pub fn step(&mut self, inputs: &[Sweep]) -> Result<(), &'static str> {
        let Some(index) = self.active else {
            return Ok(());
        };
        let mut seen = [false; 4];
        if inputs.len() > 4 {
            return Err("too many sweepers");
        }
        for input in inputs {
            if !input.valid() || seen[input.brush as usize] {
                return Err("invalid sweep input");
            }
            seen[input.brush as usize] = true;
        }
        let Record::Shot(shot) = &mut self.log.records[index] else {
            unreachable!()
        };
        // Reserve conservatively before mutation; at most four spans per tick.
        if self.span_count + inputs.len() > MAX_SPANS {
            return Err("practice sweep log is full");
        }
        for input in inputs {
            // Zero-effort samples still affect fatigue bookkeeping in the sim.
            if let Some(span) = shot
                .sweeps
                .iter_mut()
                .rev()
                .find(|s| s.input.brush == input.brush)
                && span.end == shot.ticks
                && span.input == *input
            {
                span.end += 1;
                continue;
            }
            shot.sweeps.push(SweepSpan {
                start: shot.ticks,
                end: shot.ticks + 1,
                input: *input,
            });
            self.span_count += 1;
        }
        // The canonical order is start then brush, independent of caller slice order.
        shot.sweeps.sort_by_key(|s| (s.start, s.input.brush));
        self.sim.step(inputs);
        shot.ticks += 1;
        if self.sim.timed_out {
            return Err("physics time budget exhausted");
        }
        if self.sim.is_resting() {
            shot.final_hash = Some(format!("{:016x}", self.sim.hash()));
            self.active = None;
        }
        Ok(())
    }
    pub fn idle(&mut self, ticks: u32) -> Result<(), &'static str> {
        if self.log.records.len() >= MAX_RECORDS {
            return Err("practice log is full");
        }
        self.sim.advance_idle(ticks)?;
        self.log.records.push(Record::Idle(ticks));
        Ok(())
    }
    pub fn clear_stones(&mut self) -> Result<(), &'static str> {
        if self.log.records.len() >= MAX_RECORDS {
            return Err("practice log is full");
        }
        self.sim.clear_stones()?;
        self.log.records.push(Record::ClearStones);
        Ok(())
    }
    pub fn from_log(log: SessionLog) -> Result<Self, String> {
        log.validate()?;
        let mut sim = Sim::new(log.seed);
        sim.ice.varied = log.varied_ice;
        let mut active = None;
        let mut span_count = 0;
        for (index, record) in log.records.iter().enumerate() {
            match record {
                Record::Idle(ticks) => sim.advance_idle(*ticks)?,
                Record::ClearStones => sim.clear_stones()?,
                Record::Shot(shot) => {
                    sim.release(shot.release.clone())?;
                    let mut next = 0;
                    let mut brushes: [Option<SweepSpan>; 4] = [None; 4];
                    for tick in 0..shot.ticks {
                        if sim.is_resting() {
                            return Err("record has ticks after rest".into());
                        }
                        while next < shot.sweeps.len() && shot.sweeps[next].start == tick {
                            let span = shot.sweeps[next];
                            brushes[span.input.brush as usize] = Some(span);
                            next += 1;
                        }
                        let inputs: Vec<_> = brushes
                            .iter()
                            .flatten()
                            .filter(|s| tick < s.end)
                            .map(|s| s.input)
                            .collect();
                        sim.step(&inputs);
                    }
                    if sim.timed_out {
                        return Err("record exceeded physics time budget".into());
                    }
                    match &shot.final_hash {
                        Some(hash)
                            if !sim.is_resting() || *hash != format!("{:016x}", sim.hash()) =>
                        {
                            return Err("session state hash mismatch".into());
                        }
                        None if sim.is_resting() => {
                            return Err("completed shot is missing hash".into());
                        }
                        None => active = Some(index),
                        _ => active = None,
                    }
                    span_count += shot.sweeps.len();
                }
            }
        }
        Ok(Self {
            sim,
            log,
            active,
            span_count,
        })
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn finish(p: &mut Practice) {
        while !p.sim.is_resting() {
            let id = p.sim.delivered.unwrap();
            p.step(&[Sweep::centered(id, 0)]).unwrap();
        }
    }
    #[test]
    fn continuous_ice_and_idle_replay_roundtrip() {
        let mut p = Practice::new(7);
        p.release(Release::draw()).unwrap();
        finish(&mut p);
        let ice = p.sim.ice.clone();
        let tick = p.sim.tick;
        p.idle(2400).unwrap();
        p.clear_stones().unwrap();
        assert_eq!(p.sim.ice, ice);
        assert_eq!(p.sim.tick, tick + 2400);
        p.release(Release::draw()).unwrap();
        finish(&mut p);
        let json = serde_json::to_vec(&p.log).unwrap();
        let restored = Practice::from_log(SessionLog::parse(&json).unwrap()).unwrap();
        assert_eq!(p.sim, restored.sim);
    }
    #[test]
    fn interrupted_throw_resumes_exactly() {
        let mut a = Practice::new(42);
        a.release(Release::draw()).unwrap();
        for _ in 0..2000 {
            a.step(&[Sweep::centered(0, 255)]).unwrap();
        }
        let mut b = Practice::from_log(a.log.clone()).unwrap();
        assert_eq!(a.sim.hash(), b.sim.hash());
        while !a.sim.is_resting() {
            a.step(&[]).unwrap();
            b.step(&[]).unwrap();
        }
        assert_eq!(a.sim, b.sim);
        assert_eq!(a.log, b.log);
    }
    #[test]
    fn held_sweep_compresses_without_loss() {
        let mut p = Practice::new(1);
        p.release(Release::draw()).unwrap();
        for _ in 0..2000 {
            p.step(&[Sweep::centered(0, 255)]).unwrap();
        }
        let Record::Shot(s) = &p.log.records[0] else {
            panic!()
        };
        assert_eq!(s.sweeps.len(), 1);
        assert_eq!(s.sweeps[0].end, 2000);
        assert_eq!(Practice::from_log(p.log.clone()).unwrap().sim, p.sim);
    }
    #[test]
    fn tampered_finished_hash_is_rejected() {
        let mut p = Practice::new(1);
        p.release(Release::draw()).unwrap();
        finish(&mut p);
        let Record::Shot(s) = &mut p.log.records[0] else {
            panic!()
        };
        s.final_hash = Some("0000000000000000".into());
        assert!(Practice::from_log(p.log).is_err());
    }
    #[test]
    fn cannot_clear_or_wait_during_flight() {
        let mut p = Practice::new(1);
        p.release(Release::draw()).unwrap();
        let before = p.sim.hash();
        assert!(p.clear_stones().is_err());
        assert!(p.idle(240).is_err());
        assert_eq!(before, p.sim.hash());
    }
    #[test]
    fn overlapping_spans_rejected() {
        let mut p = Practice::new(1);
        p.release(Release::draw()).unwrap();
        p.step(&[Sweep::centered(0, 255)]).unwrap();
        let Record::Shot(s) = &mut p.log.records[0] else {
            panic!()
        };
        s.sweeps.push(s.sweeps[0]);
        assert!(Practice::from_log(p.log).is_err());
    }
}
