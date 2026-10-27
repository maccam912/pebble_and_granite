class_name CurlIceBoard
extends Panel
## Observations are rebuilt by Rust. Only optional annotations use a UI sidecar.
class PathPlot extends Control:
	var shot: Dictionary = {}
	func at(point: Vector2) -> Vector2: return Vector2(210, 130) + Vector2(point.x, -point.y) * 60.0
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0c1d26"))
		for ring in [[1.829, "214b65"], [1.22, "e1dfd4"], [.61, "b65a55"], [.15, "e1dfd4"]]:
			draw_circle(at(Vector2.ZERO), ring[0] * 60.0, Color(ring[1]))
		for x in [-2.375, 0, 2.375]: draw_line(at(Vector2(x, -4.4)), at(Vector2(x, 2.2)), Color("5c7178"), 1)
		draw_line(at(Vector2(-2.375, 0)), at(Vector2(2.375, 0)), Color("52676e"), 1)
		if shot.is_empty(): return
		var origin: Vector2 = shot.release_pos
		var velocity: Vector2 = shot.release_vel
		if velocity.y > 0:
			var a := Vector2(origin.x + (-4.4 - origin.y) * velocity.x / velocity.y, -4.4)
			var b := Vector2(origin.x + (2.2 - origin.y) * velocity.x / velocity.y, 2.2)
			draw_dashed_line(at(a), at(b), Color("a8babf"), 1.5, 8)
		var path := PackedVector2Array()
		for point in shot.path: path.append(at(point))
		if path.size() >= 2:
			draw_polyline(path, Color("10232b"), 5, true)
			draw_polyline(path, CurlPresentation.GOLD, 2.5, true)
		if shot.has_finish:
			var finish := at(shot.finish)
			draw_circle(finish, 7, Color("10232b"))
			draw_circle(finish, 5, CurlPresentation.GOLD)
			if not shot.in_play:
				draw_line(finish - Vector2(5, 5), finish + Vector2(5, 5), Color.WHITE, 2)
				draw_line(finish + Vector2(-5, 5), finish + Vector2(5, -5), Color.WHITE, 2)

var game
var menu_button: Button
var modal_focus := CurlModalFocus.new()
var shade: ColorRect
var team_choice: OptionButton
var shot_list: ItemList
var plot: PathPlot
var stats_label: Label
var detail_label: Label
var note_input: LineEdit
var save_button: Button
var message: Label
var selected: Dictionary = {}
var shown: Array = []
var notes: Dictionary = {}
var notes_path_override := ""

func _ready() -> void:
	position = Vector2(120, 100)
	size = Vector2(1040, 600)
	add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11252f"), CurlPresentation.GOLD, 12))
	label("Team ice board", Vector2(24, 14), 27)
	label("Actual path —  Release ray ┄  •  House detail", Vector2(590, 56), 16)
	team_choice = OptionButton.new()
	team_choice.position = Vector2(725, 14)
	team_choice.size = Vector2(160, 44)
	team_choice.add_item("Gold team")
	team_choice.add_item("Cyan team")
	team_choice.item_selected.connect(func(_value): refresh())
	add_child(team_choice)
	var close := Button.new()
	close.text = "Close"
	close.position = Vector2(900, 14)
	close.size = Vector2(116, 44)
	close.pressed.connect(hide)
	add_child(close)
	label("Recent deliveries · select a path to inspect or annotate", Vector2(24, 56), 16)
	shot_list = ItemList.new()
	shot_list.position = Vector2(24, 82)
	shot_list.size = Vector2(535, 258)
	shot_list.fixed_icon_size = Vector2i(24, 24)
	shot_list.add_theme_font_size_override("font_size", 19)
	shot_list.add_theme_constant_override("v_separation", 8)
	shot_list.item_selected.connect(select_shot)
	add_child(shot_list)
	plot = PathPlot.new()
	plot.position = Vector2(590, 82)
	plot.size = Vector2(420, 390)
	plot.clip_contents = true
	plot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plot)
	stats_label = label("", Vector2(24, 355), 18)
	stats_label.size = Vector2(535, 160)
	detail_label = label("", Vector2(590, 480), 16)
	detail_label.size = Vector2(420, 55)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_input = LineEdit.new()
	note_input.position = Vector2(24, 540)
	note_input.size = Vector2(775, 48)
	note_input.placeholder_text = "Your ice note for this path (160 characters)"
	note_input.max_length = 160
	note_input.add_theme_font_size_override("font_size", 18)
	note_input.text_submitted.connect(func(_text): save_note())
	add_child(note_input)
	save_button = Button.new()
	save_button.text = "Save note"
	save_button.position = Vector2(820, 540)
	save_button.size = Vector2(190, 48)
	save_button.pressed.connect(save_note)
	add_child(save_button)
	message = label("", Vector2(24, 510), 15)
	hide()

func setup(owner_game) -> void:
	game = owner_game
	menu_button = game.button("Ice board", Vector2(450, 77), toggle)
	menu_button.custom_minimum_size = Vector2(180, 38)
	menu_button.size = menu_button.custom_minimum_size
	shade = ColorRect.new()
	shade.size = Vector2(1280, 800)
	shade.color = Color(0, 0, 0, .48)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.hide()
	game.add_child(shade)
	visibility_changed.connect(func():
		shade.visible = visible
		if visible:
			game.move_child(shade, -1)
			game.move_child(self, -1)
			modal_focus.open(self)
		else: modal_focus.close(self))

