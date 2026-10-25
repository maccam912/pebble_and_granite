class_name CurlOnline
extends RefCounted
## Foreground listen-server lobby. No Godot multiplayer RPC or client-selected seat.
signal changed
signal failed(message: String)
var identity_path := "user://network/player.key"
var peer: MultiplayerPeer
var authority: Object
var state: Dictionary = {}
var is_host := false
var error := ""
var endpoint := ""
var admitted: Dictionary = {}
var pending: Dictionary = {}
var outbox: Array[Dictionary] = []
var deadline := 0
var closing := false
var disconnected: Array[int] = []
var pending_failure := ""

func host(relay_only := false) -> String:
	close()
	peer = CurlTransport.host(relay_only)
	if peer == null: return "Could not start transport"
	is_host = true
	endpoint = peer.call("connection_string")
	authority = ClassDB.instantiate("CurlRoom")
	var result: String = authority.host_room(endpoint)
	if not result.is_empty():
		close()
		return result
	connect_signals()
	broadcast_state()
	return ""

func join(address: String, relay_only := false) -> String:
	close()
	peer = CurlTransport.connect_host(address, relay_only, identity_path)
	if peer == null: return "Invalid endpoint or unavailable transport"
	endpoint = address
	deadline = Time.get_ticks_msec() + 30000
	connect_signals()
	return ""

func connect_signals() -> void:
	peer.peer_connected.connect(on_connected)
	peer.peer_disconnected.connect(on_disconnected)

func on_connected(id: int) -> void:
	if is_host:
		pending[id] = Time.get_ticks_msec() + 10000
	else:
		queue_packet(1, ClassDB.class_call_static("CurlRoom", "hello_packet"))

func on_disconnected(id: int) -> void:
	# Native poll still holds the peer borrow while emitting this signal.
	# Defer all close/state callbacks until poll has returned.
	if not closing: disconnected.append(id)

func handle_disconnected(id: int) -> void:
	if is_host:
		pending.erase(id)
		if admitted.erase(id):
			authority.forget_peer(id)
			broadcast_state()
	else:
		fail("Host disconnected")

func queue_packet(target: int, bytes: PackedByteArray, replace_state := false) -> void:
	if bytes.is_empty() or bytes.size() > 1200: return
	if replace_state:
		outbox = outbox.filter(func(item: Dictionary) -> bool: return item.target != target or not item.replace_state)
	var queued_for_peer := 0
	for item: Dictionary in outbox:
		if item.target == target: queued_for_peer += 1
	if is_host and queued_for_peer >= 16:
		drop_peer(target)
		return
	if outbox.size() >= 128:
		pending_failure = "Connection send queue is full"
		return
	outbox.append({"target": target, "bytes": bytes, "replace_state": replace_state})

func decode(bytes: PackedByteArray) -> Dictionary:
	var text: String = ClassDB.class_call_static("CurlRoom", "decode_packet", bytes)
	if text.is_empty(): return {}
	return JSON.parse_string(text)

func broadcast_state() -> void:
	if authority == null: return
	var bytes: PackedByteArray = authority.state_packet()
	state = decode(bytes).get("room", {})
	for id: int in admitted.keys(): queue_packet(id, bytes, true)
	changed.emit()

func ready(value: bool) -> String:
	if peer == null: return "No room"
	if is_host:
		var result: String = authority.ready_peer(1, value)
		if result.is_empty(): broadcast_state()
		return result
	queue_packet(1, ClassDB.class_call_static("CurlRoom", "ready_packet", value))
	return ""

func start_match() -> String:
	if not is_host or authority == null: return "Only the host can start"
	var result: String = authority.start_match(1, 42)
	if result.is_empty(): broadcast_state()
	return result

func poll() -> void:
	if peer == null: return
	peer.poll()
	var events := disconnected.duplicate()
	disconnected.clear()
	for id: int in events:
		if peer == null: break
		handle_disconnected(id)
	if not pending_failure.is_empty():
		fail(pending_failure)
		return
	if peer == null: return
	if not is_host and state.is_empty() and Time.get_ticks_msec() > deadline:
		fail("Room handshake timed out")
		return
	if not is_host and peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		var detail: String = peer.call("connection_error")
		fail("Could not connect to host" + (": " + detail if not detail.is_empty() else ""))
		return
	for id: int in pending.keys():
		if Time.get_ticks_msec() > pending[id]: drop_peer(id)
	var sent := 0
	while not outbox.is_empty() and sent < 32 and peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		var item: Dictionary = outbox[0]
		peer.set_target_peer(item.target)
		peer.transfer_channel = 0
		peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
		var result := peer.put_packet(item.bytes)
		if result == ERR_BUSY: break
		outbox.pop_front()
		sent += 1
		if result != OK:
			fail("Could not send room control packet")
			return
	var received := 0
	while peer != null and peer.get_available_packet_count() > 0 and received < 64:
		var sender := peer.get_packet_peer()
		var channel := peer.get_packet_channel()
		var reliable := peer.get_packet_mode() == MultiplayerPeer.TRANSFER_MODE_RELIABLE
		var bytes := peer.get_packet()
		received += 1
		if channel != 0 or not reliable:
			if is_host: drop_peer(sender)
			else: fail("Unexpected room channel")
			continue
		receive(sender, bytes)

func receive(sender: int, bytes: PackedByteArray) -> void:
	var packet := decode(bytes)
	if packet.is_empty():
		if is_host: drop_peer(sender)
		else: fail("Invalid room packet")
		return
	if is_host:
		if packet.kind == "Hello" and pending.has(sender):
			# This identity comes from the authenticated QUIC connection, not Hello.
			var identity: String = peer.call("peer_connection_string", sender)
			var result: String = authority.join_peer(sender, identity, bytes)
			if not result.is_empty():
				drop_peer(sender)
				return
			pending.erase(sender)
			admitted[sender] = true
			broadcast_state()
		elif packet.kind == "Ready" and admitted.has(sender):
			var result: String = authority.ready_peer(sender, packet.ready)
			if result.is_empty(): broadcast_state()
			else: queue_packet(sender, ClassDB.class_call_static("CurlRoom", "reject_packet", result))
		else: drop_peer(sender)
	elif sender == 1:
		if packet.kind == "State":
			state = packet.room
			changed.emit()
		elif packet.kind == "Reject":
			error = packet.reason
			failed.emit(error)
		else: fail("Unexpected host packet")

func drop_peer(id: int) -> void:
	pending.erase(id)
	outbox = outbox.filter(func(item: Dictionary) -> bool: return item.target != id)
	if admitted.erase(id):
		authority.forget_peer(id)
		broadcast_state()
	if peer != null: peer.disconnect_peer(id, true)

func fail(message: String) -> void:
	close()
	error = message
	failed.emit(message)

func close() -> void:
	closing = true
	if peer != null:
		if peer.peer_connected.is_connected(on_connected): peer.peer_connected.disconnect(on_connected)
		if peer.peer_disconnected.is_connected(on_disconnected): peer.peer_disconnected.disconnect(on_disconnected)
		peer.close()
	peer = null
	authority = null
	state = {}
	is_host = false
	admitted.clear()
	pending.clear()
	outbox.clear()
	disconnected.clear()
	pending_failure = ""
	error = ""
	closing = false
