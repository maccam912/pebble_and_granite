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
	check(not report.is_empty() and report.mode == "practice", "Native UI probe did not report the real initial scene")
	check(report.controls.solo.x > 0 and report.controls.send.is_empty(), "UI probe exported hidden or missing controls")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(report_path))
	game.queue_free()
	await process_frame
	print("INSTALLED_UI_PROBE_OK" if not failed else "INSTALLED_UI_PROBE_FAILED")
	quit(1 if failed else 0)
