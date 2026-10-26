extends "res://scenes/lab.gd"
signal leave_requested
var online: CurlOnline
var network_time := 0.0
var last_brush_tick := -12
var waiting_release := false
var waiting_count := -1
var begin_sent := false
var delivery_count := -1
var was_paused := false
func _ready() -> void:
	authoritative_delivery = true
	persistence_enabled = false
	allow_online = false
	spatial_view = true
	super._ready()
	match_mode = true
	fresh_button.hide()
	mode_button.hide()
	button("Room / leave", Vector2(1030, 30), func(): leave_requested.emit())
	online.failed.connect(on_network_error)
	refresh_online()
func on_network_error(error: String) -> void:
	waiting_release = false
	begin_sent = false
	pointer = -99
	stop_scrub()
	hold_sweep = false
	if session != null: session.cancel_stroke()
	report = error
	if not run_active: phase = "Ready"
	update_labels()
func save_practice() -> void: pass
func refresh_online() -> void:
	var paused: bool = online.state.get("paused", true)
	if paused and not was_paused:
		pointer = -99
		begin_sent = false
		waiting_release = false
		session.cancel_stroke()
		phase = "Ready"
		stop_scrub()
		hold_sweep = false
	was_paused = paused
	var next := online.frame()
	if next.is_empty(): return
	var old_phase: String = frame.get("match_phase", "")
	var old_held: Dictionary = frame.get("in_hand", {})
	frame = next
	if delivery_count != int(frame.get("delivered_count", -1)) or old_phase != frame.match_phase:
		begin_sent = false
		delivery_count = int(frame.get("delivered_count", -1))
		if not old_held.is_empty():
			pointer = -99
			session.cancel_stroke()
			phase = "Ready"
	if not frame.get("in_hand", {}).is_empty():
		broom_mm = int(frame.in_hand.broom_mm)
		if frame.in_hand.get("suspended", false) and not old_held.get("suspended", false):
			pointer = -99
			session.cancel_stroke()
			phase = "Ready"
			report = "Delivery paused. Regrip the handle when everyone is back."
	run_active = frame.match_phase == "InFlight"
	if run_active or int(frame.get("delivered_count", -1)) != waiting_count: waiting_release = false
	if old_phase != frame.match_phase:
		pointer = -99
		session.cancel_stroke()
		phase = "Travel" if run_active else "Ready"
		stop_scrub()
		hold_sweep = false
		if run_active: last_brush_tick = frame.global_tick - 12
		if frame.match_phase == "Placement": power_side = 0; own_house = true
	update_labels()
func update_labels() -> void:
	if frame.is_empty() or not frame.has("match_phase"):
		super.update_labels()
		return
	super.update_labels()
	var index := online.seat_index()
	var team := int(index / 2)
	var player := index % 2
	var paused: bool = online.state.get("paused", true)
	hint.text = "ONLINE DOUBLES • End %d/%d • Gold %d : %d Cyan • You: %s player %d" % [frame.end, frame.scheduled_ends, frame.score_gold, frame.score_cyan, team_name(team), player + 1]
	if paused: status.text = "Online doubles  /  Waiting for players to synchronize"
	gold_order.disabled = paused or team != 0
	cyan_order.disabled = paused or team != 1
	house_button.disabled = paused or team != frame.placement_team
	power_button.disabled = paused or team != frame.placement_team or not frame.power_available
	setup_panel.get_child(setup_panel.get_child_count() - 1).disabled = paused or team != frame.placement_team
	new_button.disabled = paused or run_active or frame.match_phase in ["Placement", "Calling"] or not online.is_host
	if not frame.get("in_hand", {}).is_empty():
		new_button.disabled = paused or not owns_delivery() or frame.in_hand.in_play
		new_button.text = "Stone in play" if frame.in_hand.in_play else "Return to hack"
	new_button.text = "Host: next end" if not online.is_host and frame.match_phase == "EndComplete" else new_button.text
	sweep_button.disabled = paused or not can_sweep()
	if frame.match_phase == "Calling" and (team != frame.team or player != frame.thrower):
		report_label.text = "%s player %d is delivering. Both teammates can sweep after release." % [team_name(frame.team), frame.thrower + 1]
	elif run_active and team == frame.team and not delivered_stone().is_empty() and delivered_stone().position.y >= 0:
		report_label.text = "Past the tee: one sweeper per team. Player 1 takes priority if both hold."
	elif frame.match_phase == "Placement": report_label.text = "Each team selects its first/last thrower. The indicated team chooses placement."
	layout_feedback()
func owns_delivery() -> bool:
	var index := online.seat_index()
	return index >= 0 and int(index / 2) == frame.get("team") and index % 2 == frame.get("thrower")
func advance_local_held() -> void: pass # Only the room authority advances elapsed time.
func suspend_online_delivery() -> void:
	if online != null and owns_delivery() and (begin_sent or not frame.get("in_hand", {}).is_empty()):
		var error := online.send_command({"kind": "SuspendDelivery", "suspended": true})
		if not error.is_empty(): report = error
func cancel_pointer() -> void:
	suspend_online_delivery()
	super.cancel_pointer()
func update_delivery() -> void:
	if pointer == -99 or dragging_broom or sweeping or run_active: return
	if online.state.get("paused", true): return
	var held: Dictionary = frame.get("in_hand", {})
	if held.is_empty() and not begin_sent:
		var target: int = session.delivery_target(input_clock.call())
		if target == 0: return
		if not start_delivery(target): return
		held = frame.get("in_hand", {})
	phase = "Slide"
	if held.is_empty():
		report = "Starting delivery…"
	else:
		var weight := "Soft" if held.target_mm_s < 1950 else ("Draw" if held.target_mm_s < 2300 else "Firm")
		report = delivery_feedback(weight, held.hog_warning)
	update_labels()
