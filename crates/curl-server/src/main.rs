use curl_proto::Replay;
use std::{env, fs, process};
fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().skip(1).collect();
    match args.first().map(String::as_str){
        Some("golden")=>{
            for seed in [0,42,999]{
                let mut replay=Replay::draw(seed);replay.varied_ice=seed!=0;
                let outcome=replay.run()?;
                println!("seed={seed} ticks={} trace={} state={}",outcome.ticks,outcome.trace,outcome.state);
            }Ok(())
        }
        Some("replay") if args.len()==2=>{let bytes=fs::read(&args[1]).map_err(|e|e.to_string())?;let result=Replay::parse(&bytes)?.run()?;println!("{}",serde_json::to_string(&result).map_err(|e|e.to_string())?);Ok(())}
        Some("example") if args.len()==2=>fs::write(&args[1],serde_json::to_vec_pretty(&Replay::draw(42)).unwrap()).map_err(|e|e.to_string()),
        _=>Err("Usage: curl-server golden | replay FILE | example FILE (network listener not implemented yet)".into())
    }
}
fn main() {
    if let Err(e) = run() {
        eprintln!("{e}");
        process::exit(1);
    }
}
