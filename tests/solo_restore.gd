extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func make_scene():
	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	game.set_process(false)
	game.solo.start()
	game.solo.save_path = "user://solo-restore-test.json"
	return game
func run() -> void:
	var game = make_scene()
	game.play_settings.human_position = 2
	game.play_settings.difficulty = 0
	check(game.session.deliver(2050, -900, 1).is_empty(), "Solo test release rejected")
	check(game.session.set_solo_target(-800, -3000).is_empty(), "Solo target rejected")
	game.session.step_solo_ticks(64, 0, 0, 0, 180, 0)
	game.frame = game.session.frame()
	game.run_active = true
	game.phase = "Travel"
	game.persistence_enabled = true
	game.save_practice()
	game.save_practice() # Same state in backup for recovery fixture.
	var hash_before: String = game.session.match_hash()
	var other = make_scene()
	other.persistence_enabled = true
	other.restore_current(true)
	check(other.run_active and other.frame.format == "Teams", "In-flight solo did not restore")
	check(other.session.match_hash() == hash_before, "Solo restore changed the journal hash")
	check(other.play_settings.human_position == 2 and other.play_settings.difficulty == 0, "Solo roster/accuracy lost on restore")
	check(other.frame.solo_target_x_mm == -799 or other.frame.solo_target_x_mm == -800, "Solo called target lost")
	check(other.frame.solo_target_y_mm == -3000, "Solo weight target lost")
	check(other.solo.shot_team == 0, "Restored shot changed team")
	var file := FileAccess.open(game.solo.save_path, FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	other.reset(false)
	other.restore_current(true)
	check(other.session.match_hash() == hash_before and other.run_active, "Solo previous-save recovery failed")
	# Accelerated watching runs the same fixed ticks and produces the same result.
	for scene in [game, other]:
		scene.persistence_enabled = false
		scene.session.hog_violation() # Rejected in flight; must be atomic.
		scene.solo.shot_team = 1 # Presentation fixture: permit opponent watching.
		scene.solo.ai_effort = 0
		scene.solo.advice_time = INF
	other.play_settings.fast_opponents = true
	var real_steps := [0, 0]
	for i in range(3000):
		for index in range(2):
			var scene = [game, other][index]
			if scene.run_active:
				scene._process(1.0 / 60.0)
				real_steps[index] += 1
		if not game.run_active and not other.run_active: break
	check(not game.run_active and not other.run_active, "Watch fixture did not settle")
	check(game.session.match_hash() == other.session.match_hash(), "Fast watching changed the fixed-tick match outcome")
	check(real_steps[1] < real_steps[0] * .65, "Fast watching did not shorten opponent travel")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(game.solo.save_path + suffix))
	game.queue_free()
	other.queue_free()
	await process_frame
	print("SOLO_RESTORE_OK" if not failed else "SOLO_RESTORE_FAILED")
	quit(1 if failed else 0)
