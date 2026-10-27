class_name CurlSoloGame
extends RefCounted
## Assigns seven AI seats around one human. Rust plans/executes every AI release.
var game
var enabled := false
var planning := false
var planned: Dictionary = {}
var delay := 0.0
var advice_time := 0.0
var ai_effort := 0
var weight_zone := 0
var call_override := -1
var last_spoken := ""
var last_spoken_ms := -2000
var last_count := -1
var shot_team := 0
var solo_button: Button
var send_button: Button
var call_buttons: Array[Button] = []
var call_label: Label
var call_background: Panel
var save_path := "user://solo-teams.json"

func _init(owner_game) -> void:
	game = owner_game

func create_controls() -> void:
	solo_button = game.button("Solo 4 vs 4", Vector2(830, 77), start)
	solo_button.custom_minimum_size = Vector2(220, 38)
	solo_button.size = solo_button.custom_minimum_size
	send_button = game.button("Send called shot", Vector2(960, 555), send_shot)
	send_button.custom_minimum_size = Vector2(260, 52)
	send_button.theme_type_variation = "PrimaryButton"
	for i in range(3):
		var effort: int = [255, 80, 0][i]
		var b: Button = game.button(["↑ HARD", "≈ CLEAN", "■ OFF"][i], Vector2(750 + i * 160, 640), func(): set_call(effort))
		b.custom_minimum_size = Vector2(150, 48)
		b.size = b.custom_minimum_size
		call_buttons.append(b)
	call_background = Panel.new()
	call_background.position = Vector2(450, 136)
	call_background.size = Vector2(540, 48)
	call_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_background.add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11252f"), CurlPresentation.GOLD))
	game.add_child(call_background)
	call_label = Label.new()
	call_label.position = Vector2(12, 8)
	call_label.add_theme_font_size_override("font_size", 21)
	call_background.add_child(call_label)
	refresh_controls()

func human_position() -> int:
	return game.play_settings.human_position

func human_throws() -> bool:
	return game.frame.get("team", -1) == 0 and game.frame.get("thrower", -1) == human_position()

func human_skips() -> bool:
	# Vice calls the skip's deliveries; the skip calls the other three positions.
	var caller := 2 if game.frame.get("thrower", -1) == 3 else 3
	return game.frame.get("team", -1) == 0 and human_position() == caller

func start() -> void:
	if game.run_active or game.pointer != -99: return
	game.save_practice()
	enabled = true
	game.match_mode = true
	game.reset(false)
	game.restore_current(true)
	reset_turn()
	game.update_labels()
	game.update_spatial(0)

func reset_turn() -> void:
	planning = false
	planned.clear()
	last_spoken = ""
	delay = 0.0
	advice_time = 0.0
	ai_effort = 0
	call_override = -1
	weight_zone = 0
	last_count = int(game.frame.get("delivered_count", -1))
	shot_team = int(game.frame.get("team", 0))

func advance(delta: float) -> void:
	if not enabled: return
	var state: String = game.frame.get("match_phase", "")
	if game.run_active:
		advice_time -= delta
		if advice_time <= 0:
			advice_time = .6
			var advice: Dictionary = game.session.solo_advice(game.play_settings.difficulty)
			ai_effort = int(advice.get("effort", 0))
			weight_zone = int(advice.get("zone", 0))
			speak_call()
		return
	if state != "Calling": return
	if game.phase == "Stone at rest":
		delay += delta
		if delay >= 2.0: game.next_throw(); reset_turn()
		return
	if int(game.frame.get("delivered_count", -1)) != last_count: reset_turn()
	if human_throws(): return
	if not planning and planned.is_empty():
		var error: String = game.session.request_ai_plan()
		if not error.is_empty(): game.report = error; return
		planning = true
		game.report = "AI skip is reading the house…"
	if planning:
		var result: Dictionary = game.session.poll_ai_plan()
		if result.is_empty(): return
		planning = false
		if result.has("error"):
			game.report = result.error
			return
		planned = result
		game.broom_mm = int(result.broom_mm)
		game.turn = int(result.turn)
		game.report = "%s calls %s • %s turn.\n%s" % ["Your team" if game.frame.team == 0 else "Cyan skip", result.kind.to_lower(), "right" if game.turn > 0 else "left", "Use House camera to adjust the broom, then Send called shot." if human_skips() else "The AI thrower will deliver; follow the skip's visible calls."]
		delay = 0.0
	if not planned.is_empty() and not human_skips():
		delay += delta
		if delay >= 1.3: send_shot()

func send_shot() -> void:
	if not enabled or planned.is_empty() or game.run_active or game.pointer != -99: return
	var error: String = game.session.execute_ai_plan(game.broom_mm, game.turn, game.play_settings.difficulty)
	if not error.is_empty(): game.report = error; return
	planned.clear()
	planning = false
	game.frame = game.session.frame()
	game.previous = game.frame
	game.run_active = not game.frame.resting
	game.phase = "Travel"
	game.accumulator = 0.0
	game.release_report = {"speed_mm_s": int(game.frame.release_speed * 1000.0)}
	shot_team = game.frame.team
	advice_time = 0.0
	game.report = "Watch the skip's calls. Scrub ahead of the stone or hold to sweep." if shot_team == 0 else "Cyan is delivering."
	game.save_practice()
	game.update_labels()

func set_call(effort: int) -> void:
	if not enabled or not game.run_active or not human_skips(): return
	call_override = effort
	speak_call()
	game.update_labels()

