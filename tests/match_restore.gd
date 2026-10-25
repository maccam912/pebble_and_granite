extends SceneTree
var failed := false
const MATCH_SAVE := "user://test-match-restore.json"
const PRACTICE_SAVE := "user://test-match-practice.json"
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failed = true
func _initialize() -> void: call_deferred("run")
func make_scene() -> Control:
	var scene: Control = load("res://scenes/lab.tscn").instantiate()
	scene.persistence_enabled = false
	scene.match_save_path = MATCH_SAVE
	scene.save_path = PRACTICE_SAVE
	root.add_child(scene)
	scene.set_process(false)
	return scene
func hash_of(scene: Control) -> String:
	return scene.session.match_hash()
func finish(scene: Control) -> void:
	for i in range(240):
		if scene.session.frame().resting: break
		scene.session.step_ticks(64, 0, 0, 180)
	check(scene.session.frame().resting, "Match shot failed to settle")
	scene.frame = scene.session.frame()
	scene.run_active = false
func run() -> void:
	for path in [MATCH_SAVE, PRACTICE_SAVE]:
		for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var a := make_scene()
	a.persistence_enabled = true
	a.save_practice()
	var practice := FileAccess.get_file_as_string(PRACTICE_SAVE)
	a.switch_mode()
	a.apply_placement()
	check(a.session.deliver(2050, -900, 1).is_empty(), "Match delivery failed")
	for i in range(16): a.session.step_ticks(64, 200, 0, 180)
	a.save_practice()
	var midway := hash_of(a)
	var b := make_scene()
	b.persistence_enabled = true
	b.restore_match()
	check(b.match_mode and b.run_active, "Match did not resume interrupted shot")
	check(hash_of(b) == midway, "Match disk roundtrip changed authority state")
	finish(a)
	finish(b)
	check(hash_of(a) == hash_of(b), "Restored match diverged after continuation")
	check(FileAccess.get_file_as_string(PRACTICE_SAVE) == practice, "Match save overwrote practice")
	a.save_practice()
	var bad := FileAccess.open(MATCH_SAVE, FileAccess.WRITE)
	bad.store_string("broken")
	bad.close()
	var c := make_scene()
	c.persistence_enabled = true
	c.restore_match()
	check(hash_of(c) == midway, "Match backup recovery failed")
	check(FileAccess.get_file_as_string(MATCH_SAVE) == "broken", "Restore overwrote corrupt match")
	var before := hash_of(a)
	check(not a.session.load_match("{}").is_empty(), "Invalid match accepted")
	check(hash_of(a) == before, "Invalid match load mutated live game")
	for scene in [a,b,c]:
		scene.persistence_enabled = false
		scene.queue_free()
	for path in [MATCH_SAVE, PRACTICE_SAVE]:
		for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("MATCH_RESTORE_OK" if not failed else "MATCH_RESTORE_FAILED")
	quit(1 if failed else 0)
