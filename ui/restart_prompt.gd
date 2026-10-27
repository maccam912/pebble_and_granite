class_name CurlRestartPrompt
extends Panel
## Local, reversible review before replacing an existing session.
var game
var shade: ColorRect
var focus := CurlModalFocus.new()
var heading: Label
var detail: Label
var cancel_button: Button
var confirm_button: Button
var pending: Callable

func setup(owner_game) -> void:
	game = owner_game
	position = Vector2(350, 250)
	size = Vector2(580, 280)
	add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11252f"), CurlPresentation.GOLD, 12))
	shade = ColorRect.new()
	shade.size = Vector2(1280, 800)
	shade.color = Color(0, 0, 0, .58)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	game.add_child(shade)
	heading = Label.new()
	heading.position = Vector2(24, 22)
	heading.add_theme_font_size_override("font_size", 27)
	add_child(heading)
	detail = Label.new()
	detail.position = Vector2(24, 77)
	detail.size = Vector2(532, 115)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 20)
	add_child(detail)
	cancel_button = Button.new()
	cancel_button.text = "Keep playing"
	cancel_button.position = Vector2(24, 204)
	cancel_button.size = Vector2(252, 52)
	cancel_button.pressed.connect(cancel)
	add_child(cancel_button)
	confirm_button = Button.new()
	confirm_button.position = Vector2(300, 204)
	confirm_button.size = Vector2(256, 52)
	confirm_button.pressed.connect(confirm)
	add_child(confirm_button)
	hide()
	shade.hide()

func ask(title: String, explanation: String, action_text: String, action: Callable) -> void:
	if visible: return
	heading.text = title
	detail.text = explanation
	confirm_button.text = action_text
	pending = action
	game.stop_scrub()
	game.hold_sweep = false
	game.move_child(shade, -1)
	game.move_child(self, -1)
	shade.show()
	show()
	focus.open(self)

func close() -> void:
	hide()
	shade.hide()
	focus.close(self)
	pending = Callable()

func cancel() -> void:
	close()

func confirm() -> void:
	var action := pending
	close()
	if action.is_valid(): action.call()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
