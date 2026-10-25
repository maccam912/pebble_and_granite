extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host := CurlOnline.new()
	var error := host.host()
	if not error.is_empty():
		push_error(error)
		quit(1)
		return
	var directory := CurlRendezvous.new()
	root.add_child(directory)
	var registration := await directory.register(host.endpoint)
	if not registration.ok:
		push_error(registration.message)
		host.close()
		quit(1)
		return
	var code: String = registration.payload.code
	var token: String = registration.payload.revoke_token
	var resolved := await directory.resolve(code)
	var passed: bool = resolved.ok and resolved.payload.endpoint_id == host.endpoint
	await directory.revoke(code, token)
	var removed := await directory.resolve(code)
	passed = passed and not removed.ok
	host.close()
	directory.queue_free()
	print("ROOM_CODE_OK" if passed else "ROOM_CODE_FAILED")
	quit(0 if passed else 1)
