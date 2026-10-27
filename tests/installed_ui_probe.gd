extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var nonce := "abcdef0123456789abcdef0123456789"
	var path := "user://diagnostics/self-test-request.json"
	var report_path := "user://diagnostics/ui-state-" + nonce + ".json"
	DirAccess.make_dir_recursive_absolute("user://diagnostics")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(report_path))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": 3, "nonce": nonce}))
	file.close()
	var game = load("res://scenes/play.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	check(game.installed_ui_nonce == nonce and not FileAccess.file_exists(path), "One-use UI probe was not consumed")
	check(not game.persistence_enabled and not game.play_settings.persistence_enabled, "Installed probe can overwrite player saves/preferences")
	var deadline := Time.get_ticks_msec() + 3000
	var report: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not FileAccess.file_exists(report_path): continue
		var input := FileAccess.open(report_path, FileAccess.READ)
		var value = JSON.parse_string(input.get_as_text())
		input.close()
		if value is Dictionary and value.get("nonce") == nonce: report = value; break
	if report.is_empty():
		push_error("Native UI observer produced no report")
		game.queue_free()
		quit(1)
		return
	check(not report.is_empty() and report.mode == "practice", "Native UI probe did not report the real initial scene")
	check(not report.controls.menu.is_empty() and report.controls.solo.is_empty() and report.controls.send.is_empty(), "UI probe exported hidden or missing controls")
	check(report.controls.in_turn.is_empty() and report.controls.out_turn.is_empty() and not report.restart_visible, "Probe exposed hidden skip/restart controls")
	check(report.handle.x > 0 and report.handle.y > 0 and report.controls.drills.is_empty(), "Probe did not map the live handle or exposed a hidden drill control")
	game.drills.toggle()
	game.drills.kind = 4
	game.reset(false)
	var observer
	for child in game.get_children():
		if child.get_script() == load("res://net/installed_ui_probe.gd"): observer = child; break
	check(observer != null, "UI observer missing")
	if observer != null: observer.write_state()
	var drill_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	check(drill_report.mode == "drills" and drill_report.delivered == 0 and drill_report.drill_results.is_empty() and not drill_report.controls.drill_kind.is_empty(), "Takeout setup diagnostic is wrong")
	var session_path := "user://diagnostics/ui-session-" + nonce + ".json"
	var copy = ClassDB.instantiate("CurlSession")
	check(copy.load_session(FileAccess.get_file_as_string(session_path)).is_empty() and copy.state_hash() == game.session.state_hash(), "Exported target journal failed to replay")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(session_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(report_path))
	game.queue_free()
	await process_frame
	print("INSTALLED_UI_PROBE_OK" if not failed else "INSTALLED_UI_PROBE_FAILED")
	quit(1 if failed else 0)
