extends "res://scenes/lab.gd"
signal leave_requested
var online: CurlOnline
var network_time := 0.0
var last_brush_tick := -12
var waiting_release := false
var waiting_count := -1
func _ready() -> void:
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
	report = error
	if not run_active: phase = "Ready"
	update_labels()
func save_practice() -> void: pass
func refresh_online() -> void:
	var next := online.frame()
	if next.is_empty(): return
	var old_phase: String = frame.get("match_phase", "")
	frame = next
	run_active = frame.match_phase == "InFlight"
	if run_active or int(frame.get("delivered_count", -1)) != waiting_count: waiting_release = false
	if old_phase != frame.match_phase:
		pointer = -99
		session.cancel_stroke()
		phase = "Travel" if run_active else "Ready"
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
	if paused: status.text = "PEBBLE & GRANITE  /  Waiting for players to synchronize"
	gold_order.disabled = paused or team != 0
	cyan_order.disabled = paused or team != 1
	house_button.disabled = paused or team != frame.placement_team
	power_button.disabled = paused or team != frame.placement_team or not frame.power_available
	setup_panel.get_child(setup_panel.get_child_count() - 1).disabled = paused or team != frame.placement_team
	new_button.disabled = paused or run_active or frame.match_phase in ["Placement", "Calling"] or not online.is_host
	new_button.text = "Host: next end" if not online.is_host and frame.match_phase == "EndComplete" else new_button.text
	sweep_button.disabled = paused or not can_sweep()
	if frame.match_phase == "Calling" and (team != frame.team or player != frame.thrower):
		report_label.text = "%s player %d is delivering. Their teammate can sweep after release." % [team_name(frame.team), frame.thrower + 1]
	elif frame.match_phase == "Placement": report_label.text = "Each team selects its first/last thrower. The indicated team chooses placement."
func can_sweep() -> bool:
	var index := online.seat_index()
	if index < 0 or frame.get("match_phase") != "InFlight": return false
	var stone := delivered_stone()
	if stone.is_empty() or not stone.active: return false
	# One brush per side in this slice; the delivering teammate is the sweeper.
	if int(index / 2) == frame.team: return index % 2 != frame.thrower
	return index % 2 == 1 and stone.position.y >= 0
func _process(delta: float) -> void:
	if session == null or online == null: return
	refresh_online()
	if frame.is_empty() or online.state.get("paused", true) :
		network_time = 0.0
		return
	if can_sweep() and (hold_sweep or sweeping) and frame.global_tick >= last_brush_tick + 12:
		last_brush_tick = frame.global_tick
		var error := online.send_command({"kind": "BrushSpan", "tick": int(frame.global_tick), "count": 12, "input": {"stone": int(frame.delivered), "brush": 0, "effort": 255, "lateral_mm": 0, "ahead_mm": 180}})
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
	if not is_visible_in_tree() or online.state.get("paused", true) or waiting_release: return
	var index := online.seat_index()
	if run_active:
		if can_sweep(): super.begin_pointer(id, pos)
		return
	if index < 0 or int(index / 2) != frame.get("team") or index % 2 != frame.get("thrower"): return
	super.begin_pointer(id, pos)
func end_pointer(pos: Vector2) -> void:
	pointer = -99
	if dragging_broom:
		dragging_broom = false
		rink.mode = 0
		update_spatial(0)
		return
	if sweeping or run_active: sweeping = false; return
	var q := units(pos)
	release_report = session.lift(input_clock.call(), q.x, q.y)
	if spatial_view:
		turn = int(release_report.get("turn", 0))
		if turn != 0: release_report.line_mm = 0
	if release_report.get("hog_violation", false):
		waiting_count = int(frame.get("delivered_count", -1))
		var error := online.send_command({"kind": "HogViolation"})
		waiting_release = error.is_empty()
		phase = "Ready"
		report = "Hog-line violation. The delivery counts." if error.is_empty() else error
	elif not release_report.valid:
		phase = "Ready"
		report = "Make one smooth forward stroke, then lift. A click does not throw."
	else:
		var error := online.release_slide(int(release_report.speed_um_s), int(release_report.y_um), clampi(broom_mm + int(release_report.line_mm), -2200, 2200), turn)
		if error.is_empty():
			waiting_count = int(frame.get("delivered_count", -1))
			waiting_release = true
			phase = "Releasing…"
			path.clear()
			report = "Your teammate can sweep while the stone travels."
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
	if frame.get("match_phase") == "GameComplete":
		var error := online.rematch()
		if not error.is_empty(): report = error
		return
	if frame.get("match_phase") == "EndComplete":
		var error := online.next_end()
		if not error.is_empty(): report = error
		path.clear()
		refresh_online()
