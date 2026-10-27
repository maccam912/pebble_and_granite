//! Presentation boundary: floats may leave this crate, never enter sim math.
use curl_fx::{Fx, V2};
use curl_match::{
    Seat,
    practice::Practice,
    recorded::{Brush, RecordedMatch},
};
use curl_proto::session::SessionLog;
use curl_rules::{Phase, PowerPlay, Rules};
use curl_sim::{Release, Sweep};
use godot::prelude::*;
#[derive(PartialEq, Eq)]
struct AiContext {
    end: u8,
    delivered: u8,
    stones: Vec<curl_sim::Stone>,
    ice: curl_sim::Ice,
}
impl AiContext {
    fn of(game: &RecordedMatch) -> Self {
        Self {
            end: game.game.end,
            delivered: game.game.delivered,
            stones: game.sim.stones.clone(),
            ice: game.sim.ice.clone(),
        }
    }
    fn matches(&self, game: &RecordedMatch) -> bool {
        game.game.phase == Phase::Calling && game.in_hand.is_none() && *self == Self::of(game)
    }
}
struct AiTask {
    context: AiContext,
    worker: std::thread::JoinHandle<Result<curl_match::ai::Plan, &'static str>>,
}
struct Extension;
#[gdextension]
unsafe impl ExtensionLibrary for Extension {}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct CurlSession {
    ai_task: Option<AiTask>,
    ai_plan: Option<(AiContext, curl_match::ai::Plan)>,
    solo_target: V2,
    practice: Practice,
    game: Option<RecordedMatch>,
    match_release_speed: Fx,
    stroke: curl_input::delivery::Delivery,
    scrub: curl_input::sweep::Scrub,
    base: Base<RefCounted>,
}
#[godot_api]
impl IRefCounted for CurlSession {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            ai_task: None,
            ai_plan: None,
            solo_target: V2::ZERO,
            practice: Practice::new(42),
            game: None,
            match_release_speed: Fx::ZERO,
            stroke: curl_input::delivery::Delivery::default(),
            scrub: curl_input::sweep::Scrub::default(),
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
        self.ai_task = None;
        self.ai_plan = None;
        self.game = None;
        self.practice = Practice::new(seed as u64);
        self.stroke.cancel();
    }
    /// All public input units are integers: mm/s, millimetres, milli-revolutions/s.
    #[func]
    fn deliver(&mut self, speed_mm_s: i64, broom_mm: i64, turn: i64) -> GString {
        let r = match input_release(speed_mm_s, broom_mm, turn) {
            Ok(release) => release,
            Err(error) => return error.into(),
        };
        self.apply_delivery(r)
    }
    #[func]
    fn deliver_slide(&mut self, speed_um_s: i64, y_um: i64, broom_mm: i64, turn: i64) -> GString {
        let r = match input_release_at(speed_um_s, y_um, broom_mm, turn) {
            Ok(release) => release,
            Err(error) => return error.into(),
        };
        self.apply_delivery(r)
    }
    fn apply_delivery(&mut self, mut r: Release) -> GString {
        self.solo_target = V2::ZERO;
        let id = if let Some(a) = &self.game {
            a.game.next_stone_id()
        } else {
            let Some(id) = self.practice.next_id() else {
                return "Clear the stones before the next throw".into();
            };
            id
        };
        r.stone = id;
        r.team = id % 2;
        let result = if let Some(a) = &mut self.game {
            let speed = r.vel.length();
            let result = a.release(
                Seat {
                    team: a.game.delivering_team(),
                    position: a.game.throwing_seat(),
                },
                r,
            );
            if result.is_ok() {
                self.match_release_speed = speed;
            }
            result
        } else {
            self.practice.release(r)
        };
        match result {
            Ok(()) => GString::new(),
            Err(e) => e.into(),
        }
    }
    #[func]
    fn hog_violation(&mut self) -> GString {
        let result = if let Some(game) = &mut self.game {
            let seat = Seat {
                team: game.game.delivering_team(),
                position: game.game.throwing_seat(),
            };
            game.apply(curl_match::recorded::Record::HogViolation { seat })
        } else {
            self.practice.hog_violation()
        };
        if result.is_ok() {
            self.match_release_speed = Fx::ZERO;
        }
        result.map_or_else(|error| error.into(), |_| GString::new())
    }
    fn pending(&self) -> Option<curl_proto::session::PendingDelivery> {
        if let Some(game) = &self.game {
            game.in_hand
                .as_ref()
                .map(|d| curl_proto::session::PendingDelivery {
                    target_mm_s: d.target_mm_s,
                    broom_mm: d.broom_mm,
                    elapsed_ms: d.elapsed_ms,
                    line: d.line.clone(),
                })
        } else {
            self.practice.log.pending_delivery.clone()
        }
    }
    #[func]
    fn delivery_target(&mut self, us: i64) -> i64 {
        self.stroke.settle_target(us.max(0) as u64)
    }
    #[func]
    fn begin_held(&mut self, target_mm_s: i64, broom_mm: i64) -> GString {
        let result = if let Some(game) = &mut self.game {
            game.apply(curl_match::recorded::Record::BeginDelivery {
                seat: Seat {
                    team: game.game.delivering_team(),
                    position: game.game.throwing_seat(),
                },
                target_mm_s,
                broom_mm,
            })
        } else {
            self.practice.begin_delivery(target_mm_s, broom_mm)
        };
        result.map_or_else(|e| e.into(), |_| GString::new())
    }
    #[func]
    fn begin_analog_held(&mut self, target_mm_s: i64, broom_mm: i64) -> GString {
        let line = curl_proto::session::DeliveryLine {
            x_mm: self.stroke.launch_x_mm(),
            aim_mm: self.stroke.launch_aim_mm(),
        };
        let result = if let Some(game) = &mut self.game {
            game.apply(curl_match::recorded::Record::BeginAnalogDelivery {
                seat: Seat {
                    team: game.game.delivering_team(),
                    position: game.game.throwing_seat(),
                },
                target_mm_s,
                broom_mm,
                line,
            })
        } else {
            self.practice
                .begin_analog_delivery(target_mm_s, broom_mm, line)
        };
        result.map_or_else(|e| e.into(), |_| GString::new())
    }
    #[func]
    fn advance_held(&mut self, ms: i64) -> GString {
        if !(0..=60000).contains(&ms) {
            return "Invalid interval".into();
        }
        let result = if let Some(game) = &mut self.game {
            game.think(ms as u32)
        } else {
            self.practice.advance_delivery(ms as u32)
        };
        result.map_or_else(|e| e.into(), |_| GString::new())
    }
    #[func]
    fn release_held(&mut self, trim_mm_s: i64, line_mm: i64, turn: i64) -> GString {
        let result = if let Some(game) = &mut self.game {
            let result = game.apply(curl_match::recorded::Record::ReleaseDelivery {
                seat: Seat {
                    team: game.game.delivering_team(),
                    position: game.game.throwing_seat(),
                },
                trim_mm_s,
                line_mm,
                turn,
            });
            if result.is_ok() {
                self.match_release_speed = game.last_release_speed();
                self.solo_target = V2::ZERO;
            }
            result
        } else {
            self.practice.release_delivery(trim_mm_s, line_mm, turn)
        };
        result.map_or_else(|e| e.into(), |_| GString::new())
    }
    #[func]
    fn cancel_held(&mut self) -> GString {
        let result = if let Some(game) = &mut self.game {
            game.apply(curl_match::recorded::Record::CancelDelivery {
                seat: Seat {
                    team: game.game.delivering_team(),
                    position: game.game.throwing_seat(),
                },
            })
        } else {
            self.practice.cancel_delivery()
        };
        result.map_or_else(|e| e.into(), |_| GString::new())
    }
    #[func]
    fn regrip(&mut self, us: i64, x: i64, y: i64) -> GString {
        let Some(pending) = self.pending() else {
            return "No held delivery".into();
        };
        self.stroke.regrip(
            curl_input::Sample {
                us: us.max(0) as u64,
                x,
                y,
            },
            pending.target_mm_s,
        );
        GString::new()
    }
    #[func]
    fn regrip_target(&mut self, us: i64, x: i64, y: i64, target_mm_s: i64) -> GString {
        if us < 0 || !(1500..=5000).contains(&target_mm_s) {
            return "Invalid held target".into();
        }
        self.stroke.regrip(
            curl_input::Sample {
                us: us as u64,
                x,
                y,
            },
            target_mm_s,
        );
        GString::new()
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
        if let Some(a) = &mut self.game {
            if let Err(e) = a.advance(
                count as u32,
                Some(Brush {
                    effort: effort as u8,
                    lateral_mm: lateral_mm as i16,
                    ahead_mm: ahead_mm as u16,
                }),
            ) {
                godot_error!("Match step: {e}");
            }
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
    fn step_brush_ticks(
        &mut self,
        count: i64,
        stone: i64,
        effort: i64,
        lateral_mm: i64,
        ahead_mm: i64,
    ) -> GString {
        if !(0..=64).contains(&count)
            || !(0..16).contains(&stone)
            || !(0..=255).contains(&effort)
            || !(-350..=350).contains(&lateral_mm)
            || !(80..=700).contains(&ahead_mm)
        {
            return "Invalid spatial brush input".into();
        }
        let input = Sweep {
            stone: stone as u8,
            brush: 0,
            effort: effort as u8,
            lateral_mm: lateral_mm as i16,
            ahead_mm: ahead_mm as u16,
        };
        let result = if let Some(game) = &mut self.game {
            game.advance_targeted(
                count as u32,
                Seat {
                    team: game.game.delivering_team(),
                    position: game.game.throwing_seat(),
                },
                Some(input),
            )
        } else {
            let inputs = [input];
            (0..count).try_for_each(|_| self.practice.step(if effort > 0 { &inputs } else { &[] }))
        };
        result.err().unwrap_or("").into()
    }
    #[func]
    fn begin_scrub(&mut self, us: i64, x: i64, y: i64) {
        self.scrub.begin(curl_input::Sample {
            us: us.max(0) as u64,
            x,
            y,
        });
    }
    #[func]
    fn scrub_motion(&mut self, us: i64, x: i64, y: i64) {
        self.scrub.motion(curl_input::Sample {
            us: us.max(0) as u64,
            x,
            y,
        });
    }
    #[func]
    fn scrub_effort(&self, us: i64) -> i64 {
        self.scrub.effort(us.max(0) as u64) as i64
    }
    #[func]
    fn cancel_scrub(&mut self) {
        self.scrub.cancel();
    }
    #[func]
    fn frame(&self) -> VarDictionary {
        let last_release = self
            .practice
            .log
            .records
            .iter()
            .rev()
            .find_map(|r| {
                if let curl_proto::session::Record::Shot(s) = r {
                    Some(s.release.vel.length())
                } else if matches!(r, curl_proto::session::Record::HogViolation { .. }) {
                    Some(Fx::ZERO)
                } else {
                    None
                }
            })
            .unwrap_or(Fx::ZERO);
        let mut frame = presentation_frame(
            self.game.as_ref().map_or(&self.practice.sim, |a| &a.sim),
            self.game.as_deref(),
            if self.game.is_some() {
                self.match_release_speed
            } else {
                last_release
            },
            self.practice.next_id().is_some(),
        );
        frame.set("in_hand", &pending_frame(self.pending().as_ref()));
        frame.set("solo_target_x_mm", rounded_mm(self.solo_target.x));
        frame.set("solo_target_y_mm", rounded_mm(self.solo_target.y));
        if self.game.is_none() {
            frame.set(
                "team",
                self.practice.next_id().map_or(0, |id| id % 2) as i64,
            );
        }
        frame
    }
    #[func]
    fn drill_target(&self, kind: i64, attempt: i64) -> VarDictionary {
        let mut result = VarDictionary::new();
        if !(0..5).contains(&attempt) {
            return result;
        }
        if let Some(kind) = curl_match::drills::Kind::from_index(kind) {
            let target = kind.target(attempt as u8);
            result.set("x_mm", rounded_mm(target.x));
            result.set("y_mm", rounded_mm(target.y));
        }
        result
    }
    #[func]
    fn drill_result(&self, kind: i64, attempt: i64) -> VarDictionary {
        let mut result = VarDictionary::new();
        if self.game.is_some() || !(0..5).contains(&attempt) {
            return result;
        }
        if let Some(kind) = curl_match::drills::Kind::from_index(kind)
            && let Some(score) = kind.result(&self.practice.sim, attempt as u8)
        {
            result.set("stars", score.stars as i64);
            result.set("error_mm", score.error_mm);
            result.set("in_play", score.in_play);
        }
        result
    }
    #[func]
    fn start_sweeping_drill(&mut self, attempt: i64) -> GString {
        if self.game.is_some() || !(0..5).contains(&attempt) {
            return "Sweeping drill unavailable".into();
        }
        let target = curl_match::drills::Kind::Sweeping.target(attempt as u8);
        // A reachable underweight draw: judge the moving stone and brush it up.
        let plan = curl_match::ai::solve(
            &self.practice.sim,
            target + V2::new(Fx::ZERO, Fx::ratio(-7, 10)),
            curl_match::ai::ShotKind::Draw,
            if attempt % 2 == 0 { 1 } else { -1 },
        );
        self.apply_delivery(plan.release())
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
        GString::from(&format!(
            "{:016x}",
            self.game
                .as_ref()
                .map_or_else(|| self.practice.hash(), |a| a.sim.hash())
        ))
    }

    #[func]
    fn prepare_next(&mut self, clear: bool) -> GString {
        if self.pending().is_some() {
            return "Finish the held delivery first".into();
        }
        if let Some(a) = &self.game {
            if a.game.phase != Phase::Calling {
                return "Finish end setup before throwing".into();
            }
            self.stroke.cancel();
            return GString::new();
        }
        let mut next = self.practice.clone();
        if clear && let Err(e) = next.clear_stones() {
            return e.into();
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
        if self.game.is_some() {
            return GString::new();
        }
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
                self.game = None;
                self.practice = practice;
                self.stroke.cancel();
                GString::new()
            }
            Err(e) => GString::from(&e),
        }
    }
    #[func]
    fn match_hash(&self) -> GString {
        self.game.as_ref().map_or(GString::new(), |a| {
            GString::from(&format!("{:016x}", a.hash()))
        })
    }
    #[func]
    fn match_json(&self) -> GString {
        let Some(a) = &self.game else {
            return GString::new();
        };
        match a.json() {
            Ok(json) => GString::from(&json),
            Err(e) => {
                godot_error!("Match save: {e}");
                GString::new()
            }
        }
    }
    #[func]
    fn load_match(&mut self, json: GString) -> GString {
        match RecordedMatch::parse(json.to_string().as_bytes()) {
            Ok(game) => {
                self.match_release_speed = game.last_release_speed();
                self.ai_task = None;
                self.ai_plan = None;
                self.solo_target = V2::ZERO;
                self.game = Some(game);
                self.stroke.cancel();
                GString::new()
            }
            Err(e) => GString::from(&e),
        }
    }
    #[func]
    fn match_think(&mut self, elapsed_ms: i64) {
        if !(0..=60000).contains(&elapsed_ms) {
            return;
        }
        if let Some(a) = &mut self.game
            && let Err(e) = a.think(elapsed_ms as u32)
        {
            godot_error!("Match clock: {e}");
        }
    }
    #[func]
    fn new_match(&mut self, seed: i64) {
        self.ai_task = None;
        self.ai_plan = None;
        self.game =
            Some(RecordedMatch::new(seed as u64, Rules::mixed(), 1).expect("built-in rules valid"));
        self.match_release_speed = Fx::ZERO;
        self.stroke.cancel();
    }
    #[func]
    fn new_team_match(&mut self, seed: i64) {
        self.ai_task = None;
        self.ai_plan = None;
        self.solo_target = V2::ZERO;
        self.game =
            Some(RecordedMatch::new(seed as u64, Rules::club(), 1).expect("built-in rules valid"));
        self.match_release_speed = Fx::ZERO;
        self.stroke.cancel();
    }
    /// Planning runs on a native worker; no Godot objects cross the thread.
    #[func]
    fn request_ai_plan(&mut self) -> GString {
        let Some(game) = &self.game else {
            return "No match".into();
        };
        if game.game.phase != Phase::Calling || game.in_hand.is_some() {
            return "AI planning requires a ready delivery".into();
        }
        if self.ai_task.is_some() {
            return GString::new();
        }
        let authority: curl_match::Authority = (**game).clone();
        self.ai_plan = None;
        self.ai_task = Some(AiTask {
            context: AiContext::of(game),
            worker: std::thread::spawn(move || curl_match::ai::plan(&authority)),
        });
        GString::new()
    }
    #[func]
    fn request_called_shot(&mut self, kind: i64, x_mm: i64, y_mm: i64, turn: i64) -> GString {
        if !(-2200..=2200).contains(&x_mm)
            || !(-5000..=2000).contains(&y_mm)
            || ![-1, 1].contains(&turn)
        {
            return "Called target is outside the sheet".into();
        }
        let kind = match kind {
            0 => curl_match::ai::ShotKind::Draw,
            1 => curl_match::ai::ShotKind::Guard,
            2 => curl_match::ai::ShotKind::Hit,
            _ => return "Invalid shot type".into(),
        };
        let Some(game) = &self.game else {
            return "No match".into();
        };
        if game.game.phase != Phase::Calling || game.in_hand.is_some() || self.ai_task.is_some() {
            return "Wait for a ready delivery before changing the call".into();
        }
        let sim = game.sim.clone();
        let context = AiContext::of(game);
        self.ai_plan = None;
        self.ai_task = Some(AiTask {
            context,
            worker: std::thread::spawn(move || {
                Ok(curl_match::ai::solve(
                    &sim,
                    V2::new(Fx::ratio(x_mm, 1000), Fx::ratio(y_mm, 1000)),
                    kind,
                    turn,
                ))
            }),
        });
        GString::new()
    }
    #[func]
    fn poll_ai_plan(&mut self) -> VarDictionary {
        let mut result = VarDictionary::new();
        if self
            .ai_task
            .as_ref()
            .is_none_or(|task| !task.worker.is_finished())
        {
            return result;
        }
        let task = self.ai_task.take().expect("checked task");
        let Ok(shot) = task.worker.join() else {
            result.set("error", "AI planner worker failed");
            return result;
        };
        if self
            .game
            .as_ref()
            .is_none_or(|game| !task.context.matches(game))
        {
            result.set("error", "AI plan no longer matches this delivery");
            return result;
        }
        match shot {
            Ok(plan) => {
                result.set("kind", plan.kind.name());
                result.set("target_x_mm", rounded_mm(plan.target.x));
                result.set("target_y_mm", rounded_mm(plan.target.y));
                result.set("broom_mm", plan.broom_mm);
                result.set("speed_mm_s", plan.speed_mm_s);
                result.set("turn", plan.turn);
                self.ai_plan = Some((task.context, plan));
            }
            Err(error) => result.set("error", error),
        }
        result
    }
    #[func]
    fn execute_ai_plan(&mut self, broom_mm: i64, turn: i64, level: i64) -> GString {
        if !(-2200..=2200).contains(&broom_mm)
            || ![-1, 1].contains(&turn)
            || !(0..=2).contains(&level)
        {
            return "Invalid AI execution settings".into();
        }
        let Some(game) = &self.game else {
            return "No match".into();
        };
        let Some((context, mut plan)) = self.ai_plan.take() else {
            return "No AI shot planned".into();
        };
        if !context.matches(game) {
            return "Delivery not ready or AI plan is stale".into();
        }
        plan.broom_mm = broom_mm;
        plan.turn = turn;
        let target = plan.target;
        let seed = game.sim.ice.seed
            ^ ((game.game.end as u64) << 32)
            ^ (game.game.delivered as u64 + 1).wrapping_mul(0x9e3779b97f4a7c15);
        let error = self.apply_delivery(plan.execute(ai_level(level), seed));
        if error.is_empty() {
            self.solo_target = target;
        }
        error
    }
    #[func]
    fn set_solo_target(&mut self, x_mm: i64, y_mm: i64) -> GString {
        if !(-2200..=2200).contains(&x_mm) || !(-5000..=2000).contains(&y_mm) {
            return "Invalid saved shot target".into();
        }
        self.solo_target = V2::new(Fx::ratio(x_mm, 1000), Fx::ratio(y_mm, 1000));
        GString::new()
    }
    #[func]
    fn solo_advice(&self, level: i64) -> VarDictionary {
        let mut result = VarDictionary::new();
        if let Some(game) = &self.game {
            let (effort, zone) =
                curl_match::ai::advice(&game.sim, self.solo_target, ai_level(level));
            result.set("effort", effort as i64);
            result.set("zone", zone as i64);
        }
        result
    }
    /// Team play currently uses one combined brush per team. Keep this existing
    /// journal interpretation rather than changing historical brush identities.
    #[func]
    fn step_solo_ticks(
        &mut self,
        count: i64,
        stone: i64,
        human_effort: i64,
        lateral_mm: i64,
        ahead_mm: i64,
        ai_effort: i64,
    ) -> GString {
        if !(0..=64).contains(&count)
            || !(0..16).contains(&stone)
            || !(0..=255).contains(&human_effort)
            || !(0..=255).contains(&ai_effort)
            || !(-350..=350).contains(&lateral_mm)
            || !(80..=700).contains(&ahead_mm)
        {
            return "Invalid solo brush input".into();
        }
        let Some(game) = &mut self.game else {
            return "No match".into();
        };
        let effort = (human_effort + ai_effort).min(255) as u8;
        let input = Sweep {
            stone: stone as u8,
            brush: 0,
            effort,
            lateral_mm: lateral_mm as i16,
            ahead_mm: ahead_mm as u16,
        };
        game.advance_targeted(
            count as u32,
            Seat {
                team: game.game.delivering_team(),
                position: game.game.throwing_seat(),
            },
            Some(input),
        )
        .err()
        .unwrap_or("")
        .into()
    }
    #[func]
    fn place_match(&mut self, own_house: bool, side: i64) -> GString {
        let Some(a) = &mut self.game else {
            return "No match".into();
        };
        let side = match side {
            -1 => PowerPlay::Left,
            0 => PowerPlay::None,
            1 => PowerPlay::Right,
            _ => return "Invalid placement".into(),
        };
        match a.place_mixed(
            Seat {
                team: a.game.placement_team,
                position: 0,
            },
            own_house,
            side,
        ) {
            Ok(()) => GString::new(),
            Err(e) => e.into(),
        }
    }
    #[func]
    fn match_order(&mut self, team: i64, position: i64) -> GString {
        if !(0..=1).contains(&team) || !(0..=1).contains(&position) {
            return "Invalid player".into();
        }
        let Some(a) = &mut self.game else {
            return "No match".into();
        };
        match a.order(team as u8, position as u8) {
            Ok(()) => GString::new(),
            Err(e) => e.into(),
        }
    }
    #[func]
    fn match_next_end(&mut self) -> GString {
        let Some(a) = &mut self.game else {
            return "No match".into();
        };
        match a.next_end() {
            Ok(()) => GString::new(),
            Err(e) => e.into(),
        }
    }
    #[func]
    fn grip(&mut self, us: i64, x: i64, y: i64, one_push: bool) {
        self.stroke.grip(
            curl_input::Sample {
                us: us.max(0) as u64,
                x,
                y,
            },
            one_push,
            1000,
        );
    }
    #[func]
    fn motion(&mut self, us: i64, x: i64, y: i64) {
        self.stroke.motion(curl_input::Sample {
            us: us.max(0) as u64,
            x,
            y,
        });
    }
    #[func]
    fn stroke_phase(&self) -> GString {
        GString::from(&format!("{:?}", self.stroke.phase()))
    }
    #[func]
    fn delivery_pose(&self, us: i64) -> VarDictionary {
        let pose = self.stroke.pose(us.max(0) as u64);
        let mut d = VarDictionary::new();
        d.set("target_mm_s", self.stroke.target_mm_s());
        d.set("turn", self.stroke.finish_turn(us.max(0) as u64));
        d.set("x_mm", self.stroke.launch_x_mm());
        d.set("aim_mm", self.stroke.launch_aim_mm());
        d.set("y_um", pose.y_um);
        d.set("in_play", pose.in_play);
        d.set("hog_warning", pose.hog_warning);
        d.set("hog_violation", pose.hog_violation);
        d.set("slide_tick", pose.slide_tick as i64);
        d
    }
    #[func]
    fn cancel_stroke(&mut self) {
        self.stroke.cancel();
    }
    #[func]
    fn lift(&mut self, us: i64, x: i64, y: i64) -> VarDictionary {
        let delivery = self.stroke.release(curl_input::Sample {
            us: us.max(0) as u64,
            x,
            y,
        });
        let mut d = VarDictionary::new();
        let r = delivery.stroke;
        d.set("target_mm_s", self.stroke.target_mm_s());
        d.set("finish_valid", r.valid);
        d.set("turn", delivery.turn);
        d.set("trim_mm_s", delivery.trim_mm_s);
        d.set(
            "valid",
            delivery.outcome == curl_input::delivery::Outcome::Released,
        );
        d.set(
            "hog_violation",
            delivery.outcome == curl_input::delivery::Outcome::HogViolation,
        );
        d.set("y_um", delivery.pose.y_um);
        d.set("speed_um_s", delivery.speed_um_s);
        d.set("speed_mm_s", delivery.speed_um_s / 1000);
        d.set("line_mm", r.line_mm);
        d.set("push_mm_s", r.push_mm_s);
        d.set("drive_us", r.drive_us as i64);
        d
    }
}

