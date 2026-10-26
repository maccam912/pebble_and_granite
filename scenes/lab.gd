extends Control

const ICE := Color("dfecef")
const INK := Color("0b2330")
const GOLD := Color("eabf69")
const CYAN := Color("64cdd1")
var allow_online := true
var spatial_view := false
var rink: CurlRinkView
var camera_button: Button
var view_button: Button
var room_panel: CurlRoomPanel
var self_test_nonce := ""
var network_probe_request: Dictionary = {}
var session: Object
var frame: Dictionary = {}
var previous: Dictionary = {}
var accumulator := 0.0
var broom_mm := -900
var turn := 1
var pointer := -99
var dragging_broom := false
var sweeping := false
var hold_sweep := false
var one_push := false
var phase := "Ready"
var report := ""
var stroke_trace := PackedVector2Array()
var path := PackedVector2Array()
var release_report: Dictionary = {}
var font := ThemeDB.fallback_font
var status: Label
var report_label: Label
var hint: Label
var new_button: Button
var turn_button: Button
var sweep_button: Button
var one_button: Button
var run_active := false
var input_clock: Callable = Time.get_ticks_usec
var persistence_enabled := true
var save_allowed := true
var suspended := false
var last_save_tick := 0
var clock_remainder := 0.0
var clock_label: Label
var match_mode := false
var own_house := true
var power_side := 0
var setup_panel: Panel
var setup_label: Label
var house_button: Button
var power_button: Button
var gold_order: Button
var cyan_order: Button
var mode_button: Button
var fresh_button: Button
var save_path := "user://practice-session.json"
var match_save_path := "user://match-session.json"

func _ready() -> void:
	Input.use_accumulated_input = false
	if not ClassDB.class_exists("CurlSession"):
		push_error("Build the Rust bridge: python3 tools/build_native.py")
		return
	session = ClassDB.instantiate("CurlSession")
	var probe_path := "user://diagnostics/self-test-request.json"
	if OS.is_debug_build() and FileAccess.file_exists(probe_path):
		var request_file := FileAccess.open(probe_path, FileAccess.READ)
		if request_file != null and request_file.get_length() <= 256:
			var request = JSON.parse_string(request_file.get_as_text())
			var nonce_pattern := RegEx.create_from_string("^[a-f0-9]{32}$")
			if request is Dictionary and request.get("nonce") is String and nonce_pattern.search(request.nonce) != null:
				if request.get("schema") == 1:
					self_test_nonce = request.nonce
				elif request.get("schema") == 2 and request.get("endpoint") is String and CurlTransport.valid_endpoint(request.endpoint) and request.get("relay_only") is bool:
					network_probe_request = request
		if request_file != null: request_file.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_path))
	if not network_probe_request.is_empty():
		persistence_enabled = false
		set_process(false)
		set_process_input(false)
		hide()
		var probe = load("res://net/network_probe.gd").new()
		probe.request = network_probe_request
		add_child(probe)
		return
	if not self_test_nonce.is_empty() or "--self-test" in OS.get_cmdline_user_args():
		persistence_enabled = false
		call_deferred("run_self_test")
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	status = Label.new()
	status.position = Vector2(40, 26)
	status.add_theme_font_size_override("font_size", 27)
	add_child(status)
	hint = Label.new()
	hint.position = Vector2(40, 68)
	hint.add_theme_color_override("font_color", Color("92acb7"))
	add_child(hint)
	report_label = Label.new()
	report_label.position = Vector2(800, 510)
	report_label.size = Vector2(430, 180)
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_label.add_theme_font_size_override("font_size", 18)
	add_child(report_label)
	new_button = button("Next stone", Vector2(40, 726), func(): next_throw())
	turn_button = button("Turn: clockwise ↻", Vector2(225, 726), func(): turn *= -1; update_labels())
	sweep_button = button("Hold to sweep", Vector2(500, 726), func(): pass)
	sweep_button.button_down.connect(func(): hold_sweep = true)
	sweep_button.button_up.connect(func(): hold_sweep = false)
	one_button = button("One-push: off", Vector2(710, 726), func(): one_push = not one_push; update_labels())
	fresh_button = button("Fresh ice", Vector2(920, 726), func(): reset())
	mode_button = button("Mixed doubles", Vector2(1030, 30), func(): switch_mode())
	clock_label = Label.new()
	clock_label.position = Vector2(40, 88)
	clock_label.add_theme_font_size_override("font_size", 14)
	add_child(clock_label)
	create_match_controls()
	reset(false)
	restore_practice()
	if spatial_view: create_spatial_view()
	if allow_online:
		button("Online rooms", Vector2(840, 30), open_online)
		room_panel = CurlRoomPanel.new()
		add_child(room_panel)
		room_panel.hide()

