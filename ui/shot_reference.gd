class_name CurlShotReference
extends RefCounted
## Actual outcomes only. Never predicts the next stone's endpoint.
var shots: Dictionary = {}
var pending: Dictionary = {}
var end_number := -1

func clear() -> void:
	shots.clear()
	pending.clear()
	end_number = -1

func begin(frame: Dictionary, broom: int, turn: int, weight: String) -> void:
	if end_number != int(frame.get("end", 0)): clear()
	end_number = int(frame.get("end", 0))
	var id := int(frame.get("delivered", -1))
	for stone in frame.get("stones", []):
		if stone.id == id:
			shots.erase(int(stone.team))
			pending = {"id": id, "team": int(stone.team), "broom": broom, "turn": turn, "weight": weight}
			return

func observe(frame: Dictionary, running: bool) -> void:
	if end_number != int(frame.get("end", 0)):
		clear()
		return
	# An opponent's later hit also makes the old reference misleading.
	for team in shots.keys():
		var retained := false
		for stone in frame.get("stones", []):
			if stone.id == shots[team].id and stone.active and stone.position.distance_to(shots[team].position) < .001: retained = true
		if not retained: shots.erase(team)
	if pending.is_empty(): return
	if int(frame.get("contacts", 0)) > 0:
		pending.clear()
		return
	if running: return
	if frame.get("resting", false) and frame.get("match_phase", "") != "Choice":
		for stone in frame.get("stones", []):
			if stone.id == pending.id and stone.active:
				pending.position = stone.position
				shots[pending.team] = pending.duplicate()
	pending.clear()
