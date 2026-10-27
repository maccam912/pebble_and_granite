extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failed = true
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ref := CurlShotReference.new()
	var frame := {"end": 1, "delivered": 0, "contacts": 0, "resting": false, "stones": [{"id": 0, "team": 0, "active": true, "position": Vector2(0, -20)}]}
	ref.begin(frame, -700, 1, "Draw weight")
	frame.stones[0].position = Vector2(.2, -.4)
	frame.resting = true
	ref.observe(frame, false)
	check(ref.shots.has(0), "Clean stone reference missing")
	frame.delivered = 1
	frame.stones.append({"id": 1, "team": 1, "active": true, "position": Vector2(1, -.5)})
	ref.begin(frame, 900, -1, "Guard weight")
	frame.contacts = 1
	ref.observe(frame, true)
	ref.observe(frame, false)
	check(not ref.shots.has(1) and ref.shots.has(0), "Contact shot left a misleading reference")
	frame.stones[0].position += Vector2(.1, 0)
	ref.observe(frame, false)
	check(ref.shots.is_empty(), "Later moved stone kept its highlight")
	frame.contacts = 0
	ref.begin(frame, 900, -1, "Guard weight")
	ref.observe(frame, false)
	check(ref.shots.has(1), "Second clean reference missing")
	frame.end = 2
	ref.observe(frame, false)
	check(ref.shots.is_empty(), "Reference crossed an end boundary")
	ref.begin(frame, 900, -1, "Guard weight")
	frame.stones[1].active = false
	ref.observe(frame, false)
	check(ref.shots.is_empty(), "Out-of-play shot retained a reference")

	var game = load("res://scenes/play.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	game.set_process(false)
	var audio: CurlIceAudio = game.ice_audio
	audio.set_process(false)
	game.frame = {"global_tick": 1, "end": 1, "delivered": 0, "contacts": 0, "stones": [{"id": 0, "team": 0, "active": true, "speed": 2.0, "position": Vector2(0, -10), "velocity": Vector2(0, 2), "turns": 0.0}]}
	game.run_active = true
	audio._process(.25)
	check(audio.rumble.playing and not audio.impact.playing, "Travel rumble missing or false impact on initial frame")
	game.hold_sweep = true
	audio._process(.02)
	check(audio.brushing.playing, "Held brush effort did not sound")
	game.hold_sweep = false
	game.frame.contacts = 1
	game.frame.global_tick = 2
	audio._process(.02)
	check(audio.impact.playing, "Sim contact did not sound")
	audio.impact.stop()
	audio._process(.02)
	check(not audio.impact.playing, "Same sim contact replayed audio")
	game.frame.delivered = 1
	audio._process(.02)
	check(not audio.impact.playing, "Loading a different shot replayed an old contact")
	game.play_settings.ice_sounds = false
	audio._process(.02)
	check(not audio.rumble.playing and not audio.impact.playing and not audio.brushing.playing, "Mute left effects playing")
	game.play_settings.ice_sounds = true
	game.play_settings.show()
	audio._process(.02)
	check(not audio.rumble.playing, "Settings pause left ice rumble playing")
	game.play_settings.hide()
	game.run_active = false
	audio._process(1)
	check(not audio.rumble.playing, "Stone at rest left rumble playing")
	# Device preference round trip, isolated from the user's settings.
	var settings = game.play_settings
	settings.config_path = "user://test-ice-sounds.cfg"
	settings.persistence_enabled = true
	settings.ice_sounds = false
	game.frame = game.session.frame()
	settings.update_preferences()
	var restored := CurlPlaySettings.new()
	restored.config_path = settings.config_path
	root.add_child(restored)
	check(not restored.ice_sounds and not restored.sound_toggle.button_pressed, "Ice sound preference did not persist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.config_path))
	restored.queue_free()
	game.queue_free()
	# Audio playback retirement runs on the mixer thread after nodes are freed.
	await create_timer(.5).timeout
	print("SKIP_POLISH_OK" if not failed else "SKIP_POLISH_FAILED")
	quit(1 if failed else 0)
