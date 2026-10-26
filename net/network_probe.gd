extends Node
## One-use development diagnostic. Never touches the player's identity or saves.
var request: Dictionary
var room := CurlOnline.new()
var reconnect_at := 0
var disconnected_once := false
var restored_in_flight := false
var conceded := false
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
	if frame.match_phase == "Calling" and frame.delivered_count == 1 and not conceded:
		if not restored_in_flight: finish(false, "In-flight reconnect was not verified"); return
		conceded = true
		var error := room.send_command({"kind": "Concede"})
		if not error.is_empty(): finish(false, error); return
	if frame.match_phase == "GameComplete" and room.replica.state_hash() == room.state.hash:
		finish(restored_in_flight and conceded, "")
func finish(ok: bool, error: String) -> void:
	if finished: return
	finished = true
	var result := {"ok": ok, "error": error, "nonce": request.nonce, "platform": OS.get_name(), "relay_only": request.relay_only, "reconnected_in_flight": restored_in_flight, "hash": room.replica.state_hash() if room.replica != null else "", "seat": room.seat_index()}
	DirAccess.make_dir_recursive_absolute("user://diagnostics")
	var file := FileAccess.open("user://diagnostics/network-test.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result))
		file.close()
	room.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(room.identity_path))
	print("NETWORK_PROBE_RESULT " + JSON.stringify(result))
	get_tree().quit(0 if ok else 1)
