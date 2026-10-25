//! Connection identity and player seats are distinct. Callers must obtain identity
//! from the authenticated transport, never from the client's claimed name.
use crate::{Authority, Seat};
use curl_fx::Hash64;
use curl_proto::PROTOCOL_VERSION;
use curl_rules::{Phase, PowerPlay, RULES_VERSION, Remedy, Rules};
use curl_sim::{MODEL_VERSION, Release, Sweep};
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Compatibility {
    pub protocol: u32,
    pub model: u32,
    pub rules: u32,
}
impl Compatibility {
    pub const CURRENT: Self = Self {
        protocol: PROTOCOL_VERSION,
        model: MODEL_VERSION,
        rules: RULES_VERSION,
    };
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Player {
    pub identity: String,
    pub peer: Option<i32>,
    pub ready: bool,
    pub synchronized: bool,
    sequence: u32,
    seen: u128,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "kind", deny_unknown_fields)]
pub enum Command {
    Place { own_house: bool, side: PowerPlay },
    Order { first: u8 },
    Release { release: Release },
    Sweep { tick: u32, input: Sweep },
    Remedy { remedy: Remedy },
    Concede {},
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Envelope {
    pub epoch: u32,
    pub sequence: u32,
    pub command: Command,
}
impl Envelope {
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() > 1200 {
            return Err("command exceeds packet limit".into());
        }
        serde_json::from_slice(bytes).map_err(|e| e.to_string())
    }
}
pub struct Room {
    host_identity: String,
    players: [Option<Player>; 4],
    authority: Option<Authority>,
    epoch: u32,
}
impl Room {
    pub fn new(host_identity: &str) -> Result<Self, &'static str> {
        let mut room = Self {
            host_identity: host_identity.into(),
            players: std::array::from_fn(|_| None),
            authority: None,
            epoch: 0,
        };
        room.join(1, host_identity, Compatibility::CURRENT)?;
        Ok(room)
    }
    pub fn players(&self) -> &[Option<Player>; 4] {
        &self.players
    }
    pub fn authority(&self) -> Option<&Authority> {
        self.authority.as_ref()
    }
    pub fn epoch(&self) -> u32 {
        self.epoch
    }
    fn index(&self, peer: i32) -> Result<usize, &'static str> {
        self.players
            .iter()
            .position(|p| p.as_ref().is_some_and(|p| p.peer == Some(peer)))
            .ok_or("unknown connection")
    }
    fn seat(index: usize) -> Seat {
        Seat {
            team: (index / 2) as u8,
            position: (index % 2) as u8,
        }
    }
    pub fn join(
        &mut self,
        peer: i32,
        identity: &str,
        compat: Compatibility,
    ) -> Result<Seat, &'static str> {
        if (peer == 1) != (identity == self.host_identity)
            || peer < 1
            || identity.len() != 43
            || !identity
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
            || compat != Compatibility::CURRENT
        {
            return Err("invalid or incompatible connection");
        }
        if self.index(peer).is_ok() {
            return Err("connection already bound");
        }
        if let Some(index) = self
            .players
            .iter()
            .position(|p| p.as_ref().is_some_and(|p| p.identity == identity))
        {
            let player = self.players[index].as_mut().unwrap();
            if player.peer.is_some() {
                return Err("identity already connected");
            }
            player.peer = Some(peer);
            player.ready = false;
            player.synchronized = self.authority.is_none();
            return Ok(Self::seat(index));
        }
        if self.authority.is_some() {
            return Err("game seats are reserved");
        }
        let index = self
            .players
            .iter()
            .enumerate()
            .position(|(index, player)| player.is_none() && (index == 0) == (peer == 1))
            .ok_or("room full")?;
        self.players[index] = Some(Player {
            identity: identity.into(),
            peer: Some(peer),
            ready: false,
            synchronized: true,
            sequence: 0,
            seen: 0,
        });
        self.clear_ready();
        Ok(Self::seat(index))
    }
    fn clear_ready(&mut self) {
        for player in self.players.iter_mut().flatten() {
            player.ready = false;
        }
    }
    pub fn leave(&mut self, peer: i32) -> Result<(), &'static str> {
        let index = self.index(peer)?;
        if self.authority.is_some() {
            let player = self.players[index].as_mut().unwrap();
            player.peer = None;
            player.synchronized = false;
        } else {
            self.players[index] = None;
        }
        self.clear_ready();
        Ok(())
    }
    pub fn ready(&mut self, peer: i32, value: bool) -> Result<(), &'static str> {
        if self.authority.is_some() {
            return Err("game already started");
        }
        let index = self.index(peer)?;
        self.players[index].as_mut().unwrap().ready = value;
        Ok(())
    }
    pub fn start(&mut self, peer: i32, seed: u64) -> Result<(), &'static str> {
        if self.index(peer)? != 0
            || self.authority.is_some()
            || self
                .players
                .iter()
                .any(|p| p.as_ref().is_none_or(|p| !p.ready || p.peer.is_none()))
        {
            return Err("host and four ready players required");
        }
        let epoch = self.epoch.checked_add(1).ok_or("room epoch exhausted")?;
        let authority = Authority::new(seed, Rules::mixed(), 1)?;
        self.authority = Some(authority);
        self.epoch = epoch;
        for player in self.players.iter_mut().flatten() {
            player.sequence = 0;
            player.seen = 0;
        }
        Ok(())
    }
    pub fn paused(&self) -> bool {
        self.authority.is_some()
            && self.players.iter().any(|p| {
                p.as_ref()
                    .is_none_or(|p| p.peer.is_none() || !p.synchronized)
            })
    }
    /// Hash includes rules, clocks, and choices, not merely stone positions.
    pub fn state_hash(&self) -> Result<u64, &'static str> {
        let a = self.authority.as_ref().ok_or("no game")?;
        let mut h = Hash64::default();
        h.u64(a.sim.hash());
        let rules = serde_json::to_vec(&a.game).map_err(|_| "cannot encode rules")?;
        h.bytes(&rules);
        h.u64(a.release_snapshot.as_ref().map_or(0, |sim| sim.hash()));
        h.bytes(&serde_json::to_vec(&a.accepted_sweeps()).map_err(|_| "cannot encode sweeps")?);
        Ok(h.finish())
    }
    pub fn confirm_sync(&mut self, peer: i32, epoch: u32, hash: u64) -> Result<(), &'static str> {
        let index = self.index(peer)?;
        if epoch != self.epoch || hash != self.state_hash()? {
            return Err("resync mismatch");
        }
        self.players[index].as_mut().unwrap().synchronized = true;
        Ok(())
    }
    pub fn command(&mut self, peer: i32, envelope: Envelope) -> Result<(), &'static str> {
        let index = self.index(peer)?;
        if self.paused() || envelope.epoch != self.epoch {
            return Err("game paused or stale epoch");
        }
        let player = self.players[index].as_mut().unwrap();
        if envelope.sequence == 0 {
            return Err("zero command sequence");
        }
        if envelope.sequence > player.sequence {
            let distance = envelope.sequence - player.sequence;
            player.seen = if distance >= 128 {
                1
            } else {
                (player.seen << distance) | 1
            };
            player.sequence = envelope.sequence;
        } else {
            let distance = player.sequence - envelope.sequence;
            if distance >= 128 || player.seen & (1u128 << distance) != 0 {
                return Err("duplicate or stale command");
            }
            player.seen |= 1u128 << distance;
        }
        // A bounded receive window permits reordered sweep packets, while even
        // rejected requests are consumed so retries cannot replay a failed action.
        let seat = Self::seat(index);
        let a = self.authority.as_mut().ok_or("no game")?;
        match envelope.command {
            Command::Place { own_house, side } => a.place_mixed(seat, own_house, side),
            Command::Order { first } => a.game.set_first_thrower(seat.team, first),
            Command::Release { release } => a.release(seat, release),
            Command::Sweep { tick, input } => a.sweep(seat, tick, input).map(|_| ()),
            Command::Remedy { remedy } => a.choose(seat, remedy),
            Command::Concede {} => a.game.concede(seat.team),
        }
    }
    pub fn step(&mut self, thinking_ms: u32) -> Result<(), &'static str> {
        if self.paused() {
            return Err("game paused for disconnected player");
        }
        let a = self.authority.as_mut().ok_or("no game")?;
        a.game.think(thinking_ms);
        a.step()
    }
    pub fn next_end(&mut self, peer: i32) -> Result<(), &'static str> {
        if self.index(peer)? != 0 || self.paused() {
            return Err("host required and room must be connected");
        }
        self.authority.as_mut().ok_or("no game")?.next_end()
    }
    pub fn rematch(&mut self, peer: i32) -> Result<(), &'static str> {
        if self.index(peer)? != 0
            || self
                .authority
                .as_ref()
                .is_none_or(|a| a.game.phase != Phase::GameComplete)
        {
            return Err("finished game and host required");
        }
        self.authority = None;
        for player in &mut self.players {
            if player.as_ref().is_some_and(|p| p.peer.is_none()) {
                *player = None;
            }
        }
        self.clear_ready();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn identity(n: u8) -> String {
        char::from(b'A' + n).to_string().repeat(43)
    }
    fn lobby() -> Room {
        let mut r = Room::new(&identity(0)).unwrap();
        for n in 1..4 {
            r.join(n + 1, &identity(n as u8), Compatibility::CURRENT)
                .unwrap();
        }
        for peer in 1..=4 {
            r.ready(peer, true).unwrap();
        }
        r
    }
    fn send(r: &mut Room, peer: i32, sequence: u32, command: Command) -> Result<(), &'static str> {
        r.command(
            peer,
            Envelope {
                epoch: r.epoch(),
                sequence,
                command,
            },
        )
    }
    #[test]
    fn lobby_capacity_versions_and_host_control() {
        let mut r = lobby();
        assert!(r.join(5, &identity(5), Compatibility::CURRENT).is_err());
        assert!(r.start(2, 42).is_err());
        r.ready(4, false).unwrap();
        assert!(r.start(1, 42).is_err());
        r.ready(4, true).unwrap();
        r.start(1, 42).unwrap();
        assert_eq!(r.epoch(), 1);
        let mut r = Room::new(&identity(0)).unwrap();
        let mut old = Compatibility::CURRENT;
        old.rules += 1;
        assert!(r.join(2, &identity(1), old).is_err());
        assert_eq!(r.players().iter().flatten().count(), 1);
        assert!(r.join(2, &identity(0), Compatibility::CURRENT).is_err());
    }
    #[test]
    fn connection_seat_overrides_claimed_stone_and_team() {
        let mut r = lobby();
        r.start(1, 42).unwrap();
        assert!(
            send(
                &mut r,
                1,
                1,
                Command::Place {
                    own_house: true,
                    side: PowerPlay::None
                }
            )
            .is_err()
        );
        send(
            &mut r,
            3,
            1,
            Command::Place {
                own_house: true,
                side: PowerPlay::None,
            },
        )
        .unwrap();
        let mut release = Release::draw();
        release.team = 1;
        release.stone = 15;
        assert!(
            send(
                &mut r,
                2,
                1,
                Command::Release {
                    release: release.clone()
                }
            )
            .is_err()
        );
        send(&mut r, 1, 2, Command::Release { release }).unwrap();
        let a = r.authority().unwrap();
        assert_eq!(a.sim.delivered, Some(2));
        assert_eq!(a.sim.stones.iter().find(|s| s.id == 2).unwrap().team, 0);
    }
    #[test]
    fn reconnect_reserves_seat_pauses_clock_and_checks_full_state() {
        let mut r = lobby();
        r.start(1, 42).unwrap();
        send(
            &mut r,
            3,
            1,
            Command::Place {
                own_house: true,
                side: PowerPlay::None,
            },
        )
        .unwrap();
        let state = r.state_hash().unwrap();
        r.leave(3).unwrap();
        assert!(r.paused());
        assert!(r.step(9999).is_err());
        assert_eq!(r.state_hash().unwrap(), state);
        assert!(r.join(30, &identity(5), Compatibility::CURRENT).is_err());
        assert_eq!(
            r.join(30, &identity(2), Compatibility::CURRENT).unwrap(),
            Seat {
                team: 1,
                position: 0
            }
        );
        assert!(r.confirm_sync(30, 1, state ^ 1).is_err());
        assert!(r.paused());
        r.confirm_sync(30, 1, state).unwrap();
        assert!(!r.paused());
        assert!(send(&mut r, 3, 2, Command::Order { first: 1 }).is_err());
        assert!(send(&mut r, 30, 1, Command::Order { first: 1 }).is_err());
        send(&mut r, 30, 2, Command::Order { first: 1 }).unwrap();
        assert_ne!(r.state_hash().unwrap(), state);
    }
    #[test]
    fn rematch_requires_readiness_and_rejects_previous_epoch() {
        let mut r = lobby();
        r.start(1, 42).unwrap();
        send(
            &mut r,
            3,
            1,
            Command::Place {
                own_house: true,
                side: PowerPlay::None,
            },
        )
        .unwrap();
        send(&mut r, 1, 1, Command::Concede {}).unwrap();
        assert!(r.rematch(2).is_err());
        r.rematch(1).unwrap();
        assert!(r.start(1, 43).is_err());
        for peer in 1..=4 {
            r.ready(peer, true).unwrap();
        }
        r.start(1, 43).unwrap();
        assert_eq!(r.epoch(), 2);
        assert!(
            r.command(
                3,
                Envelope {
                    epoch: 1,
                    sequence: 100,
                    command: Command::Place {
                        own_house: true,
                        side: PowerPlay::None
                    }
                }
            )
            .is_err()
        );
        assert_eq!(r.authority().unwrap().game.phase, Phase::Placement);
    }
    #[test]
    fn packet_boundary_rejects_oversize_unknown_fields_and_numbers() {
        assert!(Envelope::parse(&vec![b' '; 1201]).is_err());
        assert!(
            Envelope::parse(br#"{"epoch":1,"sequence":1,"seat":0,"command":{"kind":"Concede"}}"#)
                .is_err()
        );
        assert!(
            Envelope::parse(br#"{"epoch":1,"sequence":-1,"command":{"kind":"Concede"}}"#).is_err()
        );
        assert!(
            Envelope::parse(br#"{"epoch":1,"sequence":1,"command":{"kind":"Concede","team":1}}"#)
                .is_err()
        );
        let e = Envelope {
            epoch: 1,
            sequence: 1,
            command: Command::Release {
                release: Release::draw(),
            },
        };
        let bytes = serde_json::to_vec(&e).unwrap();
        assert!(Envelope::parse(&bytes).is_ok());
    }
    #[test]
    fn reordered_sweeps_are_accepted_once_within_receive_window() {
        let mut r = lobby();
        r.start(1, 42).unwrap();
        send(
            &mut r,
            3,
            1,
            Command::Place {
                own_house: true,
                side: PowerPlay::None,
            },
        )
        .unwrap();
        send(
            &mut r,
            1,
            1,
            Command::Release {
                release: Release::draw(),
            },
        )
        .unwrap();
        let input = Sweep::centered(2, 255);
        send(&mut r, 1, 3, Command::Sweep { tick: 1, input }).unwrap();
        send(&mut r, 1, 2, Command::Sweep { tick: 0, input }).unwrap();
        assert_eq!(r.authority().unwrap().accepted_sweeps().len(), 2);
        assert!(send(&mut r, 1, 2, Command::Sweep { tick: 2, input }).is_err());
        assert!(send(&mut r, 1, 200, Command::Order { first: 0 }).is_err());
        assert!(send(&mut r, 1, 4, Command::Sweep { tick: 2, input }).is_err());
    }
}
