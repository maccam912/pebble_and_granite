use curl_sim::*;
fn main() {
    for effort in [0, 255] {
        let mut s = Sim::new(1);
        s.release(Release::draw()).unwrap();
        while !s.is_resting() {
            s.step(&[Sweep::centered(0, effort)]);
        }
        let a = &s.stones[0];
        println!(
            "effort={effort} ticks={} x={} y={} turns={} active={} hog={:?}",
            s.tick,
            a.pos.x.raw() as f64 / 4294967296.,
            a.pos.y.raw() as f64 / 4294967296.,
            a.turns.raw() as f64 / 4294967296.,
            a.active,
            s.hog_tick
        );
    }
}
