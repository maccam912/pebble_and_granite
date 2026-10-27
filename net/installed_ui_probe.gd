extends Node
## Read-only state/geometry for explicit development-build adb input probes.
## The bootstrap disables practice/match/settings persistence before scene setup.
var game
var nonce := ""
var age := 0.0
var interval := 0.0
var sequence := 0
var last_delivery := ""
var review_count := 0
var voice_count := -1
var last_voice_check := 0.0
var journal_hash := ""

func point(control: Control) -> Dictionary:
	if control == null or not control.is_visible_in_tree(): return {}
	var rect := control.get_global_rect()
	var ancestor := control.get_parent()
	while ancestor is Control:
		if ancestor.clip_contents: rect = rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	if rect.size.x < 20 or rect.size.y < 20: return {}
	var pixel := control.get_viewport_transform() * rect.get_center()
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
	var delivery_key := "%s/%s/%s/%s/%s" % [game.match_mode, count if game.match_mode else frame.get("delivered", -1), game.drills.kind, game.drills.attempt, game.drills.results.size()]
	if delivery_key != last_delivery:
		review_count = game.session.shot_reviews().shots.size()
		last_delivery = delivery_key
		if (game.match_mode or game.drills.enabled) and not game.run_active:
			write_journal()
	if voice_count < 0 or age - last_voice_check > 5.0:
		voice_count = DisplayServer.tts_get_voices_for_language("en").size() if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) else 0
		last_voice_check = age
	var settings = game.play_settings
	var controls := {
		"solo": point(game.solo.solo_button), "settings": point(game.settings_button), "camera": point(game.camera_button),
		"drills": point(game.drills.menu_button), "drill_kind": point(game.drills.choice), "next": point(game.new_button), "restart": point(game.fresh_button),
		"restart_confirm": point(game.restart_prompt.confirm_button), "restart_cancel": point(game.restart_prompt.cancel_button),
		"review_shots": point(settings.review_toggle), "ice_sounds": point(settings.sound_toggle), "continue": point(game.match_readout.continue_button),
		"zoom": point(game.zoom_button), "ice_board": point(game.ice_board.menu_button),
		"send": point(game.solo.send_button), "shot_kind": point(game.solo.shot_choice), "in_turn": point(game.solo.turn_buttons[0]), "out_turn": point(game.solo.turn_buttons[1]),
		"hard": point(game.solo.call_buttons[0]), "clean": point(game.solo.call_buttons[1]), "off": point(game.solo.call_buttons[2]),
		"done": point(find_button(settings, "Done")), "role": point(settings.position_choice), "difficulty": point(settings.difficulty_choice), "fast": point(settings.fast_toggle), "steady": point(settings.steady_toggle),
		"board_close": point(find_button(game.ice_board, "Close")), "accept": point(game.solo.accept_button), "restore": point(game.solo.restore_button)}
	var broom: Vector2 = game.get_viewport_transform() * (game.get_global_transform() * game.broom_screen_point())
	var handle: Vector2 = game.get_viewport_transform() * (game.get_global_transform() * game.handle_point())
	sequence += 1
	var state := {"schema": 1, "nonce": nonce, "sequence": sequence, "age_s": age, "expired": age > 360.0,
		"mode": "solo" if game.solo.enabled else ("match" if game.match_mode else "drills" if game.drills.enabled else "practice"), "phase": game.phase,
		"choice_team": frame.get("choice_team", -1), "violation": frame.get("violation", ""), "remedy_restored": frame.get("remedy_restored", false), "match_phase": frame.get("match_phase", ""), "team": frame.get("team", -1), "thrower": frame.get("thrower", -1),
		"broom": {"x": roundi(broom.x), "y": roundi(broom.y)}, "broom_mm": game.broom_mm, "turn": game.turn,
		"review_waiting": game.solo.review_waiting(), "target_visible": game.rink.target_rings.visible, "restart_visible": game.restart_prompt.visible, "ice_sounds": settings.ice_sounds,
		"handle": {"x": roundi(handle.x), "y": roundi(handle.y)}, "delivered": frame.get("delivered", -1),
		"drill_kind": game.drills.kind, "drill_attempt": game.drills.attempt, "drill_results": game.drills.results, "drill_goal_ms": game.drills.split_target_ms(), "drill_target_text": game.drills.target_label.text, "report": game.report,
		"delivered_count": count, "end": frame.get("end", -1), "run_active": game.run_active,
		"human_position": settings.human_position, "difficulty": settings.difficulty, "fast": settings.fast_opponents,
		"planning": game.solo.planning, "planned": not game.solo.planned.is_empty(), "kind": game.solo.planned.get("kind", ""),
		"call_override": game.solo.call_override, "zone": game.solo.weight_zone, "fast_active": game.solo.fast_forwarding(),
		"camera": game.rink.current_camera, "fov": game.rink.camera.fov, "camera_size": game.rink.camera.size, "zoomed": game.rink.zoomed, "steady_camera": settings.steady_camera,
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
	var destination := "user://diagnostics/ui-" + ("match-" if game.match_mode else "session-") + nonce + ".json"
	var file := FileAccess.open(destination + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(game.session.match_json() if game.match_mode else game.session.session_json())
	file.flush()
	file.close()
	journal_hash = game.session.match_hash() if game.match_mode else game.session.state_hash()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(destination + ".tmp"), ProjectSettings.globalize_path(destination))
