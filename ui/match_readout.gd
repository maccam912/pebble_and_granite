class_name CurlMatchReadout
extends Control
## Settled score and delivery inventory, derived from the native rules frame.
var game
var end_panel: Panel
var end_title: Label
var end_detail: Label
var continue_button: Button

func setup(owner_game) -> void:
	game = owner_game
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_panel = Panel.new()
	end_panel.position = Vector2(870, 210)
	end_panel.size = Vector2(350, 290)
	end_panel.add_theme_stylebox_override("panel", CurlPresentation.surface(Color("11252f"), CurlPresentation.GOLD, 12))
	add_child(end_panel)
	end_title = Label.new()
	end_title.position = Vector2(20, 18)
	end_title.add_theme_font_size_override("font_size", 27)
	end_title.add_theme_color_override("font_color", CurlPresentation.GOLD)
	end_panel.add_child(end_title)
	end_detail = Label.new()
	end_detail.position = Vector2(20, 66)
	end_detail.size = Vector2(310, 140)
	end_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_detail.add_theme_font_size_override("font_size", 21)
	end_panel.add_child(end_detail)
	continue_button = Button.new()
	continue_button.position = Vector2(20, 218)
	continue_button.size = Vector2(310, 52)
	continue_button.theme_type_variation = "PrimaryButton"
	continue_button.pressed.connect(func(): game.next_throw())
	end_panel.add_child(continue_button)
	refresh()

func refresh() -> void:
	if game == null or end_panel == null: return
	visible = game.match_mode
	var state: String = game.frame.get("match_phase", "")
	end_panel.visible = visible and state in ["EndComplete", "GameComplete"]
	# Keep the same authority/host checks as the original action.
	continue_button.disabled = game.new_button.disabled
	continue_button.text = game.new_button.text
	if end_panel.visible:
		var frame: Dictionary = game.frame
		var completed := state == "GameComplete"
		end_title.text = "%s wins" % game.team_name(frame.winner) if completed else "End %d complete" % frame.end
		var time_expired: bool = frame.clock_gold == 0 or frame.clock_cyan == 0
		var points := int(frame.get("counting_points", 0))
		var result := "No score this end" if points == 0 else "%s scores %d" % [game.team_name(frame.counting_team), points]
		if time_expired: result = "%s ran out of thinking time" % game.team_name(0 if frame.clock_gold == 0 else 1)
		end_detail.text = "%s\nGold %d  ·  Cyan %d" % [result, frame.score_gold, frame.score_cyan]
		if not completed: end_detail.text += "\nNext hammer: " + game.team_name(frame.hammer)
		if not completed and frame.end >= frame.scheduled_ends: end_detail.text += "\nTied game · extra end"
	queue_redraw()

func _draw() -> void:
	if game == null or not game.match_mode or game.run_active or not game.frame.get("in_hand", {}).is_empty(): return
	var frame: Dictionary = game.frame
	var state: String = frame.get("match_phase", "")
	if state in ["Placement", "EndComplete", "GameComplete", "Choice"]: return
	var box := Rect2(56, 194, 282, 152)
	draw_style_box(CurlPresentation.surface(Color("11252f")), box)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(70, 220), "HAMMER · " + game.team_name(frame.get("hammer", 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, CurlPresentation.PAPER)
	draw_string(font, Vector2(70, 245), "STONES TO PLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CurlPresentation.MUTED)
	var total := int(frame.get("stones_per_team", 8))
	for team in range(2):
		var left := int(frame.get("stones_left_gold" if team == 0 else "stones_left_cyan", total))
		var color := CurlPresentation.GOLD if team == 0 else CurlPresentation.CYAN
		var y := 268 + team * 28
		draw_string(font, Vector2(70, y + 5), "%s %d" % [game.team_name(team).to_upper(), left], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, color)
		for index in range(total):
			var at := Vector2(178 + index * 19, y)
			draw_circle(at, 6, color if index < left else Color("37505b"), index < left, -1.0 if index < left else 1.5, true)
	var settled: bool = frame.get("resting", true) and not game.run_active
	var points := int(frame.get("counting_points", 0))
	var text := "Stones moving…" if not settled else ("No stones counting" if points == 0 else "%s lies %d · marked on ice" % [game.team_name(frame.counting_team), points])
	draw_string(font, Vector2(70, 330), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, CurlPresentation.MUTED)
