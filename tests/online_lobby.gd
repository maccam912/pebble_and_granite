extends SceneTree
var failed := false
var rooms: Array[CurlOnline] = []
func check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		failed = true
	return ok
func _initialize() -> void: call_deferred("run")
func tick() -> void:
	for room in rooms: room.poll()
func count_players(state: Dictionary) -> int:
	var count := 0
	for player in state.get("players", []):
		if player != null: count += 1
	return count
func run() -> void:
	var host := CurlOnline.new()
	rooms.append(host)
	var relay_only := "--relay-only" in OS.get_cmdline_user_args()
	if not check(host.host(relay_only).is_empty(), "Host failed"):
		quit(1)
		return
	for i in range(3):
		var client := CurlOnline.new()
		client.identity_path = "user://network/test-lobby-%s-%d.key" % [OS.get_process_id(), i]
		client.failed.connect(func(message: String) -> void: print("LOBBY_CLIENT: ", message))
		rooms.append(client)
		check(client.join(host.endpoint, relay_only).is_empty(), "Join failed")
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		tick()
		if rooms.all(func(room: CurlOnline) -> bool: return count_players(room.state) == 4): break
		await create_timer(.01).timeout
	if check(rooms.all(func(room: CurlOnline) -> bool: return count_players(room.state) == 4), "Four-peer lobby handshake did not complete"):
		check(not rooms[1].start_match().is_empty(), "Client started the match")
		for room in rooms: check(room.ready(true).is_empty(), "Ready rejected")
		# Repeated readiness updates must coalesce state sends, not exhaust host queues.
		for i in range(48): rooms[1].ready(i % 2 == 1)
		deadline = Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline:
			tick()
			if host.state.players.all(func(player) -> bool: return player != null and player.ready): break
			await create_timer(.01).timeout
		check(host.start_match().is_empty(), "Host could not start ready match")
		deadline = Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline:
			tick()
			if rooms.all(func(room: CurlOnline) -> bool: return room.state.get("phase") == "Placement" and not room.state.paused) and rooms.slice(1).all(func(room: CurlOnline) -> bool: return room.replica != null): break
			await create_timer(.01).timeout
		check(rooms.all(func(room: CurlOnline) -> bool: return room.state.get("phase") == "Placement" and room.state.epoch == 1), "Start state did not reach every peer")
		check(await settled_network(host), "Starting replica hashes differ")
		var placer: CurlOnline
		for room in rooms:
			if room.peer.get_unique_id() == host.state.players[2].peer: placer = room
		check(placer != null and placer.send_command({"kind": "Place", "own_house": true, "side": "None"}).is_empty(), "Network placement failed")
		deadline = Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline and host.state.phase != "Calling":
			tick()
			await create_timer(.01).timeout
		check(await settled_network(host), "Placement replicas differ")
		var release := {"stone": 0, "team": 0, "pos": {"x": 0, "y": -124554051584}, "vel": {"x": 0, "y": 8804682956}, "spin": 515396075}
		check(host.send_command({"kind": "Release", "release": release}).is_empty(), "Network release failed")
		check(await settled_network(host), "Release replicas differ")
		for i in range(3):
			check(host.advance(24, 0).is_empty(), "Flight advance failed")
			check(await settled_network(host), "Flight replicas differ")
		check(host.send_command({"kind": "Sweep", "tick": 60, "input": {"stone": 2, "brush": 0, "effort": 220, "lateral_mm": 0, "ahead_mm": 180}}).is_empty(), "Late network sweep failed")
		check(await settled_network(host), "Late sweep replicas differ")
		check(host.send_command({"kind": "BrushSpan", "tick": 61, "count": 12, "input": {"stone": 2, "brush": 0, "effort": 200, "lateral_mm": 0, "ahead_mm": 180}}).is_empty(), "Network brush span failed")
		check(await settled_network(host), "Brush span replicas differ")
		var departed: int = rooms[2].peer.get_unique_id()
		rooms[2].close()
		deadline = Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline:
			tick()
			if host.state.paused: break
			await create_timer(.01).timeout
		check(host.state.paused, "Disconnected player did not pause match")
		check(count_players(host.state) == 4, "Disconnected game seat was discarded")
		check(host.state.players.all(func(player) -> bool: return player.peer != departed), "Old connection still bound")
		check(rooms[2].join(host.endpoint, relay_only).is_empty(), "Reconnect failed")
		deadline = Time.get_ticks_msec() + 10000
		while Time.get_ticks_msec() < deadline:
			tick()
			if host.state.players.all(func(player) -> bool: return player.peer != null) and not host.state.paused: break
			await create_timer(.01).timeout
		check(host.state.players.all(func(player) -> bool: return player.peer != null), "Persistent identity did not reclaim reserved seat")
		check(not host.state.paused, "Verified reconnect did not resume match")
		check(await settled_network(host), "Reconnected replica differs")
		var updates := 0
		while host.state.phase == "InFlight" and updates < 650 and not failed:
			check(host.advance(24, 0).is_empty(), "Post-reconnect flight failed")
			check(await settled_network(host), "Post-reconnect replica differs")
			updates += 1
		check(host.state.phase == "Calling", "Network shot did not settle")
		host.close()
		deadline = Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline and (rooms[1].peer != null or rooms[3].peer != null):
			tick()
			await create_timer(.01).timeout
		check(rooms[1].peer == null and rooms[3].peer == null, "Host loss did not close clients")
	for room in rooms:
		room.close()
		if room != host: DirAccess.remove_absolute(ProjectSettings.globalize_path(room.identity_path))
	print("ONLINE_LOBBY_OK relay_only=", relay_only) if not failed else print("ONLINE_LOBBY_FAILED")
	quit(1 if failed else 0)

func settled_network(host: CurlOnline) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		tick()
		if rooms.slice(1).all(func(room: CurlOnline) -> bool: return room.replica != null and room.replica.state_hash() == host.state.hash): return true
		await create_timer(.01).timeout
	return false
