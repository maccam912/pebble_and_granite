use curl_proto::Replay;
use std::{env, fs, process};

fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("golden") => {print!("{}",curl_proto::fixtures::golden_text()?);Ok(())},
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
