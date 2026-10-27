class_name CurlShotCall
extends Panel
## The call is an intention, separate from the broom's aiming point.
var game
var target := Vector2.ZERO
var heading: Label
var details: Label
var has_call := false

static func weight_kind(kind: String) -> int:
	if kind in ["Guard", "Corner guard"]: return 1
	if kind in ["Hit", "Hit-and-roll", "Peel", "Double", "Runback"]: return 2
	return 0

func setup(owner_game) -> void:
	game = owner_game
	position = Vector2(878, 194)
	size = Vector2(342, 432)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11252f"), CurlPresentation.GOLD))
	heading = Label.new()
	heading.position = Vector2(16, 12)
	heading.add_theme_font_size_override("font_size", 23)
	heading.add_theme_color_override("font_color", CurlPresentation.GOLD)
	add_child(heading)
	details = Label.new()
	details.position = Vector2(16, 48)
	details.size = Vector2(310, 165)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_theme_font_size_override("font_size", 19)
	add_child(details)
	for label in [heading, details]: label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

func show_call(call: Dictionary, waiting: bool) -> void:
	has_call = not call.is_empty()
	heading.text = "SKIP'S CALL" if has_call else "READING THE ICE…"
	if not has_call:
		details.text = "Wait for the weight, target and turn." if waiting else "Choose your own shot."
		queue_redraw()
		return
	target = Vector2(float(call.target_x_mm), float(call.target_y_mm)) / 1000.0
	var category := weight_kind(call.kind)
	var weight := "Takeout weight" if category == 2 else ("Guard weight" if category == 1 else ("Front-ring draw" if target.y < -.3 else ("Back-ring draw" if target.y > .3 else "Tee draw")))
	var across := "Centre line" if absf(target.x) < .05 else "%d cm %s" % [roundi(absf(target.x) * 100), "left" if target.x < 0 else "right"]
	var depth := "tee line" if absf(target.y) < .05 else "%.1f m %s tee" % [absf(target.y), "short of" if target.y < 0 else "behind"]
	details.text = "%s · %s\n%s · %s\nCurl %s · Broom %s" % [call.kind.to_upper(), weight, across, depth, "left ←" if int(call.turn) < 0 else "right →", "centre" if absi(game.broom_mm) < 50 else "%d cm %s" % [roundi(absf(game.broom_mm) / 10.0), "left" if game.broom_mm < 0 else "right"]]
	details.text += "\nNear-hog pace: %.2f m/s" % (float(call.speed_mm_s) / 1000.0)
	if call.has("ice_samples"):
		details.text += "\nIce read: %d clean draws" % int(call.ice_samples) if int(call.ice_samples) > 0 else "\nIce read: still learning"
	queue_redraw()

func map_point(at: Vector2) -> Vector2:
	# Same orientation as delivery: left/right from the thrower's viewpoint.
	return Vector2(171 + at.x * 24, 270 - at.y * 24)

func _draw() -> void:
	if not has_call: return
	var ink := Color("14313d")
	var ice := Color("dfecef")
	draw_rect(Rect2(108, 215, 126, 180), ice)
	for ring in [[1.829, Color("346f8e")], [1.219, ice], [.610, Color("c06462")], [.152, ice]]:
		draw_circle(map_point(Vector2.ZERO), ring[0] * 24, ring[1])
	draw_line(map_point(Vector2(0, -5)), map_point(Vector2(0, 2.2)), Color("879ea9"), 1)
	draw_line(map_point(Vector2(-2.375, 0)), map_point(Vector2(2.375, 0)), Color("879ea9"), 1)
	for stone in game.frame.get("stones", []):
		if stone.active and stone.position.y >= -5 and stone.position.y <= 2.2:
			draw_circle(map_point(stone.position), 4, ink)
			draw_circle(map_point(stone.position), 2.5, CurlPresentation.GOLD if stone.team == 0 else CurlPresentation.CYAN)
	var aim := map_point(Vector2(float(game.broom_mm) / 1000.0, 0))
	draw_rect(Rect2(aim - Vector2(5, 2), Vector2(10, 4)), ink)
	var at := map_point(target)
	draw_circle(at, 11, ink, false, 3, true)
	draw_circle(at, 8, CurlPresentation.GOLD, false, 2, true)
	draw_line(at - Vector2(14, 0), at + Vector2(14, 0), CurlPresentation.GOLD, 2, true)
	draw_line(at - Vector2(0, 14), at + Vector2(0, 14), CurlPresentation.GOLD, 2, true)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(16, 239), "TARGET", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, CurlPresentation.GOLD)
	draw_string(font, Vector2(16, 260), "Gold +", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, CurlPresentation.GOLD)
	draw_string(font, Vector2(244, 290), "BROOM", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, CurlPresentation.MUTED)
	draw_string(font, Vector2(244, 311), "Dark bar", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, CurlPresentation.MUTED)
	draw_string(font, Vector2(40, 418), "VIEWED FROM YOUR DELIVERY END", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CurlPresentation.MUTED)
