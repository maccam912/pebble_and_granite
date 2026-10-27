extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/lab.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	game.set_process(false)
	game.solo.start()
	var shots := 0
	var deadline := Time.get_ticks_msec() + 480000
	while game.frame.match_phase != "GameComplete" and game.frame.end <= 12 and Time.get_ticks_msec() < deadline:
		if game.frame.match_phase == "EndComplete":
			print("SOLO_END ", game.frame.end, " SCORE ", game.frame.score_gold, ":", game.frame.score_cyan)
			game.next_throw()
		if game.phase == "Stone at rest": game.next_throw()
		if game.solo.human_throws():
			check(game.session.deliver(2050, -900, 1).is_empty(), "Human full-match release failed")
			game.frame = game.session.frame()
			game.run_active = true
			game.phase = "Travel"
			game.release_report = {"speed_mm_s": 2050}
		else:
			var plan_deadline := Time.get_ticks_msec() + 45000
			while not game.run_active and Time.get_ticks_msec() < plan_deadline:
				game._process(.05)
				await process_frame
			check(game.run_active, "Full-match AI stalled")
			if not game.run_active: break
		for step in range(400):
			if not game.run_active: break
			game._process(64.0 / 240.0)
		check(not game.run_active, "Full-match shot did not settle")
		shots += 1
	check(game.frame.match_phase == "GameComplete" and game.frame.winner in [0, 1], "Solo full game did not declare a winner")
	check(shots >= 96 and game.new_button.text == "Rematch", "Solo full game ended early or lacks rematch")
	var restore = ClassDB.instantiate("CurlSession")
	check(restore.load_match(game.session.match_json()).is_empty() and restore.match_hash() == game.session.match_hash(), "Completed solo match failed to replay")
	var reviews: Dictionary = game.session.shot_reviews()
	var counted := 0
	for player in reviews.players: counted += int(player.shots)
	check(reviews.shots.size() == 32 and counted == shots, "Bounded paths lost full-game per-position totals")
	check(restore.shot_reviews() == reviews, "Completed match observations did not rebuild exactly")
	game.next_throw()
	check(game.solo.enabled and game.frame.end == 1 and game.frame.match_phase == "Calling", "Solo rematch lost teams mode")
	game.queue_free()
	await process_frame
	print("SOLO_FULL_MATCH_OK shots=", shots) if not failed else print("SOLO_FULL_MATCH_FAILED")
	quit(1 if failed else 0)