mod room;

fn pending_frame(pending: Option<&curl_proto::session::PendingDelivery>) -> VarDictionary {
    let mut data = VarDictionary::new();
    if let Some(pending) = pending {
        let pose = pending.pose();
        data.set("target_mm_s", pending.target_mm_s);
        data.set("elapsed_ms", pending.elapsed_ms as i64);
        data.set("broom_mm", pending.broom_mm);
        data.set("y_um", pose.y_um);
        data.set("x_um", pending.x_um());
        data.set(
            "aim_mm",
            pending.line.as_ref().map_or(0, |line| line.aim_mm),
        );
        data.set("in_play", pose.in_play);
        data.set("hog_warning", pose.hog_warning);
    }
    data
}

pub(crate) fn presentation_frame(
    sim: &curl_sim::Sim,
    game: Option<&curl_match::Authority>,
    release_speed: Fx,
    can_deliver_next: bool,
) -> VarDictionary {
    let mut frame = VarDictionary::new();
    let mut stones = Array::<VarDictionary>::new();
    for s in &sim.stones {
        let mut d = VarDictionary::new();
        d.set("id", s.id as i64);
        d.set("team", s.team as i64);
        d.set(
            "position",
            Vector2::new(render(s.pos.x) as f32, render(s.pos.y) as f32),
        );
        d.set("speed", render(s.vel.length()));
        d.set(
            "velocity",
            Vector2::new(render(s.vel.x) as f32, render(s.vel.y) as f32),
        );
        d.set("turns", render(s.turns));
        d.set("active", s.active);
        stones.push(&d);
    }
    frame.set("release_speed", render(release_speed));
    frame.set("stones", &stones);
    frame.set("tick", (sim.tick - sim.release_tick) as i64);
    frame.set("global_tick", sim.tick as i64);
    frame.set("delivered", sim.delivered.map_or(-1, |id| id as i64));
    frame.set("can_deliver_next", can_deliver_next);
    frame.set("ice_cells", sim.ice.cells.len() as i64);
    frame.set("resting", sim.is_resting());
    frame.set("contacts", sim.contacts as i64);
    frame.set(
        "hog_tick",
        sim.hog_tick.map_or(-1, |t| (t - sim.release_tick) as i64),
    );
    frame.set("timed_out", sim.timed_out);
    frame.set("mode", if game.is_some() { "match" } else { "practice" });
    let pending =
        game.and_then(|a| a.in_hand.as_ref())
            .map(|held| curl_proto::session::PendingDelivery {
                target_mm_s: held.target_mm_s,
                broom_mm: held.broom_mm,
                elapsed_ms: held.elapsed_ms,
                line: held.line.clone(),
            });
    let mut held_frame = pending_frame(pending.as_ref());
    if let Some(held) = game.and_then(|a| a.in_hand.as_ref()) {
        held_frame.set("suspended", held.suspended);
    }
    frame.set("in_hand", &held_frame);
    if let Some(a) = game {
        frame.set("release_speed", render(release_speed));
        frame.set("format", format!("{:?}", a.game.rules.format));
        frame.set("match_phase", format!("{:?}", a.game.phase));
        frame.set("end", a.game.end as i64);
        frame.set("scheduled_ends", a.game.rules.ends as i64);
        frame.set("team", a.game.delivering_team() as i64);
        frame.set("thrower", a.game.throwing_seat() as i64);
        frame.set("delivered_count", a.game.delivered as i64);
        frame.set("hammer", a.game.hammer as i64);
        frame.set("placement_team", a.game.placement_team as i64);
        frame.set("clock_gold", a.game.thinking_ms[0] as i64);
        frame.set("clock_cyan", a.game.thinking_ms[1] as i64);
        frame.set("score_gold", a.game.score[0] as i64);
        frame.set("score_cyan", a.game.score[1] as i64);
        frame.set("first_gold", a.game.first_thrower[0] as i64);
        frame.set("first_cyan", a.game.first_thrower[1] as i64);
        frame.set(
            "power_available",
            !a.game.power_play_used[a.game.placement_team as usize]
                && a.game.end <= a.game.rules.ends,
        );
        frame.set("winner", a.game.winner.map_or(-1, |t| t as i64));
        frame.set("can_deliver_next", a.game.phase == Phase::Calling);
        frame.set(
            "violation",
            a.last_resolution
                .as_ref()
                .and_then(|r| r.violation)
                .map_or(String::new(), |v| format!("{v:?}")),
        );
    }
    frame
}

