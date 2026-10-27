//! Target drills score actual settled sim positions, including misses and hogs.
use curl_fx::{Fx, V2};
use curl_sim::Sim;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Weight,
    Guard,
    Line,
    Sweeping,
}
impl Kind {
    pub fn from_index(index: i64) -> Option<Self> {
        match index {
            0 => Some(Self::Weight),
            1 => Some(Self::Guard),
            2 => Some(Self::Line),
            3 => Some(Self::Sweeping),
            _ => None,
        }
    }
    pub fn target(self, attempt: u8) -> V2 {
        match self {
            Self::Guard => V2::new(Fx::ZERO, Fx::int(-3)),
            Self::Line => V2::new(
                Fx::ratio(if attempt.is_multiple_of(2) { -8 } else { 8 }, 10),
                Fx::ZERO,
            ),
            _ => V2::ZERO,
        }
    }
    /// Weight isolates depth. The other drills measure distance to the target.
    pub fn result(self, sim: &Sim, attempt: u8) -> Option<Result> {
        let id = sim.delivered?;
        if !sim.is_resting() {
            return None;
        }
        let stone = sim.stones.iter().find(|s| s.id == id)?;
        let target = self.target(attempt);
        let offset = stone.pos - target;
        let error = if self == Self::Weight {
            offset.y.abs()
        } else {
            offset.length()
        };
        let error_mm = (error.raw() as i128 * 1000 / (1_i128 << 32)) as i64;
        let stars = if !stone.active {
            0
        } else if error <= Fx::ratio(15, 100) {
            3
        } else if error <= Fx::ratio(45, 100) {
            2
        } else if error <= Fx::ratio(9, 10) {
            1
        } else {
            0
        };
        Some(Result {
            stars,
            error_mm,
            in_play: stone.active,
        })
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Result {
    pub stars: u8,
    pub error_mm: i64,
    pub in_play: bool,
}
#[cfg(test)]
mod tests {
    use super::*;
    use curl_sim::{Release, Stone};
    #[test]
    fn targets_and_scoring_use_actual_positions_and_count_misses() {
        assert!(Kind::from_index(-1).is_none() && Kind::from_index(4).is_none());
        assert_eq!(Kind::Line.target(0).x, -Kind::Line.target(1).x);
        let mut sim = Sim::new(42);
        assert!(Kind::Weight.result(&sim, 0).is_none());
        sim.release(Release::draw()).unwrap();
        assert!(Kind::Weight.result(&sim, 0).is_none());
        sim.stones = vec![Stone::resting(0, 0, V2::new(Fx::ONE, Fx::ratio(1, 10)))];
        assert_eq!(Kind::Weight.result(&sim, 0).unwrap().stars, 3);
        assert_eq!(Kind::Sweeping.result(&sim, 0).unwrap().stars, 0);
        sim.stones[0].pos = V2::new(Fx::ratio(3, 10), Fx::ZERO);
        assert_eq!(Kind::Line.result(&sim, 1).unwrap().stars, 1);
        sim.stones[0].active = false;
        sim.stones[0].pos = V2::ZERO;
        assert_eq!(Kind::Weight.result(&sim, 0).unwrap().stars, 0);
    }
}
