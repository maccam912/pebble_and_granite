extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func make_game():
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	if "--mobile-ui" in OS.get_cmdline_user_args(): game.mobile_ui = true
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.play_settings.human_position = 0
	game.solo.start()
	return game
func capture(game, name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	game.update_spatial(0)
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/evidence/throwing-call")
	var suffix := "-mobile" if game.mobile_ui else ""
	root.get_texture().get_image().save_png("res://build/evidence/throwing-call/" + name + suffix + ".png")
func run() -> void:
	var game = make_game()
	for i in range(3): await process_frame
	var deadline := Time.get_ticks_msec() + 30000
	while game.solo.planned.is_empty() and Time.get_ticks_msec() < deadline:
		game._process(.02)
		await process_frame
	check(not game.solo.planned.is_empty(), "Human thrower did not receive a skip's call")
	if game.solo.planned.is_empty(): quit(1); return
	# Use an off-centre guard to expose accidental resets to the button during
	# save/release and to exercise target/broom separation in the inset map.
	check(game.session.request_called_shot(1, 700, -3000, -1).is_empty(), "Guard fixture rejected")
	game.solo.planned.clear()
	game.solo.planning = true
	deadline = Time.get_ticks_msec() + 30000
	while game.solo.planned.is_empty() and Time.get_ticks_msec() < deadline:
		game._process(.02)
		await process_frame
	var call: Dictionary = game.solo.planned.duplicate()
	check(game.solo.shot_card.visible and ("weight" in game.solo.shot_card.details.text or "draw" in game.solo.shot_card.details.text), "Throwing call omitted weight")
	check("tee" in game.solo.shot_card.details.text and "Broom" in game.solo.shot_card.details.text and "Curl" in game.solo.shot_card.details.text, "Throwing call omitted target, broom or turn")
	for i in range(100): game._process(.02)
	check(not game.run_active and game.frame.delivered_count == 0 and not game.solo.send_button.visible, "Skip's call took over the human delivery")
	game.update_spatial(0)
	check(game.rink.target_rings.visible and game.rink.called_target == game.solo.called_target, "Human called target missing from the ice")
	await capture(game, "01-ready")
	var clock := [0]
	game.input_clock = func(): return clock[0]
	game.one_push = false
	var handle: Vector2 = game.handle_point()
	check(not game.solo.shot_card.get_global_rect().has_point(handle), "Call card covers the handle")
	game.begin_pointer(-1, handle)
	check(game.pointer == -1, "Called human delivery cannot grip")
	for sample in [[100000, 24.0], [120000, 19.2], [240000, -9.6], [2700000, -9.6]]:
		clock[0] = sample[0]
		game.move_pointer(handle + Vector2(0, sample[1]))
	check(game.phase == "Slide" and game.solo.shot_card.visible and game.solo.planned == call, "Call disappeared or changed during the held slide")
	check("for call" in game.report or "called weight" in game.report, "Slide feedback does not compare the push to the requested weight")
	check("light for call" in game.delivery_feedback("Draw", false, int(call.speed_mm_s) - 100), "Light push not identified")
	check("heavy for call" in game.delivery_feedback("Draw", false, int(call.speed_mm_s) + 100), "Heavy push not identified")
	check("close to called weight" in game.delivery_feedback("Draw", false, int(call.speed_mm_s)), "Called push weight not identified")
	check(game.delivery_feedback("Draw", true, int(call.speed_mm_s)).begins_with("Release now"), "Weight feedback hid the hog warning")
	await capture(game, "02-slide")
	var envelope = JSON.parse_string(game.solo.save_envelope(game.session.match_json()))
	check(game.solo.valid_envelope(envelope), "Held call cannot save")
	var restored = make_game()
	check(restored.session.load_match(envelope.match).is_empty(), "Held match cannot load")
	restored.solo.restore_metadata(envelope)
	restored.frame = restored.session.frame()
	restored.solo.reset_turn()
	restored.update_labels()
	restored._process(.02)
	check(restored.solo.planned.get("kind") == call.kind and int(restored.solo.planned.get("turn", 0)) == call.turn and restored.solo.shot_card.visible and not restored.solo.planning, "Restored held call was lost or tried to re-plan")
	check(restored.solo.called_target == game.solo.called_target, "Restored held call moved the target")
	var bad: Dictionary = envelope.duplicate(true)
	bad.call.target_x_mm = 999999
	check(not restored.solo.valid_envelope(bad), "Invalid saved call accepted")
	bad = envelope.duplicate(true)
	bad.call.ice_samples = 999
	check(not restored.solo.valid_envelope(bad), "Invalid ice observation count accepted")
	var old_save: Dictionary = envelope.duplicate(true)
	old_save.erase("call")
	check(restored.solo.valid_envelope(old_save), "Existing solo saves became incompatible")
	# Every new AI intention survives a held-delivery save and has useful weight.
	for kind in ["Corner guard", "Freeze", "Tap-back", "Hit-and-roll", "Peel", "Double", "Runback"]:
		var named: Dictionary = envelope.duplicate(true)
		named.call.kind = kind
		check(restored.solo.valid_envelope(named), "New call rejected: " + kind)
		restored.solo.restore_metadata(named)
		restored.solo.reset_turn()
		restored.update_labels()
		restored._process(.02)
		check(restored.solo.planned.get("kind") == kind, "New call lost on restore: " + kind)
		var expected := "Takeout weight" if kind in ["Hit-and-roll", "Peel", "Double", "Runback"] else ("Guard weight" if kind == "Corner guard" else "draw")
		check(expected in restored.solo.shot_card.details.text, "New call has wrong weight: " + kind)
		check(restored.solo.shot_card.details.position.y + restored.solo.shot_card.details.get_minimum_size().y <= 215, "Call text overlaps map: " + kind)
	restored.hide()
	var long_call := call.duplicate(true)
	long_call.kind = "Hit-and-roll"
	long_call.speed_mm_s = 2500
	game.solo.shot_card.show_call(long_call, false)
	await capture(game, "03-long-call")
	clock[0] = 3000000
	game.end_pointer(handle + Vector2(0, -9.6))
	check(game.run_active and not game.solo.shot_card.visible, "Call blocked release or stayed over sweeping")
	check(game.frame.solo_target_x_mm == call.target_x_mm and game.frame.solo_target_y_mm == call.target_y_mm, "Human sweeping lost the intended target")
	game.next_throw() # A live shot must retain its state.
	check(game.run_active, "Next stone interrupted a called delivery")
	restored.queue_free()
	game.queue_free()
	await process_frame
	print("THROWING_CALL_OK" if not failed else "THROWING_CALL_FAILED")
	quit(1 if failed else 0)
