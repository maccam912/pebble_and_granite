//! Ordered host-accepted inputs, never a stream of stone positions.
use crate::recorded::{Record, RecordedMatch};
use serde::{Deserialize, Serialize};

pub const SYNC_SCHEMA: u32 = 1;
const SNAPSHOT_LIMIT: usize = 16 * 1024 * 1024;
const HEADER: usize = 28;
const CHUNK: usize = 1000;

/// Reliable channel 2 carries a bounded journal, not mutable Rust snapshots.
pub struct SnapshotSender {
    epoch: u32,
    revision: u32,
    journal: Vec<u8>,
    offset: usize,
    checksum: u64,
}
fn checksum(bytes: &[u8]) -> u64 {
    let mut hash = curl_fx::Hash64::default();
    hash.bytes(bytes);
    hash.finish()
}
impl SnapshotSender {
    pub fn new(epoch: u32, revision: u32, journal: Vec<u8>) -> Result<Self, &'static str> {
        if epoch == 0 || journal.is_empty() || journal.len() > SNAPSHOT_LIMIT {
            return Err("invalid snapshot size or epoch");
        }
        Ok(Self {
            epoch,
            revision,
            checksum: checksum(&journal),
            journal,
            offset: 0,
        })
    }
    pub fn next_packet(&mut self) -> Option<Vec<u8>> {
        if self.offset == self.journal.len() {
            return None;
        }
        let end = (self.offset + CHUNK).min(self.journal.len());
        let mut packet = Vec::with_capacity(HEADER + end - self.offset);
        packet.extend_from_slice(b"PGS1");
        for value in [
            self.epoch,
            self.revision,
            self.journal.len() as u32,
            self.offset as u32,
        ] {
            packet.extend_from_slice(&value.to_le_bytes());
        }
        packet.extend_from_slice(&self.checksum.to_le_bytes());
        packet.extend_from_slice(&self.journal[self.offset..end]);
        self.offset = end;
        Some(packet)
    }
}

#[derive(Default)]
pub struct SnapshotReceiver {
    transfer: Option<IncomingSnapshot>,
}
struct IncomingSnapshot {
    epoch: u32,
    revision: u32,
    size: usize,
    checksum: u64,
    journal: Vec<u8>,
}
impl SnapshotReceiver {
    /// Callers impose a wall-clock deadline and reset by dropping this object.
    /// Errors discard only the incomplete transfer; an existing replica is intact.
    pub fn receive(&mut self, packet: &[u8]) -> Result<Option<Replica>, String> {
        let result = self.accept(packet);
        if result.is_err() {
            self.transfer = None;
        }
        result
    }
    fn accept(&mut self, packet: &[u8]) -> Result<Option<Replica>, String> {
        if packet.len() <= HEADER || packet.len() > HEADER + CHUNK || &packet[..4] != b"PGS1" {
            return Err("invalid snapshot packet".into());
        }
        let number = |offset| u32::from_le_bytes(packet[offset..offset + 4].try_into().unwrap());
        let epoch = number(4);
        let revision = number(8);
        let size = number(12) as usize;
        let offset = number(16) as usize;
        let expected = u64::from_le_bytes(packet[20..28].try_into().unwrap());
        let body = &packet[HEADER..];
        if epoch == 0
            || size == 0
            || size > SNAPSHOT_LIMIT
            || offset > size
            || body.len() > size - offset
            || body.len() != CHUNK.min(size - offset)
        {
            return Err("invalid snapshot bounds".into());
        }
        if self.transfer.is_none() {
            if offset != 0 {
                return Err("snapshot does not start at zero".into());
            }
            self.transfer = Some(IncomingSnapshot {
                epoch,
                revision,
                journal: Vec::new(),
                size,
                checksum: expected,
            });
        }
        let transfer = self.transfer.as_mut().unwrap();
        if transfer.epoch != epoch
            || transfer.revision != revision
            || transfer.size != size
            || transfer.checksum != expected
            || transfer.journal.len() != offset
        {
            return Err("snapshot gap or mixed transfer".into());
        }
        transfer.journal.extend_from_slice(body);
        if transfer.journal.len() != size {
            return Ok(None);
        }
        let transfer = self.transfer.take().unwrap();
        if checksum(&transfer.journal) != expected {
            return Err("snapshot checksum mismatch".into());
        }
        Replica::restore(epoch, revision, &transfer.journal).map(Some)
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Commit {
    pub schema: u32,
    pub epoch: u32,
    pub revision: u32,
    pub before: String,
    pub after: String,
    pub records: Vec<Record>,
}
impl Commit {
    pub fn validate(&self) -> Result<(), &'static str> {
        let hash = |s: &str| {
            s.len() == 16
                && s.bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        };
        if self.schema != SYNC_SCHEMA
            || self.epoch == 0
            || self.revision == 0
            || !hash(&self.before)
            || !hash(&self.after)
            || self.records.is_empty()
            || self.records.len() > 2
        {
            return Err("invalid commit header");
        }
        for record in &self.records {
            match record {
                Record::Step { ticks, brush } if *ticks == 0 || *ticks > 24 || brush.is_some() => {
                    return Err("invalid network step");
                }
                Record::Think { ms } if *ms > 1000 => return Err("invalid network time"),
                _ => {}
            }
        }
        Ok(())
    }
    pub fn bytes(&self) -> Result<Vec<u8>, String> {
        self.validate()?;
        let bytes = serde_json::to_vec(self).map_err(|e| e.to_string())?;
        if bytes.len() > 1200 {
            return Err("commit exceeds packet limit".into());
        }
        Ok(bytes)
    }
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() > 1200 {
            return Err("commit exceeds packet limit".into());
        }
        let value: Self = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        value.validate()?;
        Ok(value)
    }
}

