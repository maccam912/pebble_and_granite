use std::collections::{HashMap, VecDeque};

use bytes::Bytes;
use godot::classes::multiplayer_peer::{ConnectionStatus, TransferMode};
use godot::classes::{IMultiplayerPeerExtension, MultiplayerPeerExtension};
use godot::global::Error;
use godot::prelude::*;
use tokio::sync::mpsc::error::TryRecvError;
use tokio::sync::mpsc::{Receiver, Sender, channel};

use crate::IrohRuntime;
use crate::connection::{IrohConnection, IrohListener};

#[derive(GodotClass)]
#[class(tool, no_init, base=MultiplayerPeerExtension)]
struct IrohServer {
    base: Base<MultiplayerPeerExtension>,
    listener: IrohListener,
    accepted_peer_sender: Sender<(i32, IrohConnection)>,
    accepted_peer_receiver: Receiver<(i32, IrohConnection)>,
    refuse_new_connections: bool,
    peers: HashMap<i32, IrohConnection>,
    last_peer_id: i32,
    received_packets: VecDeque<(i32, i32, TransferMode, Bytes)>,
    target_peer_id: i32,
    transfer_channel: i32,
    transfer_mode: TransferMode,
}

#[godot_api]
impl IrohServer {
    /// Starts a server that is listening for incoming connections.
    ///
    /// Other clients can connect to this server by calling the connect function on `IrohClient`
    /// using the connection string returned by the [Self::connection_string] function.
    #[func]
    fn start() -> Option<Gd<Self>> {
        Self::start_configured(false)
    }

    #[func]
    fn start_configured(relay_only: bool) -> Option<Gd<Self>> {
        let listener = match IrohRuntime::block_on(IrohListener::new(relay_only)) {
            Ok(listener) => listener,
            Err(_) => return None,
        };
        let (accepted_peer_sender, accepted_peer_receiver) = channel(32);
        Some(Gd::from_init_fn(|base| Self {
            base,
            listener,
            accepted_peer_sender,
            accepted_peer_receiver,
            refuse_new_connections: false,
            peers: HashMap::new(),
            last_peer_id: 1,
            received_packets: VecDeque::new(),
            transfer_channel: 0,
            transfer_mode: TransferMode::RELIABLE,
            target_peer_id: 0,
        }))
    }

    /// Returns the connection string that can be used to connect to this server.
    #[func]
    fn connection_string(&self) -> GString {
        self.listener.connection_string().to_godot_owned()
    }

    /// Connect to an other server using the connection string.
    #[func]
    fn connect_endpoint(&mut self, connection_string: GString) {
        let node_id = connection_string.to_string();
        let peer_id = {
            self.last_peer_id = (self.last_peer_id + 1) % i32::MAX;
            if self.last_peer_id < 2 {
                self.last_peer_id = 2;
            }
            self.last_peer_id
        };
        let endpoint = self.listener.endpoint.clone();
        let accepted_peer_sender = self.accepted_peer_sender.clone();
        IrohRuntime::spawn(async move {
            let (_, connection) = IrohConnection::connect(endpoint, node_id).await?;
            accepted_peer_sender.send((peer_id, connection)).await?;
            Ok::<(), anyhow::Error>(())
        });
    }

    /// Returns a dictionary of all peers currently connected to the server.
    ///
    /// The dictionary maps each peer's identifier to its connection string.
    #[func]
    fn connected_peers(&self) -> Dictionary<i32, GString> {
        self.peers
            .iter()
            .map(|(id, connection)| (*id, connection.connection_string().to_godot_owned()))
            .collect()
    }

    /// Given a `peer_id`, this function looks up the corresponding peer and returns
    /// its connection string.
    #[func]
    fn peer_connection_string(&self, peer_id: i32) -> GString {
        self.peers
            .get(&peer_id)
            .map(|connection| connection.connection_string().to_godot_owned())
            .unwrap_or_default()
    }
}

