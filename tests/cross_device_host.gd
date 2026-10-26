extends SceneTree
var rooms: Array[CurlOnline] = []
var directory := ""
var deadline := 0
var stage := "lobby"
var paused_for_reconnect := false
var resumed := false
var released_from_held := false
var next_advance := 0
var finished := false
var ready_sent: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func write_result(name: String, data: Dictionary) -> void:
	var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
func run() -> void:
	var relay_only := "--relay-only" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--probe-dir="): directory = argument.trim_prefix("--probe-dir=")
	if not directory.is_absolute_path(): quit(1); return
	DirAccess.make_dir_recursive_absolute(directory)
	deadline = Time.get_ticks_msec() + 240000
	var host := CurlOnline.new()
	rooms.append(host)
	var error := host.host(relay_only)
	if not error.is_empty(): finish(false, error); return
	for i in range(2):
		var client := CurlOnline.new()
		client.identity_path = "user://network/cross-host-%d-%d.key" % [OS.get_process_id(), i]
		client.failed.connect(func(message: String): finish(false, message))
		rooms.append(client)
		error = client.join(host.endpoint, relay_only)
		if not error.is_empty(): finish(false, error); return
	while not finished:
		for room in rooms: room.poll()
		if Time.get_ticks_msec() > deadline: finish(false, "Host probe timed out"); break
		var state := host.state
		var count: int = state.get("players", []).filter(func(p): return p != null).size()
		if stage == "lobby" and count == 3:
			write_result("endpoint.json", {"endpoint": host.endpoint})
			stage = "ready"
		if stage == "ready" and count == 4:
			for room in rooms:
				var index := room.seat_index()
				if index >= 0 and not ready_sent.has(index):
					ready_sent[index] = true
					room.ready(true)
			if state.players.all(func(p): return p.ready):
				error = host.start_match()
				if not error.is_empty(): finish(false, error); break
				stage = "placement"
		if stage == "placement" and state.get("phase") == "Placement" and not state.paused and rooms.all(func(room): return room.state.get("phase") == "Placement" and not room.state.get("paused", true)):
			for room in rooms:
				if room.seat_index() == 2:
					error = room.send_command({"kind": "Place", "own_house": true, "side": "None"})
					if not error.is_empty(): finish(false, error)
			stage = "release"
		if stage == "release" and state.get("phase") == "Calling":
			error = host.send_command({"kind": "BeginDelivery", "target_mm_s": 2050, "broom_mm": -900})
			if not error.is_empty(): finish(false, error); break
			stage = "held"
		if stage == "held" and not state.paused and Time.get_ticks_msec() >= next_advance:
			next_advance = Time.get_ticks_msec() + 50
			error = host.advance(0, 50)
			if not error.is_empty(): finish(false, error); break
			var held: Dictionary = host.frame().get("in_hand", {})
			if held.is_empty(): finish(false, "Held delivery disappeared before release"); break
			if held.elapsed_ms >= 2000:
				error = host.send_command({"kind": "ReleaseDelivery", "trim_mm_s": 20, "line_mm": 0, "turn": 1})
				if not error.is_empty(): finish(false, error); break
				released_from_held = true
				stage = "flight"
		if stage == "flight":
			if state.paused: paused_for_reconnect = true
			elif paused_for_reconnect: resumed = true
			if not state.paused and state.phase == "InFlight" and Time.get_ticks_msec() >= next_advance:
				next_advance = Time.get_ticks_msec() + 50
				error = host.advance(12, 0)
				if not error.is_empty(): finish(false, error); break
			if state.phase == "GameComplete":
				finish(resumed, "" if resumed else "No verified reconnect")
				break
		await create_timer(.01).timeout
func finish(ok: bool, error: String) -> void:
	if finished: return
	finished = true
	write_result("host.json", {"ok": ok, "error": error, "hash": rooms[0].state.get("hash", ""), "reconnected": resumed, "released_from_held": released_from_held})
	# Allow the final accepted command/state to reach the Android replica.
	for i in range(100):
		for room in rooms: room.poll()
		await create_timer(.01).timeout
	for room in rooms:
		room.close()
		if room != rooms[0]: DirAccess.remove_absolute(ProjectSettings.globalize_path(room.identity_path))
	quit(0 if ok else 1)
