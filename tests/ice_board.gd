extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func settle(game) -> void:
	for i in range(400):
		if not game.run_active: break
		game._process(64.0 / 240.0)
	check(not game.run_active, "Ice-board shot did not settle")
func run() -> void:
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	if "--mobile-ui" in OS.get_cmdline_user_args(): game.mobile_ui = true
	root.add_child(game)
	game.set_process(false)
	check(game.session.deliver_slide(2700000, -36000000, -900, 1).is_empty(), "Early release rejected")
	game.frame = game.session.frame()
	game.run_active = true
	game.phase = "Travel"
	game.release_report = {"speed_mm_s": 2700}
	settle(game)
	check(game.frame.hog_split_ms > 0 and game.frame.hog_split_ms + 2000 < game.frame.hog_tick * 1000.0 / 240.0, "Early release displayed release-to-hog as hog-to-hog")
	check("Hog-to-hog" in game.report, "Release report did not use the true split")
	game.next_throw()
	check(game.session.deliver(2050, -900, 1).is_empty(), "Second observed release rejected")
	game.frame = game.session.frame()
	game.run_active = true
	game.phase = "Travel"
	game.release_report = {"speed_mm_s": 2050}
	settle(game)
	var book: Dictionary = game.session.shot_reviews()
	check(book.shots.size() == 2 and book.shots[0].path.size() > 20, "Native shot observations missing")
	var restore = ClassDB.instantiate("CurlSession")
	check(restore.load_session(game.session.session_json()).is_empty(), "Observed practice save failed to load")
	var rebuilt: Dictionary = restore.shot_reviews()
	check(rebuilt == book, "Ice board did not rebuild exactly from the practice journal")
	var before: String = game.session.state_hash()
	game.ice_board.toggle()
	check(game.ice_board.visible and game.ice_board.shown.size() == 2, "Ice-board UI did not show observed paths")
	game._process(3.0)
	game.begin_pointer(0, game.handle_point())
	check(game.session.state_hash() == before and game.pointer == -99, "Ice-board inspection mutated the simulation or input")
	game.ice_board.notes_path_override = "user://ice-board-note-test.json"
	game.persistence_enabled = true
	game.ice_board.note_input.text = "A little more curl on this path."
	game.ice_board.save_note()
	var key: String = game.ice_board.selected.key
	game.ice_board.note_input.text = "Second observation."
	game.ice_board.save_note()
	game.ice_board.load_notes()
	check(game.ice_board.notes.get(key) == "Second observation.", "Path annotation did not persist")
	var file := FileAccess.open(game.ice_board.notes_path(), FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	game.ice_board.load_notes()
	check(game.ice_board.notes.get(key) == "A little more curl on this path.", "Path annotation backup recovery failed")
	game.persistence_enabled = false
	check(not game.ice_board.valid_notes({"schema": 1, "notes": {"wrong": "bad"}}), "Malformed path key accepted")
	game.ice_board.refresh()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for i in range(12): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/evidence/ice-board.png")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(game.ice_board.notes_path() + suffix))
	game.ice_board.hide()
	game.queue_free()
	await process_frame
	print("ICE_BOARD_OK" if not failed else "ICE_BOARD_FAILED")
	quit(1 if failed else 0)
