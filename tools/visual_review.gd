extends SceneTree
## Repeatable rendered review of existing screens. Uses isolated, unsaved fixtures.
## python3 tools/godot.py --path . --script tools/visual_review.gd
var game: Control
var failed := false
var output := "res://build/evidence/polish"

func _initialize() -> void: call_deferred("run")

func capture(name: String) -> void:
	for i in range(12): await process_frame # Let static reflection probes settle.
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + name + ".png")
	print("CAPTURE ", name)
	if game.feedback_bg != null and not game.feedback_bg.get_global_rect().encloses(game.report_label.get_global_rect()):
		push_error("Feedback panel does not contain the complete report: " + name)
		failed = true

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review requires a real renderer")
		quit(1)
		return
	var mobile_preview := "--mobile-ui" in OS.get_cmdline_user_args()
	if mobile_preview: output = "res://build/evidence/polish-mobile"
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	if mobile_preview: game.mobile_ui = true
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.reset(false)
	game.update_spatial(0)
	print("DELIVERY_HANDLE ", game.handle_point())
	await capture("01-delivery")
	game.phase = "Slide"
	game.report = "Draw weight\nNo curl · nudge left/right to turn"
	game.update_labels()
	game.update_spatial(0)
	await capture("02-slide-feedback")
	game.rink.hand_held = true
	game.rink.render_frame(game.frame, false, false, game.broom_mm, game.turn, true, 0)
	await capture("02b-held-delivery")
	game.rink.hand_held = false
	game.phase = "Stone at rest"
	game.report = "Release 2.055 m/s\nHog-to-hog 12.43 s\n2.87 rotations • 24.60 s travel\nRest: 0.12 m across, 0.36 m from tee\nIn play"
	game.update_labels()
	game.rink.mode = 3
	game.camera_button.text = "Camera: Skip"
	var display: Dictionary = game.frame.duplicate(true)
	# Presentation fixture only: show both materials near the house without
	# manufacturing a simulated shot, saving a game or changing authority.
	for i in range(6):
		display.stones.append({"id": i, "team": i % 2, "active": true,
			"position": Vector2(-.65 + float(i % 3) * .58, -.6 + floorf(float(i) / 3) * .8),
			"turns": float(i) * .13, "velocity": Vector2.ZERO})
	game.rink.render_frame(display, false, false, -900, 0, false, 0)
	await capture("03-skip-and-report")
	var resting_report: String = game.report
	game.phase = "Travel"
	game.report = "Scrub ahead of the selected stone, or hold to sweep."
	game.update_labels()
	game.rink.mode = 2
	game.camera_button.text = "Camera: Sweeper"
	game.rink.sweep_target = 0
	game.rink.brush_input = {"ahead_mm": 180, "lateral_mm": 20, "steady": false}
	display.delivered = 0
	display.stones[0].velocity = Vector2(0, .8)
	game.rink.render_frame(display, true, true, -900, 0, false, .016)
	await capture("03b-sweeper")
	game.rink.sweep_target = -1
	game.rink.brush_input = {}
	game.phase = "Stone at rest"
	game.report = resting_report
	game.update_labels()
	game.rink.mode = 4
	game.camera_button.text = "Camera: House"
	game.rink.render_frame(display, false, false, -900, 0, false, 0)
	await capture("04-house")
	game.switch_mode()
	game.update_spatial(0)
	await capture("05-match-setup")
	game.open_online()
	await capture("06-online-lobby")
	game.room_panel.code_input.text = "BAD"
	game.room_panel.join_room()
	await capture("07-room-validation")
	game.room_panel.leave()
	game.frame.score_gold = 12
	game.frame.score_cyan = 9
	game.frame.end = 8
	game.update_labels()
	await capture("08-score-spacing")
	for label in [game.gold_score, game.end_score, game.cyan_score]:
		if not game.scoreboard.get_global_rect().encloses(label.get_global_rect()):
			push_error("Score text exceeds the score panel")
			failed = true
	var setup_controls := [game.house_button, game.power_button, game.gold_order,
		game.cyan_order, game.setup_panel.get_child(game.setup_panel.get_child_count() - 1)]
	for index in range(1, setup_controls.size()):
		var prior: Rect2 = setup_controls[index - 1].get_global_rect()
		var next: Rect2 = setup_controls[index].get_global_rect()
		if next.position.y - prior.end.y < 4:
			push_error("Match setup controls lack separation")
			failed = true
	game.queue_free()
	await process_frame
	print("VISUAL_REVIEW_FAILED" if failed else "VISUAL_REVIEW_OK")
	quit(1 if failed else 0)
