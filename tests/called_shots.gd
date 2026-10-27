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
	check(game.solo.shot_choice.visible and game.solo.target_button.visible, "Skip shot card missing")
	game.solo.target_button.pressed.emit()
	game.update_spatial(0)
	game.begin_pointer(0, game.rink.ice_screen_point(Vector2(.7, -.5)))
	check(game.pointer == -99 and game.solo.planning, "Target placement began a delivery instead of a call")
	await await_plan(game)
	check(game.solo.planned.kind == "Draw" and game.solo.called_target.distance_to(Vector2(.7, -.5)) < .002, "Called target changed")
	var old_turn: int = game.turn
	var old_broom: int = game.broom_mm
	game.turn_button.pressed.emit()
	await await_plan(game)
	check(game.turn == -old_turn and absi(game.broom_mm - old_broom) > 500, "Turn reversal did not re-solve the broom line")
	game.solo.shot_choice.item_selected.emit(1)
	await await_plan(game)
	check(game.solo.planned.kind == "Guard" and game.solo.called_target.y == -3.0, "Guard call used draw weight")
	game.update_spatial(0)
	game.toggle_zoom()
	check(absf(game.rink.camera.position.z - 3.0) < .002, "House zoom did not inspect the called guard")
	game.toggle_zoom()
	game.solo.send_shot()
	check(game.run_active and not game.solo.shot_choice.visible, "Called guard did not release")
	check(game.frame.solo_target_y_mm == -3000, "Called guard target not retained for sweeping/save")
	for i in range(400):
		if not game.run_active: break
		game._process(64.0 / 240.0)
	check(not game.run_active and game.frame.delivered_count == 1, "Called guard failed to settle through rules")
	# Stale-plan/invalid calls must not mutate a live delivery or settled board.
	var before: String = game.session.match_hash()
	check(not game.session.request_called_shot(7, 0, 0, 1).is_empty(), "Unknown called shot accepted")
	check(not game.session.request_called_shot(0, 999999, 0, 1).is_empty(), "Out-of-sheet called target accepted")
	check(game.session.match_hash() == before, "Rejected call mutated the match")
	game.queue_free()
	await process_frame
	print("CALLED_SHOTS_OK" if not failed else "CALLED_SHOTS_FAILED")
	quit(1 if failed else 0)
