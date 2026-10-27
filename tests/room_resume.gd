extends SceneTree
var failed := false
var panels: Array[CurlRoomPanel] = []
var prefix := "user://network/test-resume-%d-" % OS.get_process_id()
func check(ok: bool, message: String) -> bool:
	if not ok: push_error(message); failed = true
	return ok
func _initialize() -> void: call_deferred("run")
func until(predicate: Callable, seconds := 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(.01).timeout
	return false
func panel_for(index: int) -> CurlRoomPanel:
	var panel := CurlRoomPanel.new()
	panel.room.identity_path = prefix + str(index) + ".key"
	panel.view_match = false
	root.add_child(panel)
	return panel
func run() -> void:
	var identity := prefix + "unit.key"
	check(CurlRoomResume.save(identity, "A".repeat(43)), "Could not save reconnect shortcut")
	check(CurlRoomResume.read(identity).get("endpoint") == "A".repeat(43), "Shortcut did not survive reload")
	check(not CurlRoomResume.save(identity, "invalid") and not CurlRoomResume.read(identity).is_empty(), "Invalid endpoint replaced valid shortcut")
	var panel := CurlRoomPanel.new()
	panel.room.identity_path = identity
	root.add_child(panel)
	check(panel.reconnect_button.visible and panel.forget_button.visible and panel.room.peer == null, "Saved room was not offered without connecting")
	check("host is still open" in panel.message.text, "Host requirement missing")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/evidence/room-resume")
		root.get_texture().get_image().save_png("res://build/evidence/room-resume/reconnect.png")
	panel.forget_room()
	check(CurlRoomResume.read(identity).is_empty() and not panel.reconnect_button.visible, "Forget left reconnect shortcut")
	panel.queue_free()
	for raw in ['{"schema":1,"session":"old","endpoint":"' + "A".repeat(43) + '"}', "broken", "x".repeat(2049)]:
		var file := FileAccess.open(CurlRoomResume.path_for(identity), FileAccess.WRITE)
		file.store_string(raw); file.close()
		check(CurlRoomResume.read(identity).is_empty(), "Stale or malformed shortcut accepted")
	CurlRoomResume.forget(identity)
	var room := CurlOnline.new()
	room.state = {"players": [{"peer": 1, "synchronized": true}, {"peer": null}, {"peer": 3, "synchronized": false}, {"peer": 4, "synchronized": true}]}
	check("Gold player 2 to reconnect" in room.pause_reason() and "Cyan player 1 to synchronize" in room.pause_reason(), "Pause did not name missing players")
	if "--network-resume" in OS.get_cmdline_user_args(): await network_resume()
	for item in panels:
		if not is_instance_valid(item): continue
		item.room.close()
		CurlRoomResume.forget(item.room.identity_path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(item.room.identity_path))
		item.queue_free()
	await process_frame
	print("ROOM_RESUME_OK" if not failed else "ROOM_RESUME_FAILED")
	quit(1 if failed else 0)
func network_resume() -> void:
	for index in range(4): panels.append(panel_for(index))
	var host := panels[0]
	if not check(host.room.host().is_empty(), "Resume fixture host failed"): return
	for item in panels.slice(1):
		item.last_address = host.room.endpoint
		check(item.room.join(host.room.endpoint).is_empty(), "Resume fixture join failed")
	if not check(await until(func(): return panels.all(func(p): return p.room.state.get("players", []).size() == 4 and p.room.state.players.all(func(v): return v != null)), 45), "Resume fixture peers did not join"): return
	for item in panels: item.toggle_ready()
	if not check(await until(func(): return host.room.state.players.all(func(v): return v.ready)), "Resume fixture readiness failed"): return
	check(host.room.start_match().is_empty(), "Resume fixture match start failed")
	if not check(await until(func(): return panels.all(func(p): return p.room.state.get("phase") == "Placement" and not p.room.state.paused)), "Resume fixture initial sync failed"): return
	for item in panels:
		if item.room.seat_index() == 2: check(item.room.send_command({"kind":"Place", "own_house":true, "side":"None"}).is_empty(), "Resume placement failed")
	if not check(await until(func(): return host.room.state.phase == "Calling"), "Resume placement stalled"): return
	check(host.room.send_command({"kind":"BeginDelivery", "target_mm_s":2050, "broom_mm":-900}).is_empty(), "Held resume fixture failed")
	check(host.room.advance(0, 1000).is_empty(), "Held resume advance failed")
	var departed := panels[3]
	var seat := departed.room.seat_index()
	check(not CurlRoomResume.read(departed.room.identity_path).is_empty(), "Admitted client did not save shortcut")
	departed.queue_free() # Lose the whole panel and CurlOnline, as on an app restart.
	await process_frame
	if not check(await until(func(): return host.room.state.paused), "Restart did not pause match"): return
	var frozen: String = host.room.state.hash
	check(host.room.frame().in_hand.suspended, "Restart did not suspend held delivery")
	panels[3] = panel_for(3)
	check(panels[3].last_address == host.room.endpoint, "Restart lost host endpoint")
	panels[3].reconnect()
	panels[3].view_match = false
	if not check(await until(func(): return panels.all(func(p): return p.room.state.get("phase") == "Calling" and not p.room.state.paused), 20), "Saved shortcut did not synchronize"): return
	check(panels[3].room.seat_index() == seat, "Restart reclaimed the wrong seat")
	check(host.room.state.hash == frozen and panels[3].room.replica.state_hash() == frozen, "Restart changed held match hash")
	check(host.room.frame().in_hand.suspended, "Reconnect released held stone without regrip")
	print("ROOM_RESUME_NETWORK_OK seat=", seat)
