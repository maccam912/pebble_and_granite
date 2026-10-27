class_name CurlDrills
extends RefCounted
## Five-shot learn-to-curl rounds. The core grades actual settled outcomes.
const NAMES := ["Weight to the tee", "Front guard", "Alternate line", "Sweep it home"]
const HELP := ["Aim for tee depth. This drill grades weight, so sideways error is ignored.", "Stop on the front guard target, short of the rings.", "Draw to the marked side. Targets alternate left and right.", "Start a slightly light AI draw, then judge weight and sweep it to the button."]
var game
var enabled := false
var kind := 0
var attempt := 0
var results: Array = []
var best: Array = [0, 0, 0, 0]
var save_path := "user://target-drills.json"
var menu_button: Button
var start_button: Button
var choice: OptionButton
var target_label: Label
var target_background: Panel

func _init(owner_game) -> void:
	game = owner_game

func create_controls() -> void:
	menu_button = game.button("Drills", Vector2(650, 77), toggle)
	menu_button.custom_minimum_size = Vector2(165, 38)
	menu_button.size = menu_button.custom_minimum_size
	choice = OptionButton.new()
	choice.position = Vector2(995, 134)
	choice.size = Vector2(225, 48)
	for item in NAMES: choice.add_item(item)
	choice.item_selected.connect(func(value): kind = value; game.reset())
	game.add_child(choice)
	start_button = game.button("Start sweeping draw", Vector2(940, 555), start_sweeping)
	start_button.custom_minimum_size = Vector2(280, 52)
	start_button.theme_type_variation = "PrimaryButton"
	target_background = Panel.new()
	target_background.position = Vector2(450, 136)
	target_background.size = Vector2(530, 48)
	target_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_background.add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11252f"), CurlPresentation.GOLD))
	game.add_child(target_background)
	target_label = Label.new()
	target_label.position = Vector2(12, 8)
	target_label.add_theme_font_size_override("font_size", 21)
	target_background.add_child(target_label)
	refresh_controls()

func toggle() -> void:
	if game.run_active or game.pointer != -99: return
	game.save_practice()
	enabled = not enabled
	if game.solo != null: game.solo.enabled = false
	game.match_mode = false
	game.reset(false)
	game.restore_current(false)
	game.update_labels()
	game.update_spatial(0)

func reset_round() -> void:
	attempt = 0
	results.clear()
	game.report = HELP[kind] + "\nFive attempts. Target rings: 15 cm / 45 cm / 90 cm."

func start_sweeping() -> void:
	if not enabled or kind != 3 or game.run_active or results.size() > attempt: return
	var error: String = game.session.start_sweeping_drill(attempt)
	if not error.is_empty(): game.report = error; return
	game.frame = game.session.frame()
	game.previous = game.frame
	game.run_active = not game.frame.resting
	game.phase = "Travel"
	game.accumulator = 0.0
	game.release_report = {"speed_mm_s": int(game.frame.release_speed * 1000.0)}
	game.report = "The draw is a little light. Sweep to carry it onto the target."
	game.save_practice()
	game.update_labels()

func advance() -> void:
	if not enabled or game.run_active or game.phase != "Stone at rest" or results.size() != attempt: return
	var score: Dictionary = game.session.drill_result(kind, attempt)
	if score.is_empty(): return
	results.append(score)
	if results.size() == 5: best[kind] = maxi(int(best[kind]), points())
	var distance := "Out of play · 0 stars" if not score.in_play else "%d cm error · %d / 3 stars" % [roundi(score.error_mm / 10.0), score.stars]
	game.report = distance + "\n" + ("Round complete: %d / 15 stars. Best: %d / 15." % [points(), best[kind]] if results.size() == 5 else "Next target to continue the five-shot round.")
	game.save_practice()
	game.update_labels()

func points() -> int:
	var total := 0
	for score in results: total += int(score.stars)
	return total

