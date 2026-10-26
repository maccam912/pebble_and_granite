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
	var deadline := Time.get_ticks_msec() + 10000
	while replica.state_hash().is_empty() and Time.get_ticks_msec() < deadline:
		check(replica.poll_restore().is_empty(), "Async restore failed")
		await process_frame
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
	# Build a compressed, in-flight journal and restore without blocking packet delivery.
	check(host.command_peer(1, ClassDB.class_call_static("CurlRoom", "delivery_packet", 1, 1, 2050, -900, 1)).is_empty(), "Release failed")
	while not host.take_commit().is_empty(): pass
	for i in range(300):
		check(host.advance_match(12, 0).is_empty(), "Flight failed")
		var frame: Dictionary = host.frame()
		var sweep := {"epoch": 1, "sequence": i + 2, "command": {"kind": "BrushSpan", "tick": int(frame.global_tick) - 12, "count": 12, "input": {"stone": 2, "brush": 0, "effort": 180 + i % 2, "lateral_mm": 0, "ahead_mm": 180}}}
		check(host.command_peer(1, JSON.stringify(sweep).to_utf8_buffer()).is_empty(), "Sweep failed")
		while not host.take_commit().is_empty(): pass
	var recovering = ClassDB.instantiate("CurlReplica")
	transfer = host.snapshot()
	var packet_max_us := 0
	while true:
		var bytes: PackedByteArray = transfer.next_packet()
		if bytes.is_empty(): break
		var began := Time.get_ticks_usec()
		check(recovering.receive_snapshot(bytes).is_empty(), "Compressed snapshot rejected")
		packet_max_us = maxi(packet_max_us, Time.get_ticks_usec() - began)
	check(recovering.state_hash().is_empty(), "Worker published without main-thread poll")
	deadline = Time.get_ticks_msec() + 10000
	var yielded := 0
	while recovering.state_hash().is_empty() and Time.get_ticks_msec() < deadline:
		check(recovering.poll_restore().is_empty(), "Compressed async restore failed")
		yielded += 1
		await process_frame
	state = JSON.parse_string(ClassDB.class_call_static("CurlRoom", "decode_packet", host.state_packet())).room
	check(recovering.state_hash() == state.hash, "Recovered compressed history differs")
	print("ASYNC_RESTORE packet_max_us=", packet_max_us, " yielded_frames=", yielded)
	var cancelled = ClassDB.instantiate("CurlReplica")
	transfer = host.snapshot()
	while true:
		var bytes: PackedByteArray = transfer.next_packet()
		if bytes.is_empty(): break
		check(cancelled.receive_snapshot(bytes).is_empty(), "Cancellable snapshot rejected")
	check(not cancelled.restore_progress().is_empty(), "Restore job was not retained")
	cancelled = null # Drop requests cancellation, without a main-thread join.
	for i in range(4): await process_frame
	check(recovering.state_hash() == state.hash, "Cancelled job affected published replica")
	print("REPLICA_NATIVE_OK") if not failed else print("REPLICA_NATIVE_FAILED")
	quit(1 if failed else 0)
