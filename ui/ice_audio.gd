class_name CurlIceAudio
extends Node
## Original synthesized textures. Presentation only; no simulation RNG use.
var game
var paused := false
var rumble: AudioStreamPlayer
var brushing: AudioStreamPlayer
var impact: AudioStreamPlayer
var last_contacts := 0
var last_tick := -1
var last_delivered := -1
var last_end := -1
var previous_speed := 0.0
var playing_level := 0.0

func texture(kind: int) -> AudioStreamWAV:
	var rate := 22050
	var count := rate if kind < 2 else int(rate * .18)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 81571 + kind
	var low := 0.0
	for i in range(count):
		var t := float(i) / rate
		var noise := rng.randf_range(-1, 1)
		low = lerpf(low, noise, .09)
		var value := low * .7 + noise * .06
		if kind == 1: value = noise * (.22 + .14 * sin(TAU * 4 * t))
		if kind == 2: value = (noise * .6 + sin(TAU * 1260 * t) * .28) * exp(-t * 38)
		data.encode_s16(i * 2, int(clampf(value, -1, 1) * 26000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	if kind < 2:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = count
	return stream

func _ready() -> void:
	for kind in range(3):
		var player := AudioStreamPlayer.new()
		player.stream = texture(kind)
		player.volume_db = -60
		add_child(player)
		if kind == 0: rumble = player
		elif kind == 1: brushing = player
		else: impact = player

func hush() -> void:
	for player in [rumble, brushing, impact]:
		if player != null: player.stop()
	playing_level = 0.0

func _process(delta: float) -> void:
	if game == null or game.play_settings == null: return
	var frame: Dictionary = game.frame
	var contacts := int(frame.get("contacts", 0))
	var tick := int(frame.get("global_tick", 0))
	var delivered := int(frame.get("delivered", -1))
	var end := int(frame.get("end", 0))
	var fresh := delivered != last_delivered or end != last_end or tick < last_tick or last_tick < 0
	var speed := 0.0
	for stone in frame.get("stones", []):
		if stone.active: speed = maxf(speed, float(stone.get("speed", 0)))
	var muted: bool = paused or game.play_settings.effects_volume <= 0.0 or not game.is_visible_in_tree() or not game.play_settings.ice_sounds or game.suspended or game.local_menu_open() or (game.room_panel != null and game.room_panel.visible)
	if muted: hush()
	else:
		playing_level = move_toward(playing_level, clampf(speed / 3.0, 0, 1) if game.run_active else 0.0, delta * 4)
		loop_level(rumble, playing_level, -15)
		rumble.pitch_scale = .75 + clampf(speed / 4, 0, .65)
		var brush: Dictionary = game.current_brush() if game.run_active else {}
		var effort := float(brush.get("effort", 0)) / 255.0
		if game.solo != null and game.solo.enabled and game.run_active: effort = maxf(effort, float(game.solo.brush_effort()) / 255.0)
		loop_level(brushing, effort if speed > .01 else 0.0, -24)
		if not fresh and contacts > last_contacts:
			# Contact count comes from the fixed-tick sim. Pre-contact speed is
			# a bounded loudness proxy until contact impulses reach presentation.
			impact.volume_db = lerpf(-30, -8, clampf(previous_speed / 3.0, 0, 1)) + linear_to_db(game.play_settings.effects_volume)
			impact.play()
	last_contacts = contacts
	last_tick = tick
	last_delivered = delivered
	last_end = end
	previous_speed = speed

func loop_level(player: AudioStreamPlayer, level: float, peak: float) -> void:
	if level <= .005:
		player.stop()
		return
	player.volume_db = peak + linear_to_db(level * game.play_settings.effects_volume)
	if not player.playing: player.play()

func _exit_tree() -> void:
	hush()
	for player in [rumble, brushing, impact]:
		if is_instance_valid(player): player.stream = null
