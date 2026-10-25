use curl_match::room::{Compatibility, LobbyPacket, Room};
use godot::prelude::*;
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct CurlRoom {
    room: Option<Room>,
    base: Base<RefCounted>,
}
#[godot_api]
impl IRefCounted for CurlRoom {
    fn init(base: Base<RefCounted>) -> Self {
        Self { room: None, base }
    }
}
fn answer(result: Result<(), &str>) -> GString {
    match result {
        Ok(()) => GString::new(),
        Err(e) => e.into(),
    }
}
fn packet(value: LobbyPacket) -> PackedByteArray {
    match value.bytes() {
        Ok(bytes) => PackedByteArray::from(bytes.as_slice()),
        Err(_) => PackedByteArray::new(),
    }
}
#[godot_api]
impl CurlRoom {
    #[func]
    fn host_room(&mut self, identity: GString) -> GString {
        match Room::new(&identity.to_string()) {
            Ok(room) => {
                self.room = Some(room);
                GString::new()
            }
            Err(e) => e.into(),
        }
    }
    #[func]
    fn join_peer(&mut self, peer: i32, identity: GString, hello: PackedByteArray) -> GString {
        let Ok(LobbyPacket::Hello { compatibility }) = LobbyPacket::parse(hello.as_slice()) else {
            return "Invalid handshake".into();
        };
        let Some(room) = &mut self.room else {
            return "No hosted room".into();
        };
        answer(
            room.join(peer, &identity.to_string(), compatibility)
                .map(|_| ()),
        )
    }
    #[func]
    fn ready_peer(&mut self, peer: i32, ready: bool) -> GString {
        let Some(room) = &mut self.room else {
            return "No hosted room".into();
        };
        answer(room.ready(peer, ready))
    }
    #[func]
    fn forget_peer(&mut self, peer: i32) -> GString {
        let Some(room) = &mut self.room else {
            return "No hosted room".into();
        };
        answer(room.leave(peer))
    }
    #[func]
    fn start_match(&mut self, peer: i32, seed: i64) -> GString {
        let Some(room) = &mut self.room else {
            return "No hosted room".into();
        };
        answer(room.start(peer, seed as u64))
    }
    #[func]
    fn command_peer(&mut self, peer: i32, bytes: PackedByteArray) -> GString {
        let envelope = match curl_match::room::Envelope::parse(bytes.as_slice()) {
            Ok(envelope) => envelope,
            Err(error) => return (&error).into(),
        };
        let Some(room) = &mut self.room else {
            return "No hosted room".into();
        };
        answer(room.command(peer, envelope))
    }
    #[func]
    fn advance_match(&mut self, ticks: u32, thinking_ms: u32) -> GString {
        let Some(room) = &mut self.room else {
            return "No hosted room".into();
        };
        answer(room.advance(ticks, thinking_ms))
    }
    #[func]
    fn take_commit(&mut self) -> PackedByteArray {
        self.room
            .as_mut()
            .and_then(|r| r.take_commit())
            .and_then(|c| c.bytes().ok())
            .map_or(PackedByteArray::new(), |b| b.as_slice().into())
    }
    #[func]
    fn snapshot(&self) -> Option<Gd<CurlSnapshot>> {
        let room = self.room.as_ref()?;
        let sender = curl_match::sync::SnapshotSender::new(
            room.epoch(),
            room.revision(),
            room.journal().ok()?.into_bytes(),
        )
        .ok()?;
        Some(Gd::from_init_fn(|base| CurlSnapshot { sender, base }))
    }
    #[func]
    fn confirm_sync(&mut self, peer: i32, epoch: u32, revision: u32, hash: GString) -> GString {
        let Ok(hash) = u64::from_str_radix(&hash.to_string(), 16) else {
            return "Invalid state hash".into();
        };
        let Some(room) = &mut self.room else {
            return "No hosted room".into();
        };
        answer(room.confirm_sync(peer, epoch, revision, hash))
    }
    #[func]
    fn state_packet(&self) -> PackedByteArray {
        self.room.as_ref().map_or(PackedByteArray::new(), |room| {
            packet(LobbyPacket::State { room: room.view() })
        })
    }
    #[func]
    fn hello_packet() -> PackedByteArray {
        packet(LobbyPacket::Hello {
            compatibility: Compatibility::CURRENT,
        })
    }
    #[func]
    fn ready_packet(ready: bool) -> PackedByteArray {
        packet(LobbyPacket::Ready { ready })
    }
    #[func]
    fn reject_packet(reason: GString) -> PackedByteArray {
        packet(LobbyPacket::Reject {
            reason: reason.to_string(),
        })
    }
    #[func]
    fn decode_packet(bytes: PackedByteArray) -> GString {
        LobbyPacket::parse(bytes.as_slice())
            .and_then(|p| serde_json::to_string(&p).map_err(|e| e.to_string()))
            .map_or(GString::new(), |s| GString::from(&s))
    }
}

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct CurlSnapshot {
    sender: curl_match::sync::SnapshotSender,
    base: Base<RefCounted>,
}
#[godot_api]
impl CurlSnapshot {
    #[func]
    fn next_packet(&mut self) -> PackedByteArray {
        self.sender
            .next_packet()
            .map_or(PackedByteArray::new(), |bytes| bytes.as_slice().into())
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct CurlReplica {
    replica: Option<curl_match::sync::Replica>,
    receiver: curl_match::sync::SnapshotReceiver,
    base: Base<RefCounted>,
}
#[godot_api]
impl IRefCounted for CurlReplica {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            replica: None,
            receiver: Default::default(),
            base,
        }
    }
}
#[godot_api]
impl CurlReplica {
    #[func]
    fn receive_snapshot(&mut self, bytes: PackedByteArray) -> GString {
        match self.receiver.receive(bytes.as_slice()) {
            Ok(Some(replica)) => {
                self.replica = Some(replica);
                GString::new()
            }
            Ok(None) => GString::new(),
            Err(error) => (&error).into(),
        }
    }
    #[func]
    fn apply_commit(&mut self, bytes: PackedByteArray) -> GString {
        let commit = match curl_match::sync::Commit::parse(bytes.as_slice()) {
            Ok(commit) => commit,
            Err(error) => return (&error).into(),
        };
        let Some(replica) = &mut self.replica else {
            return "Replica not initialized".into();
        };
        answer(replica.apply(&commit))
    }
    #[func]
    fn state_hash(&self) -> GString {
        self.replica.as_ref().map_or(GString::new(), |r| {
            GString::from(&format!("{:016x}", r.game.hash()))
        })
    }
    #[func]
    fn revision(&self) -> i64 {
        self.replica.as_ref().map_or(-1, |r| r.revision as i64)
    }
    #[func]
    fn epoch(&self) -> i64 {
        self.replica.as_ref().map_or(0, |r| r.epoch as i64)
    }
    #[func]
    fn phase(&self) -> GString {
        self.replica.as_ref().map_or(GString::new(), |r| {
            GString::from(&format!("{:?}", r.game.game.phase))
        })
    }
}
