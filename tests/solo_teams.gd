extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/play.tscn").instantiate()
	scene.persistence_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	scene.solo.start()
	check(scene.frame.format == "Teams" and scene.frame.match_phase == "Calling", "Solo did not use club team rules")
	check(scene.frame.stones.is_empty() and scene.frame.scheduled_ends == 6, "Solo has mixed-doubles setup")
	for position in range(4):
		scene.play_settings.human_position = position
		check(scene.solo.human_throws() == (position == 0), "Wrong human delivery assignment")
		check(scene.solo.human_skips() == (position == 3), "Wrong skip assignment")
	scene.play_settings.human_position = 0
	# Human input owns exactly the lead's two deliveries. AI takes every other seat.
	var ai_turns := 0
	for delivery in range(16):
		print("SOLO_DELIVERY ", delivery)
		check(scene.frame.delivered_count == delivery, "Wrong solo delivery count")
		if scene.solo.human_throws():
			check(scene.session.deliver(2050, -900, 1).is_empty(), "Human release rejected")
			scene.frame = scene.session.frame()
			scene.run_active = true
			scene.phase = "Travel"
			scene.release_report = {"speed_mm_s": 2050}
		else:
			var deadline := Time.get_ticks_msec() + 20000
			while not scene.run_active and Time.get_ticks_msec() < deadline:
				scene._process(.02)
				await process_frame
			check(scene.run_active, "AI failed to release delivery %d" % delivery)
			ai_turns += 1
		var saw_fast := false
		for step in range(800):
			if not scene.run_active: break
			if scene.solo.fast_forwarding(): saw_fast = true
			scene._process(64.0 / 240.0)
		check(not scene.run_active, "Solo stone failed to settle")
		check(scene.frame.delivered_count == delivery + 1, "AI skipped a rules delivery")
		if delivery < 15: scene.next_throw()
	check(ai_turns == 14, "AI did not cover remaining seven positions")
	check(scene.frame.match_phase == "EndComplete", "Solo end did not complete")
	var restored = ClassDB.instantiate("CurlSession")
	check(restored.load_match(scene.session.match_json()).is_empty(), "Solo journal rejected")
	check(restored.match_hash() == scene.session.match_hash(), "Solo journal diverged")
	scene.next_throw()
	check(scene.frame.end == 2 and scene.phase == "Ready" and not scene.setup_panel.visible, "Team next end entered mixed setup")
	# No manual input may throw for another seat. A human skip approves AI calls.
	scene.play_settings.human_position = 3
	scene.reset(false)
	var deadline := Time.get_ticks_msec() + 20000
	while scene.solo.planned.is_empty() and Time.get_ticks_msec() < deadline:
		scene._process(.02)
		await process_frame
	check(not scene.run_active and scene.solo.send_button.visible, "Skip cannot review the called AI shot")
	scene.solo.send_shot()
	check(scene.run_active, "Skip's Send called shot failed")
	scene.solo.set_call(0)
	check(scene.solo.brush_effort() == 0 and "OFF" in scene.solo.call_label.text, "Silent OFF call was ignored")
	scene.solo.set_call(255)
	check(scene.solo.brush_effort() == 255 and "HARD" in scene.solo.call_label.text, "Silent HARD call was ignored")
	# Fast-forward eligibility excludes own shots, ends of the sheet, and stopped stones.
	scene.play_settings.fast_opponents = true
	scene.solo.shot_team = 1
	var display: Dictionary = scene.frame.duplicate(true)
	for y in [-28.3, -28.0, -7.0, -6.5, 0.0]:
		scene.frame.stones[0].position.y = y
		check(scene.solo.fast_forwarding() == (y > -28.207 and y < -6.543), "Fast-forward escaped hog lines")
	scene.frame = display
	scene.solo.shot_team = 0
	check(not scene.solo.fast_forwarding(), "Own shot fast-forwarded")
	scene.queue_free()
	await process_frame
	print("SOLO_TEAMS_OK" if not failed else "SOLO_TEAMS_FAILED")
	quit(1 if failed else 0)
