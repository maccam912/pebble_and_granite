extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	game.set_process(false)
	check(game.session.deliver(2050, -900, 1).is_empty(), "Practice release failed")
	game.frame = game.session.frame()
	game.run_active = true
	game.phase = "Travel"
	game.update_labels()
	var initial: String = game.session.state_hash()
	game.request_restart()
	check(not game.restart_prompt.visible and game.session.state_hash() == initial and game.fresh_button.disabled, "Live shot can be accidentally erased")
	game.play_settings.show()
	game._process(30)
	check(game.session.state_hash() == initial, "Practice ran behind Settings")
	game.play_settings.hide()
	game._process(.02)
	check(game.frame.tick < 10 and game.session.state_hash() != initial, "Menu pause accumulated catch-up time")
	for i in range(400):
		if not game.run_active: break
		game._process(64.0 / 240.0)
	check(not game.run_active, "Practice fixture did not settle")
	initial = game.session.state_hash()
	game.fresh_button.grab_focus()
	game.request_restart()
	await process_frame
	check(game.restart_prompt.visible and root.gui_get_focus_owner() == game.restart_prompt.cancel_button, "Restart does not default to keeping progress")
	game.begin_pointer(0, game.broom_screen_point())
	game._process(3)
	check(game.pointer == -99 and game.session.state_hash() == initial, "Restart modal leaked input or simulation")
	if "--capture" in OS.get_cmdline_user_args():
		for i in range(12): await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/evidence/local-menus")
		root.get_texture().get_image().save_png("res://build/evidence/local-menus/restart.png")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	check(not game.restart_prompt.visible and not game.restart_prompt.shade.visible and game.session.state_hash() == initial, "Escape discarded the practice session")
	check(root.gui_get_focus_owner() == game.fresh_button, "Restart cancellation lost keyboard focus")
	game.request_restart()
	game.restart_prompt.confirm_button.pressed.emit()
	check(not game.restart_prompt.visible and game.frame.stones.is_empty(), "Confirmed restart did not clear practice")
	game.match_mode = true
	game.reset(false)
	var clock_before: int = game.frame.clock_gold
	game.play_settings.show()
	game._process(30)
	check(game.frame.clock_gold == clock_before, "Match clock ran behind Settings")
	game.play_settings.hide()
	# Held delivery must never be discarded by a restart button.
	game.match_mode = false
	game.reset(false)
	check(game.session.begin_held(2050, -900).is_empty(), "Held fixture failed")
	game.frame = game.session.frame()
	game.update_labels()
	initial = game.session.state_hash()
	game.request_restart()
	check(game.fresh_button.disabled and not game.restart_prompt.visible and game.session.state_hash() == initial, "Restart discarded a held delivery")
	game.pointer = -1
	game.phase = "Slide"
	await escape()
	check(game.play_settings.visible and game.pointer == -99 and not game.frame.in_hand.is_empty(), "Escape did not pause and retain the held stone")
	initial = game.session.state_hash()
	game._process(10)
	check(game.session.state_hash() == initial, "Held stone advanced behind the Escape menu")
	await escape()
	check(not game.play_settings.visible and game.phase == "Ready" and not game.frame.in_hand.is_empty(), "Closing Escape menu lost regrip state")
	# Repeated Escape closes the current menu without reopening it on the same event.
	await escape()
	check(game.play_settings.visible, "Escape did not reopen Settings")
	await escape()
	check(not game.play_settings.visible, "Escape close reopened the modal")
	game.queue_free()
	await create_timer(.5).timeout
	print("LOCAL_MENUS_OK" if not failed else "LOCAL_MENUS_FAILED")
	quit(1 if failed else 0)
