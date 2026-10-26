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
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.reset(false)
	game.update_spatial(0)
	await capture("01-delivery")
	game.phase = "Slide"
	game.report = "Draw weight\nNo curl · nudge left/right to turn"
	game.update_labels()
	game.update_spatial(0)
	await capture("02-slide-feedback")
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
	game.queue_free()
	await process_frame
	print("VISUAL_REVIEW_FAILED" if failed else "VISUAL_REVIEW_OK")
	quit(1 if failed else 0)
