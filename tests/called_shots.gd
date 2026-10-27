extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func await_plan(game) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while game.solo.planned.is_empty() and Time.get_ticks_msec() < deadline:
		game._process(.02)
		await process_frame
	check(not game.solo.planned.is_empty(), "Called-shot solve did not finish: " + game.report)
func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	game.set_process(false)
	game.play_settings.human_position = 3
	game.solo.start()
	await await_plan(game)
	check(game.solo.shot_choice.visible and game.solo.turn_buttons[0].visible, "Skip controls missing")
	game.update_spatial(0)
	check(not game.rink.target_rings.visible and not game.rink.called_target.is_finite(), "Skip aiming reveals an endpoint")
	var broom: Vector2 = game.broom_screen_point()
	game.begin_pointer(0, broom)
	check(game.dragging_broom, "Touch cannot pick up skip broom")
	game.move_pointer(game.rink.ice_screen_point(Vector2(.7, 0)))
	game.end_pointer(game.rink.ice_screen_point(Vector2(.7, 0)))
	check(absi(game.broom_mm - 700) < 3 and not game.run_active, "Broom drag did not set aim")
	check(game.rink.current_camera == "House", "Broom drop left the skip camera")
	var old_broom: int = game.broom_mm
	game.solo.turn_buttons[1].pressed.emit()
	check(game.turn == -1 and game.broom_mm == old_broom and not game.solo.planning, "Turn choice re-solved the line")
	game.solo.shot_choice.select(1)
	game.solo.shot_choice.item_selected.emit(1)
	await await_plan(game)
	check(game.solo.planned.kind == "Guard" and game.broom_mm == old_broom and game.turn == -1, "Weight call changed manual line/turn")
	game.update_spatial(0)
	check(not game.rink.target_rings.visible, "Weight call exposed a landing target")
	game.toggle_zoom()
	check(absf(game.rink.camera.size - 2.4) < .001, "House inspection zoom failed")
	game.toggle_zoom()
	game.solo.send_shot()
	check(game.run_active and not game.solo.shot_choice.visible, "Called guard did not release")
	check(game.frame.solo_target_y_mm == -3000, "Called guard target not retained for sweeping/save")
	for i in range(400):
		if not game.run_active: break
		game._process(64.0 / 240.0)
	check(not game.run_active and game.frame.delivered_count == 1, "Called guard failed to settle through rules")
	check(game.shot_reference.shots.has(0), "Clean called shot did not retain a reference")
	if game.shot_reference.shots.has(0):
		check(game.shot_reference.shots[0].broom == old_broom and game.shot_reference.shots[0].turn == -1, "Reference lost actual line/turn")
	# Stale-plan/invalid calls must not mutate a live delivery or settled board.
	var before: String = game.session.match_hash()
	check(not game.session.request_called_shot(7, 0, 0, 1).is_empty(), "Unknown called shot accepted")
	check(not game.session.request_called_shot(0, 999999, 0, 1).is_empty(), "Out-of-sheet called target accepted")
	check(game.session.match_hash() == before, "Rejected call mutated the match")
	if "--capture" in OS.get_cmdline_user_args():
		# Deliberately short opponent delivery leaves the Gold reference intact.
		game.next_throw()
		check(game.session.deliver(1800, -2200, -1).is_empty(), "Review opponent release failed")
		game.frame = game.session.frame()
		game.run_active = true
		game.phase = "Travel"
		game.solo.shot_team = 1
		for i in range(400):
			if not game.run_active: break
			game._process(64.0 / 240.0)
		game.next_throw()
		await await_plan(game)
		check(game.broom_mm == old_broom and game.turn == -1, "Opponent shot replaced the caller's line")
		check(game.shot_reference.shots.has(0), "Opponent review delivery erased clean reference")
		game.update_spatial(0)
		for i in range(12): await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/evidence/skip-polish")
		root.get_texture().get_image().save_png("res://build/evidence/skip-polish/previous-shot.png")
	game.queue_free()
	await process_frame
	print("CALLED_SHOTS_OK" if not failed else "CALLED_SHOTS_FAILED")
	quit(1 if failed else 0)
