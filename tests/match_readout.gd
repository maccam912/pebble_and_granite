extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func refresh(game) -> void:
	game.frame = game.session.frame()
	game.run_active = game.frame.match_phase == "InFlight"
	game.phase = "Travel" if game.run_active else "Stone at rest"
	game.update_labels()
	game.update_spatial(0)
func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/evidence/match-readout")
	root.get_texture().get_image().save_png("res://build/evidence/match-readout/" + name + ".png")
func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	game.set_process(false)
	game.match_mode = true
	game.solo.enabled = true
	game.play_settings.human_position = 3
	game.session.new_team_match(42)
	refresh(game)
	check(game.frame.stones_left_gold == 8 and game.frame.stones_left_cyan == 8, "Team stone inventory starts wrong")
	check(game.frame.counting_stones.is_empty(), "Empty house contains scoring marks")
	check(game.session.deliver(2050, -900, 1).is_empty(), "Scoring draw fixture failed")
	refresh(game)
	check(game.frame.stones_left_gold == 7 and game.frame.stones_left_cyan == 8, "Released stone was counted as still to play")
	check(game.frame.counting_stones.is_empty() and not game.rink.show_counting, "Moving stones were marked as settled score")
	for i in range(400):
		if game.session.frame().match_phase != "InFlight": break
		game.session.step_ticks(64, 0, 0, 180)
	refresh(game)
	check(game.frame.counting_team == 0 and game.frame.counting_points == 1 and game.frame.counting_stones == PackedInt32Array([0]), "Rules score and counting ids disagree")
	check(game.rink.stones[0].get_node("CountingRing").visible, "Counting stone has no rink mark")
	var before: String = game.session.match_hash()
	game.rink.mode = 4
	game.update_spatial(0)
	game.match_readout.refresh()
	check(game.session.match_hash() == before, "Score presentation changed authority")
	await capture("counting-stone")
	for i in range(15): check(game.session.hog_violation().is_empty(), "End fixture fault failed")
	refresh(game)
	check(game.frame.match_phase == "EndComplete" and game.frame.score_gold == 1, "Scoring end fixture failed")
	check(game.frame.stones_left_gold == 0 and game.frame.stones_left_cyan == 0, "End complete inventory not empty")
	check(not game.new_button.visible and not game.sweep_button.visible, "End result left duplicate delivery actions")
	check(game.match_readout.end_panel.visible and "Gold scores 1" in game.match_readout.end_detail.text and "Next hammer: Cyan" in game.match_readout.end_detail.text, "End result omits score or next hammer")
	var restored = ClassDB.instantiate("CurlSession")
	check(restored.load_match(game.session.match_json()).is_empty(), "End result replay failed")
	check(restored.frame().counting_stones == game.frame.counting_stones and restored.frame().counting_points == 1, "Scoring marks changed after save/load")
	await capture("end-result")
	game.match_readout.continue_button.pressed.emit()
	check(game.frame.end == 2 and game.frame.stones_left_gold == 8 and game.frame.counting_stones.is_empty() and not game.match_readout.end_panel.visible, "Next end did not clear result/counting marks")
	# A blank end and a clock forfeit must not masquerade as points scored.
	for i in range(16): check(game.session.hog_violation().is_empty(), "Blank fixture fault failed")
	refresh(game)
	check("No score this end" in game.match_readout.end_detail.text, "Blank end claims a scorer")
	game.next_throw()
	for i in range(30): game.session.match_think(60000)
	refresh(game)
	check(game.frame.match_phase == "GameComplete" and "thinking time" in game.match_readout.end_detail.text and game.match_readout.continue_button.text == "Rematch", "Clock forfeit lacks an honest result/rematch")
	game.solo.enabled = false
	game.session.new_match(42)
	check(game.session.place_match(true, 0).is_empty(), "Doubles placement failed")
	refresh(game)
	check(game.frame.stones_per_team == 5 and game.frame.stones_left_gold == 5 and game.frame.stones_left_cyan == 5, "Positioned doubles stones consumed delivery inventory")
	game.queue_free()
	await create_timer(.5).timeout
	print("MATCH_READOUT_OK" if not failed else "MATCH_READOUT_FAILED")
	quit(1 if failed else 0)
