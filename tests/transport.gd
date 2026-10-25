extends SceneTree
var failed := false
func check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		failed = true
	return ok
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not check(CurlTransport.available(), "Native transport missing"):
		quit(1)
		return
	var relay_only := "--relay-only" in OS.get_cmdline_user_args()
	var server := CurlTransport.host(relay_only)
	if not check(server != null, "Host creation failed"):
		quit(1)
		return
	var endpoint: String = server.call("connection_string")
	check(CurlTransport.valid_endpoint(endpoint), "Invalid endpoint")
	var cancelled := CurlTransport.connect_host(endpoint, relay_only)
	cancelled.close()
	check(cancelled.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED, "Connect cancellation failed")
	var client := CurlTransport.connect_host(endpoint, relay_only)
	var peers := {}
	server.peer_connected.connect(func(id: int): peers[id] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while (peers.is_empty() or client.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED) and Time.get_ticks_msec() < deadline:
		server.poll()
		client.poll()
		await create_timer(.01).timeout
	if check(not peers.is_empty() and client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "Connection deadline exceeded: " + str(client.call("connection_error"))):
		var received := [{}, {}]
		for attempt in range(30):
			for channel in range(4):
				var data := PackedByteArray()
				data.resize([1200, 82, 767, 64][channel])
				data.fill(channel + 10)
				for peer: MultiplayerPeer in [server, client]:
					peer.set_target_peer(client.get_unique_id() if peer == server else 1)
					peer.transfer_channel = channel
					peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if channel == 0 else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
					check(peer.put_packet(data) == OK, "Send failed")
			for frame in range(3):
				for index in range(2):
					var peer: MultiplayerPeer = [server, client][index]
					peer.poll()
					while peer.get_available_packet_count() > 0:
						var channel := peer.get_packet_channel()
						var data := peer.get_packet()
						if check(channel >= 0 and channel < 4, "Invalid channel"):
							check(data.size() == [1200, 82, 767, 64][channel], "Packet length changed")
							for byte in data: check(byte == channel + 10, "Packet data changed")
							received[index][channel] = true
				await create_timer(.02).timeout
		check(received[0].size() == 4 and received[1].size() == 4, "Missing bidirectional channels")
		server.disconnect_peer(client.get_unique_id(), true)
		deadline = Time.get_ticks_msec() + 5000
		while client.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED and Time.get_ticks_msec() < deadline:
			client.poll()
			await create_timer(.01).timeout
		check(client.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED, "Forced disconnect failed")
	client.close()
	server.close()
	print("TRANSPORT_TEST relay_only=", relay_only, " ok=", not failed)
	quit(1 if failed else 0)
