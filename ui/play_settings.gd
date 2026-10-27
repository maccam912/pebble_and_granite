class_name CurlPlaySettings
extends Panel
## Device preferences only. Match commands and replay data stay in Rust.
signal changed
signal closed
var fov := 52.0
var steady_camera := false
var steady_toggle: CheckButton
var fast_opponents := false
var spoken_calls := true
var difficulty := 1
var human_position := 0
var call_keys := PackedInt32Array([KEY_H, KEY_C, KEY_O])
var bindings_focus := CurlModalFocus.new()
var binding_panel: Panel
var binding_buttons: Array[Button] = []
var binding_hint: Label
var waiting_key := -1
var persistence_enabled := true
var fov_label: Label
var fov_slider: HSlider
var fast_toggle: CheckButton
var difficulty_choice: OptionButton
var position_choice: OptionButton
const PATH := "user://play-settings.cfg"
var config_path := PATH
const POSITIONS := ["Lead", "Second", "Vice", "Skip"]
const CONTROL_LABELS := ["Lead", "Second", "Vice", "Skip", "Full team", "Calling only"]

func _ready() -> void:
	position = Vector2(360, 100)
	size = Vector2(560, 600)
	add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11252f"), CurlPresentation.GOLD, 12))
	var config := ConfigFile.new()
	if persistence_enabled and config.load(config_path) == OK:
		fov = clampf(float(config.get_value("view", "fov", 52.0)), 40, 85)
		steady_camera = bool(config.get_value("view", "steady_camera", false))
		spoken_calls = bool(config.get_value("audio", "spoken_calls", true))
		fast_opponents = bool(config.get_value("solo", "fast_opponents", false))
		difficulty = clampi(int(config.get_value("solo", "difficulty", 1)), 0, 2)
		human_position = clampi(int(config.get_value("solo", "position", 0)), 0, 5)
		var saved_keys = config.get_value("input", "call_keys", call_keys)
		if valid_keys(saved_keys): call_keys = PackedInt32Array(saved_keys)
	var title := label("Play settings", Vector2(24, 18))
	title.add_theme_font_size_override("font_size", 26)
	fov_label = label("", Vector2(24, 78))
	fov_slider = HSlider.new()
	fov_slider.position = Vector2(24, 118)
	fov_slider.size = Vector2(512, 36)
	fov_slider.min_value = 40
	fov_slider.max_value = 85
	fov_slider.value = fov
	fov_slider.value_changed.connect(func(value): fov = value; update_preferences())
	add_child(fov_slider)
	steady_toggle = CheckButton.new()
	steady_toggle.text = "Steady overhead after release (Auto)"
	steady_toggle.position = Vector2(18, 164)
	steady_toggle.size = Vector2(524, 48)
	steady_toggle.button_pressed = steady_camera
	steady_toggle.toggled.connect(func(value): steady_camera = value; update_preferences())
	add_child(steady_toggle)
	fast_toggle = CheckButton.new()
	fast_toggle.text = "Fast opponent travel between hog lines (4×)"
	fast_toggle.position = Vector2(18, 220)
	fast_toggle.size = Vector2(524, 48)
	fast_toggle.button_pressed = fast_opponents
	fast_toggle.toggled.connect(func(value): fast_opponents = value; update_preferences())
	add_child(fast_toggle)
	label("AI shot accuracy", Vector2(24, 288))
	difficulty_choice = OptionButton.new()
	difficulty_choice.position = Vector2(268, 276)
	difficulty_choice.size = Vector2(268, 50)
	for tier in ["Club · forgiving", "Competitive", "Elite · precise"]: difficulty_choice.add_item(tier)
	difficulty_choice.select(difficulty)
	difficulty_choice.item_selected.connect(func(value): difficulty = value; update_preferences())
	add_child(difficulty_choice)
	label("Your solo control", Vector2(24, 352))
	position_choice = OptionButton.new()
	position_choice.position = Vector2(268, 340)
	position_choice.size = Vector2(268, 50)
	for role in CONTROL_LABELS: position_choice.add_item(role)
	position_choice.select(human_position)
	position_choice.item_selected.connect(func(value): human_position = value; update_preferences())
	add_child(position_choice)
	var speech := CheckButton.new()
	speech.text = "Spoken skip calls (device voice, if available)"
	speech.position = Vector2(18, 402)
	speech.size = Vector2(524, 48)
	speech.button_pressed = spoken_calls
	speech.toggled.connect(func(value): spoken_calls = value; update_preferences())
	add_child(speech)
	var note := label("Calls always show text and symbols.\nZ / Zoom inspects the house.\nZones: 1–3 guard · 4–6 front · 7 tee · 8–10 back.", Vector2(24, 466))
	note.add_theme_font_size_override("font_size", 16)
	var done := Button.new()
	done.text = "Done"
	done.position = Vector2(364, 538)
	done.size = Vector2(172, 48)
	done.pressed.connect(func(): hide(); closed.emit())
	add_child(done)
	var bindings := Button.new()
	bindings.text = "Call shortcuts…"
	bindings.position = Vector2(24, 538)
	bindings.size = Vector2(300, 48)
	bindings.pressed.connect(func(): binding_panel.show())
	add_child(bindings)
	create_bindings()
	visibility_changed.connect(func():
		if not visible:
			waiting_key = -1
			binding_panel.hide())
	refresh_label()
	hide()

