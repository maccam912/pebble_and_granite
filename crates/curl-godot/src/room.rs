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
