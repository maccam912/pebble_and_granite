extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/evidence/play-menu")
	root.get_texture().get_image().save_png("res://build/evidence/play-menu/" + name + ".png")
func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	game.mobile_ui = true
	root.add_child(game)
	game.set_process(false)
	await process_frame
	check(game.menu_button.visible and not game.mode_button.visible and not game.solo.solo_button.visible, "Legacy navigation still crowds the rink")
	check(not game.new_button.visible and not game.sweep_button.visible and game.one_button.visible, "Ready controls are not contextual")
	await capture("01-ready")
	game.play_menu.open()
	await process_frame
	var hash_before: String = game.session.state_hash()
	game._process(10)
	game.begin_pointer(0, game.handle_point())
	check(game.session.state_hash() == hash_before and game.pointer == -99, "Menu leaked simulation or input")
	await capture("02-menu")
	var buttons: Array = game.play_menu.actions.values()
	for i in range(buttons.size()):
		check(game.play_menu.get_global_rect().encloses(buttons[i].get_global_rect()), "Menu action overflow")
		for j in range(i + 1, buttons.size()): check(not buttons[i].get_global_rect().intersects(buttons[j].get_global_rect()), "Menu actions overlap")
	game.play_menu.actions.mixed.pressed.emit()
	check(game.match_mode and not game.solo.enabled and not game.play_menu.visible, "Mixed doubles menu action failed")
	game.play_menu.open()
	game.play_menu.actions.practice.pressed.emit()
	check(not game.match_mode and not game.drills.enabled, "Practice navigation failed")
	game.play_menu.open()
	game.play_menu.actions.drills.pressed.emit()
	check(game.drills.enabled and not game.match_mode, "Drill navigation failed")
	game.play_menu.open()
	game.play_menu.actions.solo.pressed.emit()
	check(game.solo.enabled and not game.drills.enabled, "Solo navigation failed")
	game.play_menu.open()
	game.play_menu.actions.mixed.pressed.emit()
	check(game.match_mode and not game.solo.enabled, "Solo-to-mixed navigation failed")
	game.select_mode("practice")
	game.session.deliver(2050, -900, 1)
	game.frame = game.session.frame()
	game.run_active = true
	game.phase = "Travel"
	game.report = "Scrub ahead of the moving stone, or hold to sweep."
	game.update_labels()
	game._process(.25)
	check(game.sweep_button.visible and not game.one_button.visible and not game.new_button.visible, "Travel controls still show delivery actions")
	await capture("03-travel")
	game.play_menu.open()
	hash_before = game.session.state_hash()
	game._process(20)
	check(game.session.state_hash() == hash_before and game.play_menu.actions.mixed.disabled and game.play_menu.actions.restart.disabled, "Live shot can be lost through menu")
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	check(not game.play_menu.visible and not game.play_settings.visible, "Escape did not close only the current menu")
	var tick_before: int = game.frame.tick
	game._process(.02)
	check(game.frame.tick - tick_before < 10, "Menu pause caused simulation catch-up")
	game.queue_free()
	await process_frame
	print("PLAY_MENU_OK" if not failed else "PLAY_MENU_FAILED")
	quit(1 if failed else 0)
