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
        if self.log.pending_delivery.is_some() {
            return Err("release the held delivery instead");
        }
        if self.log.records.len() >= MAX_RECORDS
            || self
                .log
                .records
                .iter()
                .filter(|r| matches!(r, Record::Shot(_) | Record::HogViolation { .. }))
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
    pub fn hog_violation(&mut self) -> Result<(), &'static str> {
        if self.active.is_some()
            || self.log.records.len() >= MAX_RECORDS
            || self
                .log
                .records
                .iter()
                .filter(|r| matches!(r, Record::Shot(_) | Record::HogViolation { .. }))
                .count()
                >= 256
        {
            return Err("practice hog violation unavailable");
        }
        let stone = self.next_id().ok_or("practice stones exhausted")?;
        let team = stone % 2;
        self.sim.hog_violation(stone, team)?;
        self.log.records.push(Record::HogViolation { stone, team });
        self.log.pending_delivery = None;
        Ok(())
    }
    pub fn begin_delivery(&mut self, target_mm_s: i64, broom_mm: i64) -> Result<(), &'static str> {
        let pending = curl_proto::session::PendingDelivery {
            target_mm_s,
            broom_mm,
            elapsed_ms: 0,
            line: None,
        };
        pending.validate()?;
        if self.active.is_some()
            || self.log.pending_delivery.is_some()
            || self.next_id().is_none()
            || self.log.records.len() >= MAX_RECORDS - 2
            || self
                .log
                .records
                .iter()
                .filter(|r| matches!(r, Record::Shot(_) | Record::HogViolation { .. }))
                .count()
                >= 256
        {
            return Err("cannot begin held practice delivery");
        }
        self.log.pending_delivery = Some(pending);
        Ok(())
    }
    pub fn begin_analog_delivery(
        &mut self,
        target_mm_s: i64,
        broom_mm: i64,
        line: curl_proto::session::DeliveryLine,
    ) -> Result<(), &'static str> {
        line.validate()?;
        self.begin_delivery(target_mm_s, broom_mm)?;
        self.log
            .pending_delivery
            .as_mut()
            .expect("begun delivery")
            .line = Some(line);
        Ok(())
    }
    pub fn advance_delivery(&mut self, ms: u32) -> Result<(), &'static str> {
        if ms > 60000 {
            return Err("delivery interval too large");
        }
        let Some(mut pending) = self.log.pending_delivery.clone() else {
            return Ok(());
        };
        let hog = curl_input::delivery::crossing_ms(pending.target_mm_s, true);
        let next_ms = pending.elapsed_ms.saturating_add(ms).min(hog);
        let ticks = next_ms * 240 / 1000 - pending.elapsed_ms * 240 / 1000;
        if ticks > 0 {
            self.idle(ticks)?;
        }
        pending.elapsed_ms = next_ms;
        self.log.pending_delivery = Some(pending);
        if next_ms == hog {
            self.hog_violation()?;
        }
        Ok(())
    }
    pub fn cancel_delivery(&mut self) -> Result<(), &'static str> {
        let pending = self
            .log
            .pending_delivery
            .as_ref()
            .ok_or("no held delivery")?;
        if pending.pose().in_play {
            return Err("in-play delivery cannot return to the hack");
        }
        self.log.pending_delivery = None;
        Ok(())
    }
    pub fn release_delivery(
        &mut self,
        trim_mm_s: i64,
        line_mm: i64,
        turn: i64,
    ) -> Result<(), &'static str> {
        let pending = self
            .log
            .pending_delivery
            .as_ref()
            .ok_or("no held delivery")?;
        if !(-70..=70).contains(&trim_mm_s)
            || !(-120..=120).contains(&line_mm)
            || !(-1..=1).contains(&turn)
            || (pending.line.is_some() && line_mm != 0)
        {
            return Err("invalid finishing gesture");
        }
        let pose = pending.pose();
        let id = self.next_id().ok_or("practice stones exhausted")?;
        let mut release = Release::draw();
        release.stone = id;
        release.team = id % 2;
        release.pos.x = curl_fx::Fx::ratio(pending.x_um(), 1_000_000);
        release.pos.y = curl_fx::Fx::ratio(pose.y_um, 1_000_000);
        let target = pending
            .line
            .as_ref()
            .map_or((pending.broom_mm + line_mm).clamp(-2200, 2200), |line| {
                line.target_mm(pending.broom_mm)
            });
        release.vel = curl_fx::V2::new(
            curl_fx::Fx::ratio(target, 1000) - release.pos.x,
            -release.pos.y,
        )
        .unit()
            * curl_fx::Fx::ratio(pose.speed_um_s + trim_mm_s * 1000, 1_000_000);
        release.spin = curl_fx::Fx::ratio(12 * turn, 100);
        let mut next = self.clone();
        next.log.pending_delivery = None;
        next.release(release)?;
        *self = next;
        Ok(())
    }
    pub fn hash(&self) -> u64 {
        let Some(pending) = &self.log.pending_delivery else {
            return self.sim.hash();
        };
        let mut hash = curl_fx::Hash64::default();
        hash.u64(self.sim.hash());
        hash.bytes(&serde_json::to_vec(pending).expect("delivery serialize"));
        hash.finish()
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
        if let Some(Record::Idle(previous)) = self.log.records.last_mut()
            && *previous + ticks <= curl_sim::HZ * 3600
        {
            *previous += ticks;
        } else {
            self.log.records.push(Record::Idle(ticks));
        }
        Ok(())
    }
    pub fn clear_stones(&mut self) -> Result<(), &'static str> {
        if self.log.pending_delivery.is_some() {
            return Err("delivery is still held");
        }
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
                Record::HogViolation { stone, team } => {
                    sim.hog_violation(*stone, *team)?;
                    active = None;
                }
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
        if log.pending_delivery.is_some()
            && (active.is_some()
                || !sim.is_resting()
                || sim.stones.len() >= MAX_STONES
                || sim.stones.iter().any(|s| s.id as usize + 1 >= MAX_STONES)
                || log
                    .records
                    .iter()
                    .filter(|r| matches!(r, Record::Shot(_) | Record::HogViolation { .. }))
                    .count()
                    >= 256)
        {
            return Err("pending delivery conflicts with recorded field".into());
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
    fn held_delivery_restores_and_cannot_rewind_after_tee() {
        let mut p = Practice::new(42);
        p.begin_delivery(2050, -900).unwrap();
        p.advance_delivery(2000).unwrap();
        let hash = p.hash();
        assert!(p.log.pending_delivery.as_ref().unwrap().pose().in_play);
        assert!(p.cancel_delivery().is_err());
        assert!(p.clear_stones().is_err());
        assert!(p.release(Release::draw()).is_err());
        assert_eq!(p.hash(), hash);
        let json = serde_json::to_vec(&p.log).unwrap();
        let mut restored = Practice::from_log(SessionLog::parse(&json).unwrap()).unwrap();
        assert_eq!(p.hash(), restored.hash());
        for item in [&mut p, &mut restored] {
            item.advance_delivery(200).unwrap();
            item.release_delivery(30, 0, -1).unwrap();
            for _ in 0..240 {
                item.step(&[]).unwrap();
            }
        }
        assert_eq!(p.hash(), restored.hash());
    }
    #[test]
    fn held_deadline_and_legacy_session_upgrade_are_bounded() {
        let mut a = Practice::new(42);
        let mut b = Practice::new(42);
        a.begin_delivery(2050, 0).unwrap();
        b.begin_delivery(2050, 0).unwrap();
        a.advance_delivery(6000).unwrap();
        for _ in 0..6000 {
            b.advance_delivery(1).unwrap();
        }
        assert_eq!(a.hash(), b.hash());
        assert_eq!(a.log, b.log);
        assert_eq!(a.next_id(), Some(1));
        assert!(a.log.pending_delivery.is_none());
        let mut old = serde_json::to_value(&a.log).unwrap();
        old["schema"] = 2.into();
        old.as_object_mut().unwrap().remove("pending_delivery");
        let upgraded = SessionLog::parse(&serde_json::to_vec(&old).unwrap()).unwrap();
        assert_eq!(upgraded.schema, curl_proto::session::SESSION_SCHEMA);
        assert_eq!(Practice::from_log(upgraded).unwrap().hash(), a.hash());
        let mut invalid = Practice::new(42);
        invalid.begin_delivery(2050, 0).unwrap();
        invalid.log.pending_delivery.as_mut().unwrap().elapsed_ms = u32::MAX;
        assert!(Practice::from_log(invalid.log).is_err());
    }
    #[test]
    fn practice_hog_faults_preserve_field_and_restore_consumed_ids() {
        let mut p = Practice::new(42);
        p.release(Release::draw()).unwrap();
        let hash = p.sim.hash();
        assert!(p.hog_violation().is_err());
        assert_eq!(p.sim.hash(), hash);
        finish(&mut p);
        let stone = p.sim.stones[0].clone();
        let ice = p.sim.ice.clone();
        p.hog_violation().unwrap();
        assert_eq!(p.next_id(), Some(2));
        assert_eq!(p.sim.stones[0], stone);
        assert_eq!(p.sim.ice, ice);
        let log = SessionLog::parse(&serde_json::to_vec(&p.log).unwrap()).unwrap();
        let restored = Practice::from_log(log).unwrap();
        assert_eq!(restored.sim.hash(), p.sim.hash());
        assert_eq!(restored.next_id(), Some(2));
        let mut old = serde_json::to_value(&p.log).unwrap();
        old["model"] = 2.into();
        assert!(SessionLog::parse(&serde_json::to_vec(&old).unwrap()).is_err());
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
