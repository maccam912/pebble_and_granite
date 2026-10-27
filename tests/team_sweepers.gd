extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	game.mobile_ui = "--mobile-ui" in OS.get_cmdline_user_args()
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.play_settings.human_position = 1
	game.solo.start()
	check(game.session.frame().model == 4, "New solo match did not use independent brushes")
	check(game.session.deliver(2050, -900, 1).is_empty(), "Team brush fixture release failed")
	# Second rests while AI Vice brushes, then joins with a fresh brush.
	for i in range(60):
		check(game.session.step_team_ticks(64, 0, 0, 0, 180, 255, 1).is_empty(), "Partner brush rejected")
	check(game.session.step_team_ticks(64, 0, 255, -80, 180, 255, 1).is_empty(), "Human brush rejected")
	game.frame = game.session.frame()
	check(game.frame.brush_fatigue.size() == 8, "Team fatigue lacks player identities")
	check(game.frame.brush_fatigue[1] == 192 and game.frame.brush_fatigue[2] > 9000, "Human and partner shared fatigue")
	check(game.frame.team_brushes.size() == 2, "Two accepted brushes missing from frame")
	game.run_active = true
	game.phase = "Travel"
	game.solo.shot_team = 0
	game.solo.ai_effort = 255
	game.solo.weight_zone = 5
	var before: String = game.session.match_hash()
	game.update_labels()
	game.update_spatial(.1)
	check(game.rink.brush.visible and game.rink.partner_brush.visible, "Two physical brushes are not visible")
	check(game.rink.brush.position.distance_to(game.rink.partner_brush.position) > .15, "Player brushes overlap exactly")
	check("Second (you) sweeping" in game.solo.sweepers_label.text and "Vice tiring" in game.solo.sweepers_label.text, "Independent effort feedback missing")
	check(game.session.match_hash() == before, "Brush presentation changed physics")
	if "--capture" in OS.get_cmdline_user_args():
		for i in range(8): await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/evidence/team-sweepers")
		root.get_texture().get_image().save_png("res://build/evidence/team-sweepers/two-brushes.png")
	var restored = ClassDB.instantiate("CurlSession")
	check(restored.load_match(game.session.match_json()).is_empty(), "New brush journal failed to load")
	check(restored.match_hash() == before and restored.frame().brush_fatigue == game.frame.brush_fatigue, "Reload changed independent fatigue")
	check(game.session.step_team_ticks(64, 0, 0, 0, 180, 0, 1).is_empty(), "OFF failed")
	game.frame = game.session.frame()
	game.solo.ai_effort = 0
	game.update_labels()
	game.update_spatial(.1)
	check(not game.rink.brush.visible and not game.rink.partner_brush.visible, "OFF left a visual brush running")
	# Selection and rendering follow each accepted target after a contact.
	var contact_frame: Dictionary = game.frame.duplicate(true)
	var contact: Dictionary = contact_frame.stones[0].duplicate(true)
	contact.id = 2
	contact.position += Vector2(1, 0)
	contact.speed = 1.0
	contact.velocity = Vector2(0, 1)
	contact_frame.stones.append(contact)
	contact_frame.team_brushes = [
		{"team": 0, "position": 1, "stone": 2, "effort": 255, "fatigue": 0, "lateral_mm": 0, "ahead_mm": 180},
		{"team": 0, "position": 2, "stone": 0, "effort": 255, "fatigue": 9000, "lateral_mm": 0, "ahead_mm": 420}]
	check(game.sweep_input.allowed(contact, contact_frame, 1), "New team model cannot select moving contact stone")
	game.frame = contact_frame
	game.update_spatial(.1)
	check(absf(game.rink.brush.position.x - game.rink.stones[2].position.x) < .11, "Human brush did not follow contact stone")
	check(absf(game.rink.partner_brush.position.x - game.rink.stones[0].position.x) < .11, "AI brush followed human selection instead of delivery")
	contact_frame.model = 3
	check(not game.sweep_input.allowed(contact, contact_frame, 1), "Legacy selection changed")
	# Old installed matches continue with their original summed brush semantics.
	var old = ClassDB.instantiate("CurlSession")
	var reference = ClassDB.instantiate("CurlSession")
	var json := FileAccess.get_file_as_string("res://validation/legacy/model3-team-match.json")
	check(old.load_match(json).is_empty() and reference.load_match(json).is_empty(), "Installed model-3 fixture did not load")
	check(old.frame().model == 3 and old.match_hash() == "c5a7a224feb8f845", "Old match hash changed")
	for session in [old, reference]: check(session.deliver(2050, -900, 1).is_empty(), "Old match cannot continue")
	check(old.step_team_ticks(64, 2, 255, 0, 180, 128, 0).is_empty(), "Old team brush fallback failed")
	check(reference.step_solo_ticks(64, 2, 255, 0, 180, 128).is_empty(), "Legacy reference failed")
	check(old.match_hash() == reference.match_hash() and old.frame().brush_fatigue.size() == 4, "Old continuation changed brush semantics")
	check(restored.load_match(old.match_json()).is_empty() and restored.match_hash() == old.match_hash(), "Continued old match did not resave/replay")
	game.queue_free()
	await process_frame
	print("TEAM_SWEEPERS_OK" if not failed else "TEAM_SWEEPERS_FAILED")
	quit(1 if failed else 0)
