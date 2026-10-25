class_name CurlRendezvous
extends Node
## Shared user-owned code directory. Tokens stay in memory; gameplay uses Iroh.

const URL: String = "https://iroh-rendezvous.maccam912.workers.dev"
const PATH: String = "/v1/join-codes"
const ALPHABET: String = "23456789ABCDEFGHJKMNPQRSTVWXYZ"


static func normalize(value: String) -> String:
	return value.strip_edges().to_upper()


static func valid_code(value: String) -> bool:
	var code := normalize(value)
	if code.length()!=4: return false
	for character in code:
		if not character in ALPHABET: return false
	return true


static func session_id() -> String:
	return "pebble-granite/" + (FileAccess.get_file_as_string("res://compatibility.json") + FileAccess.get_file_as_string("res://validation/golden.txt")).sha256_text()


func register(endpoint: String) -> Dictionary:
	if not CurlTransport.valid_endpoint(endpoint): return {"ok":false,"message":"Invalid host endpoint."}
	var reply := await request(PATH,HTTPClient.METHOD_POST,{"endpoint_id":endpoint,"session_id":session_id(),"expires_in":600})
	if not reply.ok: return reply
	var payload: Dictionary = reply.payload
	var token := str(payload.get("revoke_token", ""))
	if not valid_code(str(payload.get("code", ""))) or not valid_token(token) or payload.get("endpoint_id") != endpoint or payload.get("session_id") != session_id() or not payload.get("expires_at") is String:
		return {"ok":false,"message":"Invalid room-code response."}
	return reply


func resolve(code: String) -> Dictionary:
	if not valid_code(code): return {"ok":false,"message":"Enter a four-character room code."}
	var reply := await request(PATH+"/"+normalize(code))
	if not reply.ok: return reply
	if reply.payload.get("session_id")!=session_id():
		return {"ok":false,"message":"This room uses a different game version."}
	if not CurlTransport.valid_endpoint(str(reply.payload.get("endpoint_id",""))):
		return {"ok":false,"message":"The room-code service is unavailable."}
	return reply


static func valid_token(token: String) -> bool:
	if token.is_empty() or token.length() > 256: return false
	for character in token:
		if character.unicode_at(0) <= 32 or character.unicode_at(0) >= 127: return false
	return true

func revoke(code: String, token: String) -> void:
	if valid_code(code) and valid_token(token):
		await request(PATH+"/"+normalize(code),HTTPClient.METHOD_DELETE,{},token)


func request(path: String, method: int = HTTPClient.METHOD_GET, payload: Dictionary = {}, token: String = "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 10
	http.body_size_limit = 16384
	http.max_redirects = 0
	add_child(http)
	var headers := PackedStringArray(["Accept: application/json"])
	if method==HTTPClient.METHOD_POST: headers.append("Content-Type: application/json")
	if not token.is_empty(): headers.append("Authorization: Bearer "+token)
	var error := http.request(URL+path,headers,method,JSON.stringify(payload) if method==HTTPClient.METHOD_POST else "")
	if error!=OK:
		http.queue_free()
		return {"ok":false,"message":"The room-code service is unavailable."}
	var response: Array = await http.request_completed
	http.queue_free()
	if int(response[0])!=HTTPRequest.RESULT_SUCCESS:
		return {"ok":false,"message":"The room-code service is unavailable."}
	var status := int(response[1])
	if status==404: return {"ok":false,"message":"That room code has expired."}
	if status==429: return {"ok":false,"message":"Too many requests; wait before trying again."}
	if status==204: return {"ok":true,"payload":{}}
	if status<200 or status>=300: return {"ok":false,"message":"The room-code service is unavailable."}
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary: return {"ok":false,"message":"The room-code service is unavailable."}
	return {"ok":true,"payload":parsed}
