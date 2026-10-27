extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func shot(game, speed: int, broom: int) -> void:
	check(game.session.deliver(speed, broom, 1).is_empty(), "No-tick fixture release rejected")
	game.frame = game.session.frame()
	game.run_active = true
	game.phase = "Travel"
	game.accumulator = 0.0
	game.release_report = {"speed_mm_s": speed}
	for i in range(400):
		if not game.run_active: break
		game._process(64.0 / 240.0)
	check(not game.run_active, "No-tick fixture did not settle")
func fixture(game, owner: int) -> void:
	game.solo.enabled = false
	game.match_mode = true
	game.session.new_team_match(42)
	game.frame = game.session.frame()
	if owner == 1:
		check(game.session.hog_violation().is_empty(), "No-tick prefix fault failed")
		game.frame = game.session.frame()
	shot(game, 1981, -963)
	shot(game, 2016, -803)
	game.solo.enabled = true
	game.solo.reset_turn()
	game.update_labels()
	game.update_spatial(0)
	check(game.frame.match_phase == "Choice" and game.frame.choice_team == owner, "Physical glancing contact did not enter the expected no-tick choice")
func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	game.set_process(false)
	fixture(game, 0)
	check(game.solo.accept_button.visible and game.solo.restore_button.visible and game.new_button.disabled, "Gold no-tick remedies unavailable")
	check(game.frame.counting_stones.is_empty(), "Pending remedy displayed a settled score")
	check(game.rink.current_camera == "House", "No-tick choice did not show the board")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for i in range(12): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/evidence/no-tick-choice.png")
	var pending: String = game.session.match_json()
	game.solo.save_path = "user://no-tick-ui-test.json"
	game.persistence_enabled = true
	game.save_practice()
	game.reset(false)
	game.restore_current(true)
	game.persistence_enabled = false
	check(game.frame.match_phase == "Choice" and game.solo.restore_button.visible, "Pending no-tick save cannot resume its remedy")
	game.solo.restore_button.pressed.emit()
	check(game.frame.match_phase == "Calling" and game.frame.delivered_count == 2 and game.frame.remedy_restored, "Restore did not consume exactly one offending delivery")
	check(game.frame.stones.filter(func(stone): return stone.active).size() == 1, "Restore did not remove the offending stone")
	check(not game.session.match_choose(true).is_empty(), "A duplicate remedy was accepted")
	check(game.session.load_match(pending).is_empty(), "Pending no-tick journal failed to replay")
	game.frame = game.session.frame()
	game.update_labels()
	game.solo.accept_button.pressed.emit()
	check(game.frame.match_phase == "Calling" and game.frame.delivered_count == 2 and not game.frame.remedy_restored, "Accept did not resume the match")
	check("current positions accepted" in game.report_label.text, "Accepted no-tick result was labelled as restored")
	check(game.frame.stones.filter(func(stone): return stone.active).size() == 2, "Accept discarded a legal retained position")
	var copy = ClassDB.instantiate("CurlSession")
	check(copy.load_match(game.session.match_json()).is_empty() and copy.match_hash() == game.session.match_hash(), "Chosen remedy did not replay exactly")
	fixture(game, 1)
	check(not game.solo.accept_button.visible and not game.solo.restore_button.visible, "Gold can choose Cyan's remedy")
	game._process(1.2)
	check(game.frame.match_phase == "Calling" and game.frame.delivered_count == 3, "Cyan AI did not resolve its no-tick choice")
	check(not game.new_button.disabled, "Match remained stranded after AI remedy")
	# An early release may forfeit on time while its stone is still moving.
	# GameComplete must end local travel and expose rematch in that branch too.
	game.reset(false)
	for i in range(29): game.session.match_think(60000)
	game.session.match_think(59999)
	check(game.session.deliver_slide(1500000, -37800000, 0, 1).is_empty(), "Clock-forfeit fixture release failed")
	game.frame = game.session.frame()
	game.run_active = true
	game.phase = "Travel"
	game.release_report = {"speed_mm_s": 1500}
	game._process(.1)
	check(game.frame.match_phase == "GameComplete" and not game.run_active, "Moving clock forfeit stranded local travel")
	check(game.new_button.text == "Rematch" and not game.new_button.disabled, "Clock forfeit did not expose rematch")
	game.next_throw()
	check(game.frame.match_phase == "Calling" and game.frame.end == 1, "Clock-forfeit rematch failed")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(game.solo.save_path + suffix))
	game.queue_free()
	await process_frame
	print("TEAM_RULES_OK" if not failed else "TEAM_RULES_FAILED")
	quit(1 if failed else 0)
