extends Control

const ICE := Color("dfecef")
const INK := Color("0b2330")
const GOLD := Color("eabf69")
const CYAN := Color("64cdd1")
var allow_online := true
var spatial_view := false
var authoritative_delivery := true
var held_last_us := -1
var held_remainder_us := 0
var rink: CurlRinkView
var camera_button: Button
var view_button: Button
var room_panel: CurlRoomPanel
var self_test_nonce := ""
var installed_ui_nonce := ""
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
var sweep_input := CurlSweeping.new()
var one_push := false
var phase := "Ready"
var report := ""
var stroke_trace := PackedVector2Array()
var path := PackedVector2Array()
var release_report: Dictionary = {}
var font := ThemeDB.fallback_font
var status: Label
var report_label: Label
var feedback_bg: Panel
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
var brand: Label
var scoreboard: Panel
var gold_score: Label
var cyan_score: Label
var end_score: Label
var ice_board: CurlIceBoard
var drills: CurlDrills
var solo: CurlSoloGame
var play_settings: CurlPlaySettings
var settings_focus := CurlModalFocus.new()
var settings_shade: ColorRect
var settings_button: Button
var zoom_button: Button
var shot_reference := CurlShotReference.new()
var ice_audio: CurlIceAudio
var restart_prompt: CurlRestartPrompt

var mobile_ui := OS.get_name() == "Android"

func _ready() -> void:
	Input.use_accumulated_input = false
	theme = CurlPresentation.make_theme()
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
				elif request.get("schema") == 3:
					installed_ui_nonce = request.nonce
					persistence_enabled = false
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
	status.position = Vector2(40, 62)
	status.add_theme_font_size_override("font_size", 16)
	status.add_theme_color_override("font_color", CurlPresentation.GOLD)
	add_child(status)
	brand = Label.new()
	brand.text = "PEBBLE & GRANITE"
	brand.position = Vector2(40, 20)
	brand.add_theme_font_size_override("font_size", 31 if mobile_ui else 29)
	add_child(brand)
	hint = Label.new()
	hint.position = Vector2(40, 87)
	hint.add_theme_font_size_override("font_size", 15 if mobile_ui else 13)
	hint.add_theme_color_override("font_color", CurlPresentation.MUTED)
	add_child(hint)
	report_label = Label.new()
	report_label.position = Vector2(800, 510)
	report_label.size = Vector2(430, 180)
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_label.add_theme_font_size_override("font_size", 20 if mobile_ui else 18)
	add_child(report_label)
	report_label.minimum_size_changed.connect(func(): layout_feedback.call_deferred())
	new_button = button("Next stone", Vector2(40, 726), func(): next_throw())
	new_button.theme_type_variation = "PrimaryButton"
	turn_button = button("Turn: clockwise ↻", Vector2(225, 726), change_turn)
	sweep_button = button("Hold to sweep", Vector2(500, 726), func(): pass)
	sweep_button.theme_type_variation = "SweepButton"
	sweep_button.button_down.connect(func(): hold_sweep = true)
	sweep_button.button_up.connect(func(): hold_sweep = false)
	one_button = button("One-push: off", Vector2(710, 726), func(): one_push = not one_push; update_labels())
	fresh_button = button("Fresh ice", Vector2(920, 726), request_restart)
	mode_button = button("Mixed doubles", Vector2(1040, 30), func(): switch_mode())
	clock_label = Label.new()
	clock_label.position = Vector2(650, 87)
	clock_label.add_theme_font_size_override("font_size", 16 if mobile_ui else 14)
	add_child(clock_label)
	create_scoreboard()
	create_match_controls()
	reset(false)
	restore_practice()
	if spatial_view: create_spatial_view()
	create_play_settings()
	ice_audio = CurlIceAudio.new()
	ice_audio.game = self
	add_child(ice_audio)
	if allow_online:
		solo = CurlSoloGame.new(self)
		solo.create_controls()
		drills = CurlDrills.new(self)
		drills.create_controls()
		ice_board = CurlIceBoard.new()
		add_child(ice_board)
		ice_board.setup(self)
		move_child(play_settings, -1)
	if allow_online:
		button("Online rooms", Vector2(840, 30), open_online)
		room_panel = CurlRoomPanel.new()
		add_child(room_panel)
		room_panel.hide()
	restart_prompt = CurlRestartPrompt.new()
	add_child(restart_prompt)
	restart_prompt.setup(self)
	if not installed_ui_nonce.is_empty() and allow_online:
		var probe = load("res://net/installed_ui_probe.gd").new()
		probe.game = self
		probe.nonce = installed_ui_nonce
		add_child(probe)

