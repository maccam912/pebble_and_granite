use curl_fx::{Fx, V2};
use curl_proto::{Replay, SweepFrame};
use curl_sim::{Stone, Sweep};
use std::{env, fs, process};

fn golden() -> Result<(), String> {
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
    for (name, replay) in cases {
        let outcome = replay.run()?;
        println!(
            "{name} ticks={} trace={} state={}",
            outcome.ticks, outcome.trace, outcome.state
        );
    }
    Ok(())
}
fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("golden") => golden(),
        Some("verify-session") if args.len()==2 => {
            let bytes=fs::read(&args[1]).map_err(|e|e.to_string())?;
            let log=curl_proto::session::SessionLog::parse(&bytes)?;
            let practice=curl_match::practice::Practice::from_log(log)?;
            println!("{}",serde_json::json!({"hash":format!("{:016x}",practice.sim.hash()),"tick":practice.sim.tick,"records":practice.log.records.len(),"resting":practice.sim.is_resting()}));
            Ok(())
        }
        Some("replay") if args.len() == 2 => {
            let bytes = fs::read(&args[1]).map_err(|e| e.to_string())?;
            let result = Replay::parse(&bytes)?.run()?;
            println!("{}", serde_json::to_string(&result).map_err(|e| e.to_string())?);
            Ok(())
        }
        Some("example") if args.len() == 2 => {
            fs::write(&args[1], serde_json::to_vec_pretty(&Replay::draw(42)).unwrap()).map_err(|e| e.to_string())
        }
        _ => Err("Usage: curl-server golden | replay FILE | verify-session FILE | example FILE (network listener not implemented yet)".into()),
    }
}
fn main() {
    if let Err(e) = run() {
        eprintln!("{e}");
        process::exit(1);
    }
}
