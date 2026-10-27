extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var session = ClassDB.instantiate("CurlSession")
	session.new_team_match(42)
	var initial: String = session.match_hash()
	check(not session.request_rated_ai_plan(-1).is_empty(), "Invalid planning tier accepted")
	for level in range(3):
		check(session.request_rated_ai_plan(level).is_empty(), "Rated planner request failed")
		var started := Time.get_ticks_msec()
		var result: Dictionary = {}
		while result.is_empty() and Time.get_ticks_msec() - started < 30000:
			result = session.poll_ai_plan()
			await process_frame
		check(not result.is_empty() and not result.has("error"), "Rated planner failed or stalled")
		if result.has("kind"):
			check(int(result.get("weight_kind", -1)) == CurlShotCall.weight_kind(result.kind), "Native and visible weight categories disagree")
			check(int(result.get("ice_samples", -1)) == 0, "New match claimed prior ice observations")
		check(session.match_hash() == initial, "Planning changed authoritative match")
		print("AI_PLAN tier=%d wall_ms=%d kind=%s" % [level, Time.get_ticks_msec() - started, result.get("kind", "missing")])
	# Execute and replay the accepted release, not a serialized planning tree.
	var result: Dictionary = {}
	check(session.request_rated_ai_plan(2).is_empty(), "Final planning request failed")
	var deadline := Time.get_ticks_msec() + 30000
	while result.is_empty() and Time.get_ticks_msec() < deadline:
		result = session.poll_ai_plan()
		await process_frame
	if result.has("broom_mm"):
		check(session.execute_ai_plan(result.broom_mm, result.turn, 2).is_empty(), "Rated plan did not execute")
		for i in range(400):
			if session.frame().match_phase != "InFlight": break
			check(session.step_brush_ticks(64, int(session.frame().delivered), 0, 0, 180).is_empty(), "Rated release failed during travel")
		var restored = ClassDB.instantiate("CurlSession")
		check(restored.load_match(session.match_json()).is_empty() and restored.match_hash() == session.match_hash(), "Rated release did not replay")
		# The replay reconstructs observations, so the next estimate must match.
		var plans: Array[Dictionary] = []
		for current in [session, restored]:
			if current.frame().match_phase != "Calling": break
			check(current.request_rated_ai_plan(0).is_empty(), "Observed plan request failed")
			var next_plan: Dictionary = {}
			deadline = Time.get_ticks_msec() + 30000
			while next_plan.is_empty() and Time.get_ticks_msec() < deadline:
				next_plan = current.poll_ai_plan()
				await process_frame
			check(not next_plan.is_empty() and not next_plan.has("error"), "Observed plan stalled")
			plans.append(next_plan)
		if plans.size() == 2: check(plans[0] == plans[1], "Restored observations changed the next AI call")
	else: check(false, "Final plan unavailable")
	print("AI_STRATEGY_OK" if not failed else "AI_STRATEGY_FAILED")
	quit(1 if failed else 0)
