extends Control

const ICE := Color("dfecef")
const INK := Color("0b2330")
const GOLD := Color("eabf69")
const CYAN := Color("64cdd1")
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

func _ready() -> void:
	Input.use_accumulated_input = false
	if not ClassDB.class_exists("CurlSession"):
		push_error("Build the Rust bridge: python3 tools/build_native.py")
		return
	session = ClassDB.instantiate("CurlSession")
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
	new_button = button("New stone", Vector2(40, 726), func(): reset())
	turn_button = button("Turn: clockwise ↻", Vector2(225, 726), func(): turn *= -1; update_labels())
	sweep_button = button("Hold to sweep", Vector2(500, 726), func(): pass)
	sweep_button.button_down.connect(func(): hold_sweep = true)
	sweep_button.button_up.connect(func(): hold_sweep = false)
	one_button = button("One-push: off", Vector2(710, 726), func(): one_push = not one_push; update_labels())
	reset()

func button(text: String, pos: Vector2, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = Vector2(165, 48)
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(action)
	add_child(b)
	return b

func reset() -> void:
	if session == null: return
	session.reset(42)
	frame = session.frame()
	previous = frame
	phase = "Ready"
	pointer = -99
	dragging_broom = false
	sweeping = false
	hold_sweep = false
	run_active = false
	accumulator = 0.0
	path.clear()
	stroke_trace.clear()
	report = "Drag the broom in the house.\nGrip the stone below, pull back, push forward, hold steady, then lift."
	update_labels()
	queue_redraw()

func update_labels() -> void:
	status.text = "PEBBLE & GRANITE  /  " + phase
	hint.text = "FEEL LAB     •     Seed 42     •     Mouse / trackpad / touch"
	turn_button.text = "Turn: clockwise ↻" if turn == 1 else "Turn: counterclockwise ↺"
	one_button.text = "One-push: on" if one_push else "One-push: off"
	turn_button.size.x = 255
	turn_button.disabled = run_active
	one_button.disabled = run_active
	report_label.text = report

func sheet_point(p: Vector2) -> Vector2:
	return Vector2(168 + p.x * 30, 125 + (2.2 - p.y) * 17)

func house_point(p: Vector2) -> Vector2:
	return Vector2(555 + p.x * 94, 325 - p.y * 94)

func handle_point() -> Vector2:
	return Vector2(1030, 365)

func _process(delta: float) -> void:
	if session == null: return
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
				path.append(frame.stones[0].position)
			if frame.resting:
				run_active = false
				phase = "Stone at rest"
				var s: Dictionary = frame.stones[0]
				var split := "—" if frame.hog_tick < 0 else "%.2f s" % (float(frame.hog_tick) / 240.0)
				report = "Release %.3f m/s\nHog-to-hog %s\n%.2f rotations • %.2f s travel\nRest: %.2f m across, %.2f m from tee\n%s" % [float(release_report.get("speed_mm_s", 0)) / 1000.0, split, s.turns, float(frame.tick) / 240.0, s.position.x, s.position.y, "In play" if s.active else "Out of play"]
				update_labels()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		pointer = -99
		hold_sweep = false
		sweeping = false
		dragging_broom = false
		if session != null:
			session.cancel_stroke()
			if not run_active and phase != "Stone at rest":
				phase = "Ready"
				update_labels()

func _input(event: InputEvent) -> void:
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
	if pointer != -99 or p.y > 710: return
	if run_active:
		# The lab's accessible hold gesture follows the stone's brush position.
		if p.x < 780:
			pointer = id
			sweeping = true
		return
	if p.distance_to(house_point(Vector2(float(broom_mm) / 1000.0, 0))) < 55:
		pointer = id
		dragging_broom = true
	elif phase == "Ready" and p.distance_to(handle_point()) < 80:
		pointer = id
		var q := units(p)
		session.grip(input_clock.call(), q.x, q.y, one_push)
		stroke_trace = PackedVector2Array([p])
		phase = "Grip"
		update_labels()

func move_pointer(p: Vector2) -> void:
	if dragging_broom:
		broom_mm = clampi(int((p.x - 555) / 94.0 * 1000), -2200, 2200)
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
		return
	if run_active:
		sweeping = false
		return
	var q := units(p)
	release_report = session.lift(input_clock.call(), q.x, q.y)
	if not release_report.valid:
		phase = "Ready"
		report = "Try a smooth pull-back, then forward stroke. Lift after the push. A simple click does not throw."
	else:
		var error: String = session.deliver(release_report.speed_mm_s, clampi(broom_mm + release_report.line_mm, -2200, 2200), turn)
		if error.is_empty():
			run_active = true
			phase = "Travel"
			report = "Hold the ice or the sweep button to carry the stone. Let go to stop sweeping."
			frame = session.frame()
			if OS.get_name() == "Android": Input.vibrate_handheld(18)
		else: report = error
	update_labels()

func _draw() -> void:
	# Broad, quiet panels preserve contrast on desktop and landscape phones.
	draw_style_box(panel(Color("102b37")), Rect2(40, 110, 250, 590))
	draw_style_box(panel(Color("102b37")), Rect2(315, 110, 465, 590))
	draw_style_box(panel(Color("102b37")), Rect2(800, 110, 440, 380))
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
			stone(sheet_point(s.position), 5.0, s.turns)
			if s.position.y > -3.6: stone(house_point(s.position), 13.35, s.turns)
	if run_active and (hold_sweep or sweeping) and not frame.stones.is_empty():
		var sp: Vector2 = frame.stones[0].position + Vector2(0, 0.3)
		draw_line(sheet_point(sp) - Vector2(10, 0), sheet_point(sp) + Vector2(10, 0), GOLD, 5)
	draw_string(font, Vector2(825, 147), "THE DELIVERY", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, CYAN)
	draw_string(font, Vector2(825, 183), "Pull • push • settle • lift", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	stone(handle_point(), 63, float(turn) / 12.0)
	if stroke_trace.size() > 1: draw_polyline(stroke_trace, Color(0.91, 0.75, 0.41, 0.5), 2)
	draw_string(font, Vector2(900, 464), "Your hand on the handle", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("92acb7"))

func rings(center: Vector2, scale_m: float) -> void:
	for entry in [[1.829, Color("346f8e")], [1.219, ICE], [0.610, Color("c06462")], [0.152, ICE]]:
		draw_circle(center, entry[0] * scale_m, entry[1])

func stone(center: Vector2, radius: float, turns: float) -> void:
	draw_circle(center + Vector2(2, 3), radius + 1, Color(0.03, 0.08, 0.1, 0.3))
	draw_circle(center, radius, Color("727c80"))
	draw_circle(center, radius * 0.78, Color("b9c3c6"))
	var h := Vector2.from_angle(turns * TAU) * radius * 0.62
	draw_line(center - h, center + h, GOLD, maxf(3, radius * 0.16), true)
	draw_circle(center, radius * 0.13, INK)

func panel(color: Color) -> StyleBoxFlat:
	var p := StyleBoxFlat.new()
	p.bg_color = color
	p.set_corner_radius_all(14)
	return p
