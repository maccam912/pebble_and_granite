extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failed = true
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var lab = load("res://scenes/lab.tscn").instantiate()
	lab.persistence_enabled = false
	root.add_child(lab)
	await process_frame
	lab.mode_button.pressed.emit()
	check(lab.match_mode and lab.setup_panel.visible, "Match setup unavailable")
	check(lab.new_button.disabled, "Cannot throw before placement")
	lab.gold_order.pressed.emit()
	check(lab.frame.first_gold == 1, "Role selection failed")
	lab.apply_placement()
	check(lab.frame.stones.size() == 2 and not lab.setup_panel.visible, "Positioned stones missing")
	check(lab.frame.thrower == 1 and lab.phase == "Ready", "Wrong first thrower")
	for delivery in range(10):
		check(lab.frame.match_phase == "Calling", "Not ready for delivery " + str(delivery))
		var error: String = lab.session.deliver(2050, -900, 1)
		check(error.is_empty(), error)
		lab.run_active = true
		lab.phase = "Travel"
		lab.release_report = {"speed_mm_s": 2050}
		for step in range(240):
			if not lab.run_active: break
			lab._process(64.0 / 240.0)
		check(not lab.run_active, "Shot did not settle")
		check(lab.frame.delivered_count == delivery + 1, "Wrong delivery count")
		if delivery < 9: lab.new_button.pressed.emit()
	check(lab.frame.match_phase == "EndComplete", "End did not complete")
	check(lab.new_button.text == "Next end", "Missing next-end control")
	var score := [lab.frame.score_gold, lab.frame.score_cyan]
	var old_tick: int = lab.frame.global_tick
	lab.new_button.pressed.emit()
	check(lab.frame.end == 2 and lab.setup_panel.visible, "Next end setup missing")
	check(lab.frame.global_tick == old_tick + 14400, "Inter-end ice time wrong")
	check([lab.frame.score_gold, lab.frame.score_cyan] == score, "Score lost between ends")
	lab.power_button.pressed.emit()
	lab.apply_placement()
	check(lab.frame.stones[0].position.x < 0, "Left power play not placed")
	if "--full-match" in OS.get_cmdline_user_args():
		for end in range(12):
			if lab.frame.match_phase == "GameComplete": break
			for delivery in range(10):
				var error: String = lab.session.deliver(4000, 2200, 1)
				check(error.is_empty(), error)
				lab.run_active = true
				lab.release_report = {"speed_mm_s": 4000}
				for step in range(240):
					if not lab.run_active: break
					lab._process(64.0 / 240.0)
				check(not lab.run_active, "Full-match shot did not settle")
				if delivery < 9: lab.next_throw()
			if lab.frame.match_phase == "EndComplete":
				lab.next_throw()
				lab.apply_placement()
		check(lab.frame.match_phase == "GameComplete" and lab.frame.winner in [0, 1], "Full game failed to declare winner")
		check(lab.new_button.text == "Rematch", "Rematch control missing")
		lab.next_throw()
		check(lab.frame.end == 1 and lab.setup_panel.visible, "Rematch did not reset")
	lab.mode_button.pressed.emit()
	check(not lab.match_mode and lab.frame.mode == "practice", "Return to practice failed")
	if "--capture" in OS.get_cmdline_user_args():
		lab.mode_button.pressed.emit()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/evidence/match-setup.png")
	lab.queue_free()
	await process_frame
	print("MATCH_FLOW_OK" if not failed else "MATCH_FLOW_FAILED")
	quit(1 if failed else 0)
