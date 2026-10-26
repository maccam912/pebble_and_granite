extends Node
## One-use development diagnostic. Never touches the player's identity or saves.
var request: Dictionary
var room := CurlOnline.new()
var reconnect_at := 0
var disconnected_once := false
var restored_in_flight := false
var held_started := false
var held_disconnected := false
var held_restored := false
var held_finished := false
var frozen_held: Dictionary = {}
var regrip_at := 0
var finish_at := 0
var game: Control
var gesture_clock := [0]
var ready_sent := false
var deadline := 0
var finished := false
func _ready() -> void:
	if not OS.is_debug_build(): get_tree().quit(1); return
	room.identity_path = "user://network/probe-%s.key" % request.nonce
	room.failed.connect(func(error: String): finish(false, error))
	deadline = Time.get_ticks_msec() + 180000
	var error := room.join(request.endpoint, request.relay_only)
	if not error.is_empty(): finish(false, error)
func _process(_delta: float) -> void:
	if finished: return
	if Time.get_ticks_msec() > deadline: finish(false, "Network probe timed out"); return
	if reconnect_at > 0:
		if Time.get_ticks_msec() < reconnect_at: return
		reconnect_at = 0
		var error := room.join(request.endpoint, request.relay_only)
		if not error.is_empty(): finish(false, error); return
	room.poll()
	if finished or room.state.is_empty(): return
	if room.seat_index() != 3: finish(false, "Probe did not receive reserved fourth seat"); return
	if room.state.get("phase") == null:
		if not ready_sent:
			ready_sent = true
			room.ready(true)
		return
	var frame := room.frame()
	if frame.is_empty() or room.state.paused: return
	if frame.match_phase == "InFlight":
		if not disconnected_once and frame.tick >= 48:
			disconnected_once = true
			room.close()
			reconnect_at = Time.get_ticks_msec() + 500
			return
		if disconnected_once: restored_in_flight = true
	if frame.match_phase == "Calling" and frame.delivered_count == 1:
		if not restored_in_flight: finish(false, "In-flight reconnect was not verified"); return
		if int(frame.team) != 1 or int(frame.thrower) != 1: finish(false, "Android probe does not own second delivery"); return
		if not held_started:
			create_game()
			var point: Vector2 = game.handle_point()
			game.one_push = true
			game.begin_pointer(-1, point)
			gesture_clock[0] = 20000
			game.move_pointer(point + Vector2(0, -4.2))
			gesture_clock[0] = 120000
			game.move_pointer(point + Vector2(0, -25.2))
			gesture_clock[0] = 220000
			game.update_delivery()
			held_started = true
		var held: Dictionary = frame.get("in_hand", {})
		if not held.is_empty() and held.elapsed_ms >= 1800 and not held_disconnected:
			held_disconnected = true
			game.queue_free()
			game = null
			room.close()
			reconnect_at = Time.get_ticks_msec() + 500
			return
		if held_disconnected and not held_restored and not held.is_empty():
			if not held.get("suspended", false): finish(false, "Restored delivery was not suspended"); return
			if regrip_at == 0:
				frozen_held = held.duplicate(true)
				regrip_at = Time.get_ticks_msec() + 350
			if held != frozen_held: finish(false, "Held pose changed before regrip"); return
			if Time.get_ticks_msec() >= regrip_at:
				create_game()
				gesture_clock[0] = 10000000
				game.update_spatial(0)
				game.begin_pointer(-1, game.handle_point())
				if game.pointer == -99: finish(false, "Restored online handle could not be regripped"); return
				held_restored = true
				finish_at = Time.get_ticks_msec() + 250
		if held_restored and not held_finished and Time.get_ticks_msec() >= finish_at:
			var point: Vector2 = game.handle_point()
			gesture_clock[0] = 10100000
			game.move_pointer(point)
			gesture_clock[0] = 10200000
			game.end_pointer(point + Vector2(-30, -8))
			if game.release_report.get("turn") != -1: finish(false, "Regripped delivery lost finishing curl"); return
			held_finished = true
			game.hold_sweep = true
	if frame.match_phase == "GameComplete" and room.replica.state_hash() == room.state.hash:
		finish(restored_in_flight and held_restored and held_finished and frame.delivered_count == 2 and game != null and game.last_brush_tick >= 0, "")
func create_game() -> void:
	game = load("res://scenes/online_game.gd").new()
	game.online = room
	game.input_clock = func(): return gesture_clock[0]
	add_child(game)
	game.update_spatial(0)
func finish(ok: bool, error: String) -> void:
	if finished: return
	finished = true
	var result := {"ok": ok, "error": error, "nonce": request.nonce, "platform": OS.get_name(), "relay_only": request.relay_only, "reconnected_in_flight": restored_in_flight, "reconnected_held": held_restored, "held_finished": held_finished, "swept_as_thrower": game != null and game.last_brush_tick >= 0, "frozen_held": frozen_held, "hash": room.replica.state_hash() if room.replica != null else "", "seat": room.seat_index()}
	DirAccess.make_dir_recursive_absolute("user://diagnostics")
	var file := FileAccess.open("user://diagnostics/network-test.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result))
		file.close()
	if game != null: game.queue_free(); game = null
	room.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(room.identity_path))
	print("NETWORK_PROBE_RESULT " + JSON.stringify(result))
	get_tree().quit(0 if ok else 1)
