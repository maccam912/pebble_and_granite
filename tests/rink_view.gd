extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/evidence")
	root.get_texture().get_image().save_png("res://build/evidence/rink-" + name + ".png")
func run() -> void:
	var scene = load("res://scenes/play.tscn").instantiate()
	scene.persistence_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	scene.reset(false)
	scene.update_spatial(0)
	await process_frame
	await capture("delivery")
	check(scene.rink != null and scene.spatial_view, "Default 3D scene was not created")
	for aim in [-2200, 0, 2200]:
		scene.broom_mm = aim
		scene.update_spatial(0)
		var forward: Vector3 = -scene.rink.camera.global_basis.z
		forward.y = 0
		check(forward.normalized().dot(scene.rink.delivery_heading()) > .99999, "Delivery camera does not face the selected broom")
		check(absf(scene.broom_screen_point().x - scene.handle_point().x) < 1, "Selected broom is off the delivery sightline")
	scene.broom_mm = -900
	scene.update_spatial(0)
	var lights := 0
	for node in scene.rink.world.get_children():
		check(not node is DirectionalLight3D, "Outdoor directional light returned")
		if node is SpotLight3D:
			lights += 1
			check(node.position.y < 3.48 and node.shadow_opacity <= .25, "Arena light is above the fixture or has harsh shadows")
	check(lights > 1 and lights <= 8, "Expected overlapping arena lights within the Compatibility limit")
	# A pulled-back hand must not reset when the drive becomes a slide.
	scene.rink.hand_held = true
	scene.rink.pull_offset = .16
	for i in range(30): scene.rink.render_frame(scene.frame, false, false, -900, 0, true, 1.0 / 60.0)
	var pulled: float = scene.rink.shown_pull_offset
	scene.rink.pull_offset = 0
	scene.rink.render_frame(scene.frame, false, false, -900, 0, true, 1.0 / 60.0)
	check(scene.rink.shown_pull_offset > pulled * .5, "Drive-to-slide transition snapped to the starting point")
	for i in range(30): scene.rink.render_frame(scene.frame, false, false, -900, 0, true, 1.0 / 60.0)
	check(scene.rink.shown_pull_offset < .001, "Pull-back offset failed to settle into the slide")
	scene.rink.hand_held = false
	scene.camera_button.text = "Camera: House"
	scene.rink.mode = 4
	scene.update_spatial(0)
	var broom: Vector2 = scene.broom_screen_point()
	check(Rect2(scene.rink.position, scene.rink.size).has_point(broom), "House broom projection left the viewport")
	check(absf(scene.rink.aim_x(broom) + .9) < .01, "Broom projection does not round-trip")
	scene.begin_pointer(0, broom)
	scene.move_pointer(broom + Vector2(100, 0))
	scene.end_pointer(broom + Vector2(100, 0))
	check(scene.broom_mm > -900 and not scene.run_active, "3D broom drag did not change only aim")
	scene.broom_mm = -900
	var time := [0]
	scene.input_clock = func(): return time[0]
	var hand: Vector2 = scene.handle_point()
	scene.begin_pointer(0, hand)
	for sample in [[100000, 24.0], [120000, 19.2], [240000, -9.6]]:
		time[0] = sample[0]
		scene.move_pointer(hand + Vector2(0, sample[1]))
	time[0] = 500000
	scene.end_pointer(hand + Vector2(0, -9.6))
	check(scene.run_active, "3D scene rejected shared delivery stroke")
	for i in range(30): scene._process(1.0 / 60.0)
	scene.begin_pointer(0, scene.camera_button.get_global_rect().get_center())
	check(not scene.sweeping and scene.pointer == -99, "Camera control started a sweep gesture")
	var before: String = scene.session.state_hash()
	for i in range(50):
		scene.rink.cycle_camera()
		scene.update_spatial(.016)
	check(scene.session.state_hash() == before, "Presentation changed authoritative state")
	check(scene.rink.stones.size() == scene.frame.stones.size(), "3D stone identities differ from simulation")
	scene.camera_button.text = "Camera: Sweeper"
	scene.rink.mode = 2
	scene.hold_sweep = true
	scene.update_spatial(.016)
	await capture("sweeper")
	check(scene.rink.brush.visible, "Authorized held brush is not rendered")
	scene.camera_button.text = "Camera: Skip"
	scene.rink.mode = 3
	scene.update_spatial(0)
	await capture("skip")
	scene.camera_button.text = "Camera: House"
	scene.rink.mode = 4
	scene.update_spatial(0)
	await capture("house")
	var transition: Dictionary = scene.frame.duplicate(true)
	transition.end = 2
	transition.stones[0].team = 1
	transition.stones[0].position += Vector2(.2, .2)
	scene.rink.render_frame(transition, true, false, -900, 1, false, 0)
	var moved: Node3D = scene.rink.stones[transition.stones[0].id]
	check(moved.get_meta("team") == 1, "Reused stone ID retained another team's handle")
	check(moved.position == Vector3(transition.stones[0].position.x, 0, -transition.stones[0].position.y), "End transition interpolated an obsolete stone position")
	scene.reset(false)
	scene.update_spatial(0)
	check(scene.rink.stones.is_empty(), "Reset left stale stones in the renderer")
	scene.queue_free()
	await process_frame
	print("RINK_VIEW_OK" if not failed else "RINK_VIEW_FAILED")
	quit(1 if failed else 0)
