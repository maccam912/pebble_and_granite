use crate::{Replay, SweepFrame};
use curl_fx::{Fx, V2};
use curl_sim::{Stone, Sweep};

pub fn golden_text() -> Result<String, String> {
    golden_text_for(curl_sim::MODEL_VERSION)
}
pub fn golden_text_for(model: u32) -> Result<String, String> {
    let mut cases = Vec::new();
    for seed in [0, 42, 999] {
        let mut replay = Replay::draw(seed);
        replay.varied_ice = seed != 0;
        cases.push((format!("draw-{seed}"), replay));
    }
    let mut swept = Replay::draw(42);
    swept.sweeps = (0..4000)
        .map(|tick| SweepFrame {
            tick,
            inputs: vec![Sweep::centered(0, 255)],
        })
        .collect();
    cases.push(("swept".into(), swept));
    let mut reverse = Replay::draw(42);
    reverse.release.spin = -reverse.release.spin;
    cases.push(("counterclockwise".into(), reverse));
    let mut hit = Replay::draw(42);
    hit.release.spin = Fx::ZERO;
    hit.release.vel = V2::new(Fx::ZERO, Fx::int(3));
    hit.initial.push(Stone::resting(1, 1, V2::ZERO));
    hit.initial
        .push(Stone::resting(2, 0, V2::new(Fx::ZERO, Fx::ratio(3, 10))));
    cases.push(("runback".into(), hit));
    let mut output = String::new();
    for (name, mut replay) in cases {
        replay.model = model;
        let outcome = replay.run()?;
        output.push_str(&format!(
            "{name} ticks={} trace={} state={}\n",
            outcome.ticks, outcome.trace, outcome.state
        ));
    }
    Ok(output)
}

#[test]
fn model_three_replays_keep_every_tick_trace() {
    assert_eq!(
        golden_text_for(3).unwrap(),
        include_str!("../../../validation/legacy/model3-golden.txt")
    );
}
