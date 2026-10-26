extends SceneTree
var failed := false
const SAVE := "user://test-held-practice.json"
const MATCH := "user://test-held-match.json"
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func scene() -> Control:
	var result: Control = load("res://scenes/play.tscn").instantiate()
	result.persistence_enabled = false
	result.save_path = SAVE
	result.match_save_path = MATCH
	root.add_child(result)
	result.set_process(false)
	return result
func hash_of(game: Control) -> String:
	return game.session.match_hash() if game.match_mode else game.session.state_hash()
func clean() -> void:
	for path in [SAVE, MATCH]:
		for suffix in ["", ".bak", ".tmp"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
func run() -> void:
	clean()
	for match_mode in [false, true]:
		var game := scene()
		if match_mode:
			game.switch_mode()
			game.apply_placement()
		var clock := [0]
		game.input_clock = func(): return clock[0]
		game.one_push = true
		var point: Vector2 = game.handle_point()
		game.begin_pointer(0, point)
		clock[0] = 20000
		game.move_pointer(point + Vector2(0, -4.2))
		clock[0] = 120000
		game.move_pointer(point + Vector2(0, -25.2))
		clock[0] = 2200000
		game.update_delivery()
		check(not game.frame.in_hand.is_empty() and game.frame.in_hand.in_play, "Held stone never crossed tee")
		var held_y: int = game.frame.in_hand.y_um
		var thinking: int = game.frame.get("clock_gold", 0)
		game.persistence_enabled = true
		game._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST if match_mode else NOTIFICATION_APPLICATION_PAUSED)
		var frozen := hash_of(game)
		clock[0] = 60000000
		game._process(10)
		game._notification(NOTIFICATION_APPLICATION_RESUMED)
		game._process(.016)
		check(hash_of(game) == frozen, "Interruption advanced or discarded held delivery")
		game.next_throw()
		check(hash_of(game) == frozen, "In-play return button rewound delivery")
		game.persistence_enabled = false
		game.queue_free()
		await process_frame
		var restored := scene()
		restored.persistence_enabled = true
		if match_mode: restored.restore_match()
		else: restored.restore_practice()
		check(hash_of(restored) == frozen, "Held save restored to a different state")
		check(restored.frame.in_hand.y_um == held_y, "Restored stone moved back to hack")
		var resumed_clock := [100000000]
		restored.input_clock = func(): return resumed_clock[0]
		restored.update_spatial(0)
		point = restored.handle_point()
		restored.begin_pointer(0, point)
		resumed_clock[0] += 100000
		restored.move_pointer(point)
		resumed_clock[0] += 100000
		restored.end_pointer(point + Vector2(-30, -8))
		check(restored.run_active and restored.frame.in_hand.is_empty(), "Regripped stone did not release")
		check(restored.release_report.turn == -1, "Regrip lost finishing curl")
		if match_mode: check(restored.frame.clock_gold == thinking, "Clock ran after tee during resume")
		restored.persistence_enabled = false
		restored.queue_free()
		await process_frame
		clean()
	print("HELD_RESUME_OK" if not failed else "HELD_RESUME_FAILED")
	quit(1 if failed else 0)
