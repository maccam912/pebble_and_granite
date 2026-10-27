class_name CurlSweeping
extends RefCounted
## Local selection only. The Rust authority rechecks ownership each tick.
var target := -1
var point := Vector2.ZERO
var active := false

func allowed(stone: Dictionary, frame: Dictionary, seat: int) -> bool:
	if not stone.get("active", false) or stone.get("speed", 0.0) <= 0: return false
	if seat == -1: return true # Practice controls every stone.
	if seat < 0: return false
	var seats := 4 if frame.get("format", "MixedDoubles") == "Teams" else 2
	var team := int(seat / seats)
	if seats == 4 and frame.get("model", 3) < 4 and stone.id != frame.get("delivered", -1): return false
	if stone.position.y < 0: return stone.team == team
	return team == frame.get("team", -1) or seat % seats == seats - 1

func selected(frame: Dictionary, seat: int, held := false) -> Dictionary:
	for stone in frame.get("stones", []):
		if stone.id == target and allowed(stone, frame, seat): return stone
	# Never transfer a held gesture onto another stone after a contact or stop.
	if active or held: return {}
	for stone in frame.get("stones", []):
		if stone.id == frame.get("delivered", -1) and allowed(stone, frame, seat):
			target = stone.id
			return stone
	for stone in frame.get("stones", []):
		if allowed(stone, frame, seat):
			target = stone.id
			return stone
	target = -1
	return {}

func raw_offsets(stone: Dictionary, ice: Vector2) -> Dictionary:
	var velocity: Vector2 = stone.get("velocity", Vector2.ZERO)
	if velocity.length_squared() == 0: return {}
	var direction := velocity.normalized()
	var relative: Vector2 = ice - stone.position
	var lateral := int(round(relative.dot(Vector2(direction.y, -direction.x)) * 1000.0))
	var ahead := int(round(relative.dot(direction) * 1000.0))
	return {"lateral_mm": lateral, "ahead_mm": ahead}

func useful(offset: Dictionary) -> bool:
	return not offset.is_empty() and absi(offset.lateral_mm) <= 350 and offset.ahead_mm >= 80 and offset.ahead_mm <= 700

func offsets(stone: Dictionary, ice: Vector2) -> Dictionary:
	var offset := raw_offsets(stone, ice)
	# An off-path pointer stays off path; do not turn it into a useful edge brush.
	return offset if useful(offset) else {}

func feedback(offset: Dictionary, effort: int, steady: bool) -> String:
	if steady: return "STEADY SWEEP\nRelease the button to stop brushing."
	if offset.is_empty(): return "FIND THE ICE\nBrush just ahead of the highlighted stone."
	if offset.ahead_mm < 80: return "MOVE AHEAD\nBrush in front of the stone, not behind it."
	if offset.ahead_mm > 700: return "CLOSER TO THE STONE\nFollow just ahead as it travels."
	if absi(offset.lateral_mm) > 350: return "OFF TO THE SIDE\nMove your brush into the stone's path."
	if effort == 0: return "KEEP BRUSHING\nMove back and forth to sweep this ice."
	return "BRUSHING THE PATH\nKeep moving just ahead of the stone."
