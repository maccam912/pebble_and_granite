extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--request="):
			var probe = load("res://net/network_probe.gd").new()
			probe.request = JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--request=")))
			root.add_child(probe)
			return
	quit(1)
