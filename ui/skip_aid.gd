class_name CurlSkipAid
extends Control
## Short direction glyph and historical marks, never a trajectory preview.
var game

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func point(at: Vector2) -> Vector2:
	return game.rink.ice_screen_point(at) if game.spatial_view else game.house_point(at)

func broom_mark(at: Vector2, color: Color) -> void:
	draw_line(at + Vector2(-5, -28), at, color, 3, true)
	draw_style_box(CurlPresentation.surface(color, color, 3), Rect2(at - Vector2(16, 4), Vector2(32, 8)))

func _draw() -> void:
	if game == null or game.solo == null: return
	var font := ThemeDB.fallback_font
	draw_style_box(CurlPresentation.surface(Color("11252f"), CurlPresentation.GOLD), Rect2(944, 194, 292, 92))
	draw_string(font, Vector2(960, 220), "CALL THE SHOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, CurlPresentation.GOLD)
	draw_string(font, Vector2(960, 245), "Drag broom · judge the ice", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	draw_string(font, Vector2(960, 269), "Turns: right-handed delivery", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, CurlPresentation.MUTED)
	var broom := point(Vector2(float(game.broom_mm) / 1000.0, 0))
	if game.rink == null or game.rink.get_global_rect().grow(-30).has_point(broom):
		# Project sheet-right into the current camera, so a reversed view cannot
		# reverse the meaning. The fixed-size icon is explicitly not a path.
		var right := (point(Vector2(.2, 0)) - point(Vector2.ZERO)).normalized()
		var forward := Vector2(right.y, -right.x)
		var side: Vector2 = right * game.turn
		var start: Vector2 = broom + forward * 30 - side * 18
		var curve := PackedVector2Array()
		for i in range(17):
			var t := float(i) / 16.0
			curve.append(start + forward * (38 * t) + side * (34 * t * t))
		draw_polyline(curve, CurlPresentation.GOLD, 4, true)
		var tip := curve[-1]
		var heading := (tip - curve[-3]).normalized()
		draw_line(tip, tip - heading.rotated(.55) * 13, CurlPresentation.GOLD, 4, true)
		draw_line(tip, tip - heading.rotated(-.55) * 13, CurlPresentation.GOLD, 4, true)
		draw_circle(broom, 23, CurlPresentation.GOLD, false, 2, true)
		draw_string(font, broom + Vector2(-58, 42), "DRAG BROOM", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, CurlPresentation.GOLD)
	var previous: Dictionary = game.shot_reference.shots.get(int(game.frame.get("team", 0)), {})
	if previous.is_empty(): return
	var tint := Color(.62, .84, .88, .65)
	var old_broom := point(Vector2(float(previous.broom) / 1000.0, 0))
	var stone := point(previous.position)
	var bounds := Rect2(40, 180, 890, 500)
	if bounds.has_point(old_broom): broom_mark(old_broom, tint)
	if bounds.has_point(stone):
		for i in range(8): draw_arc(stone, 24, i * TAU / 8, (i + .65) * TAU / 8, 6, tint, 3, true)
	draw_style_box(CurlPresentation.surface(Color("11252f"), tint), Rect2(450, 183, 480, 57))
	draw_string(font, Vector2(464, 205), "LAST CLEAN SHOT · " + previous.weight + (" · right" if previous.turn > 0 else " · left"), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, tint)
	draw_string(font, Vector2(464, 227), "Ghost broom + ring: actual result, including sweeping", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tint)
