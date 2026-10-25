//! Presentation boundary: floats may leave this crate, never enter sim math.
use curl_fx::{Fx, V2};
use curl_sim::{Release, Sim, Sweep};
use godot::prelude::*;
struct Extension;
#[gdextension]
unsafe impl ExtensionLibrary for Extension {}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct CurlSession {
    sim: Sim,
    stroke: curl_input::Stroke,
    base: Base<RefCounted>,
}
#[godot_api]
impl IRefCounted for CurlSession {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            sim: Sim::new(42),
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
        self.sim = Sim::new(seed as u64);
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
        let mut r = Release::draw();
        r.vel = V2::new(Fx::ratio(broom_mm, 1000), -r.pos.y).unit() * Fx::ratio(speed_mm_s, 1000);
        r.spin = Fx::ratio(12 * turn, 100);
        match self.sim.release(r) {
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
            stone: 0,
            brush: 0,
            effort: effort as u8,
            lateral_mm: lateral_mm as i16,
            ahead_mm: ahead_mm as u16,
        };
        for _ in 0..count {
            self.sim.step(&[input]);
        }
    }
    #[func]
    fn frame(&self) -> VarDictionary {
        let mut frame = VarDictionary::new();
        let mut stones = Array::<VarDictionary>::new();
        for s in &self.sim.stones {
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
        frame.set("stones", &stones);
        frame.set("tick", self.sim.tick as i64);
        frame.set("resting", self.sim.is_resting());
        frame.set("contacts", self.sim.contacts as i64);
        frame.set("hog_tick", self.sim.hog_tick.map_or(-1, |t| t as i64));
        frame.set("timed_out", self.sim.timed_out);
        frame
    }
    #[func]
    fn state_hash(&self) -> GString {
        GString::from(&format!("{:016x}", self.sim.hash()))
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
