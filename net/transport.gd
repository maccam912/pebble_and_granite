class_name CurlTransport
extends RefCounted
## Raw Iroh channels. The Rust match authority owns all gameplay decisions.

static func available() -> bool:
	if not ClassDB.class_exists("IrohServer") or not ClassDB.class_exists("IrohClient"): return false
	if OS.has_feature("android"):
		return Engine.has_singleton("PebbleMobile") and bool(Engine.get_singleton("PebbleMobile").call("initializeIroh"))
	return true

static func valid_endpoint(value: String) -> bool:
	if value.length() != 43: return false
	for character in value:
		if not character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_": return false
	return true

static func host(relay_only := false) -> MultiplayerPeer:
	return ClassDB.class_call_static("IrohServer", "start_configured", relay_only) if available() else null

static func connect_host(endpoint: String, relay_only := false, identity_path := "") -> MultiplayerPeer:
	var path := ProjectSettings.globalize_path(identity_path) if not identity_path.is_empty() else ""
	return ClassDB.class_call_static("IrohClient", "connect_identity", endpoint, relay_only, path) if available() and valid_endpoint(endpoint) else null