func label(text: String, at: Vector2, font_size: int) -> Label:
	var item := Label.new()
	item.text = text
	item.position = at
	item.add_theme_font_size_override("font_size", font_size)
	add_child(item)
	return item

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()

func refresh_button() -> void:
	if menu_button != null: menu_button.disabled = game.pointer != -99

func toggle() -> void:
	if game.pointer != -99: return
	if visible: hide(); return
	game.hold_sweep = false
	game.stop_scrub()
	load_notes()
	refresh()
	show()

func role_name(position: int) -> String:
	if not game.match_mode: return "Practice"
	return CurlPlaySettings.POSITIONS[position] if game.frame.get("format") == "Teams" else "Player %d" % (position + 1)

func refresh() -> void:
	if game == null: return
	var own_only: bool = game.solo != null and game.solo.enabled
	team_choice.visible = not own_only and game.match_mode
	if own_only: team_choice.select(0)
	var team := team_choice.selected
	var book: Dictionary = game.session.shot_reviews()
	shown.clear()
	shot_list.clear()
	for shot in book.shots:
		if game.match_mode and shot.team != team: continue
		shown.append(shot)
		var split := "—" if shot.hog_split_ms < 0 else "%.2f s" % (shot.hog_split_ms / 1000.0)
		shot_list.add_item("%s%d · %s · %.3f m/s · HH %s" % ["E" if game.match_mode else "#", shot.end if game.match_mode else shot.ordinal, role_name(shot.position) if game.match_mode else game.team_name(shot.team), shot.speed_mm_s / 1000.0, split])
	var rows := ["Delivery totals · all release weights combined"]
	for player in book.players:
		if (game.match_mode and player.team != team) or player.shots == 0: continue
		rows.append("%s: %d delivered · %d late releases · %.3f ± %.3f m/s" % [role_name(player.position) if game.match_mode else game.team_name(player.team), player.shots, player.hog_faults, player.mean_mm_s / 1000.0, player.spread_mm_s / 1000.0])
	stats_label.text = "\n".join(rows)
	message.text = "The current shot is paused while the board is open." if game.run_active else "Notes describe observed paths; contact shots also reflect collisions."
	if shown.is_empty():
		selected = {}
		plot.shot = {}
		plot.queue_redraw()
		detail_label.text = "Play a shot to record a path and true hog-to-hog split."
		note_input.text = ""
		note_input.editable = false
		save_button.disabled = true
	else:
		shot_list.select(0)
		select_shot(0)

func select_shot(index: int) -> void:
	if index < 0 or index >= shown.size(): return
	selected = shown[index]
	plot.shot = selected
	plot.queue_redraw()
	var finish: Vector2 = selected.finish
	var rest := "Stone removed" if not selected.in_play else "Rest: %+.2f m across · %+.2f m from tee" % [finish.x, finish.y]
	var curl := absf(selected.curl_mm / 1000.0)
	detail_label.text = "%s\n%.2f m %s of release ray · %.2f turns · %d contacts" % [rest, curl, "right" if selected.curl_mm >= 0 else "left", selected.turns_milli / 1000.0, selected.contacts]
	note_input.text = str(notes.get(selected.key, ""))
	note_input.editable = true
	save_button.disabled = false

func notes_path() -> String:
	if not notes_path_override.is_empty(): return notes_path_override
	var mode := "solo" if game.solo != null and game.solo.enabled else ("mixed" if game.match_mode else ("drills" if game.drills != null and game.drills.enabled else "practice"))
	return "user://ice-notes-" + mode + ".json"

func valid_notes(data: Variant) -> bool:
	if not data is Dictionary or data.get("schema") != 1 or not data.get("notes") is Dictionary or data.notes.size() > 32: return false
	var pattern := RegEx.create_from_string("^[a-f0-9]{16}$")
	for key in data.notes:
		if not key is String or pattern.search(key) == null or not data.notes[key] is String or data.notes[key].length() > 160: return false
	return true

func load_notes() -> void:
	notes.clear()
	if not game.persistence_enabled: return
	for filename in [notes_path(), notes_path() + ".bak"]:
		var file := FileAccess.open(filename, FileAccess.READ)
		if file == null: continue
		if file.get_length() > 16384: file.close(); continue
		var parser := JSON.new()
		var error := parser.parse(file.get_as_text())
		file.close()
		if error == OK and valid_notes(parser.data): notes = parser.data.notes; return

func save_note() -> void:
	if selected.is_empty(): return
	var text := note_input.text.strip_edges()
	if text.is_empty(): notes.erase(selected.key)
	else: notes[selected.key] = text.left(160)
	while notes.size() > 32: notes.erase(notes.keys()[0])
	message.text = "Note saved for this observed path." if store_notes() else "Note kept for this run; it could not be saved on this device."

func store_notes() -> bool:
	if not game.persistence_enabled: return true
	var destination := ProjectSettings.globalize_path(notes_path())
	var file := FileAccess.open(destination + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"schema": 1, "notes": notes}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return false
	if FileAccess.file_exists(destination):
		if FileAccess.file_exists(destination + ".bak"): DirAccess.remove_absolute(destination + ".bak")
		if DirAccess.rename_absolute(destination, destination + ".bak") != OK: return false
	return DirAccess.rename_absolute(destination + ".tmp", destination) == OK

func new_session(clear_saved: bool) -> void:
	notes.clear()
	hide()
	if clear_saved and game.persistence_enabled:
		store_notes()
		if FileAccess.file_exists(notes_path() + ".bak"): DirAccess.remove_absolute(ProjectSettings.globalize_path(notes_path() + ".bak"))
