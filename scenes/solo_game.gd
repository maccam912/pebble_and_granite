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
var shot_choice: OptionButton
var auto_button: Button
var choice_waiting := false
var accept_button: Button
var restore_button: Button
var called_target := Vector2.ZERO
var call_label: Label
var call_background: Panel
var shot_card: CurlShotCall
var restored_call: Dictionary = {}
var turn_buttons: Array[Button] = []
var skip_aid: CurlSkipAid
var keep_broom := false
var caller_broom := -900
var caller_turn := 1
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
	accept_button = game.button("Accept current positions", Vector2(800, 490), func(): choose_remedy(false))
	restore_button = game.button("Restore original positions", Vector2(800, 560), func(): choose_remedy(true))
	for item in [accept_button, restore_button]:
		item.custom_minimum_size = Vector2(420, 58)
		item.size = item.custom_minimum_size
	restore_button.theme_type_variation = "PrimaryButton"
	shot_choice = OptionButton.new()
	shot_choice.position = Vector2(960, 490)
	shot_choice.size = Vector2(260, 52)
	for kind in ["Draw weight", "Guard weight", "Takeout weight"]: shot_choice.add_item(kind)
	shot_choice.item_selected.connect(revise_kind)
	game.add_child(shot_choice)
	# Weight is a call; the player owns the line and curl judgement.
	auto_button = game.button("Suggest a shot", Vector2(960, 295), suggest_again)
	auto_button.custom_minimum_size = Vector2(260, 52)
	for direction in [1, -1]:
		var b: Button = game.button("In-turn · curl right" if direction == 1 else "Out-turn · curl left", Vector2(960, 360 if direction == 1 else 425), func(): select_turn(direction))
		b.custom_minimum_size = Vector2(260, 52)
		b.size = b.custom_minimum_size
		b.toggle_mode = true
		turn_buttons.append(b)
	skip_aid = CurlSkipAid.new()
	game.add_child(skip_aid)
	skip_aid.game = game
	for i in range(3):
		var effort: int = [255, 80, 0][i]
		var b: Button = game.button(["↑ HARD", "≈ CLEAN", "■ OFF"][i], Vector2(750 + i * 160, 622), func(): set_call(effort))
		b.custom_minimum_size = Vector2(150, 64)
		b.size = b.custom_minimum_size
		b.add_theme_font_size_override("font_size", 18)
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
	shot_card = CurlShotCall.new()
	game.add_child(shot_card)
	shot_card.setup(game)
	refresh_controls()

func human_position() -> int:
	return game.play_settings.human_position

func human_throws() -> bool:
	return game.frame.get("team", -1) == 0 and (human_position() == 4 or game.frame.get("thrower", -1) == human_position())

func human_skips() -> bool:
	# Vice calls the skip's deliveries; the skip calls the other three positions.
	var caller := 2 if game.frame.get("thrower", -1) == 3 else 3
	return game.frame.get("team", -1) == 0 and (human_position() in [4, 5] or human_position() == caller)

func start() -> void:
	if game.run_active or game.pointer != -99: return
	game.save_practice()
	if game.drills != null: game.drills.enabled = false
	enabled = true
	game.match_mode = true
	game.reset(false)
	game.restore_current(true)
	reset_turn()
	game.update_labels()
	game.update_spatial(0)

