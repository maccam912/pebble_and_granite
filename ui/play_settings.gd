class_name CurlPlaySettings
extends Panel
## Device preferences only. Match commands and replay data stay in Rust.
signal changed
signal closed
var fov := 52.0
var fast_opponents := false
var spoken_calls := true
var difficulty := 1
var human_position := 0
var persistence_enabled := true
var fov_label: Label
var fov_slider: HSlider
var fast_toggle: CheckButton
var difficulty_choice: OptionButton
var position_choice: OptionButton
const PATH := "user://play-settings.cfg"
const POSITIONS := ["Lead", "Second", "Vice", "Skip"]

func _ready() -> void:
	position = Vector2(360, 128)
	size = Vector2(560, 544)
	add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11252f"), CurlPresentation.GOLD, 12))
	var config := ConfigFile.new()
	if persistence_enabled and config.load(PATH) == OK:
		fov = clampf(float(config.get_value("view", "fov", 52.0)), 40, 85)
		spoken_calls = bool(config.get_value("audio", "spoken_calls", true))
		fast_opponents = bool(config.get_value("solo", "fast_opponents", false))
		difficulty = clampi(int(config.get_value("solo", "difficulty", 1)), 0, 2)
		human_position = clampi(int(config.get_value("solo", "position", 0)), 0, 3)
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
	fast_toggle = CheckButton.new()
	fast_toggle.text = "Fast opponent travel between hog lines (4×)"
	fast_toggle.position = Vector2(18, 164)
	fast_toggle.size = Vector2(524, 48)
	fast_toggle.button_pressed = fast_opponents
	fast_toggle.toggled.connect(func(value): fast_opponents = value; update_preferences())
	add_child(fast_toggle)
	label("AI shot accuracy", Vector2(24, 232))
	difficulty_choice = OptionButton.new()
	difficulty_choice.position = Vector2(268, 220)
	difficulty_choice.size = Vector2(268, 50)
	for tier in ["Club · forgiving", "Competitive", "Elite · precise"]: difficulty_choice.add_item(tier)
	difficulty_choice.select(difficulty)
	difficulty_choice.item_selected.connect(func(value): difficulty = value; update_preferences())
	add_child(difficulty_choice)
	label("Your solo position", Vector2(24, 296))
	position_choice = OptionButton.new()
	position_choice.position = Vector2(268, 284)
	position_choice.size = Vector2(268, 50)
	for role in POSITIONS: position_choice.add_item(role)
	position_choice.select(human_position)
	position_choice.item_selected.connect(func(value): human_position = value; update_preferences())
	add_child(position_choice)
	var speech := CheckButton.new()
	speech.text = "Spoken skip calls (device voice, if available)"
	speech.position = Vector2(18, 346)
	speech.size = Vector2(524, 48)
	speech.button_pressed = spoken_calls
	speech.toggled.connect(func(value): spoken_calls = value; update_preferences())
	add_child(speech)
	var note := label("Text and symbols always show skip calls.\nZ or the Zoom button inspects the house.", Vector2(24, 410))
	note.add_theme_font_size_override("font_size", 17)
	var done := Button.new()
	done.text = "Done"
	done.position = Vector2(364, 482)
	done.size = Vector2(172, 48)
	done.pressed.connect(func(): hide(); closed.emit())
	add_child(done)
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
		config.set_value("audio", "spoken_calls", spoken_calls)
		config.set_value("solo", "fast_opponents", fast_opponents)
		config.set_value("solo", "difficulty", difficulty)
		config.set_value("solo", "position", human_position)
		config.save(PATH)
	changed.emit()
