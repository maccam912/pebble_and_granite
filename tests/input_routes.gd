extends SceneTree
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failed = true

func event(scene: Control, kind: String, position: Vector2, pressed := true, index := 0) -> void:
	var e: InputEvent
	match kind:
		"mouse":
			e = InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
		"motion":
			e = InputEventMouseMotion.new()
		"touch":
			e = InputEventScreenTouch.new()
			e.pressed = pressed
			e.index = index
		"drag":
			e = InputEventScreenDrag.new()
			e.index = index
	e.position = position
	scene._input(e)

func throw_with(scene: Control, touch: bool) -> Dictionary:
	scene.reset()
	var clock := [0]
	scene.input_clock = func(): return clock[0]
	var start: Vector2 = scene.handle_point()
	event(scene, "touch" if touch else "mouse", start)
	if touch:
		event(scene, "touch", start, true, 1)
		check(scene.pointer == 0, "Second finger stole delivery")
		event(scene, "touch", start, false, 1)
		check(scene.pointer == 0, "Second finger released delivery")
		var synthetic := InputEventMouseButton.new()
		synthetic.device = InputEvent.DEVICE_ID_EMULATION
		synthetic.button_index = MOUSE_BUTTON_LEFT
		synthetic.pressed = false
		synthetic.position = start
		scene._input(synthetic)
		check(scene.pointer == 0, "Synthetic mouse released touch")
	for sample in [[100000, 24.0], [120000, 19.2], [240000, -9.6]]:
		clock[0] = sample[0]
		event(scene, "drag" if touch else "motion", start + Vector2(0, sample[1]))
	clock[0] = 500000
	event(scene, "touch" if touch else "mouse", start + Vector2(0, -9.6), false)
	check(scene.run_active, "Valid stroke did not start travel")
	return scene.release_report.duplicate()

func run() -> void:
	var scene: Control = load("res://scenes/lab.tscn").instantiate()
	scene.persistence_enabled = false
	root.add_child(scene)
	await process_frame
	var mouse := throw_with(scene, false)
	var touch := throw_with(scene, true)
	check(mouse == touch, "Mouse/trackpad and touch changed release for identical stroke")
	scene.reset()
	event(scene, "touch", scene.handle_point())
	scene._notification(NOTIFICATION_APPLICATION_PAUSED)
	event(scene, "touch", scene.handle_point(), false)
	check(not scene.run_active, "Backgrounding released a stone")
	check(scene.phase == "Ready", "Backgrounding did not restore ready prompt")
	scene.reset()
	var broom: Vector2 = scene.house_point(Vector2(-0.9, 0))
	event(scene, "touch", broom)
	event(scene, "drag", broom + Vector2(100, 0))
	event(scene, "touch", broom + Vector2(100, 0), false)
	check(scene.broom_mm > 0, "Touch broom drag did not change aim")
	check(scene.session.frame().stones.is_empty(), "Broom drag threw a stone")

	# Native GUI buttons need touch-to-mouse emulation. The stroke route ignores
	# those synthetic mouse events, while Controls still receive them.
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = root.get_final_transform() * scene.one_button.get_global_rect().get_center()
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = down.position
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	check(scene.one_push, "Touch did not activate the accessibility button")
	scene.queue_free()
	print("INPUT_ROUTES_OK" if not failed else "INPUT_ROUTES_FAILED")
	quit(1 if failed else 0)
