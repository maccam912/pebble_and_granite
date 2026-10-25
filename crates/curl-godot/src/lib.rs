//! Presentation boundary: floats may leave this crate, never enter sim math.
use curl_fx::{Fx, V2};
use curl_match::practice::Practice;
use curl_proto::session::SessionLog;
use curl_sim::{Release, Sweep};
use godot::prelude::*;
struct Extension;
#[gdextension]
unsafe impl ExtensionLibrary for Extension {}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct CurlSession {
    practice: Practice,
    stroke: curl_input::Stroke,
    base: Base<RefCounted>,
}
#[godot_api]
impl IRefCounted for CurlSession {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            practice: Practice::new(42),
            stroke: curl_input::Stroke::default(),
            base,
        }
    }
}
fn render(n: Fx) -> f64 {
    n.raw() as f64 / 4294967296.0
}
#[godot_api]
impl CurlSession {
    #[func]
    fn reset(&mut self, seed: i64) {
        self.practice = Practice::new(seed as u64);
        self.stroke.cancel();
    }
    /// All public input units are integers: mm/s, millimetres, milli-revolutions/s.
    #[func]
    fn deliver(&mut self, speed_mm_s: i64, broom_mm: i64, turn: i64) -> GString {
        if !(100..=6000).contains(&speed_mm_s)
            || !(-2200..=2200).contains(&broom_mm)
            || ![-1, 1].contains(&turn)
        {
            return "Invalid delivery".into();
        }
        let Some(id) = self.practice.next_id() else {
            return "Clear the stones before the next throw".into();
        };
        let mut r = Release::draw();
        r.stone = id;
        r.team = id % 2;
        r.vel = V2::new(Fx::ratio(broom_mm, 1000), -r.pos.y).unit() * Fx::ratio(speed_mm_s, 1000);
        r.spin = Fx::ratio(12 * turn, 100);
        match self.practice.release(r) {
            Ok(()) => GString::new(),
            Err(e) => e.into(),
        }
    }
    #[func]
    fn step_ticks(&mut self, count: i64, effort: i64, lateral_mm: i64, ahead_mm: i64) {
        if !(0..=64).contains(&count)
            || !(0..=255).contains(&effort)
            || !(-350..=350).contains(&lateral_mm)
            || !(80..=700).contains(&ahead_mm)
        {
            return;
        }
        let input = Sweep {
            stone: self.practice.sim.delivered.unwrap_or(0),
            brush: 0,
            effort: effort as u8,
            lateral_mm: lateral_mm as i16,
            ahead_mm: ahead_mm as u16,
        };
        for _ in 0..count {
            if let Err(error) = self.practice.step(&[input]) {
                godot_error!("Practice step: {error}");
                break;
            }
        }
    }
    #[func]
    fn frame(&self) -> VarDictionary {
        let mut frame = VarDictionary::new();
        let mut stones = Array::<VarDictionary>::new();
        for s in &self.practice.sim.stones {
            let mut d = VarDictionary::new();
            d.set("id", s.id as i64);
            d.set("team", s.team as i64);
            d.set(
                "position",
                Vector2::new(render(s.pos.x) as f32, render(s.pos.y) as f32),
            );
            d.set("speed", render(s.vel.length()));
            d.set("turns", render(s.turns));
            d.set("active", s.active);
            stones.push(&d);
        }
        let last_release = self.practice.log.records.iter().rev().find_map(|r| {
            if let curl_proto::session::Record::Shot(s) = r {
                Some(s.release.vel.length())
            } else {
                None
            }
        });
        frame.set("release_speed", last_release.map_or(0.0, render));
        frame.set("stones", &stones);
        frame.set(
            "tick",
            (self.practice.sim.tick - self.practice.sim.release_tick) as i64,
        );
        frame.set("global_tick", self.practice.sim.tick as i64);
        frame.set(
            "delivered",
            self.practice.sim.delivered.map_or(-1, |id| id as i64),
        );
        frame.set("can_deliver_next", self.practice.next_id().is_some());
        frame.set("ice_cells", self.practice.sim.ice.cells.len() as i64);
        frame.set("resting", self.practice.sim.is_resting());
        frame.set("contacts", self.practice.sim.contacts as i64);
        frame.set(
            "hog_tick",
            self.practice
                .sim
                .hog_tick
                .map_or(-1, |t| (t - self.practice.sim.release_tick) as i64),
        );
        frame.set("timed_out", self.practice.sim.timed_out);
        frame
    }
    #[func]
    fn golden_trace(&self) -> GString {
        match curl_proto::fixtures::golden_text() {
            Ok(text) => GString::from(&text),
            Err(e) => GString::from(&e),
        }
    }
    #[func]
    fn state_hash(&self) -> GString {
        GString::from(&format!("{:016x}", self.practice.sim.hash()))
    }

    #[func]
    fn prepare_next(&mut self, clear: bool) -> GString {
        let mut next = self.practice.clone();
        if clear {
            if let Err(e) = next.clear_stones() {
                return e.into();
            }
        }
        if let Err(e) = next.idle(480) {
            return e.into();
        }
        self.practice = next;
        self.stroke.cancel();
        GString::new()
    }
    #[func]
    fn session_json(&self) -> GString {
        match serde_json::to_string(&self.practice.log) {
            Ok(json) => GString::from(&json),
            Err(e) => {
                godot_error!("Session serialize: {e}");
                GString::new()
            }
        }
    }
    #[func]
    fn load_session(&mut self, json: GString) -> GString {
        let parsed = SessionLog::parse(json.to_string().as_bytes()).and_then(Practice::from_log);
        match parsed {
            Ok(practice) => {
                self.practice = practice;
                self.stroke.cancel();
                GString::new()
            }
            Err(e) => GString::from(&e),
        }
    }
    #[func]
    fn grip(&mut self, us: i64, x: i64, y: i64, one_push: bool) {
        self.stroke.one_push = one_push;
        self.stroke.grip(curl_input::Sample {
            us: us.max(0) as u64,
            x,
            y,
        });
    }
    #[func]
    fn motion(&mut self, us: i64, x: i64, y: i64) {
        self.stroke.sample(curl_input::Sample {
            us: us.max(0) as u64,
            x,
            y,
        });
    }
    #[func]
    fn stroke_phase(&self) -> GString {
        GString::from(&format!("{:?}", self.stroke.phase))
    }
    #[func]
    fn cancel_stroke(&mut self) {
        self.stroke.cancel();
    }
    #[func]
    fn lift(&mut self, us: i64, x: i64, y: i64) -> VarDictionary {
        let r = self.stroke.release(curl_input::Sample {
            us: us.max(0) as u64,
            x,
            y,
        });
        let mut d = VarDictionary::new();
        d.set("valid", r.valid);
        d.set("speed_mm_s", r.speed_mm_s);
        d.set("line_mm", r.line_mm);
        d.set("push_mm_s", r.push_mm_s);
        d.set("drive_us", r.drive_us as i64);
        d
    }
}
