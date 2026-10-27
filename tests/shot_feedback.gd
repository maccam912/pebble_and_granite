extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void:
	var clean := CurlShotFeedback.summary(2.05, 14555, -2.8, 0, true, Vector2(-.35, -.8))
	check("35 cm left" in clean and "0.80 m short of tee" in clean, "Negative coordinates were not translated into curling directions")
	check("14.55 s" in clean and "2.80 rotations" in clean and not "-2.80" in clean, "Split/rotation readout is misleading")
	check("no stone contact" in clean, "Clean outcome lacks a contact distinction")
	var hit := CurlShotFeedback.summary(3, -1, .5, 2, false, Vector2(9, -30))
	check(hit.begins_with("Out of play") and not "Finished" in hit and "not completed" in hit and "2 stone contacts" in hit, "Removed stone or missing split was presented as a valid finish")
	check("centre line" in CurlShotFeedback.location(Vector2.ZERO) and "on the tee" in CurlShotFeedback.location(Vector2.ZERO), "Exact tee finish is not readable")
	check("right" in CurlShotFeedback.location(Vector2(.4, .7)) and "behind" in CurlShotFeedback.location(Vector2(.4, .7)), "Back-right position reversed")
	print("SHOT_FEEDBACK_OK" if not failed else "SHOT_FEEDBACK_FAILED")
	quit(1 if failed else 0)