func speak_call() -> void:
	if not game.persistence_enabled or not game.play_settings.spoken_calls: return
	var effort := call_override if human_skips() and call_override >= 0 else ai_effort
	var text := "Hurry hard!" if effort > 100 else ("Clean." if effort > 0 else "Off! Whoa.")
	if text == last_spoken or Time.get_ticks_msec() - last_spoken_ms < 1500: return
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty(): return
	last_spoken = text
	last_spoken_ms = Time.get_ticks_msec()
	DisplayServer.tts_speak(text, voices[0], 90, 1.0, 1.0, 0, true)

func save_envelope(match_json: String) -> String:
	return JSON.stringify({"schema": 1, "match": match_json, "position": human_position(), "difficulty": game.play_settings.difficulty,
		"target_x_mm": game.frame.get("solo_target_x_mm", 0), "target_y_mm": game.frame.get("solo_target_y_mm", 0)})

func valid_envelope(data: Variant) -> bool:
	if not data is Dictionary or data.get("schema") != 1 or not data.get("match") is String: return false
	for key in ["position", "difficulty", "target_x_mm", "target_y_mm"]:
		if not (data.get(key) is float or data.get(key) is int) or not is_finite(float(data[key])) or float(data[key]) != floorf(float(data[key])): return false
	return data.position >= 0 and data.position <= 3 and data.difficulty >= 0 and data.difficulty <= 2 and absi(int(data.target_x_mm)) <= 2200 and data.target_y_mm >= -5000 and data.target_y_mm <= 1800

func restore_metadata(data: Dictionary) -> void:
	game.play_settings.human_position = int(data.position)
	game.play_settings.position_choice.select(int(data.position))
	game.play_settings.difficulty = int(data.difficulty)
	game.play_settings.difficulty_choice.select(int(data.difficulty))
	game.session.set_solo_target(int(data.target_x_mm), int(data.target_y_mm))

func brush_effort() -> int:
	if human_skips() and call_override >= 0: return call_override
	# Human sweepers supply one half; the AI partner supplies the other half.
	return ai_effort if human_skips() or shot_team != 0 else int(ai_effort / 2)

func fast_forwarding() -> bool:
	if not enabled or not game.run_active or not game.play_settings.fast_opponents or shot_team != 1: return false
	var stone: Dictionary = game.delivered_stone()
	# Whole stone must be beyond the near hog and short of the far hog.
	return not stone.is_empty() and stone.active and stone.position.y > -28.207 and stone.position.y < -6.543

func fast_step_limit(steps: int) -> int:
	var stone: Dictionary = game.delivered_stone()
	if stone.is_empty(): return steps
	var speed: float = stone.get("velocity", Vector2.ZERO).y
	if speed <= 0: return steps
	return mini(steps, maxi(1, floori((-6.543 - stone.position.y) / speed * 240.0)))

func update_camera() -> void:
	if game.rink == null: return
	game.rink.role_camera = ""
	if not enabled: return
	if game.run_active:
		game.rink.role_camera = "Skip" if human_skips() or shot_team != 0 else "Sweeper"
	elif game.frame.get("match_phase", "") == "Calling" and not human_throws():
		game.rink.role_camera = "House" if human_skips() else "Skip"

func refresh_controls() -> void:
	if solo_button == null: return
	solo_button.disabled = game.run_active or game.pointer != -99
	solo_button.text = "Solo 4 vs 4" if not enabled else "Resume solo"
	solo_button.visible = not enabled
	var owns_call := enabled and human_skips()
	for b in call_buttons:
		b.visible = owns_call and game.run_active
	send_button.visible = owns_call and not game.run_active and not planned.is_empty()
	call_background.visible = enabled and game.run_active
	if not enabled: return
	var effort := call_override if owns_call and call_override >= 0 else ai_effort
	var text := "↑ HARD · SWEEP" if effort > 100 else ("≈ CLEAN · LIGHT BRUSH" if effort > 0 else "■ OFF · NO SWEEP")
	call_label.text = "%s  |  Weight zone %d" % [text, weight_zone] if weight_zone > 0 else (text if call_override >= 0 else "Reading weight…")
	if fast_forwarding(): call_label.text += "  |  4×"
	game.hint.text = "SOLO TEAMS · You: Gold %s · %s AI · Autosaved" % [CurlPlaySettings.POSITIONS[human_position()], ["Club", "Competitive", "Elite"][game.play_settings.difficulty]]
	var state: String = game.frame.get("match_phase", "")
	if state == "Calling" or state == "InFlight":
		game.status.text = "4 vs 4  /  %s %s%s • %s" % [game.team_name(game.frame.team), CurlPlaySettings.POSITIONS[game.frame.thrower], " (you)" if human_throws() else " (AI)", game.phase]
		if not game.run_active and game.phase != "Stone at rest" and not human_throws(): game.new_button.disabled = true
	if state == "EndComplete": game.status.text = "4 vs 4  /  End complete"
	elif state == "GameComplete": game.status.text = "4 vs 4  /  %s wins" % game.team_name(game.frame.winner)
	if game.run_active: game.new_button.text = "Stone in play"
	game.mode_button.text = "Practice"
	game.turn_button.visible = owns_call and not game.run_active and not planned.is_empty()
	if game.spatial_view and game.turn_button.visible:
		game.turn_button.position = Vector2(960, 490)
	game.clock_label.text = "Gold %s  •  Cyan %s" % [game.clock_text(game.frame.clock_gold), game.clock_text(game.frame.clock_cyan)]
	game.clock_label.size.x = 300
