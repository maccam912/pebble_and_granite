extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	game.set_process(false)
	game.play_settings.human_position = 5
	game.play_settings.position_choice.select(5)
	game.solo.start()
	var deadline := Time.get_ticks_msec() + 30000
	while game.solo.planned.is_empty() and Time.get_ticks_msec() < deadline:
		game._process(.02)
		await process_frame
	check(not game.solo.planned.is_empty(), "Caller plan not ready")
	game.solo.send_shot()
	for i in range(400):
		if not game.run_active: break
		game._process(64.0 / 240.0)
	check(game.solo.review_waiting() and game.new_button.text == "Continue", "Gold result did not wait for review")
	var before: String = game.session.match_hash()
	for i in range(50): game._process(1.0)
	check(game.solo.review_waiting() and game.session.match_hash() == before, "Review charged thinking time or started the opponent")
	# Restoring a settled result must use the previous team, not frame.team.
	var save: String = game.session.match_json()
	game.reset(false)
	check(game.session.load_match(save).is_empty(), "Review journal failed to load")
	game.frame = game.session.frame()
	game.phase = "Stone at rest"
	game.solo.reset_turn()
	check(game.solo.review_waiting(), "Settled reload lost review pause")
	game.new_button.pressed.emit()
	check(not game.solo.review_waiting() and game.phase == "Ready", "Continue did not release the review pause")
	# Opponent results still move on automatically.
	check(game.session.hog_violation().is_empty(), "Opponent review fixture failed")
	game.frame = game.session.frame()
	game.phase = "Stone at rest"
	check(not game.solo.review_waiting(), "Opponent result stalled behind a human review")
	# Optional classic pacing advances after two seconds.
	game.session.hog_violation()
	game.frame = game.session.frame()
	game.phase = "Stone at rest"
	game.play_settings.review_shots = false
	game.play_settings.review_toggle.set_pressed_no_signal(false)
	game.solo.delay = 0
	game._process(2.1)
	check(game.phase == "Ready" and not game.solo.review_waiting(), "Automatic continuation preference was ignored")
	game.play_settings.show()
	game.play_settings.content_scroll.scroll_vertical = 250
	await process_frame
	game.play_settings.volume_slider.grab_focus()
	await process_frame
	check(game.play_settings.get_global_rect().encloses(game.play_settings.volume_slider.get_global_rect()), "Volume slider cannot be brought into view")
	if "--capture" in OS.get_cmdline_user_args():
		for i in range(12): await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/evidence/shot-review")
		root.get_texture().get_image().save_png("res://build/evidence/shot-review/settings.png")
	game.queue_free()
	await create_timer(.5).timeout
	print("SHOT_REVIEW_PAUSE_OK" if not failed else "SHOT_REVIEW_PAUSE_FAILED")
	quit(1 if failed else 0)
