//! Fixtures captured from installed Android 83, before model 4 existed.
use crate::{practice::Practice, recorded::RecordedMatch};

#[test]
fn installed_model_three_practice_and_match_remain_loadable_and_resavable() {
    let json = include_bytes!("../../../validation/legacy/model3-practice.json");
    let practice =
        Practice::from_log(curl_proto::session::SessionLog::parse(json).unwrap()).unwrap();
    assert_eq!(practice.sim.version, 3);
    assert_eq!(format!("{:016x}", practice.sim.hash()), "276ccc1fe9c6d48e");
    let saved = serde_json::to_vec(&practice.log).unwrap();
    assert_eq!(
        Practice::from_log(curl_proto::session::SessionLog::parse(&saved).unwrap())
            .unwrap()
            .sim
            .hash(),
        practice.sim.hash()
    );
    let bytes = include_bytes!("../../../validation/legacy/model3-team-match.json");
    let game = RecordedMatch::parse(bytes).unwrap();
    assert_eq!(game.sim.version, 3);
    assert_eq!(format!("{:016x}", game.hash()), "c5a7a224feb8f845");
    let resaved = game.json().unwrap();
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&resaved).unwrap()["model"],
        3
    );
    assert_eq!(
        RecordedMatch::parse(resaved.as_bytes()).unwrap().hash(),
        game.hash()
    );
}
