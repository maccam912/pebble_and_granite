extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	assert(ClassDB.class_exists("CurlSession"))
	var session: Object = ClassDB.instantiate("CurlSession")
	session.grip(0, 0, 0, false)
	session.motion(100000, 0, 30000)
	session.motion(120000, 0, 24000)
	session.motion(240000, 0, -12000)
	var report: Dictionary = session.lift(500000, 0, -12000)
	assert(report.valid)
	assert(session.deliver(report.speed_mm_s, -900, 1) == "")
	var ticks := 0
	while not session.frame().resting and ticks < 14400:
		session.step_ticks(16, 0, 0, 180)
		ticks += 16
	assert(session.frame().resting)
	assert(not session.frame().timed_out)
	assert(session.state_hash().length() == 16)
	var scene: Control = load("res://scenes/lab.tscn").instantiate()
	scene.persistence_enabled = false
	root.add_child(scene)
	await process_frame
	assert(scene.status.text.contains("Ready"))
	# Godot events must feed the same bridge and cancellation must not throw.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = scene.handle_point()
	scene._input(press)
	assert(scene.pointer == -1)
	scene._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(scene.pointer == -99)
	assert(scene.session.frame().stones.is_empty())
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		DirAccess.make_dir_recursive_absolute("res://build/evidence")
		image.save_png("res://build/evidence/lab.png")
	scene.queue_free()
	print("LAB_SMOKE_OK")
	quit()
