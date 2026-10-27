class_name CurlShotFeedback
extends RefCounted
## Human-readable observations, never a forecast or a judgement of shot quality.
static func location(at: Vector2) -> String:
	var across := "on the centre line" if absf(at.x) < .005 else "%d cm %s" % [roundi(absf(at.x) * 100), "left" if at.x < 0 else "right"]
	var depth := "on the tee" if absf(at.y) < .005 else "%.2f m %s tee" % [absf(at.y), "short of" if at.y < 0 else "behind"]
	return across + " · " + depth

static func summary(speed: float, split_ms: int, turns: float, contacts: int, active: bool, at: Vector2) -> String:
	var split := "Hog-to-hog: not completed" if split_ms < 0 else "Hog-to-hog: %.2f s" % (float(split_ms) / 1000.0)
	var finish := "Finished " + location(at) if active else "Out of play"
	var contact := "Clean run · no stone contact" if contacts == 0 else "%d stone contact%s" % [contacts, "" if contacts == 1 else "s"]
	return "%s\n%s\n%s\nRelease %.2f m/s · %.2f rotations" % [finish, split, contact, speed, absf(turns)]

static func from_frame(frame: Dictionary) -> String:
	var stone: Dictionary = {}
	for candidate in frame.get("stones", []):
		if candidate.id == frame.get("delivered", -1): stone = candidate; break
	return summary(float(frame.get("release_speed", 0)), int(frame.get("hog_split_ms", -1)), float(stone.get("turns", 0)), int(frame.get("contacts", 0)), bool(stone.get("active", false)), stone.get("position", Vector2.ZERO))

static func from_review(shot: Dictionary) -> String:
	return summary(float(shot.speed_mm_s) / 1000.0, int(shot.hog_split_ms), float(shot.turns_milli) / 1000.0, int(shot.contacts), bool(shot.in_play), shot.finish)
