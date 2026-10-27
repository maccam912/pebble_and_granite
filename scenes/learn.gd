extends "res://scenes/lab.gd"
## Disposable lessons use ordinary input and authority, never the player's save.
const TITLES := ["Place the broom", "Find draw weight", "Add finishing curl", "Sweep, then stop"]
const INSTRUCTIONS := [
	"Drag the broom onto the gold target, then lift. The broom sets your delivery line.",
	"Grip the handle. Pull back, push smoothly forward, hold briefly, then lift. Stop near tee depth; sideways error does not matter here.",
	"Make another delivery. Once sliding, nudge left or right, then lift. Sideways movement before sliding sets line; after sliding it adds curl.",
	"Start the practice draw. Scrub across the ice just ahead of the moving stone, or hold the sweep button. Sweep for half a second, then lift to stop."
]
var return_game: Control
var step := 0
var passed := false
var graded := false
var swept_ticks := 0
var aim_moved := false
var lesson_card: Panel
var lesson_title: Label
var lesson_help: Label
var lesson_result: Label
var continue_button: Button
var retry_button: Button
var skip_button: Button
var start_button: Button

func _init() -> void:
	spatial_view = true
	allow_online = false
	lesson_mode = true
	persistence_enabled = false

func _ready() -> void:
	super._ready()
	lesson_card = Panel.new()
	lesson_card.position = Vector2(850, 224)
	lesson_card.size = Vector2(370, 420)
	lesson_card.mouse_filter = Control.MOUSE_FILTER_STOP
	lesson_card.add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11252f"), CurlPresentation.GOLD, 12))
	add_child(lesson_card)
	lesson_title = lesson_label(Vector2(20, 18), Vector2(330, 58), 24)
	lesson_help = lesson_label(Vector2(20, 86), Vector2(330, 160), 20)
	lesson_result = lesson_label(Vector2(20, 260), Vector2(330, 130), 20)
	lesson_result.add_theme_color_override("font_color", CurlPresentation.GOLD)
	continue_button = button("Next lesson", Vector2(1000, 726), next_lesson)
	continue_button.custom_minimum_size.x = 240
	continue_button.theme_type_variation = "PrimaryButton"
	retry_button = button("Try again", Vector2(40, 726), prepare_lesson)
	skip_button = button("Skip this step", Vector2(700, 726), skip_lesson)
	start_button = button("Start practice draw", Vector2(850, 150), start_draw)
	start_button.custom_minimum_size.x = 370
	button("Return to game", Vector2(1020, 30), leave_lesson).custom_minimum_size.x = 220
	prepare_lesson()

