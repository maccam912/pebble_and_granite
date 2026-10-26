class_name CurlOnline
extends RefCounted
## Foreground listen-server lobby. No Godot multiplayer RPC or client-selected seat.
signal changed
signal failed(message: String)
var identity_path := "user://network/player.key"
var peer: MultiplayerPeer
var authority: Object
var replica: Object
var transfers: Dictionary = {}
var sync_deadlines: Dictionary = {}
var receiving_snapshot := false
var snapshot_deadline := 0
var sequence := 0
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
		transfers.erase(id)
		sync_deadlines.erase(id)
		outbox = outbox.filter(func(item: Dictionary) -> bool: return item.target != id)
		if admitted.erase(id):
			authority.forget_peer(id)
			broadcast_state()
	else:
		fail("Host disconnected")

func queue_packet(target: int, bytes: PackedByteArray, replace_state := false, channel := 0) -> void:
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
	outbox.append({"target": target, "bytes": bytes, "replace_state": replace_state, "channel": channel})

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
	if result.is_empty():
		sequence = 0
		for id: int in admitted.keys(): begin_snapshot(id)
		broadcast_state()
	return result

func begin_snapshot(id: int) -> void:
	var result: String = authority.require_sync(id)
	if not result.is_empty():
		drop_peer(id)
		return
	var transfer = authority.snapshot()
	if transfer == null:
		drop_peer(id)
		return
	transfers[id] = transfer
	sync_deadlines[id] = Time.get_ticks_msec() + 60000

func pump_snapshots() -> void:
	for id: int in sync_deadlines.keys():
		if Time.get_ticks_msec() > sync_deadlines[id]: drop_peer(id)
	for id: int in transfers.keys():
		var count := outbox.filter(func(item: Dictionary) -> bool: return item.target == id).size()
		while count < 8 and transfers.has(id):
			var bytes: PackedByteArray = transfers[id].next_packet()
			if bytes.is_empty():
				transfers.erase(id)
				break
			queue_packet(id, bytes, false, 2)
			count += 1

func send_command(command: Dictionary) -> String:
	if peer == null or state.get("phase") == null or state.get("paused", true): return "Match is not ready"
	var id := peer.get_unique_id()
	for player in state.players:
		if player != null and player.peer == id: sequence = maxi(sequence, int(player.sequence))
	if sequence >= 4294967295: return "Command sequence exhausted"
	sequence += 1
	var bytes := JSON.stringify({"epoch": int(state.epoch), "sequence": sequence, "command": command}).to_utf8_buffer()
	if bytes.size() > 1200: return "Command too large"
	if is_host:
		var result: String = authority.command_peer(1, bytes)
		if result.is_empty(): flush_commits()
		return result
	queue_packet(1, bytes, false, 1)
	return ""

func advance(ticks: int, thinking_ms: int) -> String:
	if ticks < 0 or ticks > 24 or thinking_ms < 0 or thinking_ms > 1000: return "Invalid authority interval"
	if not is_host or authority == null: return "Host required"
	var result: String = authority.advance_match(ticks, thinking_ms)
	if result.is_empty(): flush_commits()
	return result