pub struct Replica {
    pub game: RecordedMatch,
    pub epoch: u32,
    pub revision: u32,
}
impl Replica {
    /// The caller must obtain epoch/revision/journal from the authenticated host.
    pub fn restore(epoch: u32, revision: u32, journal: &[u8]) -> Result<Self, String> {
        if epoch == 0 {
            return Err("invalid replica epoch".into());
        }
        Ok(Self {
            game: RecordedMatch::parse(journal)?,
            epoch,
            revision,
        })
    }
    pub fn apply(&mut self, commit: &Commit) -> Result<(), &'static str> {
        commit.validate()?;
        if commit.epoch != self.epoch
            || Some(commit.revision) != self.revision.checked_add(1)
            || commit.before != format!("{:016x}", self.game.hash())
        {
            return Err("replica gap or previous state mismatch");
        }
        // A failed hash/record never partially advances the visible client state.
        let mut next = self.game.clone();
        for record in &commit.records {
            next.apply(record.clone())?;
        }
        if commit.after != format!("{:016x}", next.hash()) {
            return Err("replica state mismatch");
        }
        self.game = next;
        self.revision = commit.revision;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::room::{Command, Compatibility, Envelope, Room};
    use curl_rules::{Phase, PowerPlay};
    use curl_sim::{Release, Sweep};
    fn room() -> Room {
        let mut room = Room::new(&"A".repeat(43)).unwrap();
        for n in 2..=4 {
            room.join(
                n,
                &char::from(b'A' + n as u8).to_string().repeat(43),
                Compatibility::CURRENT,
            )
            .unwrap();
        }
        for n in 1..=4 {
            room.ready(n, true).unwrap();
        }
        room.start(1, 42).unwrap();
        room
    }
    fn send(room: &mut Room, peer: i32, sequence: u32, command: Command) {
        room.command(
            peer,
            Envelope {
                epoch: room.epoch(),
                sequence,
                command,
            },
        )
        .unwrap();
    }
    fn copy(room: &Room) -> Replica {
        Replica::restore(
            room.epoch(),
            room.revision(),
            room.journal().unwrap().as_bytes(),
        )
        .unwrap()
    }
    fn deliver(room: &mut Room, replicas: &mut [&mut Replica]) {
        while let Some(commit) = room.take_commit() {
            let decoded = Commit::parse(&commit.bytes().unwrap()).unwrap();
            for replica in &mut *replicas {
                replica.apply(&decoded).unwrap();
                assert_eq!(replica.game.hash(), room.state_hash().unwrap());
            }
        }
    }
    #[test]
    fn live_inputs_late_sweeps_and_reconnect_reproduce_host() {
        let mut room = room();
        let mut first = copy(&room);
        send(
            &mut room,
            3,
            1,
            Command::Place {
                own_house: true,
                side: PowerPlay::None,
            },
        );
        deliver(&mut room, &mut [&mut first]);
        room.advance(0, 137).unwrap();
        deliver(&mut room, &mut [&mut first]);
        send(
            &mut room,
            1,
            1,
            Command::Release {
                release: Release::draw(),
            },
        );
        deliver(&mut room, &mut [&mut first]);
        room.advance(24, 0).unwrap();
        deliver(&mut room, &mut [&mut first]);
        let tick = room.authority().unwrap().sim.tick;
        send(
            &mut room,
            1,
            2,
            Command::Sweep {
                tick: tick - 12,
                input: Sweep {
                    stone: 2,
                    brush: 0,
                    effort: 220,
                    lateral_mm: 0,
                    ahead_mm: 250,
                },
            },
        );
        deliver(&mut room, &mut [&mut first]);
        // A reconnect restored in flight must retain the release snapshot and
        // accepted late-input history, not merely current stone coordinates.
        let mut rejoined = copy(&room);
        send(
            &mut room,
            1,
            3,
            Command::Sweep {
                tick: tick - 6,
                input: Sweep {
                    stone: 2,
                    brush: 0,
                    effort: 190,
                    lateral_mm: 20,
                    ahead_mm: 250,
                },
            },
        );
        deliver(&mut room, &mut [&mut first, &mut rejoined]);
        while room.authority().unwrap().game.phase == Phase::InFlight {
            room.advance(24, 0).unwrap();
            deliver(&mut room, &mut [&mut first, &mut rejoined]);
        }
        assert_eq!(first.game.hash(), rejoined.game.hash());
        assert_eq!(first.game.game.delivered, 1);
    }
    #[test]
    fn journal_transfer_bounds_order_and_checksum() {
        let mut room = room();
        send(
            &mut room,
            3,
            1,
            Command::Place {
                own_house: true,
                side: PowerPlay::None,
            },
        );
        send(
            &mut room,
            1,
            1,
            Command::Release {
                release: Release::draw(),
            },
        );
        for i in 0..150 {
            room.advance(1, 0).unwrap();
            send(
                &mut room,
                1,
                i + 2,
                Command::Sweep {
                    tick: i + 1,
                    input: Sweep::centered(2, 200),
                },
            );
            while room.take_commit().is_some() {}
        }
        let mut sender = SnapshotSender::new(
            room.epoch(),
            room.revision(),
            room.journal().unwrap().into_bytes(),
        )
        .unwrap();
        let mut packets = Vec::new();
        while let Some(packet) = sender.next_packet() {
            packets.push(packet);
        }
        assert!(packets.len() > 2);
        let mut receiver = SnapshotReceiver::default();
        let mut result = None;
        for packet in &packets {
            result = receiver.receive(packet).unwrap();
        }
        let replica = result.unwrap();
        assert_eq!(replica.game.hash(), room.state_hash().unwrap());
        assert_eq!(replica.revision, room.revision());
        assert!(receiver.receive(&packets[1]).is_err());
        receiver.receive(&packets[0]).unwrap();
        assert!(receiver.receive(&packets[0]).is_err());
        let mut oversized = packets[0].clone();
        oversized[12..16].copy_from_slice(&u32::MAX.to_le_bytes());
        assert!(receiver.receive(&oversized).is_err());
        let last = packets.len() - 1;
        *packets[last].last_mut().unwrap() ^= 1;
        for packet in &packets[..last] {
            assert!(receiver.receive(packet).unwrap().is_none());
        }
        assert!(receiver.receive(&packets[last]).is_err());
        assert_eq!(replica.game.hash(), room.state_hash().unwrap());
    }

    #[test]
    fn corruption_gaps_duplicates_and_old_epochs_are_atomic() {
        let mut room = room();
        let mut replica = copy(&room);
        send(
            &mut room,
            3,
            1,
            Command::Place {
                own_house: true,
                side: PowerPlay::None,
            },
        );
        let commit = room.take_commit().unwrap();
        let before = replica.game.hash();
        for altered in 0..4 {
            let mut bad = commit.clone();
            match altered {
                0 => bad.after = "0000000000000000".into(),
                1 => bad.revision += 1,
                2 => bad.epoch += 1,
                _ => bad.records.push(Record::NextEnd {}),
            }
            assert!(replica.apply(&bad).is_err());
            assert_eq!(replica.game.hash(), before);
            assert_eq!(replica.revision, 0);
        }
        replica.apply(&commit).unwrap();
        assert!(replica.apply(&commit).is_err());
        assert!(Commit::parse(&vec![b' '; 1201]).is_err());
        let mut value = serde_json::to_value(&commit).unwrap();
        value["unknown"] = true.into();
        assert!(Commit::parse(&serde_json::to_vec(&value).unwrap()).is_err());
    }
}