func lesson_label(at: Vector2, dimensions: Vector2, pixels: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", pixels)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lesson_card.add_child(label)
	return label

func prepare_lesson() -> void:
	reset(false)
	passed = false
	graded = false
	swept_ticks = 0
	aim_moved = false
	broom_mm = -900
	rink.mode = 4 if step == 0 else 0
	rink.zoomed = false
	camera_button.text = "Camera: House" if step == 0 else "Camera: Auto"
	rink.drill_target = Vector2(.7, 0) if step == 0 else Vector2.INF
	lesson_title.text = "%d / 4 · %s" % [step + 1, TITLES[step]]
	lesson_help.text = INSTRUCTIONS[step]
	lesson_result.text = "One-push is available below if the full stroke is uncomfortable." if step in [1, 2] else ""
	update_labels()
	update_spatial(0)

func update_labels() -> void:
	super.update_labels()
	for control in [mode_button, fresh_button, new_button, settings_button, turn_button, view_button, shot_clock]:
		if control != null: control.hide()
	if lesson_card == null: return
	status.text = "Learn to play  /  " + phase
	hint.text = "A separate practice sheet · Return whenever you like"
	one_button.visible = step in [1, 2]
	one_button.position = Vector2(235, 726)
	sweep_button.visible = step == 3
	continue_button.disabled = not passed
	continue_button.text = "Finish lesson" if step == 3 else "Next lesson"
	skip_button.text = "Finish for now" if step == 3 else "Skip this step"
	start_button.visible = step == 3 and not run_active and phase == "Ready"
	# The short live gesture/sweep cue remains; the lesson card carries the help.
	feedback_bg.visible = phase in ["Grip", "Pull", "Drive", "Slide", "Travel"]
	report_label.visible = feedback_bg.visible

func begin_pointer(id: int, p: Vector2) -> void:
	if lesson_card != null and lesson_card.get_global_rect().has_point(p): return
	if step == 0 and p.distance_to(broom_screen_point()) >= 55: return
	if step == 3 and not run_active: return
	super.begin_pointer(id, p)

func move_pointer(p: Vector2) -> void:
	var was_aiming := dragging_broom
	super.move_pointer(p)
	if was_aiming: aim_moved = true

func _process(delta: float) -> void:
	var before := int(frame.get("global_tick", 0))
	var brush := current_brush()
	super._process(delta)
	if lesson_card == null or local_menu_open() or suspended: return
	if step == 0 and aim_moved and not dragging_broom:
		passed = absi(broom_mm - 700) <= 200
		lesson_result.text = "Line set. Gripping the handle returns you to the delivery view." if passed else "Move the broom closer to the gold target, then lift."
	elif step == 1 and phase == "Stone at rest" and not graded:
		graded = true
		var stone := delivered_stone()
		var depth: float = stone.get("position", Vector2.ZERO).y
		passed = bool(stone.get("active", false)) and absf(depth) <= 2.0
		lesson_result.text = "Good draw weight: within 2 m of tee depth." if passed else ("Short of the target. Try a slightly faster forward push." if depth < 0 else "Past the target. Try a slightly slower forward push.")
		if frame.get("violation", "") == "HogRelease": lesson_result.text = "You held past the hog line. Lift sooner on the next try."
	elif step == 2 and run_active and not graded:
		graded = true
		passed = int(release_report.get("turn", 0)) != 0
		lesson_result.text = "Curl %s recognized. Watch the handle rotate and the path bend." % ("left" if turn < 0 else "right") if passed else "Neutral release. Try again: nudge sideways after the slide begins, then lift."
	elif step == 2 and phase == "Stone at rest" and not graded:
		graded = true
		lesson_result.text = "Lift before the hog line. Try again, adding a small sideways finish once sliding."
	elif step == 3 and not passed:
		if int(brush.get("effort", 0)) > 0: swept_ticks += maxi(0, int(frame.get("global_tick", 0)) - before)
		if run_active and swept_ticks >= 120 and current_brush().is_empty() and not hold_sweep and not sweeping:
			passed = true
			lesson_result.text = "Sweep and stop complete. Try the weight drill next, or return here to repeat any skipped steps."
		elif swept_ticks >= 120: lesson_result.text = "Sweeping registered. Lift or release the button to stop."
		elif run_active: lesson_result.text = "Useful sweeping: %.1f / 0.5 seconds" % (swept_ticks / 240.0)
		elif phase == "Stone at rest": lesson_result.text = "The stone stopped. Try again and sweep while it is moving."
	update_labels()

func start_draw() -> void:
	if run_active or step != 3: return
	var error: String = session.start_sweeping_drill(0)
	if not error.is_empty(): lesson_result.text = error; return
	frame = session.frame()
	previous = frame
	run_active = not frame.resting
	phase = "Travel"
	rink.mode = 2
	camera_button.text = "Camera: Sweeper"
	report = "Brush just ahead of the moving stone, or hold to sweep."
	update_labels()
	update_spatial(0)

func next_lesson() -> void:
	if not passed: return
	skip_lesson()

func skip_lesson() -> void:
	if step == 3: leave_lesson(); return
	step += 1
	prepare_lesson()

func leave_lesson() -> void:
	cancel_pointer()
	if is_instance_valid(return_game): return_game.close_lessons()
	else: queue_free()