func create_spatial_view() -> void:
	rink = CurlRinkView.new()
	rink.position = Vector2(40, 110)
	rink.size = Vector2(1200, 590)
	add_child(rink)
	move_child(rink, 0)
	camera_button = button("Camera: Auto", Vector2(52, 122), func():
		if pointer == -99: camera_button.text = "Camera: " + rink.cycle_camera())
	camera_button.custom_minimum_size = Vector2(190, 40)
	var toggle := button("2D lab", Vector2(600, 122), func(): pass)
	view_button = toggle
	toggle.custom_minimum_size = Vector2(165, 40)
	toggle.pressed.connect(func():
		if pointer != -99: return
		spatial_view = not spatial_view
		rink.visible = spatial_view
		camera_button.visible = spatial_view
		toggle.text = "2D lab" if spatial_view else "3D rink"
		update_labels()
		queue_redraw())
	var feedback_bg := Panel.new()
	feedback_bg.position = Vector2(50, 580)
	feedback_bg.size = Vector2(565, 110)
	feedback_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback_bg.add_theme_stylebox_override("panel", panel(Color(0.04, 0.10, 0.13, 0.88)))
	add_child(feedback_bg)
	move_child(feedback_bg, report_label.get_index())
	report_label.position = Vector2(60, 590)
	report_label.size = Vector2(540, 100)
	report_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_button.hide()
	view_button.hide()
	update_spatial(0.0)
func update_spatial(delta: float) -> void:
	if rink == null or not spatial_view: return
	var aiming: bool = not run_active and phase != "Stone at rest" and frame.get("match_phase", "Calling") == "Calling"
	rink.hand_held = pointer != -99 and not dragging_broom and not sweeping and not run_active
	rink.pull_offset = clampf((stroke_trace[-1].y - stroke_trace[0].y) * .004, -.08, .18) if rink.hand_held and stroke_trace.size() > 1 and phase in ["Grip", "Pull", "Drive"] else 0.0
	rink.delivery_y = float(session.delivery_pose(input_clock.call()).y_um) / 1000000.0 if aiming else -37.8
	rink.render_frame(frame, run_active, hold_sweep or sweeping, broom_mm, turn, aiming, delta)
func broom_screen_point() -> Vector2:
	return rink.broom_point() if spatial_view and rink != null else house_point(Vector2(float(broom_mm) / 1000.0, 0))

func open_online() -> void:
	save_practice()
	pointer = -99
	session.cancel_stroke()
	room_panel.show()

