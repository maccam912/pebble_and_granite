class_name CurlRoomPanel
extends Control
signal closed
var room := CurlOnline.new()
var directory: CurlRendezvous
var body: Panel
var game: Control
var code_input: LineEdit
var heading: Label
var message: Label
var roster: Label
var host_button: Button
var join_button: Button
var ready_button: Button
var start_button: Button
var renew_button: Button
var reconnect_button: Button
var code := ""
var token := ""
var expires := 0
var generation := 0
var busy := false
var last_address := ""
var ready_value := false
var view_match := true
var was_restoring := false
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	directory = CurlRendezvous.new()
	add_child(directory)
	var shade := ColorRect.new()
	shade.color = Color(0.015, .04, .06, .97)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	body = Panel.new()
	body.position = Vector2(260, 90)
	body.size = Vector2(760, 620)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("102b37")
	background.set_corner_radius_all(14)
	body.add_theme_stylebox_override("panel", background)
	add_child(body)
	heading = label_at("ONLINE MIXED DOUBLES", Vector2(30, 24), 27)
	label_at("Host stays open. Four players • two per team.", Vector2(30, 68), 18)
	host_button = action("Host by code", Vector2(30, 116), host_room)
	code_input = LineEdit.new()
	code_input.position = Vector2(275, 116)
	code_input.size = Vector2(180, 48)
	code_input.placeholder_text = "ROOM CODE"
	code_input.max_length = 4
	code_input.add_theme_font_size_override("font_size", 24)
	body.add_child(code_input)
	join_button = action("Join by code", Vector2(480, 116), join_room)
	roster = label_at("", Vector2(30, 195), 22)
	roster.size = Vector2(690, 180)
	roster.add_theme_constant_override("line_spacing", 10)
	message = label_at("Create a room or enter a four-character code.", Vector2(30, 385), 18)
	message.size = Vector2(690, 70)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ready_button = action("Ready", Vector2(30, 478), toggle_ready)
	start_button = action("Start match", Vector2(275, 478), start_match)
	renew_button = action("New room code", Vector2(480, 478), register_code)
	reconnect_button = action("Reconnect", Vector2(275, 548), reconnect)
	action("Leave / back", Vector2(30, 548), leave)
	room.changed.connect(refresh)
	room.failed.connect(func(error: String): message.text = error; refresh())
	refresh()
func label_at(text: String, pos: Vector2, size_px: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", size_px)
	body.add_child(label)
	return label
func action(text: String, pos: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.custom_minimum_size = Vector2(200, 48)
	button.add_theme_font_size_override("font_size", 19)
	button.pressed.connect(callback)
	body.add_child(button)
	return button
func host_room() -> void:
	view_match = true
	if busy or room.peer != null: return
	var error := room.host()
	if not error.is_empty(): message.text = error; return
	await register_code()
func register_code() -> void:
	if busy or not room.is_host: return
	busy = true
	refresh()
	var current := generation
	var address := room.endpoint
	var reply := await directory.register(address)
	busy = false
	if current != generation or not room.is_host or room.endpoint != address:
		refresh()
		if reply.ok: await directory.revoke(reply.payload.code, reply.payload.revoke_token)
		return
	if reply.ok:
		var old_code := code
		var old_token := token
		code = reply.payload.code
		token = reply.payload.revoke_token
		expires = Time.get_ticks_msec() + 600000
		message.text = "Share code %s with three friends. Everyone selects Ready." % code
		refresh()
		if not old_code.is_empty() and old_code != code: await directory.revoke(old_code, old_token)
	else: message.text = reply.message
	refresh()
func join_room() -> void:
	view_match = true
	if busy or room.peer != null: return
	if not CurlRendezvous.valid_code(code_input.text):
		message.text = "Enter four letters or numbers from the host's room code."
		return
	busy = true
	var current := generation
	refresh()
	var reply := await directory.resolve(code_input.text)
	busy = false
	if current != generation:
		refresh()
		return
	if reply.ok:
		last_address = reply.payload.endpoint_id
		var error := room.join(last_address)
		message.text = "Connecting to host…" if error.is_empty() else error
	else: message.text = reply.message
	refresh()
func reconnect() -> void:
	view_match = true
	if busy or room.peer != null or last_address.is_empty(): return
	var error := room.join(last_address)
	message.text = "Restoring your seat…" if error.is_empty() else error
	refresh()
func toggle_ready() -> void:
	ready_value = not ready_value
	var error := room.ready(ready_value)
	if not error.is_empty(): message.text = error
func start_match() -> void:
	view_match = true
	if room.state.get("phase") != null: return
	var error := room.start_match()
	if not error.is_empty(): message.text = error
func refresh() -> void:
	if body == null: return
	var connected := room.peer != null
	host_button.disabled = busy or connected
	join_button.disabled = busy or connected
	code_input.editable = not busy and not connected
	ready_button.disabled = not connected or room.state.is_empty() or room.state.get("phase") != null
	start_button.text = "Return to match" if room.state.get("phase") != null else "Start match"
	start_button.disabled = room.state.get("phase") == null and (not room.is_host or room.state.get("players", []).size() != 4 or not room.state.players.all(func(p): return p != null and p.ready))
	renew_button.disabled = busy or not room.is_host
	reconnect_button.visible = not connected and not last_address.is_empty()
	heading.text = "ROOM " + code if not code.is_empty() else "ONLINE MIXED DOUBLES"
	var rows := PackedStringArray()
	for index in range(4):
		var player = room.state.get("players", [null, null, null, null])[index]
		var description := "Waiting for player"
		if player != null:
			description = "Disconnected" if player.peer == null else ("Ready" if player.ready else "Connected")
			if room.state.get("phase") != null and player.peer != null: description = "Synced" if player.synchronized else "Synchronizing…"
			if index == room.seat_index():
				description += " • You"
				ready_value = player.ready
		rows.append("%s • Player %d     %s" % ["Gold" if index < 2 else "Cyan", index % 2 + 1, description])
	roster.text = "\n".join(rows)
	ready_button.text = "Not ready" if ready_value else "Ready"
func _process(_delta: float) -> void:
	room.poll()
	if not visible: return
	if room.receiving_snapshot and room.replica != null:
		var progress: Dictionary = room.replica.restore_progress()
		message.text = "Receiving match history…" if progress.is_empty() else "Rebuilding match: %d / %d records. You can leave at any time." % [progress.records, progress.total]
		was_restoring = true
	elif was_restoring:
		was_restoring = false
		if room.peer != null: message.text = "Match synchronized."
	if expires > 0 and Time.get_ticks_msec() > expires:
		expires = 0
		message.text = "The code expired. Existing players stay connected; choose New room code for new arrivals."
	if view_match and not room.frame().is_empty() and game == null:
		game = load("res://scenes/online_game.gd").new()
		game.online = room
		game.leave_requested.connect(show_lobby)
		add_child(game)
		body.hide()
	elif game != null and (room.peer == null or room.state.get("phase") == null):
		game.queue_free()
		game = null
		show_lobby()
		view_match = true
	elif game != null:
		game.visible = view_match
		body.visible = not view_match
func show_lobby() -> void:
	view_match = false
	if game != null:
		game.cancel_pointer()
		game.hide()
	body.show()
	refresh()
func leave() -> void:
	generation += 1
	room.close()
	if game != null:
		game.queue_free()
		game = null
	show_lobby()
	var previous_code := code
	var previous_token := token
	code = ""
	token = ""
	expires = 0
	hide()
	closed.emit()
	if not previous_code.is_empty(): await directory.revoke(previous_code, previous_token)

func _exit_tree() -> void:
	room.close()
