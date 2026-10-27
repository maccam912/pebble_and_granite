extends Node
## Read-only state/geometry for explicit development-build adb input probes.
## The bootstrap disables practice/match/settings persistence before scene setup.
var game
var nonce := ""
var age := 0.0
var interval := 0.0
var sequence := 0
var last_delivered := -99
var review_count := 0
var voice_count := -1
var last_voice_check := 0.0
var journal_hash := ""

func point(control: Control) -> Dictionary:
	if control == null or not control.is_visible_in_tree(): return {}
	var pixel := control.get_viewport_transform() * control.get_global_rect().get_center()
	return {"x": roundi(pixel.x), "y": roundi(pixel.y), "disabled": control.disabled if control is BaseButton else false}

func find_button(parent: Node, text: String) -> Control:
	for node in parent.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree(): return node
	return null

func _process(delta: float) -> void:
	age += delta
	interval += delta
	if interval < .25: return
	interval = 0.0
	write_state()
	if age > 360.0: queue_free()

func write_state() -> void:
	if game == null or game.session == null: return
	var frame: Dictionary = game.frame
	var count := int(frame.get("delivered_count", -1))
	if count != last_delivered:
		review_count = game.session.shot_reviews().shots.size()
		last_delivered = count
		if game.match_mode and not game.run_active:
			write_journal()
	if voice_count < 0 or age - last_voice_check > 5.0:
		voice_count = DisplayServer.tts_get_voices_for_language("en").size() if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) else 0
		last_voice_check = age
	var settings = game.play_settings
	var controls := {
		"solo": point(game.solo.solo_button), "settings": point(game.settings_button), "camera": point(game.camera_button),
		"zoom": point(game.zoom_button), "ice_board": point(game.ice_board.menu_button),
		"send": point(game.solo.send_button), "shot_kind": point(game.solo.shot_choice), "place_target": point(game.solo.target_button),
		"hard": point(game.solo.call_buttons[0]), "clean": point(game.solo.call_buttons[1]), "off": point(game.solo.call_buttons[2]),
		"done": point(find_button(settings, "Done")), "role": point(settings.position_choice), "difficulty": point(settings.difficulty_choice), "fast": point(settings.fast_toggle),
		"board_close": point(find_button(game.ice_board, "Close"))}
	sequence += 1
	var state := {"schema": 1, "nonce": nonce, "sequence": sequence, "age_s": age, "expired": age > 360.0,
		"mode": "solo" if game.solo.enabled else ("match" if game.match_mode else "practice"), "phase": game.phase,
		"match_phase": frame.get("match_phase", ""), "team": frame.get("team", -1), "thrower": frame.get("thrower", -1),
		"delivered_count": count, "end": frame.get("end", -1), "run_active": game.run_active,
		"human_position": settings.human_position, "difficulty": settings.difficulty, "fast": settings.fast_opponents,
		"planning": game.solo.planning, "planned": not game.solo.planned.is_empty(), "kind": game.solo.planned.get("kind", ""),
		"call_override": game.solo.call_override, "zone": game.solo.weight_zone, "fast_active": game.solo.fast_forwarding(),
		"camera": game.rink.current_camera, "fov": game.rink.camera.fov, "camera_size": game.rink.camera.size, "zoomed": game.rink.zoomed,
		"settings_visible": settings.visible, "board_visible": game.ice_board.visible, "review_count": review_count,
		"voice_feature": DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH), "voice_count": voice_count,
		"journal_hash": journal_hash, "hash": game.session.match_hash() if game.match_mode else game.session.state_hash(), "controls": controls}
	var directory := "user://diagnostics"
	DirAccess.make_dir_recursive_absolute(directory)
	var destination := directory + "/ui-state-" + nonce + ".json"
	var file := FileAccess.open(destination + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(state))
	file.flush()
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(destination + ".tmp"), ProjectSettings.globalize_path(destination))

func write_journal() -> void:
	var destination := "user://diagnostics/ui-match-" + nonce + ".json"
	var file := FileAccess.open(destination + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(game.session.match_json())
	file.flush()
	file.close()
	journal_hash = game.session.match_hash()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(destination + ".tmp"), ProjectSettings.globalize_path(destination))
