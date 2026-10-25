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
			if rooms.all(func(room: CurlOnline) -> bool: return room.state.get("phase") == "Placement"): break
			await create_timer(.01).timeout
		check(rooms.all(func(room: CurlOnline) -> bool: return room.state.get("phase") == "Placement" and room.state.epoch == 1), "Start state did not reach every peer")
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
		host.close()
		deadline = Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline and (rooms[1].peer != null or rooms[3].peer != null):
			tick()
			await create_timer(.01).timeout
		check(rooms[1].peer == null and rooms[3].peer == null, "Host loss did not close clients")
	for room in rooms: room.close()
	print("ONLINE_LOBBY_OK relay_only=", relay_only) if not failed else print("ONLINE_LOBBY_FAILED")
	quit(1 if failed else 0)
