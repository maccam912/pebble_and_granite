extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func settle(game) -> void:
	for i in range(600):
		game._process(64.0 / 240.0)
		if not game.run_active: break
	check(not game.run_active, "Lesson shot did not settle")
func capture(game, name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	game.update_spatial(0)
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/evidence/learn")
	root.get_texture().get_image().save_png("res://build/evidence/learn/" + name + ".png")
	for label in [game.lesson_title, game.lesson_help, game.lesson_result]:
		check(game.lesson_card.get_global_rect().encloses(label.get_global_rect()), "Lesson text overflowed its panel")
func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	game.mobile_ui = true
	root.add_child(game)
	game.set_process(false)
	await process_frame
	check(game.session.begin_held(2050, -900).is_empty(), "Saved game fixture failed")
	game.frame = game.session.frame()
	var before: String = game.session.state_hash()
	game.open_lessons()
	var lesson = game.learning_game
	if lesson == null: check(false, "Lesson did not open"); quit(1); return
	lesson.set_process(false)
	await process_frame
	check(not lesson.persistence_enabled and not lesson.play_settings.persistence_enabled, "Lesson may overwrite player saves or preferences")
	game._process(10)
	check(game.session.state_hash() == before and not game.visible, "Opening lessons changed the saved game")
	lesson._process(0)
	check(not lesson.passed, "Aim succeeded without dragging")
	await capture(lesson, "01-aim")
	lesson.begin_pointer(0, lesson.broom_screen_point())
	check(lesson.dragging_broom, "Lesson broom cannot be gripped")
	var target: Vector2 = lesson.rink.ice_screen_point(Vector2(.7, 0))
	lesson.move_pointer(target)
	lesson.end_pointer(target)
	lesson._process(0)
	check(lesson.passed and not lesson.continue_button.disabled, "Correct broom drag did not advance aim")
	lesson.next_lesson()
	check(lesson.step == 1 and not lesson.passed, "Next lesson retained success")
	await capture(lesson, "02-weight")
	# A real too-light release fails and a near-tee release passes on the same ice.
	check(lesson.session.deliver(1650, 0, 1).is_empty(), "Light release failed")
	lesson.frame = lesson.session.frame()
	lesson.run_active = true
	settle(lesson)
	check(not lesson.passed and "faster" in lesson.lesson_result.text, "Light shot lacked actionable feedback")
	lesson.prepare_lesson()
	check(lesson.session.deliver(2050, -900, 1).is_empty(), "Draw release failed")
	lesson.frame = lesson.session.frame()
	lesson.run_active = true
	settle(lesson)
	check(lesson.passed, "Achievable draw weight was rejected")
	await capture(lesson, "03-weight-result")
	lesson.next_lesson()
	var clock := [0]
	lesson.input_clock = func(): return clock[0]
	var handle: Vector2 = lesson.handle_point()
	lesson.begin_pointer(0, handle)
	for sample in [[100000, 0, 24.0], [120000, 0, 19.2], [240000, 0, -9.6], [2700000, 0, -9.6], [2850000, 6, -9.6]]:
		clock[0] = sample[0]
		lesson.move_pointer(handle + Vector2(sample[1], sample[2]))
	clock[0] = 3000000
	lesson.end_pointer(handle + Vector2(6, -9.6))
	lesson._process(.016)
	check(lesson.passed and lesson.turn == 1, "Real finishing curl did not complete lesson")
	await capture(lesson, "04-curl")
	lesson.next_lesson()
	lesson.start_draw()
	check(lesson.run_active, "Sweeping lesson did not launch")
	lesson._process(.1)
	check(lesson.swept_ticks == 0 and not lesson.passed, "Unbrushed travel counted as sweeping")
	lesson.hold_sweep = true
	lesson.play_settings.show()
	lesson._process(1)
	check(lesson.swept_ticks == 0, "Paused lesson counted sweeping")
	lesson.play_settings.hide()
	lesson.hold_sweep = true
	for i in range(3): lesson._process(.25)
	check(lesson.swept_ticks >= 120 and not lesson.passed, "Sweep lesson did not require stopping")
	lesson.hold_sweep = false
	lesson._process(.016)
	check(lesson.passed, "Release after useful sweeping did not finish")
	await capture(lesson, "05-sweep-result")
	var log: Dictionary = JSON.parse_string(lesson.session.session_json())
	check(not log.records[-1].data.sweeps.is_empty(), "Tutorial credited sweeping without a recorded brush")
	lesson.next_lesson()
	await process_frame
	check(game.visible and game.learning_game == null and game.session.state_hash() == before, "Returning from tutorial lost held game")
	game.open_lessons()
	game.learning_game.set_process(false)
	game.learning_game.skip_lesson()
	check(game.learning_game.step == 1 and not game.learning_game.passed, "Skip recorded false success")
	game.learning_game.leave_lesson()
	game.queue_free()
	await process_frame
	print("LEARN_OK" if not failed else "LEARN_FAILED")
	quit(1 if failed else 0)
