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
	scene.queue_free()
	print("DELIVERY_SLIDE_OK" if not failed else "DELIVERY_SLIDE_FAILED")
	quit(1 if failed else 0)