func button(text: String, pos: Vector2, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = Vector2(165, 48)
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(action)
	add_child(b)
	return b

func reset(persist := true) -> void:
	if session == null: return
	if match_mode: session.new_match(42)
	else: session.reset(42)
	frame = session.frame()
	previous = frame
	phase = "Ready"
	if spatial_view: turn = 0
	clock_remainder = 0.0
	last_save_tick = 0
	save_allowed = true
	pointer = -99
	dragging_broom = false
	sweeping = false
	hold_sweep = false
	run_active = false
	accumulator = 0.0
	path.clear()
	stroke_trace.clear()
	report = ("House camera: drag the broom to aim." if spatial_view else "Drag the broom in the house.") + "\nGrab the handle on the ice. Pull back, push forward, hold, then flick left or right as you release."
	update_labels()
	queue_redraw()
	if match_mode:
		phase = "Choose placement"
		update_labels()
	if persist: save_practice()

func update_labels() -> void:
	status.text = "PEBBLE & GRANITE  /  " + phase
	hint.text = "CLUB ICE     •     Mouse / trackpad / touch" if spatial_view else "FEEL LAB     •     Seed 42     •     Mouse / trackpad / touch"
	turn_button.text = "Turn: clockwise ↻" if turn == 1 else "Turn: counterclockwise ↺"
	one_button.text = "One-push: on" if one_push else "One-push: off"
	new_button.disabled = run_active
	new_button.text = "Next stone" if frame.get("can_deliver_next", true) else "Clear stones"
	turn_button.size.x = 255
	turn_button.disabled = run_active
	one_button.disabled = run_active
	report_label.text = report
	clock_label.visible = match_mode
	sweep_button.disabled = not run_active
	mode_button.text = "Practice" if match_mode else "Mixed doubles"
	mode_button.disabled = run_active
	fresh_button.text = "New match" if match_mode else "Fresh ice"
	setup_panel.visible = match_mode and frame.get("match_phase", "") == "Placement"
	if match_mode:
		clock_label.text = "Thinking time   Gold %s   •   Cyan %s" % [clock_text(frame.clock_gold), clock_text(frame.clock_cyan)]
		hint.text = "LOCAL DOUBLES  •  End %d/%d  •  Gold %d : %d Cyan  •  Autosaved" % [frame.end, frame.scheduled_ends, frame.score_gold, frame.score_cyan]
		if frame.match_phase == "Placement":
			status.text = "PEBBLE & GRANITE  /  Choose placement"
			new_button.text = "Next stone"
			setup_label.text = "%s chooses the placement" % team_name(frame.placement_team)
			house_button.text = "Take the house" if own_house else "Take the guard"
			power_button.text = "Centre placement" if power_side == 0 else ("Left power play" if power_side < 0 else "Right power play")
			power_button.disabled = not frame.power_available
			gold_order.text = "Gold: player %d throws 1 & 5" % (frame.first_gold + 1)
			cyan_order.text = "Cyan: player %d throws 1 & 5" % (frame.first_cyan + 1)
			new_button.disabled = true
			report_label.text = "Pass the device between players. Select each team's first/last thrower, then choose where to place the stones."
		elif frame.match_phase in ["Calling", "InFlight"]:
			status.text = "PEBBLE & GRANITE  /  %s • Player %d • %s" % [team_name(frame.team), frame.thrower + 1, phase]
		elif frame.match_phase == "EndComplete":
			new_button.text = "Next end"
			status.text = "PEBBLE & GRANITE  /  End complete"
		elif frame.match_phase == "GameComplete":
			new_button.text = "Rematch"
			status.text = "PEBBLE & GRANITE  /  %s wins" % team_name(frame.winner)
		if not frame.get("violation", "").is_empty():
			report_label.text += "\nProtected stone removed: positions restored; delivery forfeited."

func clock_text(ms: int) -> String:
	var seconds := int(ceil(float(ms) / 1000.0))
	return "%d:%02d" % [seconds / 60, seconds % 60]

func team_name(team: int) -> String:
	return "Gold" if team == 0 else "Cyan"

func create_match_controls() -> void:
	setup_panel = Panel.new()
	setup_panel.position = Vector2(800, 110)
	setup_panel.size = Vector2(440, 380)
	setup_panel.add_theme_stylebox_override("panel", panel(Color("102b37")))
	add_child(setup_panel)
	setup_label = Label.new()
	setup_label.position = Vector2(20, 18)
	setup_label.add_theme_font_size_override("font_size", 22)
	setup_panel.add_child(setup_label)
	house_button = setup_button(Vector2(20, 70), func(): own_house = not own_house; update_labels())
	power_button = setup_button(Vector2(20, 128), func(): power_side = -1 if power_side == 0 else (1 if power_side == -1 else 0); update_labels())
	gold_order = setup_button(Vector2(20, 186), func(): change_order(0))
	cyan_order = setup_button(Vector2(20, 244), func(): change_order(1))
	var apply_button := setup_button(Vector2(20, 310), func(): apply_placement())
	apply_button.text = "Place stones & begin"

func setup_button(pos: Vector2, action: Callable) -> Button:
	var b := button("", Vector2.ZERO, action)
	b.reparent(setup_panel)
	b.position = pos
	b.custom_minimum_size = Vector2(400, 48)
	return b

func switch_mode() -> void:
	if run_active: return
	save_practice()
	match_mode = not match_mode
	own_house = true
	power_side = 0
	reset(false)
	if match_mode: restore_match()
	else: restore_practice()

func change_order(team: int) -> void:
	var current: int = frame.first_gold if team == 0 else frame.first_cyan
	var error: String = session.match_order(team, 1 - current)
	if not error.is_empty(): report = error
	frame = session.frame()
	update_labels()
	save_practice()

func apply_placement() -> void:
	var error: String = session.place_match(own_house, power_side)
	if not error.is_empty():
		report = error
	else:
		frame = session.frame()
		previous = frame
		phase = "Ready"
		report = "Ten deliveries this end. The player shown above throws; the other player calls the shot. Hold to sweep after release."
	update_labels()
	queue_redraw()
	save_practice()

func sheet_point(p: Vector2) -> Vector2:
	return Vector2(168 + p.x * 30, 125 + (2.2 - p.y) * 17)

func house_point(p: Vector2) -> Vector2:
	return Vector2(555 + p.x * 94, 325 - p.y * 94)

func handle_point() -> Vector2:
	return rink.handle_point() if spatial_view and rink != null else Vector2(1030, 365)

func _process(delta: float) -> void:
	if session == null or suspended or (room_panel != null and room_panel.visible): return
	if match_mode and not run_active and frame.get("match_phase", "") == "Calling":
		clock_remainder += delta * 1000.0
		var elapsed := mini(int(clock_remainder), 60000)
		clock_remainder -= elapsed
		session.match_think(elapsed)
		frame = session.frame()
		update_labels()
		if frame.global_tick - last_save_tick >= 240: save_practice()
	if run_active:
		# Retain all time debt. Never change fixed dt or silently skip ticks.
		accumulator += delta
		var steps := mini(int(accumulator * 240.0), 64)
		if steps > 0:
			previous = frame
			session.step_ticks(steps, 255 if hold_sweep or sweeping else 0, 0, 180)
			accumulator -= float(steps) / 240.0
			frame = session.frame()
			if not frame.stones.is_empty():
				if not delivered_stone().is_empty(): path.append(delivered_stone().position)
			if frame.resting:
				run_active = false
				phase = "Stone at rest"
				var s: Dictionary = delivered_stone()
				if s.is_empty(): s = {"turns": 0.0, "position": Vector2.ZERO, "active": false}
				var split := "—" if frame.hog_tick < 0 else "%.2f s" % (float(frame.hog_tick) / 240.0)
				report = "Release %.3f m/s\nHog-to-hog %s\n%.2f rotations • %.2f s travel\nRest: %.2f m across, %.2f m from tee\n%s" % [float(release_report.get("speed_mm_s", 0)) / 1000.0, split, s.turns, float(frame.tick) / 240.0, s.position.x, s.position.y, "In play" if s.active else "Out of play"]
				update_labels()
			if frame.resting or frame.global_tick - last_save_tick >= 240:
				save_practice()
	update_delivery()
	update_spatial(delta)
	queue_redraw()

func update_delivery() -> void:
	if pointer == -99 or dragging_broom or sweeping or run_active: return
	var pose: Dictionary = session.delivery_pose(input_clock.call())
	if pose.hog_violation and not stroke_trace.is_empty():
		end_pointer(stroke_trace[-1])
	elif pose.slide_tick > 0:
		phase = "Slide"
		var weight := "Soft" if pose.target_mm_s < 1950 else ("Draw" if pose.target_mm_s < 2300 else "Firm")
		report = "Release now — hog line." if pose.hog_warning else weight + " weight. Hold steady; finish left or right for curl. A small forward/back finish trims weight."
		update_labels()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		suspended = false
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		suspended = true
		save_practice()
		pointer = -99
		hold_sweep = false
		sweeping = false
		dragging_broom = false
		if session != null:
			session.cancel_stroke()
			if status != null and not run_active and phase != "Stone at rest":
				phase = "Ready"
				update_labels()

func _input(event: InputEvent) -> void:
	if room_panel != null and room_panel.visible: return
	if session == null: return
	if event is InputEventScreenTouch:
		if event.pressed: begin_pointer(event.index, event.position)
		elif pointer == event.index: end_pointer(event.position)
	elif event is InputEventScreenDrag and pointer == event.index:
		move_pointer(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed: begin_pointer(-1, event.position)
		elif pointer == -1: end_pointer(event.position)
	elif event is InputEventMouseMotion and pointer == -1:
		move_pointer(event.position)

func units(p: Vector2) -> Vector2i:
	return Vector2i(p * (1000000.0 / 800.0))

func begin_pointer(id: int, p: Vector2) -> void:
	for control in [camera_button, view_button]:
		if control != null and control.is_visible_in_tree() and control.get_global_rect().has_point(p): return
	if match_mode and not run_active and frame.get("match_phase", "") != "Calling": return
	if pointer != -99 or p.y > 710: return
	if run_active:
		# The lab's accessible hold gesture follows the stone's brush position.
		if (spatial_view and rink != null and rink.get_global_rect().has_point(p)) or (not spatial_view and p.x < 780):
			pointer = id
			sweeping = true
		return
	if p.distance_to(broom_screen_point()) < 55:
		pointer = id
		dragging_broom = true
	elif phase == "Ready" and p.distance_to(handle_point()) < 80:
		pointer = id
		var q := units(p)
		session.grip(input_clock.call(), q.x, q.y, one_push)
		stroke_trace = PackedVector2Array([p])
		if spatial_view and rink != null: rink.mode = 0
		phase = "Grip"
		update_labels()

func move_pointer(p: Vector2) -> void:
	if sweeping: return
	if dragging_broom:
		broom_mm = int(rink.aim_x(p) * 1000.0) if spatial_view and rink != null else clampi(int((p.x - 555) / 94.0 * 1000), -2200, 2200)
	elif not run_active:
		var q := units(p)
		session.motion(input_clock.call(), q.x, q.y)
		stroke_trace.append(p)
		phase = session.stroke_phase()
		update_labels()

func end_pointer(p: Vector2) -> void:
	pointer = -99
	if dragging_broom:
		dragging_broom = false
		if spatial_view and rink != null:
			rink.mode = 0
			update_spatial(0)
		return
	if sweeping or run_active:
		sweeping = false
		return
	var q := units(p)
	release_report = session.lift(input_clock.call(), q.x, q.y)
	if spatial_view:
		turn = int(release_report.get("turn", 0))
		if turn != 0: release_report.line_mm = 0
	if release_report.get("hog_violation", false):
		var error: String = session.hog_violation()
		frame = session.frame()
		phase = "Stone at rest" if error.is_empty() else "Ready"
		report = "Hog-line violation. The stone is removed; the delivery counts." if error.is_empty() else error
		save_practice()
	elif not release_report.valid:
		phase = "Ready"
		report = "Try a smooth pull-back, then forward stroke. Lift after the push. A simple click does not throw."
	else:
		var error: String = session.deliver_slide(release_report.speed_um_s, release_report.y_um, clampi(broom_mm + release_report.line_mm, -2200, 2200), turn)
		if error.is_empty():
			run_active = true
			phase = "Travel"
			report = "Hold the ice or the sweep button to carry the stone. Let go to stop sweeping."
			frame = session.frame()
			save_practice()
			if OS.get_name() == "Android": Input.vibrate_handheld(18)
		else: report = error
	update_labels()

func _draw() -> void:
	if not spatial_view:
		draw_style_box(panel(Color("102b37")), Rect2(800, 110, 440, 380))
		# Broad, quiet panels preserve contrast on desktop and landscape phones.
		draw_style_box(panel(Color("102b37")), Rect2(40, 110, 250, 590))
		draw_style_box(panel(Color("102b37")), Rect2(315, 110, 465, 590))
		draw_rect(Rect2(sheet_point(Vector2(-2.375, 2.2)), Vector2(142.5, 550)), ICE)
		for y in [-28.349, -6.401]:
			draw_line(sheet_point(Vector2(-2.375, y)), sheet_point(Vector2(2.375, y)), Color("b3464d"), 3)
		draw_line(sheet_point(Vector2(0, -30)), sheet_point(Vector2(0, 2)), Color("87a1ad"), 1)
		rings(sheet_point(Vector2.ZERO), 30)
		draw_string(font, Vector2(65, 680), "FULL SHEET", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, CYAN)
		draw_rect(Rect2(330, 125, 450, 560), ICE)
		rings(house_point(Vector2.ZERO), 94)
		draw_line(Vector2(555, 125), Vector2(555, 685), Color("96a7af"), 1)
		draw_line(Vector2(330, 325), Vector2(780, 325), Color("96a7af"), 1)
		draw_line(Vector2(330, 153), Vector2(780, 153), Color("b3464d"), 2)
		if path.size() > 1:
			for i in range(1, path.size()):
				draw_line(sheet_point(path[i-1]), sheet_point(path[i]), Color("4b9ea5"), 2)
				if path[i].y > -3.7: draw_line(house_point(path[i-1]), house_point(path[i]), Color("4b9ea5"), 2)
		var bp := house_point(Vector2(float(broom_mm) / 1000.0, 0))
		draw_line(bp - Vector2(0, 35), bp + Vector2(0, 18), INK, 3)
		draw_rect(Rect2(bp - Vector2(18, 6), Vector2(36, 12)), GOLD)
		for s in frame.get("stones", []):
			if s.active:
				stone(sheet_point(s.position), 5.0, s.turns, s.team)
				if s.position.y > -3.6: stone(house_point(s.position), 13.35, s.turns, s.team)
		if run_active and (hold_sweep or sweeping) and not delivered_stone().is_empty():
			var sp: Vector2 = delivered_stone().position + Vector2(0, 0.3)
			draw_line(sheet_point(sp) - Vector2(10, 0), sheet_point(sp) + Vector2(10, 0), GOLD, 5)
		draw_string(font, Vector2(825, 147), "THE DELIVERY", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, CYAN)
		draw_string(font, Vector2(825, 183), "Pull • push • settle • lift", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
		stone(handle_point(), 63, float(turn) / 12.0, int(frame.get("team", 0)))
		if stroke_trace.size() > 1: draw_polyline(stroke_trace, Color(0.91, 0.75, 0.41, 0.5), 2)
		draw_string(font, Vector2(900, 464), "Your hand on the handle", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("92acb7"))

func rings(center: Vector2, scale_m: float) -> void:
	for entry in [[1.829, Color("346f8e")], [1.219, ICE], [0.610, Color("c06462")], [0.152, ICE]]:
		draw_circle(center, entry[0] * scale_m, entry[1])

func stone(center: Vector2, radius: float, turns: float, team := 0) -> void:
	draw_circle(center + Vector2(2, 3), radius + 1, Color(0.03, 0.08, 0.1, 0.3))
	draw_circle(center, radius, Color("727c80"))
	draw_circle(center, radius * 0.78, Color("b9c3c6"))
	var h := Vector2.from_angle(turns * TAU) * radius * 0.62
	draw_line(center - h, center + h, GOLD if team == 0 else CYAN, maxf(3, radius * 0.16), true)
	if team == 1:
		var cross := h.orthogonal() * 0.4
		draw_line(center - cross, center + cross, INK, maxf(2, radius * 0.12), true)
	draw_circle(center, radius * 0.13, INK)

func panel(color: Color) -> StyleBoxFlat:
	var p := StyleBoxFlat.new()
	p.bg_color = color
	p.set_corner_radius_all(14)
	return p

func delivered_stone() -> Dictionary:
	for s in frame.get("stones", []):
		if s.id == frame.get("delivered", -1): return s
	return {}

func next_throw() -> void:
	if session == null or run_active: return
	if match_mode and frame.match_phase == "GameComplete":
		reset()
		return
	if match_mode and frame.match_phase == "EndComplete":
		var end_error: String = session.match_next_end()
		if not end_error.is_empty(): report = end_error
		frame = session.frame()
		previous = frame
		power_side = 0
		own_house = true
		phase = "Choose placement"
		path.clear()
		stroke_trace.clear()
		update_labels()
		save_practice()
		return
	var error: String = session.prepare_next(not frame.get("can_deliver_next", true))
	if not error.is_empty():
		report = error
		update_labels()
		return
	frame = session.frame()
	previous = frame
	phase = "Ready"
	stroke_trace.clear()
	path.clear()
	report = "Aim again. The stones and the ice stay in play.
Fresh ice starts a new practice session."
	update_labels()
	save_practice()

func save_practice() -> void:
	if not persistence_enabled or not save_allowed or session == null: return
	var json: String = session.match_json() if match_mode else session.session_json()
	if json.is_empty():
		save_error("Could not encode the current session.")
		return
	var destination := match_save_path if match_mode else save_path
	var temp := destination + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		save_error("Could not save on this device.")
		return
	file.store_string(json)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		save_error("Could not finish saving.")
		return
	var target := ProjectSettings.globalize_path(destination)
	var backup := target + ".bak"
	if FileAccess.file_exists(target):
		if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(target, backup) != OK:
			save_error("Could not retain the previous save.")
			return
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), target) != OK:
		save_error("Could not finish saving; the previous save is retained.")
		return
	last_save_tick = session.frame().global_tick

func save_error(message: String) -> void:
	save_allowed = false
	report = message + " Your current session can continue."
	if report_label != null: report_label.text = report

func restore_practice() -> void:
	restore_current(false)

func restore_match() -> void:
	restore_current(true)

func restore_current(is_match: bool) -> void:
	if not persistence_enabled: return
	var found := false
	var source := match_save_path if is_match else save_path
	for filename in [source, source + ".bak"]:
		if not FileAccess.file_exists(filename): continue
		found = true
		var file := FileAccess.open(filename, FileAccess.READ)
		if file == null or file.get_length() > 16 * 1024 * 1024: continue
		var json := file.get_as_text()
		file.close()
		var error: String = session.load_match(json) if is_match else session.load_session(json)
		if not error.is_empty(): continue
		match_mode = is_match
		frame = session.frame()
		previous = frame
		run_active = frame.match_phase == "InFlight" if is_match else not frame.resting
		phase = "Travel" if run_active else "Ready"
		last_save_tick = frame.global_tick
		release_report = {"speed_mm_s": int(frame.get("release_speed", 0.0) * 1000.0)}
		report = ("Match" if is_match else "Practice") + " restored. The ice and your stones are just as you left them."
		update_labels()
		return
	if found:
		save_error("The saved session could not be restored. Existing files are retained; start a new session to replace them.")

func run_self_test() -> void:
	var actual: String = session.golden_trace()
	var expected := FileAccess.get_file_as_string("res://validation/golden.txt")
	var nonce := self_test_nonce if not self_test_nonce.is_empty() else "local"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--probe-id="): nonce = argument.trim_prefix("--probe-id=")
	var transport_ready := CurlTransport.available()
	var result := {"ok": not expected.is_empty() and actual == expected and transport_ready, "transport_ready": transport_ready, "nonce": nonce, "trace": actual, "platform": OS.get_name()}
	DirAccess.make_dir_recursive_absolute("user://diagnostics")
	var file := FileAccess.open("user://diagnostics/self-test.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result))
		file.close()
	print("PEBBLE_SELF_TEST_RESULT " + JSON.stringify(result))
	get_tree().quit(0 if result.ok else 1)
