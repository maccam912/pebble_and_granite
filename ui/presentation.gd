class_name CurlPresentation
extends RefCounted
## Shared club palette for the existing game, setup and room controls.

const PAPER := Color("ece8dc")
const MUTED := Color("a8babf")
const GOLD := Color("dfbd78")
const CYAN := Color("65c1c9")

static func surface(fill: Color, edge := Color("34484f"), radius := 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", PAPER)
	theme.set_color("font_focus_color", "Button", PAPER)
	theme.set_color("font_disabled_color", "Button", Color("7e9096"))
	theme.set_stylebox("normal", "Button", surface(Color("192d36")))
	theme.set_stylebox("hover", "Button", surface(Color("29414b"), Color("82948f")))
	theme.set_stylebox("pressed", "Button", surface(Color("101f27"), GOLD))
	theme.set_stylebox("disabled", "Button", surface(Color("12222a"), Color("25373e")))
	var focus := surface(Color.TRANSPARENT, GOLD)
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("panel", "Panel", surface(Color("11252f"), Color("3f5358"), 12))
	theme.set_stylebox("normal", "LineEdit", surface(Color("0a1a22"), Color("4a626a")))
	theme.set_stylebox("read_only", "LineEdit", surface(Color("14252d")))
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_color("font_color", "LineEdit", PAPER)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_color("selection_color", "LineEdit", Color("386774"))
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", surface(GOLD, Color("edd29e")))
	theme.set_stylebox("hover", "PrimaryButton", surface(Color("efce90"), Color("fff0ce")))
	theme.set_stylebox("pressed", "PrimaryButton", surface(Color("bf9c5f"), GOLD))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(state, "PrimaryButton", Color("16252c"))
	theme.set_type_variation("SweepButton", "Button")
	theme.set_stylebox("normal", "SweepButton", surface(Color("234d58"), Color("5599a3")))
	theme.set_stylebox("hover", "SweepButton", surface(Color("306673"), CYAN))
	theme.set_stylebox("pressed", "SweepButton", surface(Color("193b45"), CYAN))
	return theme
