extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failed = true
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host = ClassDB.instantiate("CurlRoom")
	check(host.host_room("A".repeat(43)).is_empty(), "Host failed")
	for id in range(2, 5):
		check(host.join_peer(id, String.chr(65 + id).repeat(43), ClassDB.class_call_static("CurlRoom", "hello_packet")).is_empty(), "Join failed")
	for id in range(1, 5): check(host.ready_peer(id, true).is_empty(), "Ready failed")
	check(host.start_match(1, 42).is_empty(), "Start failed")
	var replica = ClassDB.instantiate("CurlReplica")
	var transfer = host.snapshot()
	while true:
		var bytes: PackedByteArray = transfer.next_packet()
		if bytes.is_empty(): break
		check(replica.receive_snapshot(bytes).is_empty(), "Snapshot rejected")
	check(replica.phase() == "Placement" and replica.epoch() == 1, "Replica not initialized")
	var command := {"epoch": 1, "sequence": 1, "command": {"kind": "Place", "own_house": true, "side": "None"}}
	check(host.command_peer(3, JSON.stringify(command).to_utf8_buffer()).is_empty(), "Placement failed")
	var commit: PackedByteArray = host.take_commit()
	check(not commit.is_empty(), "Commit missing")
	check(replica.apply_commit(commit).is_empty(), "Commit rejected")
	check(replica.phase() == "Calling" and replica.revision() == 1, "Replica did not advance")
	check(not replica.apply_commit(commit).is_empty(), "Duplicate commit accepted")
	check(host.advance_match(0, 137).is_empty(), "Thinking advance failed")
	check(replica.apply_commit(host.take_commit()).is_empty(), "Clock update rejected")
	var state: Dictionary = JSON.parse_string(ClassDB.class_call_static("CurlRoom", "decode_packet", host.state_packet())).room
	check(replica.state_hash() == state.hash, "Exact state mismatch")
	print("REPLICA_NATIVE_OK") if not failed else print("REPLICA_NATIVE_FAILED")
	quit(1 if failed else 0)