func start_delivery(target: int) -> bool:
	if begin_sent or not frame.get("in_hand", {}).is_empty(): return true
	var gesture: Dictionary = session.delivery_pose(input_clock.call())
	var error := online.send_command({"kind": "BeginAnalogDelivery", "target_mm_s": target, "broom_mm": broom_mm, "line": {"x_mm": int(gesture.x_mm), "aim_mm": int(gesture.aim_mm)}})
	if not error.is_empty():
		report = error
		return false
	begin_sent = true
	refresh_online()
	return true
func sweep_seat() -> int:
	var index := online.seat_index() if online != null else -1
	return index if index >= 0 else -2
func _process(delta: float) -> void:
	if session == null or online == null: return
	refresh_online()
	if frame.is_empty() or online.state.get("paused", true) :
		network_time = 0.0
		return
	var brush := current_brush()
	if not brush.is_empty() and brush.effort > 0 and frame.global_tick >= last_brush_tick + 12:
		last_brush_tick = frame.global_tick
		var error := online.send_command({"kind": "BrushSpan", "tick": int(frame.global_tick), "count": 12, "input": {"stone": brush.stone, "brush": 0, "effort": brush.effort, "lateral_mm": brush.lateral_mm, "ahead_mm": brush.ahead_mm}})
		if not error.is_empty(): report = error
	if online.is_host:
		network_time += delta
		if network_time >= .05:
			network_time -= .05
			var error := online.advance(12 if run_active else 0, 50 if frame.match_phase == "Calling" else 0)
			if not error.is_empty(): report = error
			refresh_online()
	if run_active and not delivered_stone().is_empty():
		var pos: Vector2 = delivered_stone().position
		if path.is_empty() or path[-1] != pos: path.append(pos)
	update_delivery()
	update_spatial(delta)
	queue_redraw()
func begin_pointer(id: int, pos: Vector2) -> void:
	if suspended or not is_visible_in_tree() or online.state.get("paused", true) or waiting_release: return
	var index := online.seat_index()
	if run_active:
		if can_sweep(): super.begin_pointer(id, pos)
		return
	if index < 0 or int(index / 2) != frame.get("team") or index % 2 != frame.get("thrower"): return
	if not frame.get("in_hand", {}).is_empty():
		if pointer != -99 or pos.distance_to(handle_point()) >= 80: return
		var q := units(pos)
		var error: String = session.regrip_target(input_clock.call(), q.x, q.y, int(frame.in_hand.target_mm_s))
		if not error.is_empty(): report = error; return
		if frame.in_hand.get("suspended", false):
			error = online.send_command({"kind": "SuspendDelivery", "suspended": false})
			if not error.is_empty(): report = error; return
		pointer = id
		stroke_trace = PackedVector2Array([pos])
		phase = "Slide"
		update_labels()
	else: super.begin_pointer(id, pos)
func end_pointer(pos: Vector2) -> void:
	pointer = -99
	if dragging_broom:
		dragging_broom = false
		rink.mode = 0
		update_spatial(0)
		return
	if sweeping or run_active: stop_scrub(); return
	var q := units(pos)
	release_report = session.lift(input_clock.call(), q.x, q.y)
	if spatial_view:
		turn = int(release_report.get("turn", 0))
		release_report.line_mm = 0
	if not release_report.get("finish_valid", false):
		phase = "Ready"
		report = "Regrip the stone to finish." if not frame.get("in_hand", {}).is_empty() else "Make one smooth forward stroke, then lift. A click does not throw."
	elif start_delivery(int(release_report.target_mm_s)):
		# Begin and finish use consecutive reliable commands. The host derives
		# position from its accepted held plan, never from client screen coordinates.
		var error := online.send_command({"kind": "ReleaseDelivery", "trim_mm_s": int(release_report.trim_mm_s), "line_mm": int(release_report.line_mm), "turn": turn})
		if error.is_empty():
			waiting_count = int(frame.get("delivered_count", -1))
			waiting_release = true
			phase = "Releasing…"
			path.clear()
			report = "Tap a moving stone to select it. Scrub ahead, or hold the sweep button."
		else: report = error; phase = "Ready"
	refresh_online()
func change_order(team: int) -> void:
	if int(online.seat_index() / 2) != team: return
	var error := online.send_command({"kind": "Order", "first": 1 - int(frame.first_gold if team == 0 else frame.first_cyan)})
	if not error.is_empty(): report = error
	refresh_online()
func apply_placement() -> void:
	var error := online.send_command({"kind": "Place", "own_house": own_house, "side": "Left" if power_side < 0 else ("Right" if power_side > 0 else "None")})
	if not error.is_empty(): report = error
	refresh_online()
func next_throw() -> void:
	if not frame.get("in_hand", {}).is_empty():
		var error := online.send_command({"kind": "CancelDelivery"})
		if error.is_empty():
			begin_sent = false
			pointer = -99
			session.cancel_stroke()
			phase = "Ready"
		else: report = error
		refresh_online()
		return
	if frame.get("match_phase") == "GameComplete":
		var error := online.rematch()
		if not error.is_empty(): report = error
		return
	if frame.get("match_phase") == "EndComplete":
		var error := online.next_end()
		if not error.is_empty(): report = error
		path.clear()
		refresh_online()