#[godot_api]
impl IMultiplayerPeerExtension for IrohServer {
    fn poll(&mut self) {
        // Accept new connections
        while let Ok(connection) = self.listener.receive_connection() {
            if self.refuse_new_connections || self.peers.len() >= 16 {
                connection.close(0u32.into(), b"Room unavailable");
                continue;
            }
            let peer_id = {
                self.last_peer_id = (self.last_peer_id + 1) % i32::MAX;
                if self.last_peer_id < 2 {
                    self.last_peer_id = 2;
                }
                self.last_peer_id
            };
            let accepted_peer_sender = self.accepted_peer_sender.clone();
            IrohRuntime::spawn(async move {
                let connection = IrohConnection::accept(connection, peer_id).await?;
                accepted_peer_sender.send((peer_id, connection)).await?;
                Ok::<(), anyhow::Error>(())
            });
        }

        // Register new peers
        while let Ok((peer_id, connection)) = self.accepted_peer_receiver.try_recv() {
            if self.refuse_new_connections || self.peers.len() >= 16 {
                connection.close();
                continue;
            }
            self.peers.insert(peer_id, connection);
            self.base_mut()
                .emit_signal("peer_connected", &[peer_id.to_variant()]);
        }

        // Receive packets from peers
        let mut disconnected_peers = Vec::new();
        for (peer_id, connection) in &mut self.peers {
            while self.received_packets.len() < 256 {
                match connection.receive_packet() {
                    Ok((channel, mode, packet)) => self
                        .received_packets
                        .push_back((*peer_id, channel, mode, packet)),
                    Err(TryRecvError::Disconnected) => {
                        disconnected_peers.push(*peer_id);
                        break;
                    }
                    Err(TryRecvError::Empty) => break,
                }
            }
        }

        // Remove disconnected peers
        for peer_id in disconnected_peers {
            self.peers.remove(&peer_id);
            self.base_mut()
                .emit_signal("peer_disconnected", &[peer_id.to_variant()]);
        }
    }

    fn get_connection_status(&self) -> ConnectionStatus {
        match self.listener.is_closed() {
            true => ConnectionStatus::DISCONNECTED,
            false => ConnectionStatus::CONNECTED,
        }
    }

    fn close(&mut self) {
        self.listener.close();
        self.peers.clear();
        self.received_packets.clear();
    }

    fn disconnect_peer(&mut self, peer_id: i32, force: bool) {
        if let Some(connection) = self.peers.remove(&peer_id) {
            connection.close();
            self.received_packets
                .retain(|(sender, _, _, _)| *sender != peer_id);
            if !force {
                self.base_mut()
                    .emit_signal("peer_disconnected", &[peer_id.to_variant()]);
            }
        }
    }

    fn get_unique_id(&self) -> i32 {
        1
    }

    fn get_max_packet_size(&self) -> i32 {
        if self.transfer_mode == TransferMode::RELIABLE {
            1200
        } else {
            1024
        }
    }

    fn get_available_packet_count(&self) -> i32 {
        self.received_packets.len() as i32
    }

    fn get_packet_channel(&self) -> i32 {
        match self.received_packets.front() {
            Some((_, channel, _, _)) => *channel,
            None => 0,
        }
    }

    fn get_packet_mode(&self) -> TransferMode {
        match self.received_packets.front() {
            Some((_, _, mode, _)) => *mode,
            None => TransferMode::RELIABLE,
        }
    }

    fn get_packet_peer(&self) -> i32 {
        match self.received_packets.front() {
            Some((peer_id, _, _, _)) => *peer_id,
            None => -1,
        }
    }

    fn get_packet_script(&mut self) -> PackedByteArray {
        match self.received_packets.pop_front() {
            Some((_, _, _, packet)) => packet.to_vec().into(),
            _ => PackedByteArray::new(),
        }
    }

    fn get_transfer_channel(&self) -> i32 {
        self.transfer_channel
    }

    fn set_transfer_channel(&mut self, channel: i32) {
        self.transfer_channel = channel;
    }

    fn get_transfer_mode(&self) -> TransferMode {
        self.transfer_mode
    }

    fn set_transfer_mode(&mut self, mode: TransferMode) {
        self.transfer_mode = mode;
    }

    fn set_target_peer(&mut self, peer_id: i32) {
        self.target_peer_id = peer_id;
    }

    fn put_packet_script(&mut self, buffer: PackedByteArray) -> Error {
        if buffer.is_empty()
            || buffer.len() > self.get_max_packet_size() as usize
            || !(0..4).contains(&self.transfer_channel)
        {
            return Error::ERR_INVALID_PARAMETER;
        }
        match self.target_peer_id {
            0 => {
                for connection in self.peers.values_mut() {
                    let _ = connection.send_packet(
                        self.transfer_channel,
                        self.transfer_mode,
                        buffer.to_vec(),
                    );
                }
            }
            peer_id if peer_id < 0 => {
                for (other_id, connection) in &mut self.peers {
                    if *other_id == peer_id {
                        continue;
                    }
                    let _ = connection.send_packet(
                        self.transfer_channel,
                        self.transfer_mode,
                        buffer.to_vec(),
                    );
                }
            }
            peer_id => {
                if let Some(connection) = self.peers.get_mut(&peer_id) {
                    return connection.send_packet(
                        self.transfer_channel,
                        self.transfer_mode,
                        buffer.to_vec(),
                    );
                }
            }
        }
        Error::OK
    }

    fn is_server(&self) -> bool {
        true
    }

    fn is_server_relay_supported(&self) -> bool {
        true
    }

    fn is_refusing_new_connections(&self) -> bool {
        self.refuse_new_connections
    }

    fn set_refuse_new_connections(&mut self, enable: bool) {
        self.refuse_new_connections = enable;
    }
}

impl Drop for IrohServer {
    fn drop(&mut self) {
        self.close();
    }
}
