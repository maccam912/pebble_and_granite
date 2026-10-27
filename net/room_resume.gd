class_name CurlRoomResume
extends RefCounted
## A public endpoint shortcut; seat ownership stays with the persistent Iroh key.
static func path_for(identity: String) -> String:
	return identity.get_basename() + "-room.json"

static func read(identity: String) -> Dictionary:
	var path := path_for(identity)
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 2048: return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary: return {}
	var data: Dictionary = parser.data
	if data.get("schema") != 1 or data.get("session") != CurlRendezvous.session_id(): return {}
	if not data.get("endpoint") is String or not CurlTransport.valid_endpoint(data.endpoint): return {}
	return data

static func save(identity: String, endpoint: String) -> bool:
	if not CurlTransport.valid_endpoint(endpoint): return false
	var path := path_for(identity)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"schema": 1, "endpoint": endpoint, "session": CurlRendezvous.session_id()}))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) == OK

static func forget(identity: String) -> void:
	for suffix in ["", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(identity) + suffix))
