class_name CurlPlayMenu
extends Panel
## Mode navigation pauses local play; active deliveries cannot be replaced.
var game
var shade: ColorRect
var focus := CurlModalFocus.new()
var actions: Dictionary = {}
var caption: Label

func setup(owner_game) -> void:
	game = owner_game
	position = Vector2(340, 140)
	size = Vector2(600, 520)
	add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11252f"), CurlPresentation.GOLD, 12))
	shade = ColorRect.new()
	shade.size = Vector2(1280, 800)
	shade.color = Color(0, 0, 0, .58)
	game.add_child(shade)
	var heading := Label.new()
	heading.text = "Choose your ice"
	heading.position = Vector2(24, 20)
	heading.add_theme_font_size_override("font_size", 27)
	add_child(heading)
	caption = Label.new()
	caption.position = Vector2(24, 65)
	caption.size = Vector2(552, 60)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 18)
	add_child(caption)
	add_action("learn", "Learn to play", 0, func(): game.open_lessons())
	add_action("practice", "Practice", 1, func(): game.select_mode("practice"))
	add_action("drills", "Drills", 2, func(): game.select_mode("drills"))
	add_action("solo", "Solo 4 vs 4", 3, func(): game.select_mode("solo"))
	add_action("mixed", "Mixed doubles", 4, func(): game.select_mode("mixed"))
	add_action("online", "Online rooms", 5, func(): game.open_online())
	add_action("restart", "Fresh ice", 6, func(): game.request_restart())
	add_action("resume", "Resume game", 7, func(): pass)
	actions.resume.theme_type_variation = "PrimaryButton"
	hide()
	shade.hide()

func add_action(key: String, title: String, index: int, callback: Callable) -> void:
	var item := Button.new()
	item.text = title
	item.position = Vector2(24 + (index % 2) * 286, 140 + (index / 2) * 88)
	item.size = Vector2(266, 64)
	item.add_theme_font_size_override("font_size", 22)
	item.pressed.connect(func(): close(); callback.call())
	add_child(item)
	actions[key] = item

func refresh() -> void:
	if actions.is_empty(): return
	var busy: bool = game.run_active or not game.frame.get("in_hand", {}).is_empty()
	for key in ["practice", "drills", "solo", "mixed", "online", "restart"]: actions[key].disabled = busy
	actions.restart.text = "Restart drill" if game.drills.enabled else ("New match" if game.match_mode else "Fresh ice")
	caption.text = "Your shot is paused. Resume it before changing modes." if busy else "Local play is paused. Each mode keeps its own saved session."

func open() -> void:
	if visible: return
	game.cancel_pointer()
	refresh()
	game.move_child(shade, -1)
	game.move_child(self, -1)
	shade.show()
	show()
	focus.open(self)

func close() -> void:
	hide()
	shade.hide()
	focus.close(self)

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
