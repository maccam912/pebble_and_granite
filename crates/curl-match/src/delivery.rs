//! Host-owned in-hand delivery. Only authority elapsed time advances this state.
use crate::{Authority, Seat};
use curl_fx::{Fx, V2};
use curl_input::delivery::{HZ, Pose, crossing_ms, slide_pose};
use curl_rules::Phase;
use curl_sim::Release;
use serde::{Deserialize, Serialize};

pub const DELIVERY_TEE: Fx = Fx::ratio(-34750, 1000);
#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct FlightClock {
    pub remainder: u32,
    pub stop_tick: Option<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct InHand {
    pub seat: Seat,
    pub target_mm_s: i64,
    pub broom_mm: i64,
    pub elapsed_ms: u32,
}
impl InHand {
    pub fn pose(&self) -> Pose {
        slide_pose(self.target_mm_s, self.elapsed_ms as u64 * HZ / 1000)
    }
}
impl Authority {
    pub(crate) fn advance_flight_clock(&mut self) {
        let Some(clock) = &mut self.flight_clock else {
            return;
        };
        if clock.stop_tick.is_some() {
            return;
        }
        let total = clock.remainder + 1000;
        clock.remainder = total % 240;
        self.game.charge_delivery_time(total / 240);
        if self.sim.stones.iter().any(|stone| {
            Some(stone.id) == self.sim.delivered && stone.pos.y + curl_sim::RADIUS >= DELIVERY_TEE
        }) {
            clock.stop_tick = Some(self.sim.tick);
        }
    }

