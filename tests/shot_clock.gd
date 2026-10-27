extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/evidence/shot-clock")
	root.get_texture().get_image().save_png("res://build/evidence/shot-clock/" + name + ".png")
func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	game.set_process(false)
	check(not game.shot_clock.visible, "Clock showed a previous split before delivery")
	check(game.session.deliver_slide(2700000, -36000000, -900, 1).is_empty(), "Early release failed")
	game.frame = game.session.frame()
	game.run_active = true
	game.phase = "Travel"
	game.report = "Watch the stone's weight. Scrub ahead or hold to sweep."
	game.update_labels()
	check(game.shot_clock.visible and game.frame.hog_clock_state == "Waiting" and game.shot_clock.reading.text == "—", "Clock started at release instead of near hog")
	var sampled := false
	var complete := -1
	for i in range(400):
		if not game.run_active: break
		game._process(64.0 / 240.0)
		if game.frame.hog_clock_state == "Running" and game.frame.hog_clock_ms >= 5000 and not sampled:
			sampled = true
			var before: String = game.session.state_hash()
			var ms: int = game.frame.hog_clock_ms
			game.play_settings.show()
			game._process(30)
			check(game.session.state_hash() == before and game.frame.hog_clock_ms == ms, "Stopwatch advanced during local pause")
			game.play_settings.hide()
			var restored = ClassDB.instantiate("CurlSession")
			check(restored.load_session(game.session.session_json()).is_empty(), "In-flight clock restore failed")
			check(restored.frame().hog_clock_ms == ms and restored.frame().hog_clock_state == "Running", "Resume rebuilt a different stopwatch")
			await capture("running")
		if game.frame.hog_clock_state == "Complete":
			if complete < 0:
				complete = game.frame.hog_clock_ms
				await capture("split")
			check(game.frame.hog_clock_ms == complete and complete == game.frame.hog_split_ms, "Clock continued after the far hog")
	check(sampled and complete > 0 and not game.run_active and not game.shot_clock.visible, "Stopwatch lifecycle did not complete")
	check(complete + 2000 < game.frame.hog_tick * 1000.0 / 240.0, "Clock counted release-to-near-hog travel")
	game.next_throw()
	check(not game.shot_clock.visible, "Previous clock carried into the next delivery")
	game.queue_free()
	await create_timer(.5).timeout
	print("SHOT_CLOCK_OK" if not failed else "SHOT_CLOCK_FAILED")
	quit(1 if failed else 0)