func label(text: String, at: Vector2) -> Label:
	var item := Label.new()
	item.text = text
	item.position = at
	add_child(item)
	return item

func refresh_label() -> void:
	fov_label.text = "Field of view: %d°" % roundi(fov)

func update_preferences() -> void:
	refresh_label()
	if persistence_enabled:
		var config := ConfigFile.new()
		config.set_value("view", "fov", fov)
		config.set_value("view", "steady_camera", steady_camera)
		config.set_value("audio", "spoken_calls", spoken_calls)
		config.set_value("solo", "fast_opponents", fast_opponents)
		config.set_value("solo", "difficulty", difficulty)
		config.set_value("solo", "position", human_position)
		config.set_value("input", "call_keys", call_keys)
		config.save(config_path)
	changed.emit()

func valid_call_key(code: int) -> bool:
	return code > 0 and code not in [KEY_ESCAPE, KEY_Z, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META] and not OS.get_keycode_string(code).is_empty()

func valid_keys(value: Variant) -> bool:
	if not (value is Array or value is PackedInt32Array or value is PackedInt64Array) or value.size() != 3: return false
	var seen := []
	for key in value:
		if not key is int or not valid_call_key(key) or key in seen: return false
		seen.append(key)
	return true

func create_bindings() -> void:
	binding_panel = Panel.new()
	binding_panel.size = size
	binding_panel.add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11252f"), CurlPresentation.GOLD, 12))
	add_child(binding_panel)
	var title := label("Call shortcuts", Vector2(24, 18))
	title.reparent(binding_panel)
	title.add_theme_font_size_override("font_size", 26)
	binding_hint = label("", Vector2(24, 66))
	binding_hint.reparent(binding_panel)
	binding_hint.add_theme_font_size_override("font_size", 17)
	for index in range(3):
		var button := Button.new()
		button.position = Vector2(24, 124 + index * 66)
		button.size = Vector2(512, 52)
		button.pressed.connect(func(): waiting_key = index; refresh_bindings())
		binding_buttons.append(button)
		binding_panel.add_child(button)
	var help := label("Use these keys while calling a solo shot.\nEsc cancels key capture. Z remains inspection zoom.\nRepeated presses repeat your call; held keys do not.", Vector2(24, 340))
	help.reparent(binding_panel)
	help.add_theme_font_size_override("font_size", 17)
	var defaults := Button.new()
	defaults.text = "Restore H / C / O"
	defaults.position = Vector2(24, 538)
	defaults.size = Vector2(300, 48)
	defaults.pressed.connect(func(): call_keys = PackedInt32Array([KEY_H, KEY_C, KEY_O]); waiting_key = -1; update_preferences(); refresh_bindings())
	binding_panel.add_child(defaults)
	var back := Button.new()
	back.text = "Back"
	back.position = Vector2(364, 538)
	back.size = Vector2(172, 48)
	back.pressed.connect(func(): waiting_key = -1; binding_panel.hide())
	binding_panel.add_child(back)
	binding_panel.hide()
	binding_panel.visibility_changed.connect(func():
		if binding_panel.visible:
			refresh_bindings()
			bindings_focus.open(binding_panel)
		else: bindings_focus.close(binding_panel))

func refresh_bindings() -> void:
	for index in range(3): binding_buttons[index].text = "%s: %s" % [["↑ HARD", "≈ CLEAN", "■ OFF"][index], "press a key…" if waiting_key == index else OS.get_keycode_string(call_keys[index])]
	binding_hint.text = "Press a key for %s." % ["HARD", "CLEAN", "OFF"][waiting_key] if waiting_key >= 0 else "Select a call, then press the key you want to use."

func bind_key(code: int) -> bool:
	if waiting_key < 0 or not valid_call_key(code): return false
	var previous := call_keys[waiting_key]
	var duplicate := call_keys.find(code)
	if duplicate >= 0: call_keys[duplicate] = previous
	call_keys[waiting_key] = code
	waiting_key = -1
	update_preferences()
	refresh_bindings()
	return true

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if not binding_panel.visible:
		if event.keycode == KEY_ESCAPE:
			hide()
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		if waiting_key >= 0: waiting_key = -1; refresh_bindings()
		else: binding_panel.hide()
	elif waiting_key >= 0:
		if not bind_key(event.keycode): binding_hint.text = "Choose a non-modifier key other than Esc or Z."
	else: return
	get_viewport().set_input_as_handled()