func create_play_settings() -> void:
	settings_button = button("Settings", Vector2(1070, 77), func():
		if pointer != -99: return
		play_settings.visible = not play_settings.visible)
	settings_button.custom_minimum_size = Vector2(170, 38)
	settings_button.size = settings_button.custom_minimum_size
	settings_shade = ColorRect.new()
	settings_shade.size = Vector2(1280, 800)
	settings_shade.color = Color(0, 0, 0, .42)
	settings_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_shade.hide()
	add_child(settings_shade)
	play_settings = CurlPlaySettings.new()
	play_settings.persistence_enabled = persistence_enabled or not allow_online
	add_child(play_settings)
	play_settings.changed.connect(apply_play_settings)
	play_settings.visibility_changed.connect(func():
		settings_shade.visible = play_settings.visible
		if play_settings.visible:
			stop_scrub()
			hold_sweep = false
			play_settings.position_choice.disabled = run_active or not frame.get("in_hand", {}).is_empty()
			move_child(settings_shade, -1)
			move_child(play_settings, -1)
			settings_focus.open(play_settings)
		else: settings_focus.close(play_settings))
	if rink != null:
		zoom_button = button("Zoom · Z", Vector2(270, 134), toggle_zoom)
		zoom_button.custom_minimum_size = Vector2(155, 40)
		zoom_button.size = zoom_button.custom_minimum_size
		move_child(play_settings, -1)
	apply_play_settings()

func apply_play_settings() -> void:
	if rink != null:
		rink.field_of_view = play_settings.fov
		rink.steady_camera = play_settings.steady_camera
	if not play_settings.spoken_calls and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH): DisplayServer.tts_stop()
	if solo != null: solo.refresh_controls()
	update_spatial(0)

func toggle_zoom() -> void:
	if rink == null or pointer != -99: return
	rink.zoomed = not rink.zoomed
	zoom_button.text = "Zoom out · Z" if rink.zoomed else "Zoom · Z"
	update_spatial(0)

func create_spatial_view() -> void:
	rink = CurlRinkView.new()
	rink.position = Vector2(40, 118)
	rink.size = Vector2(1200, 582)
	add_child(rink)
	move_child(rink, 0)
	camera_button = button("Camera: Auto", Vector2(56, 134), func():
		if pointer == -99: camera_button.text = "Camera: " + rink.cycle_camera())
	camera_button.custom_minimum_size = Vector2(208, 52) if mobile_ui else Vector2(190, 40)
	camera_button.size = camera_button.custom_minimum_size
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
	feedback_bg = Panel.new()
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
	new_button.custom_minimum_size.x = 220
	sweep_button.position.x = 278
	sweep_button.custom_minimum_size.x = 290
	one_button.position.x = 830
	one_button.custom_minimum_size.x = 200
	fresh_button.position.x = 1048
	fresh_button.custom_minimum_size.x = 192
	update_spatial(0.0)
func update_spatial(delta: float) -> void:
	if rink == null or not spatial_view: return
	if solo != null: solo.update_camera()
	if drills != null: drills.update_view()
	var aiming: bool = not run_active and phase != "Stone at rest" and frame.get("match_phase", "Calling") == "Calling"
	rink.hand_held = pointer != -99 and not dragging_broom and not sweeping and not run_active
	rink.pull_offset = clampf((stroke_trace[-1].y - stroke_trace[0].y) * .004, -.08, .18) if rink.hand_held and stroke_trace.size() > 1 and phase in ["Grip", "Pull", "Drive"] else 0.0
	var held: Dictionary = frame.get("in_hand", {}) if authoritative_delivery else {}
	var gesture: Dictionary = session.delivery_pose(input_clock.call())
	rink.delivery_y = float(held.y_um) / 1000000.0 if not held.is_empty() else (float(gesture.y_um) / 1000000.0 if aiming else -37.8)
	rink.delivery_x = float(held.get("x_um", 0)) / 1000000.0 if not held.is_empty() else (float(gesture.get("x_mm", 0)) / 1000.0 if rink.hand_held else 0.0)
	rink.delivery_aim_mm = int(held.get("aim_mm", 0)) if not held.is_empty() else int(gesture.get("aim_mm", 0))
	rink.sliding = not held.is_empty() or phase == "Slide"
	var brush := current_brush()
	if solo != null and solo.enabled and run_active and solo.brush_effort() > 0:
		if brush.is_empty(): brush = {"stone": int(frame.get("delivered", -1)), "effort": solo.brush_effort(), "ahead_mm": 180, "lateral_mm": 0, "steady": true}
	var selected := selected_sweep_stone()
	rink.sweep_target = int(selected.get("id", -1))
	rink.brush_input = brush
	rink.render_frame(frame, run_active, not brush.is_empty() and brush.effort > 0, broom_mm, turn, aiming, delta)
func broom_screen_point() -> Vector2:
	return rink.broom_point() if spatial_view and rink != null else house_point(Vector2(float(broom_mm) / 1000.0, 0))

func open_online() -> void:
	save_practice()
	cancel_pointer()
	room_panel.show()