func flush_commits() -> void:
	while true:
		var bytes: PackedByteArray = authority.take_commit()
		if bytes.is_empty(): break
		for id: int in admitted.keys(): queue_packet(id, bytes, false, 1)
	broadcast_state()

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
	if is_host: pump_snapshots()
	elif receiving_snapshot:
		if Time.get_ticks_msec() > snapshot_deadline:
			fail("Match synchronization timed out")
			return
		var result: String = replica.poll_restore()
		if not result.is_empty():
			fail(result)
			return
		if not replica.state_hash().is_empty():
			receiving_snapshot = false
			queue_packet(1, ClassDB.class_call_static("CurlRoom", "synced_packet", replica.epoch(), replica.revision(), replica.state_hash()))
			changed.emit()
	var sent := 0
	while not outbox.is_empty() and sent < 32 and peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		var item: Dictionary = outbox[0]
		peer.set_target_peer(item.target)
		peer.transfer_channel = item.channel
		peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
		var result := peer.put_packet(item.bytes)
		if result == ERR_BUSY: break
		outbox.pop_front()
		sent += 1
		if result != OK:
			if is_host: drop_peer(item.target)
			else:
				fail("Could not send room packet")
				return
	var received := 0
	while peer != null and peer.get_available_packet_count() > 0 and received < 64:
		var sender := peer.get_packet_peer()
		var channel := peer.get_packet_channel()
		var reliable := peer.get_packet_mode() == MultiplayerPeer.TRANSFER_MODE_RELIABLE
		var bytes := peer.get_packet()
		received += 1
		if channel < 0 or channel > 2 or not reliable:
			if is_host: drop_peer(sender)
			else: fail("Unexpected room channel")
			continue
		if channel == 0: receive(sender, bytes)
		elif channel == 1:
			if is_host and admitted.has(sender):
				var result: String = authority.command_peer(sender, bytes)
				if result.is_empty(): flush_commits()
				else: queue_packet(sender, ClassDB.class_call_static("CurlRoom", "reject_packet", result))
			elif not is_host and sender == 1 and replica != null and not receiving_snapshot:
				var result: String = replica.apply_commit(bytes)
				if not result.is_empty(): fail(result)
				else: changed.emit()
			elif is_host: drop_peer(sender)
			else: fail("Gameplay arrived before synchronization")
		elif not is_host and sender == 1:
			if not receiving_snapshot:
				replica = ClassDB.instantiate("CurlReplica")
				receiving_snapshot = true
				snapshot_deadline = Time.get_ticks_msec() + 60000
			var result: String = replica.receive_snapshot(bytes)
			if not result.is_empty():
				fail(result)
		else: drop_peer(sender)

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
			if state.get("phase") != null: begin_snapshot(sender)
			broadcast_state()
		elif packet.kind == "Synced" and sync_deadlines.has(sender):
			var result: String = authority.confirm_sync(sender, int(packet.epoch), int(packet.revision), packet.hash)
			if result.is_empty():
				sync_deadlines.erase(sender)
				broadcast_state()
			else: drop_peer(sender)
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
	transfers.erase(id)
	sync_deadlines.erase(id)
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
	replica = null
	transfers.clear()
	sync_deadlines.clear()
	receiving_snapshot = false
	state = {}
	is_host = false
	admitted.clear()
	pending.clear()
	outbox.clear()
	disconnected.clear()
	pending_failure = ""
	error = ""
	closing = false

func frame() -> Dictionary:
	if state.get("phase") == null: return {}
	if is_host and authority != null: return authority.frame()
	if replica != null and not receiving_snapshot: return replica.frame()
	return {}

func seat_index() -> int:
	if peer == null: return -1
	for index in range(state.get("players", []).size()):
		var player = state.players[index]
		if player != null and player.peer == peer.get_unique_id(): return index
	return -1

func release_stone(speed: int, broom: int, turn: int) -> String:
	if peer == null or state.get("paused", true): return "Match is not ready"
	var index := seat_index()
	if index < 0: return "No player seat"
	sequence = maxi(sequence, int(state.players[index].sequence))
	if sequence >= 4294967295: return "Command sequence exhausted"
	sequence += 1
	var bytes: PackedByteArray = ClassDB.class_call_static("CurlRoom", "delivery_packet", int(state.epoch), sequence, speed, broom, turn)
	if bytes.is_empty(): return "Invalid delivery"
	if is_host:
		var result: String = authority.command_peer(1, bytes)
		if result.is_empty(): flush_commits()
		return result
	queue_packet(1, bytes, false, 1)
	return ""

func next_end() -> String:
	if not is_host or authority == null: return "Only the host can begin the next end"
	var result: String = authority.next_end()
	if result.is_empty(): flush_commits()
	return result

func rematch() -> String:
	if not is_host or authority == null: return "Only the host can offer a rematch"
	var result: String = authority.rematch()
	if result.is_empty():
		sequence = 0
		broadcast_state()
	return result
