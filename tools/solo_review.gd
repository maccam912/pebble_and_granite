extends SceneTree
var game
var output := "res://build/evidence/solo"
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + name + ".png")
	print("CAPTURE ", name)
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	if "--mobile-ui" in OS.get_cmdline_user_args(): game.mobile_ui = true; output += "-mobile"; DirAccess.make_dir_recursive_absolute(output)
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.play_settings.human_position = 3
	game.play_settings.position_choice.select(3)
	game.solo.start()
	var deadline := Time.get_ticks_msec() + 20000
	while game.solo.planned.is_empty() and Time.get_ticks_msec() < deadline:
		game._process(.016)
		await process_frame
	if game.solo.planned.is_empty(): push_error("AI plan missing"); quit(1); return
	game.update_spatial(0)
	await capture("01-skip-call")
	game.play_settings.show()
	await capture("02-settings")
	game.play_settings.binding_panel.show()
	await capture("02b-shortcuts")
	game.play_settings.binding_panel.hide()
	game.play_settings.hide()
	game.toggle_zoom()
	await capture("03-house-zoom")
	game.toggle_zoom()
	game.solo.send_shot()
	for i in range(35): game._process(.25)
	game.update_spatial(0)
	await capture("04-skip-travel")
	game.solo.set_call(255)
	game._process(.016)
	game.update_spatial(0)
	await capture("05-hard-call")
	game.play_settings.human_position = 1
	game.solo.call_override = -1
	game.hold_sweep = true
	game.update_labels()
	game.update_spatial(0)
	await capture("06-sweeper")
	game.queue_free()
	await process_frame
	print("SOLO_REVIEW_OK")
	quit()
