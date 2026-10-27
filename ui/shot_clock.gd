class_name CurlShotClock
extends Panel
## Observed crossing times only. No weight or destination forecast.
var game
var reading: Label
var detail: Label

func setup(owner_game) -> void:
	game = owner_game
	position = Vector2(56, 194)
	size = Vector2(254, 112)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11252f")))
	var title := Label.new()
	title.position = Vector2(14, 8)
	title.text = "HOG-TO-HOG"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", CurlPresentation.MUTED)
	add_child(title)
	reading = Label.new()
	reading.position = Vector2(14, 29)
	reading.add_theme_font_size_override("font_size", 31)
	add_child(reading)
	detail = Label.new()
	detail.position = Vector2(14, 78)
	detail.add_theme_font_size_override("font_size", 15)
	detail.add_theme_color_override("font_color", CurlPresentation.MUTED)
	add_child(detail)
	for child in get_children(): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh()

func refresh() -> void:
	visible = game.spatial_view and game.run_active and game.frame.has("hog_clock_state")
	if not visible: return
	var state: String = game.frame.hog_clock_state
	reading.text = "%.2f s" % (float(game.frame.hog_clock_ms) / 1000.0) if state in ["Running", "Complete"] else "—"
	reading.add_theme_color_override("font_color", CurlPresentation.GOLD if state == "Complete" else CurlPresentation.PAPER)
	detail.text = {"Waiting": "Starts at the near hog", "Running": "Timing to the far hog…", "Complete": "Split complete", "Incomplete": "Split not completed"}.get(state, "")
	if state == "Running" and game.solo != null and game.solo.fast_forwarding(): detail.text = "4× travel · ice time shown"
