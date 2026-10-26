extends SceneTree
func _initialize() -> void:
	var logo := Image.new()
	var error := logo.load_svg_from_string(FileAccess.get_file_as_string("res://assets/branding/icon.svg"))
	if error == OK:
		error = logo.save_png("res://assets/branding/splash.png")
	print("BRANDING_RENDER_OK" if error == OK else "BRANDING_RENDER_FAILED")
	quit(0 if error == OK else 1)
