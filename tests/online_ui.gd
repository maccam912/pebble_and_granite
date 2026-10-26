extends SceneTree
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func run() -> void:
	var lab = load("res://scenes/lab.tscn").instantiate()
	lab.persistence_enabled = false
	root.add_child(lab)
	await process_frame
	lab.open_online()
	check(lab.room_panel.visible and lab.room_panel.roster.text.contains("Waiting for player"), "Room panel missing")
	lab.room_panel.code_input.text = "BAD"
	lab.room_panel.join_button.pressed.emit()
	check(lab.room_panel.message.text.contains("Enter four"), "Invalid room code not explained")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/evidence/online-room.png")
	lab.room_panel.leave()
	check(not lab.room_panel.visible, "Room did not close")
	lab.queue_free()
	await process_frame
	# Offline UI fixture: real host identity, native authority, synthetic admitted
	# seats; no external code-directory entry and no remote players are contacted.
	var online := CurlOnline.new()
	check(online.host().is_empty(), "Host unavailable")
	for id in range(2, 5): check(online.authority.join_peer(id, String.chr(65 + id).repeat(43), ClassDB.class_call_static("CurlRoom", "hello_packet")).is_empty(), "Fixture seat rejected")
	for id in range(1, 5): online.authority.ready_peer(id, true)
	check(online.authority.start_match(1, 42).is_empty(), "Fixture start rejected")
	online.broadcast_state()
	var game = load("res://scenes/online_game.gd").new()
	game.online = online
	root.add_child(game)
	game.set_process(false)
	check(game.house_button.disabled and game.cyan_order.disabled and not game.gold_order.disabled, "Seat ownership not reflected by setup controls")
	check(not game.persistence_enabled and not game.allow_online, "Online view enabled local persistence")
	var command := {"epoch": 1, "sequence": 1, "command": {"kind": "Place", "own_house": true, "side": "None"}}
	check(online.authority.command_peer(3, JSON.stringify(command).to_utf8_buffer()).is_empty(), "Placement fixture failed")
	online.flush_commits()
	game.refresh_online()
	var clock := [0]
	game.input_clock = func(): return clock[0]
	var start: Vector2 = game.handle_point()
	game.begin_pointer(0, start)
	for sample in [[100000, 24.0], [120000, 19.2], [240000, -9.6]]:
		clock[0] = sample[0]
		game.move_pointer(start + Vector2(0, sample[1]))
	clock[0] = 500000
	game.update_delivery()
	check(not game.frame.in_hand.is_empty(), "Online push did not begin host-held delivery")
	for i in range(40): game._process(.05)
	check(game.frame.in_hand.in_play, "Held authority did not cross delivery tee")
	var thinking: int = game.frame.clock_gold
	var cancelled := InputEventScreenTouch.new()
	cancelled.index = 0
	cancelled.pressed = false
	cancelled.canceled = true
	cancelled.position = start
	game._input(cancelled)
	game.refresh_online()
	check(not game.run_active and game.frame.in_hand.suspended, "Online canceled touch released instead of suspending")
	game._notification(NOTIFICATION_APPLICATION_PAUSED)
	game.refresh_online()
	check(game.frame.in_hand.suspended, "Focus loss did not suspend authority delivery")
	var frozen: String = online.state.hash
	for i in range(200): game._process(.05)
	check(online.state.hash == frozen, "Paused online slide advanced")
	game._notification(NOTIFICATION_APPLICATION_RESUMED)
	game.update_spatial(0)
	var point: Vector2 = game.handle_point()
	game.begin_pointer(0, point)
	clock[0] = 600000
	game.move_pointer(point)
	clock[0] = 700000
	game.end_pointer(point + Vector2(-30, -8))
	check(game.release_report.turn == -1, "Online regrip lost finishing curl")
	check(game.frame.clock_gold == thinking, "Online clock ran after delivery tee")
	check(game.run_active and game.frame.match_phase == "InFlight", "Online stroke did not release through authority")
	check(not game.can_sweep(), "Deliverer stole teammate brush role")
	for i in range(1300):
		if not game.run_active: break
		game._process(.05)
	check(not game.run_active and game.frame.delivered_count == 1, "Online scene did not finish shot")
	check(game.frame.match_phase == "Calling", "Online scene not ready for next player")
	game.begin_pointer(0, start)
	check(game.pointer == -99, "Wrong team could grip")
	command = {"epoch": 1, "sequence": 2, "command": {"kind": "Concede"}}
	check(online.authority.command_peer(3, JSON.stringify(command).to_utf8_buffer()).is_empty(), "Concession fixture failed")
	online.flush_commits()
	game.refresh_online()
	check(game.new_button.text == "Rematch" and not game.new_button.disabled, "Host rematch control missing")
	game.new_button.pressed.emit()
	check(online.state.phase == null, "Rematch did not return to readiness")
	game.queue_free()
	online.close()
	await process_frame
	print("ONLINE_UI_OK" if not failed else "ONLINE_UI_FAILED")
	quit(1 if failed else 0)