func next_target() -> void:
	if results.size() <= attempt:
		game.report = "Finish this target first."
		game.update_labels()
		return
	if results.size() == 5:
		game.reset()
		return
	var error: String = game.session.prepare_next(true)
	if not error.is_empty(): game.report = error; return
	attempt += 1
	game.frame = game.session.frame()
	game.previous = game.frame
	game.phase = "Ready"
	game.path.clear()
	game.stroke_trace.clear()
	game.sweep_input.target = -1
	game.report = HELP[kind]
	game.update_labels()
	game.update_spatial(0)
	game.save_practice()

func target() -> Vector2:
	var data: Dictionary = game.session.drill_target(kind, attempt)
	return Vector2(float(data.get("x_mm", 0)) / 1000.0, float(data.get("y_mm", 0)) / 1000.0)

func update_view() -> void:
	if game.rink == null: return
	game.rink.drill_target = target() if enabled else Vector2.INF

func refresh_controls() -> void:
	if menu_button == null: return
	menu_button.visible = not game.match_mode
	menu_button.text = "Practice" if enabled else "Drills"
	menu_button.disabled = game.run_active or game.pointer != -99
	choice.visible = enabled
	choice.disabled = game.run_active or not game.frame.get("in_hand", {}).is_empty()
	start_button.visible = enabled and kind == 3 and not game.run_active and results.size() == attempt
	target_background.visible = enabled
	if not enabled: return
	game.hint.text = "TARGET DRILLS · Five shots · Autosaved"
	game.status.text = "%s  /  %s" % [NAMES[kind], game.phase]
	var at := target()
	var detail := "Tee depth" if kind == 0 else ("Front guard" if kind == 1 else ("Left target" if at.x < 0 else "Right target" if at.x > 0 else "Button"))
	target_label.text = "%s · Shot %d / 5 · %d stars" % [detail, attempt + 1, points()]
	if game.frame.get("in_hand", {}).is_empty():
		game.new_button.text = "New round" if results.size() == 5 else "Next target"
		game.new_button.disabled = game.run_active or results.size() <= attempt
	game.fresh_button.text = "Restart drill"

func save_envelope(session_json: String) -> String:
	return JSON.stringify({"schema": 1, "session": session_json, "kind": kind, "attempt": attempt, "results": results, "best": best})

func valid_envelope(data: Variant) -> bool:
	if not data is Dictionary or data.get("schema") != 1 or not data.get("session") is String: return false
	for key in ["kind", "attempt"]:
		if not (data.get(key) is float or data.get(key) is int) or not is_finite(float(data[key])) or float(data[key]) != floorf(float(data[key])): return false
	if data.kind < 0 or data.kind > 3 or data.attempt < 0 or data.attempt > 4: return false
	if not data.get("results") is Array or data.results.size() < data.attempt or data.results.size() > data.attempt + 1: return false
	for score in data.results:
		if not score is Dictionary or not score.get("in_play") is bool: return false
		for key in ["stars", "error_mm"]:
			if not (score.get(key) is float or score.get(key) is int) or not is_finite(float(score[key])) or float(score[key]) != floorf(float(score[key])): return false
		if score.stars < 0 or score.stars > 3 or score.error_mm < 0 or score.error_mm > 100000: return false
	if not data.get("best") is Array or data.best.size() != 4: return false
	for value in data.best:
		if not (value is float or value is int) or not is_finite(float(value)) or value < 0 or value > 15 or float(value) != floorf(float(value)): return false
	return true

func restore_metadata(data: Dictionary) -> void:
	kind = int(data.kind)
	attempt = int(data.attempt)
	results = data.results
	best = data.best
	choice.select(kind)
	if game.frame.resting and int(game.frame.get("delivered", -1)) >= 0:
		game.phase = "Stone at rest"
	if results.size() > attempt:
		game.phase = "Stone at rest"
		game.report = "Drill restored. %d / 15 stars; continue with Next target." % points()
