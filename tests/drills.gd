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
func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
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
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(game.drills.save_path + suffix))
	game.drills.toggle()
	check(not game.drills.enabled and not game.rink.target_rings.visible, "Leaving drills retained targets")
	game.queue_free()
	await process_frame
	print("DRILLS_OK" if not failed else "DRILLS_FAILED")
	quit(1 if failed else 0)
