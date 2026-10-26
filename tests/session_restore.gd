extends SceneTree
var failed := false
const TEST_SAVE := "user://test-session-restore.json"

func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func make_scene() -> Control:
	var scene: Control = load("res://scenes/lab.tscn").instantiate()
	scene.persistence_enabled = false
	scene.save_path = TEST_SAVE
	root.add_child(scene)
	return scene

func finish(scene: Control) -> void:
	var count := 0
	while not scene.session.frame().resting and count < 1000:
		scene.session.step_ticks(16, 0, 0, 180)
		count += 1
	check(scene.session.frame().resting, "Stone did not settle")
	scene.frame = scene.session.frame()
	scene.run_active = false

func run() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE + suffix))
	var a := make_scene()
	check(a.session.deliver(2050, -900, 1).is_empty(), "Initial release failed")
	for i in range(125): a.session.step_ticks(16, 255, 0, 180)
	var halfway: String = a.session.state_hash()
	a.persistence_enabled = true
	a.save_practice()
	check(a.save_allowed, "Save failed")
	var b := make_scene()
	b.persistence_enabled = true
	b.restore_practice()
	check(b.run_active, "Mid-shot restore did not resume travel")
	check(b.session.state_hash() == halfway, "Mid-shot state changed on disk roundtrip")
	finish(a)
	finish(b)
	check(a.session.state_hash() == b.session.state_hash(), "Restored shot diverged after continuation")
	# Releasing a held sweep after rest must not become a new delivery gesture.
	a.phase = "Stone at rest"
	a.pointer = -1
	a.sweeping = true
	a.end_pointer(Vector2(160, 200))
	check(a.phase == "Stone at rest", "Sweep release erased the completed-shot report")
	a.next_throw()
	check(a.frame.stones.size() == 1, "Next stone erased the field")
	check(a.frame.ice_cells > 0, "Next stone erased the ice")
	check(a.session.deliver(2070, -800, -1).is_empty(), "Second release failed")
	finish(a)
	check(a.frame.stones.size() == 2, "Practice failed to retain two stones")
	a.save_practice()
	# Corrupt current file. Recovery must use the prior valid save without writing
	# a new file over the evidence of the failure during restore.
	var bad := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	bad.store_string("broken save")
	bad.close()
	var c := make_scene()
	c.persistence_enabled = true
	c.restore_practice()
	check(c.session.frame().stones.size() == 1, "Backup recovery failed")
	check(FileAccess.get_file_as_string(TEST_SAVE) == "broken save", "Restore overwrote corrupt save")
	# Native load errors must be atomic.
	var before: String = a.session.state_hash()
	check(not a.session.load_session("{}").is_empty(), "Invalid log was accepted")
	check(before == a.session.state_hash(), "Invalid restore partially changed session")
	# A hog release consumes a stone without disturbing the existing field/ice.
	var fault: Object = ClassDB.instantiate("CurlSession")
	check(fault.hog_violation().is_empty(), "Practice hog fault rejected")
	var fault_hash: String = fault.state_hash()
	var restored: Object = ClassDB.instantiate("CurlSession")
	check(restored.load_session(fault.session_json()).is_empty(), "Hog fault restore failed")
	check(restored.state_hash() == fault_hash, "Hog fault replay diverged")
	check(restored.frame().stones.size() == 1 and not restored.frame().stones[0].active, "Faulted stone remained active")
	check(restored.deliver(2050, -900, 1).is_empty(), "Fault prevented next practice delivery")
	var in_flight: String = restored.state_hash()
	check(not restored.hog_violation().is_empty(), "Fault accepted during flight")
	check(restored.state_hash() == in_flight, "Rejected fault mutated flight")
	for scene in [a,b,c]:
		scene.persistence_enabled = false
		scene.queue_free()
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE + suffix))
	print("SESSION_RESTORE_OK" if not failed else "SESSION_RESTORE_FAILED")
	quit(1 if failed else 0)