    pub fn begin_delivery(
        &mut self,
        seat: Seat,
        target_mm_s: i64,
        broom_mm: i64,
    ) -> Result<(), &'static str> {
        if self.in_hand.is_some()
            || self.game.phase != Phase::Calling
            || !self.valid_seat(seat)
            || seat.team != self.game.delivering_team()
            || seat.position != self.game.throwing_seat()
            || !self.sim.is_resting()
            || !(1500..=5000).contains(&target_mm_s)
            || !(-2200..=2200).contains(&broom_mm)
        {
            return Err("invalid delivery start");
        }
        self.in_hand = Some(InHand {
            seat,
            target_mm_s,
            broom_mm,
            elapsed_ms: 0,
        });
        self.last_resolution = None;
        Ok(())
    }
    pub fn cancel_delivery(&mut self, seat: Seat) -> Result<(), &'static str> {
        let delivery = self.in_hand.as_ref().ok_or("no active delivery")?;
        if delivery.seat != seat || delivery.pose().in_play {
            return Err("in-play delivery cannot be returned to the hack");
        }
        self.in_hand = None;
        Ok(())
    }
    pub fn release_delivery(
        &mut self,
        seat: Seat,
        trim_mm_s: i64,
        line_mm: i64,
        turn: i64,
    ) -> Result<(), &'static str> {
        let delivery = self.in_hand.as_ref().ok_or("no active delivery")?;
        if delivery.seat != seat
            || !(-70..=70).contains(&trim_mm_s)
            || !(-120..=120).contains(&line_mm)
            || !(-1..=1).contains(&turn)
        {
            return Err("invalid delivery release");
        }
        let pose = delivery.pose();
        if pose.hog_violation {
            return Err("delivery already reached hog line");
        }
        let mut release = Release::draw();
        release.pos.y = Fx::ratio(pose.y_um, 1_000_000);
        let broom = (delivery.broom_mm + line_mm).clamp(-2200, 2200);
        release.vel = V2::new(Fx::ratio(broom, 1000), -release.pos.y).unit()
            * Fx::ratio(pose.speed_um_s + trim_mm_s * 1000, 1_000_000);
        release.spin = Fx::ratio(12 * turn, 100);
        let mut next = self.clone();
        next.in_hand = None;
        next.release(seat, release)?;
        *self = next;
        Ok(())
    }
    pub(crate) fn advance_delivery(&mut self, ms: u32) -> Result<(), &'static str> {
        let mut delivery = self.in_hand.clone().ok_or("no active delivery")?;
        let tee = crossing_ms(delivery.target_mm_s, false);
        let hog = crossing_ms(delivery.target_mm_s, true);
        let mut part = ms.min(hog.saturating_sub(delivery.elapsed_ms));
        let thinking = part.min(tee.saturating_sub(delivery.elapsed_ms));
        let remaining = self.game.thinking_ms[delivery.seat.team as usize];
        if remaining <= thinking {
            part = part.min(remaining);
        }
        let thinking = thinking.min(part);
        let total = part * 240 + self.idle_remainder;
        self.sim.advance_idle(total / 1000)?;
        self.idle_remainder = total % 1000;
        self.game.think(thinking);
        if self.game.phase == Phase::GameComplete {
            self.in_hand = None;
            return Ok(());
        }
        delivery.elapsed_ms += part;
        self.in_hand = Some(delivery.clone());
        if delivery.elapsed_ms == hog {
            self.hog_violation(delivery.seat)?;
            // Remaining authority time belongs to the next team's calling phase.
            self.think(ms - part)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::recorded::{Record, RecordedMatch};
    use curl_rules::{PowerPlay, Rules};
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
    const SEAT: Seat = Seat {
        team: 0,
        position: 0,
    };
    fn start(m: &mut RecordedMatch) {
        m.apply(Record::BeginDelivery {
            seat: SEAT,
            target_mm_s: 2050,
            broom_mm: -900,
        })
        .unwrap();
    }
    #[test]
    fn tee_clock_cancel_and_journal_restore() {
        let mut m = game();
        start(&mut m);
        m.think(100).unwrap();
        m.apply(Record::CancelDelivery { seat: SEAT }).unwrap();
        let remaining = m.game.thinking_ms[0];
        start(&mut m);
        let tee = crossing_ms(2050, false);
        m.think(tee - 1).unwrap();
        assert!(!m.in_hand.as_ref().unwrap().pose().in_play);
        m.think(1).unwrap();
        assert!(m.in_hand.as_ref().unwrap().pose().in_play);
        let hash = m.hash();
        assert!(m.apply(Record::CancelDelivery { seat: SEAT }).is_err());
        assert!(m.order(0, 1).is_err());
        assert_eq!(m.hash(), hash);
        m.think(500).unwrap();
        assert_eq!(m.game.thinking_ms[0], remaining - tee);
        let restored = RecordedMatch::parse(m.json().unwrap().as_bytes()).unwrap();
        assert_eq!(restored.hash(), m.hash());
        assert_eq!(restored.in_hand, m.in_hand);
    }
    #[test]
    fn deadline_and_partitioning_are_exact() {
        let mut batched = game();
        let mut frames = game();
        start(&mut batched);
        start(&mut frames);
        let duration = crossing_ms(2050, true) + 137;
        batched.think(duration).unwrap();
        for _ in 0..duration {
            frames.think(1).unwrap();
        }
        assert_eq!(batched.hash(), frames.hash());
        assert!(batched.in_hand.is_none());
        assert_eq!(batched.game.delivered, 1);
        assert_eq!(
            batched.game.thinking_ms[1],
            Rules::mixed().thinking_ms - 137
        );
        assert_eq!(
            RecordedMatch::parse(batched.json().unwrap().as_bytes())
                .unwrap()
                .hash(),
            batched.hash()
        );
    }
    #[test]
    fn released_before_tee_keeps_clock_running() {
        let mut m = game();
        start(&mut m);
        m.apply(Record::ReleaseDelivery {
            seat: SEAT,
            trim_mm_s: 0,
            line_mm: 0,
            turn: 1,
        })
        .unwrap();
        let before = m.game.thinking_ms[0];
        m.advance(24, None).unwrap();
        assert_eq!(m.game.thinking_ms[0], before - 100);
        for _ in 0..30 {
            m.advance(24, None).unwrap();
        }
        let stopped = m.game.thinking_ms[0];
        m.advance(24, None).unwrap();
        assert_eq!(m.game.thinking_ms[0], stopped);
        assert_eq!(
            RecordedMatch::parse(m.json().unwrap().as_bytes())
                .unwrap()
                .hash(),
            m.hash()
        );
    }
    #[test]
    fn expiry_before_tee_forfeits_and_invalid_commands_are_atomic() {
        let mut rules = Rules::mixed();
        rules.thinking_ms = 100;
        let mut m = RecordedMatch::new(42, rules, 1).unwrap();
        m.place_mixed(
            Seat {
                team: 1,
                position: 0,
            },
            true,
            PowerPlay::None,
        )
        .unwrap();
        start(&mut m);
        let hash = m.hash();
        assert!(
            m.apply(Record::ReleaseDelivery {
                seat: SEAT,
                trim_mm_s: 71,
                line_mm: 0,
                turn: 1,
            })
            .is_err()
        );
        assert_eq!(m.hash(), hash);
        m.think(500).unwrap();
        assert_eq!(m.game.phase, Phase::GameComplete);
        assert_eq!(m.game.winner, Some(1));
        assert!(m.in_hand.is_none());
    }
}
