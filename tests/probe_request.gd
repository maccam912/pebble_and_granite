extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var path := "user://diagnostics/self-test-request.json"
	DirAccess.make_dir_recursive_absolute("user://diagnostics")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"schema":1,"nonce":"0123456789abcdef0123456789abcdef"}')
	file.close()
	var scene = load("res://scenes/lab.tscn").instantiate()
	root.add_child(scene)
	if FileAccess.file_exists(path) or scene.self_test_nonce != "0123456789abcdef0123456789abcdef":
		push_error("One-shot probe request was not consumed")
		quit(1)
