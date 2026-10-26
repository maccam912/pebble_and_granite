extends SceneTree
var panels: Array[CurlRoomPanel] = []
var failed := false
var rejects: Array[String] = []
var timing := [0, 0, 0]
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if not ok: push_error(message); failed = true
	return ok
func until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(.01).timeout
	return false
func at_seat(index: int) -> CurlRoomPanel:
	for panel in panels:
		if panel.room.seat_index() == index: return panel
	return null
func cleanup() -> void:
	for panel in panels:
		var identity := panel.room.identity_path
		await panel.leave()
		panel.queue_free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(identity))
	await process_frame
func run() -> void:
	for i in range(4):
		var panel := CurlRoomPanel.new()
		panel.room.identity_path = "user://network/test-room-flow-%s-%d.key" % [OS.get_process_id(), i]
		panel.room.failed.connect(func(message: String): rejects.append(message))
		root.add_child(panel)
		panels.append(panel)
	var host := panels[0]
	await host.host_room()
	if not check(not host.code.is_empty(), "UI host registration failed: " + host.message.text):
		await cleanup(); quit(1); return
	for panel in panels.slice(1):
		panel.code_input.text = host.code
		await panel.join_room()
	if not check(await until(func(): return host.room.state.get("players", []).size() == 4 and host.room.state.players.all(func(p): return p != null) and panels.all(func(p): return p.room.state.get("players", []).size() == 4), 45), "UI joins timed out: " + str(panels.map(func(p): return p.message.text)) + " / " + str(rejects)):
		await cleanup(); quit(1); return
	for panel in panels: panel.toggle_ready()
	if not check(await until(func(): return host.room.state.players.all(func(p): return p != null and p.ready), 10), "UI readiness timed out"):
		await cleanup(); quit(1); return
	host.start_match()
	if not check(await until(func(): return panels.all(func(p): return p.game != null and not p.room.state.paused), 20), "UI match synchronization timed out"):
		await cleanup(); quit(1); return
	at_seat(2).game.apply_placement()
	if not check(await until(func(): return panels.all(func(p): return p.room.frame().get("match_phase") == "Calling"), 10), "UI placement timed out"):
		await cleanup(); quit(1); return
	# Exercise the actual card-to-slide-to-packet path, with reproducible input time.
	deliver_gesture(host.game, 3000000)
	check(await until(func(): return panels.all(func(p): return p.game.run_active), 10), "Flight state not delivered")
	var sweeper := at_seat(1)
	sweeper.game.sweep_button.button_down.emit()
	timing = [Time.get_ticks_usec(), 0, 0]
	var monitor := func():
		var now := Time.get_ticks_usec()
		timing[1] = maxi(timing[1], now - timing[0])
		timing[0] = now
		timing[2] += 1
	process_frame.connect(monitor)
	var began := Time.get_ticks_usec()
	check(await until(func(): return host.room.frame().get("match_phase") == "Calling", 180), "Continuously swept shot did not finish")
	var elapsed := float(Time.get_ticks_usec() - began) / 1000000.0
	process_frame.disconnect(monitor)
	sweeper.game.sweep_button.button_up.emit()
	if host.game != null: host.game.set_process(false)
	check(await until(func(): return panels.slice(1).all(func(p): return p.room.replica != null and p.room.replica.state_hash() == host.room.state.hash), 10), "UI replica hashes diverged")
	var final_frame := host.room.frame()
	check(final_frame.get("delivered_count") == 1, "Wrong delivered count")
	check(rejects.is_empty(), "Gameplay requests rejected: " + str(rejects))
	print("ONLINE_ROOM_TIMING wall_seconds=", elapsed, " simulation_seconds=", float(final_frame.get("tick", 0)) / 240.0, " max_frame_ms=", float(timing[1]) / 1000.0, " frames=", timing[2])
	var fault_player := at_seat(int(final_frame.team) * 2 + int(final_frame.thrower))
	deliver_gesture(fault_player.game, 6000000, true)
	check(await until(func(): return host.room.frame().get("delivered_count") == 2 and synchronized(host), 10), "Held online hog fault did not synchronize")
	check(host.room.frame().get("violation") == "HogRelease", "Online held fault lost rule resolution")
	if "--full-match" in OS.get_cmdline_user_args() and not failed: await finish_match(host)
	await cleanup()
	print("ONLINE_ROOM_FLOW_OK" if not failed else "ONLINE_ROOM_FLOW_FAILED")
	quit(1 if failed else 0)

func deliver_gesture(game: Control, release_us: int, hold := false) -> void:
	var clock := [0]
	game.input_clock = func(): return clock[0]
	game.one_push = true
	var handle: Vector2 = game.handle_point()
	game.begin_pointer(-1, handle)
	clock[0] = 20000
	game.move_pointer(handle + Vector2(0, -4.2))
	clock[0] = 120000
	game.move_pointer(handle + Vector2(0, -25.2))
	clock[0] = release_us
	if hold: game.update_delivery()
	else: game.end_pointer(handle + Vector2(0, -25.2))

func synchronized(host: CurlRoomPanel) -> bool:
	return panels.slice(1).all(func(p): return p.room.replica != null and p.room.replica.state_hash() == host.room.state.hash)

func finish_match(host: CurlRoomPanel) -> void:
	# Accelerated driver: the real scene's fixed-step callback runs once per
	# network frame. No clock/physics values are changed and no packets are skipped.
	for delivery in range(120):
		var frame := host.room.frame()
		if frame.match_phase == "GameComplete": break
		if frame.match_phase == "EndComplete":
			print("ONLINE_END_COMPLETE end=", frame.end, " score=", frame.score_gold, ":", frame.score_cyan)
			host.game.next_throw()
			if not check(await until(func(): return synchronized(host), 10), "End transition did not synchronize"): return
			frame = host.room.frame()
		if frame.match_phase == "Placement":
			at_seat(int(frame.placement_team) * 2).game.apply_placement()
			if not check(await until(func(): return host.room.frame().get("match_phase") == "Calling" and synchronized(host), 10), "Next placement failed"): return
			frame = host.room.frame()
		var thrower := at_seat(int(frame.team) * 2 + int(frame.thrower))
		if not check(thrower.room.release_stone(4000, 2200, 1).is_empty(), "Full-match release failed"): return
		if not check(await until(func(): return host.room.frame().get("match_phase") == "InFlight", 10), "Release did not reach host"): return
		for step in range(1300):
			if host.room.frame().get("match_phase") != "InFlight": break
			host.game._process(.05)
			await process_frame
		if not check(host.room.frame().get("match_phase") != "InFlight", "Full-match shot did not settle"): return
		if not check(await until(func(): return synchronized(host), 10), "Full-match hashes diverged"): return
	if not check(host.room.frame().get("match_phase") == "GameComplete", "Full game did not finish"): return
	var finished := host.room.frame()
	print("ONLINE_GAME_COMPLETE end=", finished.end, " score=", finished.score_gold, ":", finished.score_cyan)
	host.game.new_button.pressed.emit()
	if not check(await until(func(): return panels.all(func(p): return p.game == null and p.room.state.get("phase") == null), 10), "Rematch did not return all players to room"): return
	for panel in panels: panel.toggle_ready()
	if not check(await until(func(): return host.room.state.players.all(func(p): return p.ready), 10), "Rematch readiness failed"): return
	host.start_match()
	check(await until(func(): return panels.all(func(p): return p.game != null and p.room.state.epoch == 2 and not p.room.state.paused), 20), "Rematch epoch did not synchronize")
	check(rejects.is_empty(), "Full-match requests rejected: " + str(rejects))