func button(text: String, pos: Vector2, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = Vector2(165, 64 if mobile_ui else 48)
	b.add_theme_font_size_override("font_size", 22 if mobile_ui and spatial_view else 19)
	b.pressed.connect(action)
	add_child(b)
	return b

func request_restart() -> void:
	if run_active or pointer != -99 or not frame.get("in_hand", {}).is_empty(): return
	if restart_prompt == null or restart_prompt.visible: return
	var progress: bool = int(frame.get("delivered", -1)) >= 0 or int(frame.get("delivered_count", 0)) > 0 or int(frame.get("end", 1)) > 1
	if not progress or frame.get("match_phase", "") == "GameComplete":
		reset()
		return
	var drill: bool = drills != null and drills.enabled
	var title := "Restart this drill?" if drill else ("Start a new match?" if match_mode else "Start on fresh ice?")
	var explanation := "This five-shot round will be replaced. Your personal best stays saved." if drill else ("The current match and its autosave will be replaced. Keep playing to return to this end." if match_mode else "The stones, ice wear and current practice session will be cleared.")
	restart_prompt.ask(title, explanation, "Restart drill" if drill else ("New match" if match_mode else "Fresh ice"), func(): reset())

func local_menu_open() -> bool:
	return (play_settings != null and play_settings.visible) or (ice_board != null and ice_board.visible) or (restart_prompt != null and restart_prompt.visible)

func reset(persist := true) -> void:
	shot_reference.clear()
	if session == null: return
	if ice_board != null: ice_board.new_session(persist)
	if match_mode:
		if solo != null and solo.enabled: session.new_team_match(42)
		else: session.new_match(42)
	else: session.reset(42)
	frame = session.frame()
	previous = frame
	phase = "Ready"
	if spatial_view: turn = 0
	clock_remainder = 0.0
	held_last_us = -1
	held_remainder_us = 0
	last_save_tick = 0
	save_allowed = true
	pointer = -99
	dragging_broom = false
	sweeping = false
	hold_sweep = false
	sweep_input.target = -1
	stop_scrub()
	run_active = false
	accumulator = 0.0
	path.clear()
	stroke_trace.clear()
	report = ("House camera: drag the broom to aim." if spatial_view else "Drag the broom in the house.") + "\nGrip handle; pull back and push. Sideways sets aim.\nOnce sliding, nudge left/right for curl, then lift."
	if drills != null and drills.enabled: drills.reset_round()
	update_labels()
	queue_redraw()
	if match_mode:
		phase = "Ready" if solo != null and solo.enabled else "Choose placement"
		if solo != null and solo.enabled: solo.reset_turn()
		update_labels()
	if persist: save_practice()

func update_labels() -> void:
	status.text = "Practice  /  " + phase
	hint.text = "CLUB ICE  •  Aim · deliver · sweep" if spatial_view else "FEEL LAB     •     Seed 42     •     Mouse / trackpad / touch"
	turn_button.text = "Turn: clockwise ↻" if turn == 1 else "Turn: counterclockwise ↺"
	one_button.text = "One-push: on" if one_push else "One-push: off"
	one_button.theme_type_variation = "SweepButton" if one_push else "Button"
	new_button.disabled = run_active
	new_button.text = "Next stone" if frame.get("can_deliver_next", true) else "Clear stones"
	turn_button.size.x = 255
	turn_button.disabled = run_active
	one_button.disabled = run_active
	report_label.text = report
	clock_label.visible = match_mode
	scoreboard.visible = match_mode
	sweep_button.disabled = not can_sweep()
	mode_button.text = "Practice" if match_mode else "Mixed doubles"
	mode_button.disabled = run_active
	fresh_button.text = "New match" if match_mode else "Fresh ice"
	fresh_button.disabled = run_active or pointer != -99 or not frame.get("in_hand", {}).is_empty()
	setup_panel.visible = match_mode and frame.get("match_phase", "") == "Placement"
	if match_mode:
		gold_score.text = "GOLD  %d" % frame.score_gold
		cyan_score.text = "%d  CYAN" % frame.score_cyan
		end_score.text = "END %d / %d" % [frame.end, frame.scheduled_ends]
		clock_label.text = "Gold %s   •   Cyan %s" % [clock_text(frame.clock_gold), clock_text(frame.clock_cyan)]
		hint.text = "LOCAL MIXED DOUBLES  •  Autosaved"
		if frame.match_phase == "Placement":
			status.text = "Mixed doubles  /  Choose placement"
			new_button.text = "Next stone"
			setup_label.text = "%s chooses the placement" % team_name(frame.placement_team)
			setup_label.add_theme_color_override("font_color", CurlPresentation.GOLD if frame.placement_team == 0 else CurlPresentation.CYAN)
			house_button.text = "Take the house" if own_house else "Take the guard"
			power_button.text = "Centre placement" if power_side == 0 else ("Left power play" if power_side < 0 else "Right power play")
			power_button.disabled = not frame.power_available
			gold_order.text = "Gold: player %d throws 1 & 5" % (frame.first_gold + 1)
			cyan_order.text = "Cyan: player %d throws 1 & 5" % (frame.first_cyan + 1)
			new_button.disabled = true
			report_label.text = "Pass the device between players. Select each team's first/last thrower, then choose where to place the stones."
		elif frame.match_phase in ["Calling", "InFlight"]:
			status.text = "Mixed doubles  /  %s • Player %d • %s" % [team_name(frame.team), frame.thrower + 1, phase]
		elif frame.match_phase == "EndComplete":
			new_button.text = "Next end"
			status.text = "Mixed doubles  /  End complete"
		elif frame.match_phase == "GameComplete":
			new_button.text = "Rematch"
			status.text = "Mixed doubles  /  %s wins" % team_name(frame.winner)
		if frame.get("violation", "") == "HogRelease":
			report_label.text += "\nHog-line violation: stone removed; delivery counts."
		elif frame.get("violation", "") == "NoTick":
			if frame.match_phase == "Choice": report_label.text += "\nCentre guard moved: opponent chooses the remedy."
			else: report_label.text += "\nNo-tick remedy: " + ("original positions restored." if frame.get("remedy_restored", false) else "current positions accepted.")
		elif not frame.get("violation", "").is_empty():
			report_label.text += "\nProtected stone removed: positions restored; delivery forfeited."
	if authoritative_delivery and not frame.get("in_hand", {}).is_empty():
		new_button.text = "Stone in play" if frame.in_hand.in_play else "Return to hack"
		new_button.disabled = frame.in_hand.in_play
	if solo != null: solo.refresh_controls()
	if drills != null: drills.refresh_controls()
	if ice_board != null: ice_board.refresh_button()
	layout_feedback()

func layout_feedback() -> void:
	if feedback_bg == null: return
	var width := 365.0 if phase == "Slide" or frame.get("match_phase", "") == "Choice" else 490.0
	report_label.size.x = width - 24
	report_label.size.y = report_label.get_minimum_size().y
	var height := maxf(report_label.get_minimum_size().y + 24, 72)
	feedback_bg.size = Vector2(width, height)
	feedback_bg.position = Vector2(56, 684 - height)
	report_label.position = feedback_bg.position + Vector2(12, 11)

func clock_text(ms: int) -> String:
	var seconds := int(ceil(float(ms) / 1000.0))
	return "%d:%02d" % [seconds / 60, seconds % 60]

func change_turn() -> void:
	turn *= -1
	update_labels()

func team_name(team: int) -> String:
	return "Gold" if team == 0 else "Cyan"

func create_scoreboard() -> void:
	scoreboard = Panel.new()
	scoreboard.position = Vector2(444, 20 if mobile_ui else 22)
	scoreboard.size = Vector2(350, 40 if mobile_ui else 38)
	scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard.add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11262f"), Color("29424b"), 8))
	add_child(scoreboard)
	gold_score = score_label(Vector2(14, 3), Vector2(112, 32), GOLD, 23)
	end_score = score_label(Vector2(124, 9), Vector2(104, 24), CurlPresentation.MUTED, 13)
	cyan_score = score_label(Vector2(226, 3), Vector2(112, 32), CYAN, 23)

func score_label(pos: Vector2, dimensions: Vector2, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	if mobile_ui: label.add_theme_font_size_override("font_size", font_size + 2)
	label.add_theme_color_override("font_color", color)
	scoreboard.add_child(label)
	return label

func create_match_controls() -> void:
	setup_panel = Panel.new()
	setup_panel.position = Vector2(800, 110)
	setup_panel.size = Vector2(440, 380)
	var setup_background := panel(Color("122832"))
	setup_background.shadow_color = Color(0, 0, 0, .22)
	setup_background.shadow_size = 12
	setup_background.shadow_offset = Vector2(0, 8)
	setup_panel.add_theme_stylebox_override("panel", setup_background)
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
	apply_button.theme_type_variation = "PrimaryButton"
	gold_order.add_theme_color_override("font_color", GOLD)
	cyan_order.add_theme_color_override("font_color", CYAN)

func setup_button(pos: Vector2, action: Callable) -> Button:
	var b := button("", Vector2.ZERO, action)
	b.reparent(setup_panel)
	b.position = pos
	b.custom_minimum_size = Vector2(400, 52 if mobile_ui else 48)
	b.size = b.custom_minimum_size
	return b

func switch_mode() -> void:
	if run_active: return
	save_practice()
	if solo != null: solo.enabled = false
	if drills != null: drills.enabled = false
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
	if local_menu_open(): return
	if drills != null and drills.enabled:
		drills.advance()
	if solo != null and solo.enabled:
		solo.advance(delta)
	if match_mode and not run_active and frame.get("match_phase", "") == "Calling" and frame.get("in_hand", {}).is_empty():
		clock_remainder += delta * 1000.0
		var elapsed := mini(int(clock_remainder), 60000)
		clock_remainder -= elapsed
		session.match_think(elapsed)
		frame = session.frame()
		update_labels()
		if frame.global_tick - last_save_tick >= 240: save_practice()
	if run_active:
		# Retain all time debt. Never change fixed dt or silently skip ticks.
		var fast := solo != null and solo.fast_forwarding()
		accumulator += delta * (4.0 if fast else 1.0)
		var steps := mini(int(accumulator * 240.0), 64)
		if fast: steps = solo.fast_step_limit(steps)
		if steps > 0:
			previous = frame
			var brush := current_brush()
			var error: String
			if solo != null and solo.enabled:
				var human_effort := int(brush.get("effort", 0)) if solo.shot_team == 0 else 0
				error = session.step_solo_ticks(steps, int(frame.get("delivered", 0)), human_effort, int(brush.get("lateral_mm", 0)), int(brush.get("ahead_mm", 180)), solo.brush_effort())
			else:
				error = session.step_brush_ticks(steps, int(brush.get("stone", 0)), int(brush.get("effort", 0)), int(brush.get("lateral_mm", 0)), int(brush.get("ahead_mm", 180)))
			if not error.is_empty(): report = error
			accumulator -= float(steps) / 240.0
			frame = session.frame()
			if fast and not solo.fast_forwarding(): accumulator = 0.0
			if not frame.stones.is_empty():
				if not delivered_stone().is_empty(): path.append(delivered_stone().position)
			if frame.resting or (match_mode and frame.get("match_phase", "") != "InFlight"):
				run_active = false
				stop_scrub()
				hold_sweep = false
				pointer = -99
				phase = "Stone at rest"
				var s: Dictionary = delivered_stone()
				if s.is_empty(): s = {"turns": 0.0, "position": Vector2.ZERO, "active": false}
				var true_split := int(frame.get("hog_split_ms", -1))
				var split := "%.2f s" % (true_split / 1000.0) if true_split >= 0 else ("—" if frame.hog_tick < 0 else "%.2f s" % (float(frame.hog_tick) / 240.0))
				var split_name := "Hog-to-hog" if true_split >= 0 else "Release to far hog"
				report = "Release %.3f m/s\n%s %s\n%.2f rotations • %.2f s travel\nRest: %.2f m across, %.2f m from tee\n%s" % [float(release_report.get("speed_mm_s", 0)) / 1000.0, split_name, split, s.turns, float(frame.tick) / 240.0, s.position.x, s.position.y, "In play" if s.active else "Out of play"]
				if match_mode and frame.get("match_phase", "") == "GameComplete" and not frame.resting:
					report = "Thinking time expired. %s wins. Choose Rematch to play again." % team_name(frame.winner)
				update_labels()
			if not run_active or frame.global_tick - last_save_tick >= 240:
				save_practice()
	shot_reference.observe(frame, run_active)
	update_delivery()
	if run_active: update_labels()
	update_spatial(delta)
	queue_redraw()

func advance_local_held() -> void:
	if frame.get("in_hand", {}).is_empty() or held_last_us < 0: return
	var now: int = input_clock.call()
	var elapsed: int = maxi(0, now - held_last_us) + held_remainder_us
	held_last_us = now
	held_remainder_us = elapsed % 1000
	var error: String = session.advance_held(mini(elapsed / 1000, 60000))
	if not error.is_empty(): report = error; return
	frame = session.frame()
	if frame.get("in_hand", {}).is_empty():
		pointer = -99
		held_last_us = -1
		session.cancel_stroke()
		phase = "Stone at rest"
		report = "The thinking clock expired." if frame.get("match_phase") == "GameComplete" else "Hog-line violation. The stone is removed; the delivery counts."
		save_practice()
		update_labels()

func update_delivery() -> void:
	if not authoritative_delivery:
		update_legacy_delivery()
		return
	if pointer == -99 or dragging_broom or sweeping or run_active: return
	if frame.get("in_hand", {}).is_empty():
		var target: int = session.delivery_target(input_clock.call())
		if target == 0: return
		var error: String = session.begin_analog_held(target, broom_mm) if spatial_view else session.begin_held(target, broom_mm)
		if not error.is_empty(): report = error; return
		frame = session.frame()
		held_last_us = input_clock.call()
		held_remainder_us = 0
		save_practice()
	advance_local_held()
	var held: Dictionary = frame.get("in_hand", {})
	if held.is_empty(): return
	phase = "Slide"
	var weight := "Soft" if held.target_mm_s < 1950 else ("Draw" if held.target_mm_s < 2300 else "Firm")
	report = delivery_feedback(weight, held.hog_warning, int(held.target_mm_s))
	if frame.global_tick - last_save_tick >= 240: save_practice()
	update_labels()

func update_legacy_delivery() -> void:
	if pointer == -99 or dragging_broom or sweeping or run_active: return
	var pose: Dictionary = session.delivery_pose(input_clock.call())
	if pose.hog_violation and not stroke_trace.is_empty():
		end_pointer(stroke_trace[-1])
	elif pose.slide_tick > 0:
		phase = "Slide"
		var weight := "Soft" if pose.target_mm_s < 1950 else ("Draw" if pose.target_mm_s < 2300 else "Firm")
		report = delivery_feedback(weight, pose.hog_warning, int(pose.target_mm_s))
		update_labels()

func delivery_feedback(weight: String, hog_warning: bool, push_mm_s := 0) -> String:
	if spatial_view: turn = int(session.delivery_pose(input_clock.call()).get("turn", 0))
	var curl := "Curl left ←" if turn < 0 else ("Curl right →" if turn > 0 else "No curl · nudge left/right to turn")
	var weight_feedback := weight + " weight"
	if solo != null and solo.enabled and solo.human_throws() and not solo.planned.is_empty() and push_mm_s > 0:
		var difference: int = push_mm_s - int(solo.planned.speed_mm_s)
		weight_feedback = "Push: " + ("light for call" if difference < -60 else ("heavy for call" if difference > 60 else "close to called weight"))
	return ("Release now — hog line." if hog_warning else weight_feedback) + "\n" + curl

func cancel_pointer() -> void:
	# An OS-cancelled contact is an interruption, not a voluntary finger lift.
	if authoritative_delivery and session != null and pointer != -99: advance_local_held()
	save_practice()
	pointer = -99
	held_last_us = -1
	hold_sweep = false
	stop_scrub()
	dragging_broom = false
	if session != null:
		session.cancel_stroke()
		if status != null and not run_active and phase != "Stone at rest":
			phase = "Ready"
			if not frame.get("in_hand", {}).is_empty(): report = "Delivery paused. Regrip the handle to finish from here."
			update_labels()
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		suspended = false
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		suspended = true
		cancel_pointer()

func _input(event: InputEvent) -> void:
	if room_panel != null and room_panel.visible: return
	if session == null: return
	if local_menu_open(): return
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and solo != null and solo.enabled and run_active and solo.human_skips():
		var call := play_settings.call_keys.find(event.keycode)
		if call >= 0:
			solo.set_call([255, 80, 0][call])
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Z:
		toggle_zoom()
		return
	if event is InputEventScreenTouch:
		if event.canceled:
			if pointer == event.index: cancel_pointer()
			return
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
	if local_menu_open(): return
	if solo != null and solo.enabled and not run_active and (solo.planning or (not solo.human_throws() and not solo.human_skips())): return
	if solo != null and solo.enabled and solo.human_throws() and not run_active and solo.planned.is_empty() and frame.get("in_hand", {}).is_empty(): return
	var controls := [camera_button, view_button, settings_button, zoom_button]
	if solo != null: controls.append_array([solo.solo_button, solo.send_button, solo.shot_choice, solo.auto_button, solo.accept_button, solo.restore_button, solo.shot_card] + solo.call_buttons + solo.turn_buttons)
	if ice_board != null: controls.append(ice_board.menu_button)
	if drills != null: controls.append_array([drills.menu_button, drills.start_button, drills.choice])
	for control in controls:
		if control != null and control.is_visible_in_tree() and control.get_global_rect().has_point(p): return
	if drills != null and drills.enabled and drills.kind == 3 and not run_active: return
	if match_mode and not run_active and frame.get("match_phase", "") != "Calling": return
	if pointer != -99 or p.y > 710: return
	if run_active:
		if (spatial_view and rink != null and rink.get_global_rect().has_point(p)) or (not spatial_view and p.x < 780):
			pick_sweep_target(p)
			if not can_sweep(): return
			pointer = id
			sweeping = true
			sweep_input.active = true
			sweep_input.point = p
			var q := units(p)
			session.begin_scrub(input_clock.call(), q.x, q.y)
		return
	if (not authoritative_delivery or frame.get("in_hand", {}).is_empty()) and p.distance_to(broom_screen_point()) < 55:
		pointer = id
		dragging_broom = true
	elif phase == "Ready" and (solo == null or not solo.enabled or solo.human_throws()) and p.distance_to(handle_point()) < 80:
		pointer = id
		var q := units(p)
		if authoritative_delivery and not frame.get("in_hand", {}).is_empty():
			session.regrip(input_clock.call(), q.x, q.y)
			held_last_us = input_clock.call()
			held_remainder_us = 0
		else: session.grip(input_clock.call(), q.x, q.y, one_push)
		stroke_trace = PackedVector2Array([p])
		if spatial_view and rink != null:
			rink.mode = 0
			rink.zoomed = false
			if zoom_button != null: zoom_button.text = "Zoom · Z"
		phase = "Grip"
		update_labels()

func move_pointer(p: Vector2) -> void:
	if sweeping:
		sweep_input.point = p
		var q := units(p)
		session.scrub_motion(input_clock.call(), q.x, q.y)
		return
	if dragging_broom:
		broom_mm = int(rink.aim_x(p) * 1000.0) if spatial_view and rink != null else clampi(int((p.x - 555) / 94.0 * 1000), -2200, 2200)
		update_spatial(0)
		if solo != null: solo.skip_aid.queue_redraw()
	elif not run_active:
		var q := units(p)
		session.motion(input_clock.call(), q.x, q.y)
		stroke_trace.append(p)
		phase = session.stroke_phase()
		if authoritative_delivery: update_delivery()
		update_labels()

func end_pointer(p: Vector2) -> void:
	if authoritative_delivery and not dragging_broom and not sweeping and not run_active:
		update_delivery()
		if pointer == -99: return
	pointer = -99
	if dragging_broom:
		dragging_broom = false
		if spatial_view and rink != null:
			if solo == null or not solo.enabled or not solo.human_skips(): rink.mode = 0
			update_spatial(0)
		return
	if sweeping or run_active:
		stop_scrub()
		return
	var q := units(p)
	release_report = session.lift(input_clock.call(), q.x, q.y)
	if spatial_view:
		turn = int(release_report.get("turn", 0))
		release_report.line_mm = 0
	if not authoritative_delivery and release_report.get("hog_violation", false):
		var error: String = session.hog_violation()
		frame = session.frame()
		phase = "Stone at rest" if error.is_empty() else "Ready"
		report = "Hog-line violation. The stone is removed; the delivery counts." if error.is_empty() else error
		save_practice()
	elif not (release_report.get("finish_valid", false) if authoritative_delivery else release_report.valid):
		phase = "Ready"
		report = "Try a smooth pull-back, then forward stroke. Lift after the push. A simple click does not throw."
	else:
		var error := ""
		if authoritative_delivery:
			if frame.get("in_hand", {}).is_empty():
				error = session.begin_analog_held(release_report.target_mm_s, broom_mm) if spatial_view else session.begin_held(release_report.target_mm_s, broom_mm)
			if error.is_empty(): error = session.release_held(release_report.trim_mm_s, release_report.line_mm, turn)
		else: error = session.deliver_slide(release_report.speed_um_s, release_report.y_um, clampi(broom_mm + release_report.line_mm, -2200, 2200), turn)
		if error.is_empty():
			run_active = true
			phase = "Travel"
			report = "Scrub the ice ahead of the stone, or hold the sweep button. Tap a moving stone to select it."
			frame = session.frame()
			if solo != null and solo.enabled:
				if not solo.planned.is_empty():
					session.set_solo_target(int(solo.planned.target_x_mm), int(solo.planned.target_y_mm))
					frame = session.frame()
				shot_reference.begin(frame, broom_mm, turn, "Human delivery")
				solo.shot_team = int(frame.team)
				solo.advice_time = 0.0
			release_report.speed_mm_s = int(frame.release_speed * 1000.0)
			held_last_us = -1
			save_practice()
			if OS.get_name() == "Android": Input.vibrate_handheld(18)
		else: report = error
	update_labels()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b1820"))
	draw_line(Vector2(40, 11), Vector2(145, 11), CurlPresentation.GOLD, 2)
	draw_line(Vector2(40, 712), Vector2(1240, 712), Color("2b4149"), 1)
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
	return CurlPresentation.surface(color, Color("3c535b"), 10)

func delivered_stone() -> Dictionary:
	for s in frame.get("stones", []):
		if s.id == frame.get("delivered", -1): return s
	return {}

func sweep_seat() -> int:
	if solo != null and solo.enabled:
		return mini(solo.human_position(), 3) if solo.shot_team == 0 else -2
	return int(frame.get("team", 0)) * 2 + int(frame.get("thrower", 0)) if match_mode else -1

func selected_sweep_stone() -> Dictionary:
	return sweep_input.selected(frame, sweep_seat(), hold_sweep) if run_active else {}

func can_sweep() -> bool:
	return not selected_sweep_stone().is_empty()

func stop_scrub() -> void:
	sweeping = false
	sweep_input.active = false
	if session != null: session.cancel_scrub()

func pick_sweep_target(p: Vector2) -> void:
	var distance := 42.0
	for stone in frame.get("stones", []):
		if not sweep_input.allowed(stone, frame, sweep_seat()): continue
		var projected: Vector2 = rink.stone_point(stone.id) if spatial_view and rink != null else (house_point(stone.position) if p.x > 315 else sheet_point(stone.position))
		var candidate := p.distance_to(projected)
		if candidate < distance:
			distance = candidate
			sweep_input.target = stone.id

func current_brush() -> Dictionary:
	if suspended or not run_active: return {}
	var stone := selected_sweep_stone()
	if stone.is_empty(): return {}
	if hold_sweep:
		return {"stone": int(stone.id), "brush": 0, "effort": 255, "lateral_mm": 0, "ahead_mm": 180, "steady": true}
	if not sweeping: return {}
	var ice: Variant
	var displayed := stone.duplicate()
	if spatial_view and rink != null:
		ice = rink.ice_point(sweep_input.point)
		if rink.stones.has(stone.id):
			var shown: Vector3 = rink.stones[stone.id].position
			displayed.position = Vector2(shown.x, -shown.z)
	else:
		var p := sweep_input.point
		if Rect2(40, 110, 250, 590).has_point(p): ice = Vector2((p.x - 168) / 30, 2.2 - (p.y - 125) / 17)
		elif Rect2(315, 110, 465, 590).has_point(p): ice = Vector2((p.x - 555) / 94, (325 - p.y) / 94)
	if ice == null: return {}
	var offsets := sweep_input.offsets(displayed, ice)
	if offsets.is_empty(): return {}
	return {"stone": int(stone.id), "brush": 0, "effort": int(session.scrub_effort(input_clock.call())), "lateral_mm": offsets.lateral_mm, "ahead_mm": offsets.ahead_mm, "steady": false}

func next_throw() -> void:
	if authoritative_delivery and not frame.get("in_hand", {}).is_empty():
		var error: String = session.cancel_held()
		if error.is_empty():
			session.cancel_stroke()
			frame = session.frame()
			phase = "Ready"
			pointer = -99
			held_last_us = -1
			report = "Returned to the hack before the tee line."
			save_practice()
		else: report = "This stone is already in play. Regrip the handle to continue."
		update_labels()
		return
	if session == null or run_active: return
	if drills != null and drills.enabled:
		drills.next_target()
		return
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
		phase = "Ready" if solo != null and solo.enabled else "Choose placement"
		if solo != null and solo.enabled: solo.reset_turn()
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
	if solo != null and solo.enabled: solo.reset_turn()
	update_labels()
	save_practice()

func save_practice() -> void:
	if not persistence_enabled or not save_allowed or session == null: return
	var json: String = session.match_json() if match_mode else session.session_json()
	if solo != null and solo.enabled and not json.is_empty(): json = solo.save_envelope(json)
	if drills != null and drills.enabled and not json.is_empty(): json = drills.save_envelope(json)
	if json.is_empty():
		save_error("Could not encode the current session.")
		return
	var destination := drills.save_path if drills != null and drills.enabled else solo.save_path if solo != null and solo.enabled else (match_save_path if match_mode else save_path)
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
	var source := drills.save_path if drills != null and drills.enabled else solo.save_path if solo != null and solo.enabled else (match_save_path if is_match else save_path)
	for filename in [source, source + ".bak"]:
		if not FileAccess.file_exists(filename): continue
		found = true
		var file := FileAccess.open(filename, FileAccess.READ)
		if file == null or file.get_length() > (36 if (solo != null and solo.enabled) or (drills != null and drills.enabled) else 16) * 1024 * 1024: continue
		var json := file.get_as_text()
		file.close()
		var envelope: Dictionary = {}
		if drills != null and drills.enabled:
			var decoder := JSON.new()
			if decoder.parse(json) != OK or not drills.valid_envelope(decoder.data): continue
			envelope = decoder.data
			json = envelope.session
		elif solo != null and solo.enabled:
			var decoder := JSON.new()
			if decoder.parse(json) != OK: continue
			var parsed = decoder.data
			if not solo.valid_envelope(parsed): continue
			envelope = parsed
			json = envelope.match
		if is_match:
			var header = JSON.parse_string(json)
			if not header is Dictionary or not header.get("rules") is Dictionary: continue
			if header.rules.get("format") != ("Teams" if solo != null and solo.enabled else "MixedDoubles"): continue
		var error: String = session.load_match(json) if is_match else session.load_session(json)
		if not error.is_empty(): continue
		if not envelope.is_empty() and solo != null and solo.enabled: solo.restore_metadata(envelope)
		var loaded: Dictionary = session.frame()
		if is_match and loaded.get("format", "") != ("Teams" if solo != null and solo.enabled else "MixedDoubles"): continue
		match_mode = is_match
		frame = loaded
		previous = frame
		run_active = frame.match_phase == "InFlight" if is_match else not frame.resting
		phase = "Travel" if run_active else "Ready"
		last_save_tick = frame.global_tick
		if solo != null and solo.enabled: solo.reset_turn()
		release_report = {"speed_mm_s": int(frame.get("release_speed", 0.0) * 1000.0)}
		report = "Delivery restored. Regrip the handle to continue from this point." if not frame.get("in_hand", {}).is_empty() else ("Match" if is_match else "Practice") + " restored. The ice and your stones are just as you left them."
		held_last_us = -1
		if drills != null and drills.enabled: drills.restore_metadata(envelope)
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
