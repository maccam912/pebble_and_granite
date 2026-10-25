//! Portable Q32.32 arithmetic. Overflow is a programming error on every build.
//! Public input validators constrain physical values before arithmetic.
use serde::{Deserialize, Serialize};
use std::ops::{Add, AddAssign, Div, Mul, Neg, Sub, SubAssign};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Fx(pub i64);

impl Fx {
    pub const ZERO: Self = Self(0);
    pub const ONE: Self = Self(1_i64 << 32);
    pub const EPSILON: Self = Self(1);
    pub const fn int(n: i32) -> Self {
        Self((n as i64) << 32)
    }
    /// Truncate toward zero, identically on every architecture.
    pub const fn ratio(n: i64, d: i64) -> Self {
        assert!(d != 0);
        let value = ((n as i128) << 32) / d as i128;
        assert!(value >= i64::MIN as i128 && value <= i64::MAX as i128);
        Self(value as i64)
    }
    pub fn abs(self) -> Self {
        Self(self.0.checked_abs().expect("fixed abs overflow"))
    }
    pub fn sign(self) -> Self {
        Self::int(self.0.signum() as i32)
    }
    pub fn sqrt(self) -> Self {
        assert!(self.0 >= 0, "negative square root");
        Self(isqrt((self.0 as u128) << 32) as i64)
    }
    pub fn clamp(self, min: Self, max: Self) -> Self {
        self.max(min).min(max)
    }
    pub fn raw(self) -> i64 {
        self.0
    }
}

pub fn isqrt(n: u128) -> u128 {
    if n < 2 {
        return n;
    }
    let mut x = 1_u128 << (128 - n.leading_zeros()).div_ceil(2);
    loop {
        let next = (x + n / x) / 2;
        if next >= x {
            return x;
        }
        x = next;
    }
}

impl Add for Fx {
    type Output = Self;
    fn add(self, rhs: Self) -> Self {
        Self(self.0.checked_add(rhs.0).expect("fixed add overflow"))
    }
}
impl Sub for Fx {
    type Output = Self;
    fn sub(self, rhs: Self) -> Self {
        Self(self.0.checked_sub(rhs.0).expect("fixed sub overflow"))
    }
}
impl Neg for Fx {
    type Output = Self;
    fn neg(self) -> Self {
        Self(self.0.checked_neg().expect("fixed neg overflow"))
    }
}
impl Mul for Fx {
    type Output = Self;
    fn mul(self, rhs: Self) -> Self {
        Self(
            i64::try_from((self.0 as i128 * rhs.0 as i128) / (1_i128 << 32))
                .expect("fixed mul overflow"),
        )
    }
}
impl Div for Fx {
    type Output = Self;
    fn div(self, rhs: Self) -> Self {
        Self(i64::try_from(((self.0 as i128) << 32) / rhs.0 as i128).expect("fixed div overflow"))
    }
}
impl AddAssign for Fx {
    fn add_assign(&mut self, rhs: Self) {
        *self = *self + rhs;
    }
}
impl SubAssign for Fx {
    fn sub_assign(&mut self, rhs: Self) {
        *self = *self - rhs;
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct V2 {
    pub x: Fx,
    pub y: Fx,
}
impl V2 {
    pub const ZERO: Self = Self {
        x: Fx::ZERO,
        y: Fx::ZERO,
    };
    pub const fn new(x: Fx, y: Fx) -> Self {
        Self { x, y }
    }
    pub fn dot(self, rhs: Self) -> Fx {
        self.x * rhs.x + self.y * rhs.y
    }
    pub fn length(self) -> Fx {
        self.dot(self).sqrt()
    }
    pub fn unit(self) -> Self {
        let l = self.length();
        if l == Fx::ZERO {
            Self::ZERO
        } else {
            self * (Fx::ONE / l)
        }
    }
    /// Right of the path, viewed from above, with delivery traveling in +y.
    pub fn right(self) -> Self {
        Self::new(self.y, -self.x)
    }
}
impl Add for V2 {
    type Output = Self;
    fn add(self, rhs: Self) -> Self {
        Self::new(self.x + rhs.x, self.y + rhs.y)
    }
}
impl Sub for V2 {
    type Output = Self;
    fn sub(self, rhs: Self) -> Self {
        Self::new(self.x - rhs.x, self.y - rhs.y)
    }
}
impl Mul<Fx> for V2 {
    type Output = Self;
    fn mul(self, rhs: Fx) -> Self {
        Self::new(self.x * rhs, self.y * rhs)
    }
}

/// SplitMix64, with explicit wrapping semantics; never use platform randomness.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Rng(pub u64);
impl Rng {
    pub fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e3779b97f4a7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        z ^ (z >> 31)
    }
}

/// Stable FNV-1a checksum for desync detection (not an authentication primitive).
pub struct Hash64(u64);
impl Default for Hash64 {
    fn default() -> Self {
        Self(0xcbf29ce484222325)
    }
}
impl Hash64 {
    pub fn bytes(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.0 = (self.0 ^ *b as u64).wrapping_mul(0x100000001b3);
        }
    }
    pub fn u64(&mut self, n: u64) {
        self.bytes(&n.to_le_bytes());
    }
    pub fn fx(&mut self, n: Fx) {
        self.bytes(&n.0.to_le_bytes());
    }
    pub fn finish(self) -> u64 {
        self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_arithmetic() {
        assert_eq!(Fx::ratio(-7, 2) * Fx::int(2), Fx::int(-7));
        assert_eq!(Fx::ratio(-7, 2) / Fx::int(2), Fx::ratio(-7, 4));
        assert_eq!(V2::new(Fx::int(3), Fx::int(4)).length(), Fx::int(5));
        assert_eq!(Fx::int(4).sqrt(), Fx::int(2));
        assert_eq!(Fx::EPSILON.sqrt().raw(), 65536);
    }
    #[test]
    fn sqrt_floor_invariant() {
        let mut rng = Rng(42);
        for _ in 0..10000 {
            let n = rng.next_u64() as u128;
            let r = isqrt(n);
            assert!(r * r <= n && (r + 1) * (r + 1) > n);
        }
        assert_eq!(isqrt(u128::MAX), u64::MAX as u128);
    }
    #[test]
    fn stable_rng_vector() {
        assert_eq!(Rng(0).next_u64(), 0xe220a8397b1dcdaf);
    }
    #[test]
    fn stable_hash_vector() {
        let mut h = Hash64::default();
        h.bytes(b"hello");
        assert_eq!(h.finish(), 0xa430d84680aabd0b);
    }
    #[test]
    #[should_panic]
    fn overflow_never_wraps() {
        let _ = Fx(i64::MAX) + Fx::ONE;
    }
}
