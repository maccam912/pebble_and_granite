extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func stroke(session: Object, when: int) -> Dictionary:
	session.grip(0, 0, 0, true)
	session.motion(20000, 0, -5250)
	session.motion(120000, 0, -31500)
	return session.lift(when, 0, -31500)
func gesture_event(scene: Control, touch: bool, point: Vector2, kind: String) -> void:
	var event: InputEvent
	if kind == "move":
		event = InputEventScreenDrag.new() if touch else InputEventMouseMotion.new()
	else:
		event = InputEventScreenTouch.new() if touch else InputEventMouseButton.new()
		event.pressed = kind == "down"
		if not touch: event.button_index = MOUSE_BUTTON_LEFT
	if touch: event.index = 0
	event.position = point
	scene._input(event)
func direct_throw(scene: Control, touch: bool, direction: int, gentle := false) -> Dictionary:
	scene.reset(false)
	scene.broom_mm = 0
	scene.one_push = false
	scene.rink.mode = 0
	scene.update_spatial(0)
	var clock := [0]
	scene.input_clock = func(): return clock[0]
	var handle: Vector2 = scene.handle_point()
	check(scene.rink.get_global_rect().has_point(handle), "3D handle is not on the ice viewport")
	gesture_event(scene, touch, handle, "down")
	check(scene.pointer != -99, "Direct handle touch did not grip")
	for sample in [[100000, 24.0], [120000, 19.2], [240000, -9.6], [2700000, -9.6]]:
		clock[0] = sample[0]
		gesture_event(scene, touch, handle + Vector2(0, sample[1]), "move")
	if gentle:
		clock[0] = 2850000
		gesture_event(scene, touch, handle + Vector2(direction * 6, -9.6), "move")
		check(scene.turn == direction and scene.report.contains("Curl left" if direction < 0 else "Curl right"), "Gentle finish did not show its curl before lift")
	clock[0] = 3000000
	gesture_event(scene, touch, handle + (Vector2(direction * 6, -9.6) if gentle else Vector2(direction * 30, -20)), "up")
	check(scene.run_active, "Direct ice flick did not release")
	check(scene.release_report.turn == direction, "Flick direction did not set rotation")
	check(scene.release_report.trim_mm_s == 0 if gentle else scene.release_report.trim_mm_s > 0, "Finish changed weight incorrectly")
	check(scene.release_report.line_mm == 0, "Curl flick also changed broom aim")
	return scene.release_report.duplicate()
func check_curl_travel(scene: Control, direction: int) -> void:
	var ticks := 0
	while not scene.session.frame().resting and ticks < 14400:
		scene.session.step_ticks(64, 0, 0, 180)
		ticks += 64
	var stone: Dictionary = scene.session.frame().stones[0]
	check(scene.session.frame().resting, "Gentle curl shot did not finish")
	check(direction * stone.position.x > .3, "Gentle finish did not produce visible sideways curl")
	check(direction * stone.turns > 1, "Gentle finish did not rotate the real stone")
	print("GENTLE_CURL direction=%d x=%.3f turns=%.2f" % [direction, stone.position.x, stone.turns])
func analog_throw(scene: Control, touch: bool, direction: int) -> void:
	scene.reset(false)
	scene.broom_mm = direction * 900
	scene.one_push = false
	scene.update_spatial(0)
	var clock := [0]
	scene.input_clock = func(): return clock[0]
	var handle: Vector2 = scene.handle_point()
	gesture_event(scene, touch, handle, "down")
	clock[0] = 100000
	gesture_event(scene, touch, handle + Vector2(direction * 16, 24), "move")
	scene.update_spatial(.016)
	check(direction * scene.rink.preview.position.x > .09, "Pullback did not move the actual preview sideways")
	for sample in [[120000, 17.6, 19.2], [220000, 25.6, -4.8]]:
		clock[0] = sample[0]
		gesture_event(scene, touch, handle + Vector2(direction * sample[1], sample[2]), "move")
	clock[0] = 2700000
	scene.update_delivery()
	var held: Dictionary = scene.frame.in_hand.duplicate(true)
	check(direction * held.x_um > 150000 and direction * held.aim_mm > 900, "Analog origin and push aim did not reach authority")
	clock[0] = 2850000
	gesture_event(scene, touch, handle + Vector2(direction * 19.6, -4.8), "move")
	check(direction * int(scene.frame.in_hand.aim_mm) > 900, "Finishing curl steered the captured push aim")
	clock[0] = 3000000
	scene.update_delivery()
	var release_x: float = float(scene.frame.in_hand.x_um) / 1000000.0
	gesture_event(scene, touch, handle + Vector2(direction * 19.6, -4.8), "up")
	check(scene.run_active and scene.release_report.turn == -direction, "Analog throw did not accept independent finishing curl")
	check(absf(scene.frame.stones[0].position.x - release_x) < .00001, "Release snapped the rock sideways to the centre line")