func reset_turn() -> void:
	keep_broom = false
	if human_skips() and not human_throws():
		game.broom_mm = caller_broom
		game.turn = caller_turn
	planning = false
	planned.clear()
	if not game.frame.get("in_hand", {}).is_empty() and not restored_call.is_empty():
		planned = restored_call.duplicate()
		called_target = Vector2(float(planned.target_x_mm), float(planned.target_y_mm)) / 1000.0
		game.broom_mm = int(game.frame.in_hand.get("broom_mm", planned.broom_mm))
	else: restored_call.clear()
	choice_waiting = false
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
	if state == "Choice":
		if not choice_waiting: delay = 0.0; choice_waiting = true
		if game.frame.get("choice_team", -1) == 1:
			delay += delta
			if delay >= 1.0:
				var recommended: int = game.session.recommended_remedy()
				if recommended >= 0: apply_remedy(recommended == 1)
		return
	if game.run_active:
		advice_time -= delta
		if advice_time <= 0:
			advice_time = .6
			var advice: Dictionary = game.session.solo_advice(game.play_settings.difficulty)
			ai_effort = int(advice.get("effort", 0))
			weight_zone = int(advice.get("zone", 0))
			if human_position() != 4 or shot_team != 0: speak_call()
		return
	if state != "Calling": return
	if game.phase == "Stone at rest":
		if review_waiting(): return
		delay += delta
		if delay >= 2.0: game.next_throw(); reset_turn()
		return
	if int(game.frame.get("delivered_count", -1)) != last_count: reset_turn()
	# The human needs the same skip's intention as the AI throwers. Never try
	# to plan against an interrupted held delivery; its saved call stays visible.
	if not game.frame.get("in_hand", {}).is_empty(): return
	if not planning and planned.is_empty():
		if human_skips() and not human_throws():
			if game.turn == 0: game.turn = 1
			request_call(0, Vector2.ZERO)
			return
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
		called_target = Vector2(float(result.target_x_mm) / 1000.0, float(result.target_y_mm) / 1000.0)
		shot_choice.select(["Draw", "Guard", "Hit"].find(result.kind))
		if not keep_broom:
			game.broom_mm = int(result.broom_mm)
			game.turn = int(result.turn)
		keep_broom = false
		game.session.set_solo_target(int(result.target_x_mm), int(result.target_y_mm))
		game.frame = game.session.frame()
		var instruction := "Grip the handle, pull back, push and finish with the called curl." if human_throws() else ("Drag the broom, call weight and choose a turn. The arrow shows curl direction only." if human_skips() else "The AI thrower will deliver; follow the skip's visible calls.")
		game.report = "%s calls %s • %s turn.\n%s" % ["Your skip" if human_throws() else ("Your team" if game.frame.team == 0 else "Cyan skip"), result.kind.to_lower(), "right" if game.turn > 0 else "left", instruction]
		delay = 0.0
	if not planned.is_empty() and not human_skips() and not human_throws():
		delay += delta
		if delay >= 1.3: send_shot()

func review_waiting() -> bool:
	# After settlement, frame.team is the NEXT team. Deriving the previous
	# team here also works after a saved settled shot is loaded.
	return enabled and game.play_settings.review_shots and game.phase == "Stone at rest" and game.frame.get("match_phase", "") == "Calling" and game.frame.get("team", -1) == 1

func choose_remedy(restore: bool) -> void:
	if not enabled or game.frame.get("match_phase", "") != "Choice" or game.frame.get("choice_team", -1) != 0: return
	apply_remedy(restore)

func apply_remedy(restore: bool) -> void:
	var owner := int(game.frame.get("choice_team", -1))
	var error: String = game.session.match_choose(restore)
	if not error.is_empty(): game.report = error; return
	game.frame = game.session.frame()
	game.previous = game.frame
	game.phase = "Stone at rest"
	choice_waiting = false
	delay = 0.0
	game.report = "%s chose to %s. The delivery counts." % [game.team_name(owner), "restore the original stones and remove the delivered stone" if restore else "accept the current stone positions"]
	game.save_practice()
	game.update_labels()
	game.update_spatial(0)

func suggest_again() -> void:
	if not enabled or planning or game.run_active: return
	var error: String = game.session.request_ai_plan()
	if not error.is_empty(): game.report = error; return
	planning = true
	keep_broom = false
	planned.clear()
	delay = 0.0
	game.report = "AI skip is suggesting weight and broom placement…"
	game.update_labels()

func request_call(kind: int, target: Vector2) -> void:
	if not enabled or not human_skips() or game.run_active or planning: return
	if kind == 0: target.y = clampf(target.y, -1.8, 1.8)
	elif kind == 1: target.y = clampf(target.y, -5.0, -2.1)
	target.x = clampf(target.x, -2.2, 2.2)
	var error: String = game.session.request_called_shot(kind, roundi(target.x * 1000.0), roundi(target.y * 1000.0), game.turn)
	if not error.is_empty(): game.report = error; return
	planning = true
	keep_broom = true
	called_target = target
	planned.clear()
	game.report = "Calling weight… Your broom sets the line."
	game.update_labels()

func revise_kind(kind: int) -> void:
	request_call(kind, Vector2(0, -3.0 if kind == 1 else 0.0))

func select_turn(direction: int) -> void:
	if not enabled or not human_skips() or game.run_active or planning or game.pointer != -99: return
	game.turn = direction
	game.report = "Curl %s. Your broom stays where you placed it.\nChoose weight, then send the shot." % ("right" if direction > 0 else "left")
	game.update_labels()
	game.update_spatial(0)

