extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func settle(game) -> void:
	for step in range(400):
		if not game.run_active: break
		game._process(64.0 / 240.0)
	game._process(0)
	check(not game.run_active, "Drill shot did not settle")
func capture(game, filename: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	game.update_spatial(0)
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/evidence/" + filename + ".png")

func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	if "--mobile-ui" in OS.get_cmdline_user_args(): game.mobile_ui = true
	root.add_child(game)
	game.set_process(false)
	game.drills.toggle()
	check(game.drills.enabled and not game.match_mode, "Target drill entry failed")
	game.rink.mode = 4
	game.update_spatial(0)
	check(game.rink.target_rings.visible, "Target rings missing")
	for attempt in range(5):
		check(game.drills.attempt == attempt, "Wrong drill attempt")
		check(game.session.deliver(2050, -900, 1).is_empty(), "Drill throw rejected")
		game.frame = game.session.frame()
		game.run_active = true
		game.phase = "Travel"
		game.release_report = {"speed_mm_s": 2050}
		settle(game)
		check(game.drills.results.size() == attempt + 1, "Settled drill was not graded exactly once")
		game._process(0)
		check(game.drills.results.size() == attempt + 1, "Repeated frame duplicated drill points")
		if attempt < 4: game.next_throw()
	check(game.new_button.text == "New round", "Drill round cannot restart")
	check(game.drills.best[0] == game.drills.points(), "Drill best was not recorded")
	var before: String = game.session.state_hash()
	game.update_spatial(0)
	game.toggle_zoom()
	check(game.session.state_hash() == before, "Drill target display changed the core")
	game.toggle_zoom()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for i in range(12): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/evidence/drill-round.png")
	game.next_throw()
	check(game.drills.results.is_empty() and game.drills.attempt == 0, "New round retained old scores")
	game.drills.kind = 2
	game.reset(false)
	check(game.drills.target().x < 0, "Left line target missing")
	game.drills.kind = 3
	game.reset(false)
	game.drills.start_sweeping()
	check(game.run_active and game.can_sweep(), "Sweeping drill did not release a reachable stone")
	game.drills.save_path = "user://drill-restore-test.json"
	game.persistence_enabled = true
	game.save_practice()
	var hash: String = game.session.state_hash()
	game.reset(false)
	game.restore_current(false)
	check(game.drills.kind == 3 and game.run_active and game.session.state_hash() == hash, "Interrupted drill failed to restore")
	game.persistence_enabled = false
	game.hold_sweep = true
	settle(game)
	check(game.drills.results.size() == 1, "Restored sweeping attempt did not score")
	check(not game.drills.valid_envelope({"schema": 1, "session": "{}", "kind": 0, "attempt": 0, "results": [], "best": [100, 0, 0, 0]}), "Malformed drill scores accepted")
	# A checkpoint between settlement and grading must not strand the round.
	game.drills.kind = 1
	game.reset(false)
	game.session.deliver(2050, -900, 1)
	while not game.session.frame().resting: game.session.step_ticks(64, 0, 0, 180)
	game.frame = game.session.frame()
	game.phase = "Stone at rest"
	game.persistence_enabled = true
	game.save_practice()
	game.reset(false)
	game.restore_current(false)
	game.persistence_enabled = false
	game._process(0)
	check(game.drills.results.size() == 1 and not game.new_button.disabled, "Saved ungraded shot stranded the drill")
	# Older four-drill wrappers retain their best scores when upgraded.
	var old := {"schema": 1, "session": game.session.session_json(), "kind": 1, "attempt": 0, "results": [], "best": [3, 6, 9, 12]}
	check(game.drills.valid_envelope(old), "Legacy drill wrapper rejected")
	game.drills.restore_metadata(old)
	check(game.drills.best == [3, 6, 9, 12, 0, 0], "Legacy best scores were not upgraded")
	game.drills.kind = 4
	game.reset(false)
	check(game.frame.stones.size() == 1 and game.frame.stones[0].active and game.frame.delivered == 0, "Takeout setup did not create a recorded target")
	game._process(0)
	check(game.drills.results.is_empty() and game.phase == "Ready", "Target placement counted as a human attempt")
	# Restoring a ready target must allow a delivery, not strand the drill at rest.
	game.persistence_enabled = true
	game.save_practice()
	var target_hash: String = game.session.state_hash()
	game.reset(false)
	game.restore_current(false)
	game.persistence_enabled = false
	check(game.drills.kind == 4 and game.phase == "Ready" and game.session.state_hash() == target_hash, "Ready takeout target failed to restore")
	await capture(game, "drill-takeout")
	for i in range(5):
		check(game.drills.attempt == i and game.frame.stones.size() == 1, "Takeout target did not reset between attempts")
		if i == 0:
			check(game.session.hog_violation().is_empty(), "Takeout hog fault rejected")
			game.frame = game.session.frame()
			game.phase = "Stone at rest"
			game._process(0)
			check(game.drills.results[0].stars == 0 and not game.drills.results[0].target_removed, "Fault removed the target or earned takeout points")
		else:
			check(game.session.deliver(3000, -1050 if i % 2 == 0 else 1050, 1 if i % 2 == 0 else -1).is_empty(), "Takeout attempt rejected")
			game.frame = game.session.frame()
			game.run_active = true
			game.phase = "Travel"
			game.release_report = {"speed_mm_s": 3000}
			settle(game)
		check(game.drills.results.size() == i + 1, "Takeout round did not grade exactly one player attempt")
		check(game.drills.valid_envelope(JSON.parse_string(game.drills.save_envelope(game.session.session_json()))), "Takeout grade cannot save")
		if i < 4: game.next_throw()
	check(game.drills.best[4] == game.drills.points(), "Takeout best did not record")
	game.drills.kind = 5
	game.reset(false)
	game.update_spatial(0)
	check(not game.rink.target_rings.visible and "14.00 s" in game.drills.target_label.text, "Split trainer shows a positional target or lacks its time goal")
	check(game.session.deliver(2050, -900, 1).is_empty(), "Split trainer release rejected")
	game.frame = game.session.frame()
	game.run_active = true
	game.phase = "Travel"
	game.release_report = {"speed_mm_s": 2050}
	game._process(1)
	game.persistence_enabled = true
	game.save_practice()
	var split_hash: String = game.session.state_hash()
	game.reset(false)
	game.restore_current(false)
	game.persistence_enabled = false
	check(game.drills.kind == 5 and game.run_active and game.session.state_hash() == split_hash, "In-flight timing drill failed to restore")
	settle(game)
	check(game.drills.results.size() == 1 and game.drills.results[0].has("split_ms") and " / 3 stars" in game.report, "Split trainer did not grade its measured crossing")
	check(game.drills.valid_envelope(JSON.parse_string(game.drills.save_envelope(game.session.session_json()))), "Measured split grade cannot save")
	await capture(game, "drill-timing")
	game.next_throw()
	check("15.00 s" in game.drills.target_label.text, "Split goal did not change with attempt")
	game.session.hog_violation()
	game.frame = game.session.frame()
	game.phase = "Stone at rest"
	game._process(0)
	check(game.drills.results.size() == 2 and game.drills.results[1].stars == 0 and not game.drills.results[1].has("split_ms"), "Hog fault received a fabricated split")
	check("Did not cross both" in game.report, "Missing split lacked accessible feedback")
	var invalid: Dictionary = JSON.parse_string(game.drills.save_envelope(game.session.session_json()))
	invalid.results[1]["split_ms"] = "bad"
	invalid.results[1]["error_ms"] = 0
	check(not game.drills.valid_envelope(invalid), "Malformed timing metric accepted")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(game.drills.save_path + suffix))
	game.drills.toggle()
	check(not game.drills.enabled and not game.rink.target_rings.visible, "Leaving drills retained targets")
	game.queue_free()
	await process_frame
	print("DRILLS_OK" if not failed else "DRILLS_FAILED")
	quit(1 if failed else 0)