fn rounded_mm(value: Fx) -> i64 {
    let raw = value.raw() as i128 * 1000;
    ((raw + raw.signum() * (1_i128 << 31)) / (1_i128 << 32)) as i64
}

fn ai_level(level: i64) -> curl_match::ai::Difficulty {
    match level {
        0 => curl_match::ai::Difficulty::Club,
        2 => curl_match::ai::Difficulty::Elite,
        _ => curl_match::ai::Difficulty::Competitive,
    }
}

pub(crate) fn input_release(
    speed_mm_s: i64,
    broom_mm: i64,
    turn: i64,
) -> Result<Release, &'static str> {
    if !(100..=6000).contains(&speed_mm_s)
        || !(-2200..=2200).contains(&broom_mm)
        || ![-1, 1].contains(&turn)
    {
        return Err("Invalid delivery");
    }
    let mut release = Release::draw();
    release.vel =
        V2::new(Fx::ratio(broom_mm, 1000), -release.pos.y).unit() * Fx::ratio(speed_mm_s, 1000);
    release.spin = Fx::ratio(12 * turn, 100);
    Ok(release)
}

/// Integer input boundary shared by local play and authenticated online packets.
pub(crate) fn input_release_at(
    speed_um_s: i64,
    y_um: i64,
    broom_mm: i64,
    turn: i64,
) -> Result<Release, &'static str> {
    if !(100_000..=6_000_000).contains(&speed_um_s)
        || !(curl_input::delivery::START_Y_UM..curl_input::delivery::HOG_CENTER_UM).contains(&y_um)
        || !(-2200..=2200).contains(&broom_mm)
        || !(-1..=1).contains(&turn)
    {
        return Err("Invalid delivery");
    }
    let mut release = Release::draw();
    release.pos.y = Fx::ratio(y_um, 1_000_000);
    release.vel = V2::new(Fx::ratio(broom_mm, 1000), -release.pos.y).unit()
        * Fx::ratio(speed_um_s, 1_000_000);
    release.spin = Fx::ratio(12 * turn, 100);
    release.validate()?;
    Ok(release)
}
