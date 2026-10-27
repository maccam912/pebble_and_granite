extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func press_key(code: int, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
func await_ai(game) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while not game.run_active and Time.get_ticks_msec() < deadline:
		game._process(.05)
		await process_frame
	check(game.run_active, "AI control mode stalled")
func settle(game) -> void:
	for i in range(400):
		if not game.run_active: break
		game._process(64.0 / 240.0)
	check(not game.run_active, "Control-mode shot did not settle")
func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	game.set_process(false)
	var settings = game.play_settings
	var before: String = game.session.state_hash()
	settings.show()
	settings.binding_panel.show()
	await process_frame
	for i in range(8):
		var focused := root.gui_get_focus_owner()
		check(focused != null and settings.binding_panel.is_ancestor_of(focused), "Keyboard focus escaped the shortcut modal at Tab %d: %s" % [i, str(focused.get_path()) if focused != null else "none"])
		await press_key(KEY_TAB)
	settings.binding_buttons[0].pressed.emit()
	await press_key(KEY_J)
	check(settings.call_keys[0] == KEY_J, "Native key capture failed")
	settings.binding_buttons[1].pressed.emit()
	await press_key(KEY_J)
	check(settings.call_keys[0] == KEY_C and settings.call_keys[1] == KEY_J, "Duplicate remapping did not swap keys")
	settings.binding_buttons[2].pressed.emit()
	await press_key(KEY_Z)
	check(settings.waiting_key == 2 and settings.call_keys[2] == KEY_O, "Reserved zoom key was captured")
	await press_key(KEY_ESCAPE)
	check(settings.waiting_key == -1 and settings.binding_panel.visible, "Esc did not cancel capture")
	await press_key(KEY_ESCAPE)
	check(not settings.binding_panel.visible and settings.visible, "Esc did not return to play settings")
	await press_key(KEY_ESCAPE)
	check(not settings.visible and game.session.state_hash() == before, "Closing settings mutated the game")
	if "--focus-only" in OS.get_cmdline_user_args():
		game.queue_free()
		await process_frame
		quit(1 if failed else 0)
		return
	settings.human_position = 5
	game.solo.start()
	check(not game.solo.human_throws() and game.solo.human_skips(), "Calling-only mode assigned a human delivery")
	var deadline := Time.get_ticks_msec() + 30000
	while game.solo.planned.is_empty() and Time.get_ticks_msec() < deadline:
		game._process(.05)
		await process_frame
	game.solo.send_shot()
	check(game.run_active, "Calling-only mode could not send the AI throw")
	await press_key(KEY_C)
	check(game.solo.call_override == 255 and "HARD" in game.solo.call_label.text, "Remapped hard call was ignored")
	await press_key(KEY_O)
	check(game.solo.call_override == 0 and "OFF" in game.solo.call_label.text, "Off shortcut was ignored")
	await press_key(KEY_C, true)
	check(game.solo.call_override == 0, "Held-key repeats issued another call")
	settings.show()
	check(settings.position_choice.disabled, "Live role change can strand a delivery")
	await press_key(KEY_C)
	check(game.solo.call_override == 0, "Shortcut escaped settings")
	settings.hide()
	check(game.solo.valid_envelope(JSON.parse_string(game.solo.save_envelope(game.session.match_json()))), "Calling-only mode cannot save")
	# Full team owns every Gold delivery and supplies its own brush commands.
	settings.human_position = 4
	game.reset(false)
	var manual := 0
	var ai := 0
	var reference = ClassDB.instantiate("CurlSession")
	reference.new_team_match(42)
	reference.deliver(2050, -900, 1)
	for delivery in range(16):
		if game.frame.team == 0:
			check(game.solo.human_throws(), "Full team lost a human delivery")
			check(game.session.deliver(2050, -900, 1).is_empty(), "Full-team release rejected")
			game.frame = game.session.frame()
			game.run_active = true
			game.phase = "Travel"
			game.release_report = {"speed_mm_s": 2050}
			manual += 1
		else:
			check(not game.solo.human_throws(), "Full team took an opponent delivery")
			await await_ai(game)
			ai += 1
		settle(game)
		if delivery == 0:
			while reference.frame().match_phase == "InFlight": reference.step_solo_ticks(64, 0, 0, 0, 180, 0)
			check(game.session.match_hash() == reference.match_hash(), "Full team applied hidden automatic sweeping")
		if delivery < 15: game.next_throw()
	check(manual == 8 and ai == 8 and game.frame.match_phase == "EndComplete", "Full-team end did not assign eight deliveries per side")
	var prefs := CurlPlaySettings.new()
	prefs.config_path = "user://call-settings-test.cfg"
	root.add_child(prefs)
	prefs.call_keys = PackedInt32Array([KEY_J, KEY_K, KEY_L])
	prefs.human_position = 5
	prefs.steady_camera = true
	prefs.update_preferences()
	var loaded := CurlPlaySettings.new()
	loaded.config_path = prefs.config_path
	root.add_child(loaded)
	check(loaded.call_keys == prefs.call_keys and loaded.human_position == 5 and loaded.steady_camera and loaded.steady_toggle.button_pressed, "Call shortcuts/control mode did not persist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs.config_path))
	prefs.queue_free()
	loaded.queue_free()
	game.queue_free()
	await process_frame
	print("ACCESSIBILITY_OK" if not failed else "ACCESSIBILITY_FAILED")
	quit(1 if failed else 0)