func send_shot() -> void:
	if not enabled or human_throws() or planned.is_empty() or game.run_active or game.pointer != -99: return
	if human_skips():
		caller_broom = game.broom_mm
		caller_turn = game.turn
	var error: String = game.session.execute_ai_plan(game.broom_mm, game.turn, game.play_settings.difficulty)
	if not error.is_empty(): game.report = error; return
	planned.clear()
	planning = false
	game.frame = game.session.frame()
	game.shot_reference.begin(game.frame, game.broom_mm, game.turn, shot_choice.get_item_text(shot_choice.selected))
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
	speak_call(true)
	game.update_labels()

func speak_call(force := false) -> void:
	if not game.persistence_enabled or not game.play_settings.spoken_calls: return
	var effort := call_override if human_skips() and call_override >= 0 else ai_effort
	var text := "Hurry hard!" if effort > 100 else ("Clean." if effort > 0 else "Off! Whoa.")
	if not force and (text == last_spoken or Time.get_ticks_msec() - last_spoken_ms < 1500): return
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty(): return
	last_spoken = text
	last_spoken_ms = Time.get_ticks_msec()
	DisplayServer.tts_speak(text, voices[0], 90, 1.0, 1.0, 0, true)

func save_envelope(match_json: String) -> String:
	return JSON.stringify({"schema": 1, "match": match_json, "position": human_position(), "difficulty": game.play_settings.difficulty,
		"target_x_mm": game.frame.get("solo_target_x_mm", 0), "target_y_mm": game.frame.get("solo_target_y_mm", 0),
		"call": planned if human_throws() else {}})

func valid_envelope(data: Variant) -> bool:
	if not data is Dictionary or data.get("schema") != 1 or not data.get("match") is String: return false
	for key in ["position", "difficulty", "target_x_mm", "target_y_mm"]:
		if not (data.get(key) is float or data.get(key) is int) or not is_finite(float(data[key])) or float(data[key]) != floorf(float(data[key])): return false
	var call = data.get("call", {})
	if not call is Dictionary: return false
	if not call.is_empty():
		if call.get("kind") not in ["Draw", "Guard", "Hit"]: return false
		for key in ["target_x_mm", "target_y_mm", "broom_mm", "speed_mm_s", "turn"]:
			if not (call.get(key) is float or call.get(key) is int) or not is_finite(float(call[key])) or float(call[key]) != floorf(float(call[key])): return false
		if absf(call.target_x_mm) > 2200 or call.target_y_mm < -5000 or call.target_y_mm > 2000 or absf(call.broom_mm) > 2200 or call.speed_mm_s < 1400 or call.speed_mm_s > 5000 or int(call.turn) not in [-1, 1]: return false
	return data.position >= 0 and data.position <= 5 and data.difficulty >= 0 and data.difficulty <= 2 and absi(int(data.target_x_mm)) <= 2200 and data.target_y_mm >= -5000 and data.target_y_mm <= 2000

func restore_metadata(data: Dictionary) -> void:
	game.shot_reference.clear()
	restored_call = data.get("call", {}).duplicate()
	game.play_settings.human_position = int(data.position)
	game.play_settings.position_choice.select(int(data.position))
	game.play_settings.difficulty = int(data.difficulty)
	game.play_settings.difficulty_choice.select(int(data.difficulty))
	game.session.set_solo_target(int(data.target_x_mm), int(data.target_y_mm))

func brush_effort() -> int:
	if human_position() == 4 and shot_team == 0: return maxi(0, call_override)
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
	game.rink.calling_view = enabled and human_skips() and not human_throws() and not game.run_active
	game.rink.called_target = called_target if enabled and human_throws() and not game.run_active and not planned.is_empty() else Vector2.INF
	if not enabled: return
	if game.frame.get("match_phase", "") == "Choice":
		game.rink.role_camera = "House"
	elif game.run_active:
		game.rink.role_camera = "Skip" if (human_skips() and human_position() != 4) or shot_team != 0 else "Sweeper"
	elif game.frame.get("match_phase", "") == "Calling" and not human_throws():
		game.rink.role_camera = "House" if human_skips() else "Skip"