func run() -> void:
	var early: Object = ClassDB.instantiate("CurlSession")
	var late: Object = ClassDB.instantiate("CurlSession")
	var a := stroke(early, 500000)
	var b := stroke(late, 3000000)
	check(a.valid and b.valid, "Valid slides were rejected")
	check(a.y_um < b.y_um and a.speed_um_s > b.speed_um_s, "Timing did not change actual release")
	check(early.deliver_slide(a.speed_um_s, a.y_um, -900, 1).is_empty(), "Early release rejected")
	check(abs(early.frame().stones[0].position.y - float(a.y_um) / 1000000.0) < 0.000001, "Native release lost slide position")
	var bytes: PackedByteArray = ClassDB.class_call_static("CurlRoom", "slide_packet", 1, 1, a.speed_um_s, a.y_um, -900, 1)
	var packet: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	check(abs(float(packet.command.release.pos.y) / 4294967296.0 - early.frame().stones[0].position.y) < 0.000001, "Online packet and local origin differ")
	for y in [-37800001, -28593000, 9223372036854775807]:
		var invalid: PackedByteArray = ClassDB.class_call_static("CurlRoom", "slide_packet", 1, 1, 2050000, y, 0, 1)
		check(invalid.is_empty(), "Out-of-bounds slide packet accepted")
	var before: String = late.state_hash()
	check(not late.deliver_slide(b.speed_um_s, -28593000, 0, 1).is_empty(), "Hog-boundary release accepted")
	check(late.state_hash() == before, "Rejected release changed native state")
	var scene: Control = load("res://scenes/play.tscn").instantiate()
	scene.persistence_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	# Let the native window deliver its initial focus/visibility events before
	# injecting a held gesture; focus cancellation has separate coverage.
	await process_frame
	await process_frame
	await process_frame
	var clock := [0]
	scene.input_clock = func(): return clock[0]
	scene.one_push = true
	var handle: Vector2 = scene.handle_point()
	scene.begin_pointer(-1, handle)
	clock[0] = 20000
	scene.move_pointer(handle + Vector2(0, -4.2))
	clock[0] = 120000
	scene.move_pointer(handle + Vector2(0, -25.2))
	clock[0] = 3000000
	scene.update_delivery()
	scene.update_spatial(0)
	check(scene.rink.preview.position.z < 37.8, "Held stone did not slide in 3D")
	if "--capture" in OS.get_cmdline_user_args():
		scene.queue_redraw()
		await process_frame
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/evidence/delivery-slide.png")
	clock[0] = 6000000
	scene.update_delivery()
	check(scene.pointer == -99 and not scene.run_active, "Hog fault failed to end held gesture")
	check(scene.frame.stones.size() == 1 and not scene.frame.stones[0].active, "Held hog violation did not consume stone")
	var fault_hash: String = scene.session.state_hash()
	scene.update_delivery()
	check(scene.session.state_hash() == fault_hash, "Repeated frame consumed another stone")
	var mouse := direct_throw(scene, false, 1)
	var touch := direct_throw(scene, true, 1)
	check(mouse == touch, "Direct mouse and touch gestures diverged")
	direct_throw(scene, true, -1)
	var gentle_mouse := direct_throw(scene, false, 1, true)
	check_curl_travel(scene, 1)
	var gentle_touch := direct_throw(scene, true, 1, true)
	check(gentle_mouse == gentle_touch, "Gentle mouse and touch finishes diverged")
	direct_throw(scene, true, -1, true)
	check_curl_travel(scene, -1)
	analog_throw(scene, false, 1)
	analog_throw(scene, true, -1)
	scene.queue_free()
	print("DELIVERY_SLIDE_OK" if not failed else "DELIVERY_SLIDE_FAILED")
	quit(1 if failed else 0)
