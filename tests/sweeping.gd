extends SceneTree
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func event(scene: Control, touch: bool, point: Vector2, kind: String, index := 0) -> void:
	var e: InputEvent
	if kind == "move": e = InputEventScreenDrag.new() if touch else InputEventMouseMotion.new()
	else:
		e = InputEventScreenTouch.new() if touch else InputEventMouseButton.new()
		e.pressed = kind == "down"
		if not touch: e.button_index = MOUSE_BUTTON_LEFT
	if touch: e.index = index
	e.position = point
	scene._input(e)
func launch(scene: Control) -> void:
	scene.reset(false)
	check(scene.session.deliver(2050, -900, 1).is_empty(), "Sweep fixture release failed")
	scene.frame = scene.session.frame()
	scene.run_active = true
	scene.phase = "Travel"
	scene.rink.mode = 2
	scene.update_spatial(0)
func scrub(scene: Control, touch: bool) -> Dictionary:
	launch(scene)
	var clock := [0]
	scene.input_clock = func(): return clock[0]
	var stone: Dictionary = scene.selected_sweep_stone()
	var start: Vector2 = scene.rink.ice_screen_point(stone.position + Vector2(0, .35))
	check(scene.rink.get_global_rect().has_point(start), "Brush point left the sweeper view")
	event(scene, touch, start, "down")
	check(scene.sweeping and scene.pointer == (0 if touch else -1), "Ice contact did not start scrubbing")
	check(scene.current_brush().get("effort", 0) == 0, "Stationary contact created heat")
	if touch:
		event(scene, true, start, "down", 1)
		event(scene, true, start, "up", 1)
		check(scene.pointer == 0, "Extra finger stole or released the brush")
	for sample in [[50000, -12], [100000, 12], [150000, -12]]:
		clock[0] = sample[0]
		event(scene, touch, start + Vector2(sample[1], 0), "move")
	var brush: Dictionary = scene.current_brush()
	check(brush.get("effort", 0) > 0 and absi(brush.get("lateral_mm", 0)) > 0, "Scrub did not map rate and position")
	scene._process(.05)
	var saved: Dictionary = JSON.parse_string(scene.session.session_json())
	var shot: Dictionary = saved.records[-1].data
	check(shot.sweeps.size() > 0, "Spatial sweep was not recorded")
	check(shot.sweeps[0].input.stone == stone.id and shot.sweeps[0].input.lateral_mm != 0, "Recorder replaced the spatial brush with a centered one")
	clock[0] = 400000
	check(scene.current_brush().get("effort", 0) == 0, "Stopped scrub kept heating the ice")
	event(scene, touch, start, "up")
	check(not scene.sweep_input.active and scene.current_brush().is_empty(), "Lift retained scrub intent")
	return brush
func run() -> void:
	var scene = load("res://scenes/play.tscn").instantiate()
	scene.persistence_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	var mouse := scrub(scene, false)
	var touch := scrub(scene, true)
	check(mouse == touch, "Mouse/trackpad and touch mapped different spatial input")
	launch(scene)
	var stone: Dictionary = scene.selected_sweep_stone()
	for offset in [Vector2(0, -.2), Vector2(.6, .35), Vector2(0, 1.1)]:
		var point: Vector2 = scene.rink.ice_screen_point(stone.position + offset)
		scene.begin_pointer(0, point)
		scene.move_pointer(point + Vector2(12, 0))
		check(scene.current_brush().is_empty(), "Off-path or behind-stone pointer was clamped into a useful brush")
		scene.end_pointer(point)
	scene.hold_sweep = true
	var held: Dictionary = scene.current_brush()
	check(held.get("effort") == 255 and held.get("lateral_mm") == 0 and held.get("ahead_mm") == 180, "Accessible hold lost steady centered effort")
	scene.update_spatial(.016)
	check(scene.rink.brush.visible and scene.rink.selection.visible, "Selected stone and held brush were not presented")
	scene._notification(NOTIFICATION_APPLICATION_PAUSED)
	check(scene.current_brush().is_empty() and not scene.hold_sweep, "Backgrounding retained brush effort")
	scene._notification(NOTIFICATION_APPLICATION_RESUMED)
	# Eligibility uses each moving target, including a collision stone while the
	# delivered stone is stopped; the authority independently enforces this too.
	var f := {"team": 0, "delivered": 2, "stones": [
		{"id": 0, "team": 0, "position": Vector2(-.5, -.4), "velocity": Vector2(.1, 1), "speed": 1.0, "active": true, "turns": 0.0},
		{"id": 1, "team": 1, "position": Vector2(.5, -.4), "velocity": Vector2(0, 1), "speed": 1.0, "active": true, "turns": 0.0},
		{"id": 2, "team": 0, "position": Vector2(0, -.4), "velocity": Vector2.ZERO, "speed": 0.0, "active": true, "turns": 0.0}]}
	var input := CurlSweeping.new()
	check(not input.allowed(f.stones[0], f, -2), "Unseated online player received practice permissions")
	check(input.selected(f, 0).get("id") == 0, "Stopped delivered stone blocked a moving own stone")
	check(not input.allowed(f.stones[1], f, 0), "Opponent was selectable before tee")
	check(input.allowed(f.stones[1], f, 2), "Defending player could not sweep their own moving stone before tee")
	f.stones[1].position.y = .1
	check(input.allowed(f.stones[1], f, 0), "Delivering player could not sweep past tee")
	check(not input.allowed(f.stones[1], f, 2) and input.allowed(f.stones[1], f, 3), "Defending skip restriction was lost")
	input.target = 0
	input.active = true
	f.stones[0].speed = 0
	check(input.selected(f, 3).is_empty(), "A held scrub jumped to another moving stone")
	input.active = false
	check(input.selected(f, 3, true).is_empty(), "Accessible hold jumped to another moving stone")
	# Actual selection uses rendered stone positions, independently of camera mode.
	f.stones[0].speed = 1
	scene.frame = f
	scene.rink.mode = 4
	scene.update_spatial(0)
	var point: Vector2 = scene.rink.stone_point(1)
	scene.begin_pointer(0, point)
	check(scene.sweep_input.target == 1, "Tap did not select the moving stone")
	scene.end_pointer(point)
	if DisplayServer.get_name() != "headless":
		scene.hold_sweep = true
		scene.phase = "Travel"
		scene.report = "Tap a moving stone to select it. Scrub ahead, or hold the sweep button."
		scene.camera_button.text = "Camera: House"
		scene.update_labels()
		scene.update_spatial(.016)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/evidence/spatial-sweeping.png")
	scene.queue_free()
	await process_frame
	print("SWEEPING_OK" if not failed else "SWEEPING_FAILED")
	quit(1 if failed else 0)