func refresh_controls() -> void:
	if solo_button == null: return
	solo_button.disabled = game.run_active or game.pointer != -99
	solo_button.text = "Solo 4 vs 4" if not enabled else "Resume solo"
	solo_button.visible = not enabled
	var human_choice: bool = enabled and game.frame.get("match_phase", "") == "Choice" and game.frame.get("choice_team", -1) == 0
	accept_button.visible = human_choice
	restore_button.visible = human_choice
	var owns_call := enabled and human_skips()
	var throwing: bool = enabled and human_throws() and not game.run_active and game.phase != "Stone at rest" and game.frame.get("match_phase", "") == "Calling"
	shot_card.visible = throwing
	shot_card.position.x = 878 if game.spatial_view else 48
	if throwing: shot_card.show_call(planned, planning)
	var show_card: bool = owns_call and not human_throws() and not game.run_active and (planning or not planned.is_empty())
	skip_aid.visible = show_card
	skip_aid.queue_redraw()
	for control in [shot_choice, auto_button] + turn_buttons:
		control.visible = show_card
		control.disabled = planning
	for index in range(turn_buttons.size()):
		var selected: bool = game.turn == (1 if index == 0 else -1)
		turn_buttons[index].set_pressed_no_signal(selected)
		turn_buttons[index].theme_type_variation = "PrimaryButton" if selected else "Button"
	for index in range(call_buttons.size()):
		var b := call_buttons[index]
		b.text = "%s\n%s" % [["↑ HARD", "≈ CLEAN", "■ OFF"][index], OS.get_keycode_string(game.play_settings.call_keys[index])]
		b.visible = owns_call and game.run_active
	send_button.visible = owns_call and not human_throws() and not game.run_active and not planned.is_empty()
	call_background.visible = enabled and game.run_active
	if not enabled: return
	var effort := maxi(0, call_override) if human_position() == 4 and shot_team == 0 else (call_override if owns_call and call_override >= 0 else ai_effort)
	var text := "↑ HARD · SWEEP" if effort > 100 else ("≈ CLEAN · LIGHT BRUSH" if effort > 0 else "■ OFF · NO SWEEP")
	call_label.text = "%s  |  Weight zone %d" % [text, weight_zone] if weight_zone > 0 else (text if call_override >= 0 else "Reading weight…")
	if fast_forwarding(): call_label.text += "  |  4×"
	game.hint.text = "SOLO · Gold %s · %s AI" % [CurlPlaySettings.CONTROL_LABELS[human_position()], ["Club", "Competitive", "Elite"][game.play_settings.difficulty]]
	var state: String = game.frame.get("match_phase", "")
	if state == "Calling" or state == "InFlight":
		game.status.text = "4 vs 4  /  %s %s%s • %s" % [game.team_name(game.frame.team), CurlPlaySettings.POSITIONS[game.frame.thrower], " (you)" if human_throws() else " (AI)", game.phase]
		if game.phase == "Stone at rest":
			game.status.text = "4 vs 4  /  Stone at rest • Next: %s %s%s" % [game.team_name(game.frame.team), CurlPlaySettings.POSITIONS[game.frame.thrower], " (you)" if human_throws() else " (AI)"]
		if not game.run_active and game.phase != "Stone at rest" and not human_throws(): game.new_button.disabled = true
	if state == "Choice":
		game.status.text = "4 vs 4  /  %s chooses the no-tick remedy" % game.team_name(game.frame.get("choice_team", -1))
		game.new_button.disabled = true
		game.new_button.text = "Choose remedy"
		game.report_label.text = "A protected centre guard moved off the centre line or into the house. %s chooses whether to accept this result or restore the original stones and remove the delivered stone." % game.team_name(game.frame.get("choice_team", -1))
	elif state == "EndComplete": game.status.text = "4 vs 4  /  End complete"
	elif state == "GameComplete": game.status.text = "4 vs 4  /  %s wins" % game.team_name(game.frame.winner)
	if review_waiting():
		game.new_button.text = "Continue"
		game.new_button.disabled = false
		game.status.text = "4 vs 4  /  Review Gold’s shot"
		game.hint.text += " · Continue when ready"
	if game.run_active: game.new_button.text = "Stone in play"
	game.mode_button.text = "Practice"
	game.turn_button.hide()
	game.clock_label.text = "Gold %s  •  Cyan %s" % [game.clock_text(game.frame.clock_gold), game.clock_text(game.frame.clock_cyan)]
	game.clock_label.size.x = 300
