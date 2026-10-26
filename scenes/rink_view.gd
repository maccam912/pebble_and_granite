class_name CurlRinkView
extends SubViewportContainer
## Presentation only: coordinates, cameras and smoothing never feed the authority.
const MODES := ["Auto", "Delivery", "Sweeper", "Skip", "House"]
var view: SubViewport
var world: Node3D
var ceiling: Node3D
var camera: Camera3D
var broom: Node3D
var brush: Node3D
var selection: Node3D
var sweep_target := -1
var brush_input: Dictionary = {}
var hand: Node3D
var hand_held := false
var pull_offset := 0.0
var shown_pull_offset := 0.0
var preview: Node3D
var stones: Dictionary = {}
var preview_team := 0
var delivery_y := -37.8
var delivery_x := 0.0
var delivery_aim_mm := 0
var sliding := false
var shown_camera_x := 0.0
var mode := 0
var current_camera := "Delivery"
var last_tick := -1
var last_end := -1
var was_running := false
var brush_time := 0.0
var stone_shape: ArrayMesh
var handle_cap_shape: ArrayMesh
var handle_grip_shape: ArrayMesh
var granite_material: ShaderMaterial
var shadow_material: ShaderMaterial
var handle_materials: Array[StandardMaterial3D] = []
var material_cache: Dictionary = {}
# The lighting preparation tool regenerates the same original club geometry.
var prepare_lighting_source := false
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	view = SubViewport.new()
	view.size = Vector2i(size)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	view.msaa_3d = Viewport.MSAA_2X if OS.get_name() == "Android" else Viewport.MSAA_4X
	add_child(view)
	world = Node3D.new()
	view.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("384249")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("e0e8eb")
	settings.ambient_light_energy = .58
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	if OS.get_name() != "Android":
		settings.ssao_enabled = true
		settings.ssao_radius = .5
		settings.ssao_intensity = 1.1
		settings.ssao_light_affect = .35
	environment.environment = settings
	world.add_child(environment)
	stone_shape = CurlRinkArt.stone_body()
	handle_cap_shape = CurlRinkArt.handle_cap()
	handle_grip_shape = CurlRinkArt.handle_grip()
	granite_material = CurlRinkArt.shader_material("res://render/granite.gdshader")
	granite_material.set_shader_parameter("granite_texture", load("res://assets/textures/curling-granite.png"))
	shadow_material = CurlRinkArt.shader_material("res://render/contact_shadow.gdshader")
	for color in ["e5ac24", "28a6b3"]:
		var handle_mat := material(color, .32)
		handle_materials.append(handle_mat)
	if prepare_lighting_source:
		build_club()
	else:
		var club: Node3D = load("res://render/club/club.tscn").instantiate()
		world.add_child(club)
		ceiling = club.get_node("Ceiling")
	camera = Camera3D.new()
	camera.near = .05
	camera.far = 100
	camera.fov = 62
	world.add_child(camera)
	camera.current = true
	broom = Node3D.new()
	world.add_child(broom)
	brush_head(broom)
	var shaft := cylinder(broom, .012, 1.1, Vector3(.10, .57, 0), material("253038", .28))
	shaft.rotation.z = -.18
	brush = Node3D.new()
	world.add_child(brush)
	brush_head(brush)
	var brush_shaft := cylinder(brush, .011, .8, Vector3(.30, .34, 0), material("c7d1d3", .25))
	brush_shaft.rotation.z = -.8
	selection = Node3D.new()
	world.add_child(selection)
	var selection_shape := TorusMesh.new()
	selection_shape.inner_radius = .178
	selection_shape.outer_radius = .191
	selection_shape.rings = 48
	selection_shape.ring_segments = 8
	mesh(selection, selection_shape, Vector3(0, .012, 0), material("e5bc60"))
	selection.visible = false
	hand = Node3D.new()
	world.add_child(hand)
	var glove := SphereMesh.new()
	glove.radius = .05
	glove.height = .08
	var palm := mesh(hand, glove, Vector3(0, .218, .015), material("303a40", .9))
	palm.scale.z = 1.25
	var sleeve := cylinder(hand, .048, .48, Vector3(.10, .27, .26), material("203c4a", .9))
	sleeve.rotation_degrees = Vector3(90, 16, 0)
	hand.visible = false
	preview = stone_mesh(0)
	world.add_child(preview)
	preview.position = Vector3(0, 0, 29)
	set_camera("Delivery", Vector3.ZERO)
func material(color: String, roughness := .65) -> StandardMaterial3D:
	var key := color + ":" + str(roughness)
	if material_cache.has(key): return material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.roughness = roughness
	material_cache[key] = mat
	return mat
func mesh(parent: Node3D, shape: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.position = pos
	instance.material_override = mat
	if parent in [broom, brush, selection, hand] or parent.has_meta("team"):
		instance.layers = 2
		instance.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	parent.add_child(instance)
	return instance
func box(parent: Node3D, dimensions: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = dimensions
	return mesh(parent, shape, pos, mat)
func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 48
	return mesh(parent, shape, pos, mat)
func brush_head(parent: Node3D) -> void:
	var pad := CapsuleMesh.new()
	pad.radius = .045
	pad.height = .27
	var head := mesh(parent, pad, Vector3(0, .035, 0), material("d5b25e", .88))
	head.rotation.z = PI / 2
	head.scale.z = .8
	var backing := box(parent, Vector3(.23, .018, .065), Vector3(0, .062, 0), material("26343b", .35))
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cylinder(parent, .025, .035, Vector3(0, .082, 0), material("26343b", .35))

func build_club() -> void:
	var wood := CurlRinkArt.shader_material("res://render/oak.gdshader")
	wood.set_shader_parameter("oak_texture", load("res://assets/textures/curling-oak.png"))
	var cross_wood := wood.duplicate() as ShaderMaterial
	cross_wood.set_shader_parameter("grain_along_x", true)
	var steel := material("66727a", .46)
	var plaster := CurlRinkArt.shader_material("res://render/club_finish.gdshader")
	plaster.set_shader_parameter("paint_color", Color("b5babc"))
	var rubber := material("273238", .94)
	box(world, Vector3(18, .2, 47), Vector3(0, -.16, 17.2), rubber)
	for lane in [-6.0, 0.0, 6.0]:
		var ice := CurlRinkArt.shader_material("res://render/ice.gdshader")
		ice.set_shader_parameter("lane_center", lane)
		ice.set_shader_parameter("ice_texture", load("res://assets/textures/curling-ice.png"))
		box(world, Vector3(4.75, .06, 43), Vector3(lane, -.03, 17.3), ice)
		for end in [-3.658, 38.408]:
			for x in [-.17, .17]:
				box(world, Vector3(.14, .05, .22), Vector3(lane + x, .025, end), rubber)
		for edge in [-2.48, 2.48]:
			box(world, Vector3(.15, .18, 43.2), Vector3(lane + edge, .07, 17.3), wood)
			box(world, Vector3(.16, .025, 43.2), Vector3(lane + edge, .17, 17.3), wood)
			box(world, Vector3(.035, .045, 43.2), Vector3(lane + edge - signf(edge) * .065, .05, 17.3), material("c9cecb"))
	for end in [-4.5, 40.0]:
		box(world, Vector3(18, 3.8, .25), Vector3(0, 1.9, end), plaster)
		box(world, Vector3(18, .8, .06), Vector3(0, .4, end + (.15 if end < 0 else -.15)), material("2e4851"))
		box(world, Vector3(18, .065, .08), Vector3(0, .83, end + (.16 if end < 0 else -.16)), cross_wood)
	for side in [-9.0, 9.0]:
		box(world, Vector3(.25, 3.8, 47), Vector3(side, 1.9, 17.2), plaster)
		box(world, Vector3(.07, .9, 47), Vector3(side - signf(side) * .15, .45, 17.2), material("344f58"))
		box(world, Vector3(.09, .06, 47), Vector3(side - signf(side) * .16, .92, 17.2), wood)
		for z in range(0, 40, 6):
			box(world, Vector3(.18, 3.8, .13), Vector3(side - signf(side) * .19, 1.9, z), steel)
			box(world, Vector3(.20, 1.0, 3.6), Vector3(side - signf(side) * .21, 2.45, z + 2.5), material("526e79", .2))
			for division in [-1.8, 0.0, 1.8]:
				box(world, Vector3(.23, 1.08, .045), Vector3(side - signf(side) * .23, 2.45, z + 2.5 + division), steel)
			box(world, Vector3(.24, .045, 3.7), Vector3(side - signf(side) * .22, 1.93, z + 2.5), steel)
			box(world, Vector3(.24, .045, 3.7), Vector3(side - signf(side) * .22, 2.97, z + 2.5), steel)
	# Benches, kickboards and sheet signs give familiar scale to the existing club.
	for lane in [-6.0, 0.0, 6.0]:
		box(world, Vector3(2.7, .075, .35), Vector3(lane, .45, -4.05), cross_wood)
		for x in [-1.05, 1.05]: box(world, Vector3(.06, .45, .25), Vector3(lane + x, .20, -4.05), steel)
		club_sign(str(int(lane / 6) + 2).pad_zeros(2), Vector3(lane, 1.12, -4.31), 44, .004, "e2d2ae")
	box(world, Vector3(6.2, .95, .06), Vector3(0, 2.35, -4.31), material("19333e"))
	club_sign("PEBBLE & GRANITE", Vector3(0, 2.48, -4.265), 84, .005, "e5dfcf")
	club_sign("C U R L I N G   C L U B", Vector3(0, 2.13, -4.26), 35, .004, "bfad84")
	ceiling = Node3D.new()
	world.add_child(ceiling)
	var ceiling_finish := CurlRinkArt.shader_material("res://render/club_finish.gdshader")
	ceiling_finish.set_shader_parameter("paint_color", Color("9ba6ac"))
	ceiling_finish.set_shader_parameter("ceiling", true)
	box(ceiling, Vector3(18, .10, 47), Vector3(0, 3.95, 17.2), ceiling_finish)
	var lamp := material("f8f4e7")
	lamp.emission_enabled = true
	lamp.emission = Color("fff8e8")
	lamp.emission_energy_multiplier = 1.25
	for z in range(-2, 42, 6):
		box(ceiling, Vector3(18, .12, .10), Vector3(0, 3.66, z), steel)
		for x in [-6.0, 0.0, 6.0]:
			box(ceiling, Vector3(2.6, .08, .27), Vector3(x, 3.49, z), material("3b454d", .5))
			box(ceiling, Vector3(2.45, .018, .18), Vector3(x, 3.44, z), lamp)
		for x in [-7.0, -3.5, 0.0, 3.5, 7.0]:
			CurlRinkArt.capsule_between(ceiling, Vector3(x, 3.7, z), Vector3(x + 1.75, 3.92, z), .023, steel)
		# Keep eight overlapping fixtures and soft indoor shadows on Compatibility.
		var light := SpotLight3D.new()
		light.position = Vector3(0, 3.40, z)
		light.rotation_degrees.x = -90
		light.light_color = Color("fff5e8")
		light.light_energy = .15
		light.light_specular = .35
		light.spot_range = 13.0
		light.spot_angle = 76.0
		light.spot_attenuation = .5
		light.spot_angle_attenuation = .35
		light.shadow_enabled = true
		light.shadow_opacity = .22
		light.shadow_blur = 1.5
		world.add_child(light)
	for geometry in ceiling.find_children("*", "MeshInstance3D", true, false):
		geometry.layers = 4
	var reflection := ReflectionProbe.new()
	reflection.position = Vector3(0, 1.7, 17.2)
	reflection.size = Vector3(18, 4, 47)
	reflection.box_projection = true
	reflection.interior = true
	reflection.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	reflection.intensity = .65
	reflection.cull_mask = 5 # Static room and ceiling; exclude moving props.
	reflection.max_distance = 55
	world.add_child(reflection)

func club_sign(text: String, pos: Vector3, font_size: int, pixel_size: float, color: String) -> void:
	var sign_label := Label3D.new()
	sign_label.text = text
	sign_label.font_size = font_size
	sign_label.pixel_size = pixel_size
	sign_label.position = pos
	sign_label.modulate = Color(color)
	sign_label.outline_size = 0
	world.add_child(sign_label)

func stone_mesh(team: int) -> Node3D:
	var stone := Node3D.new()
	stone.set_meta("team", team)
	mesh(stone, stone_shape, Vector3.ZERO, granite_material).layers = 2
	var shadow := PlaneMesh.new()
	shadow.size = Vector2(.40, .40)
	var contact := mesh(stone, shadow, Vector3(0, .002, 0), shadow_material)
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contact.layers = 2
	var color: StandardMaterial3D = handle_materials[team]
	mesh(stone, handle_cap_shape, Vector3.ZERO, color).layers = 2
	mesh(stone, handle_grip_shape, Vector3.ZERO, color).layers = 2
	var tip := SphereMesh.new()
	tip.radius = .015
	tip.height = .03
	mesh(stone, tip, Vector3(-.069, .201, 0), color).layers = 2
	if team == 1:
		var stripe := box(stone, Vector3(.012, .002, .022), Vector3(-.02, .217, 0), material("143943", .5))
		stripe.layers = 2
	return stone
func cycle_camera() -> String:
	mode = (mode + 1) % MODES.size()
	return MODES[mode]
func render_frame(frame: Dictionary, running: bool, sweep: bool, broom_mm: int, turn: int, aiming: bool, delta: float) -> void:
	if camera == null or frame.is_empty(): return
	var tick: int = frame.get("global_tick", 0)
	var end: int = frame.get("end", 0)
	var snap := last_tick < 0 or tick < last_tick or end != last_end or running != was_running
	last_end = end
	last_tick = tick
	was_running = running
	var present := {}
	var followed := Vector3.ZERO
	var has_followed := false
	var selected_stone: Dictionary = {}
	for data in frame.get("stones", []):
		var id: int = data.id
		present[id] = true
		if stones.has(id) and stones[id].get_meta("team") != data.team:
			stones[id].queue_free()
			stones.erase(id)
		if not stones.has(id):
			var stone := stone_mesh(data.team)
			world.add_child(stone)
			stone.position = Vector3(data.position.x, 0, -data.position.y)
			stones[id] = stone
		var node: Node3D = stones[id]
		node.visible = data.active
		var target := Vector3(data.position.x, 0, -data.position.y)
		node.position = target if snap or node.position.distance_to(target) > 2.0 else node.position.lerp(target, 1.0 - exp(-22.0 * delta))
		node.rotation.y = -data.turns * TAU
		if id == (sweep_target if sweep_target >= 0 and running else int(frame.get("delivered", -1))) and data.active:
			followed = node.position
			has_followed = true
			selected_stone = data
	for id in stones.keys():
		if not present.has(id): stones[id].queue_free(); stones.erase(id)
	broom.position = Vector3(float(broom_mm) / 1000.0, 0, 0)
	broom.visible = not running
	var team: int = frame.get("team", 0)
	if team != preview_team:
		preview.queue_free()
		preview = stone_mesh(team)
		world.add_child(preview)
		preview.position = Vector3(0, 0, 29)
		preview_team = team
	# Retain the hand's current offset across Drive -> Slide; removing the
	# pullback target immediately used to snap the stone back to its origin.
	shown_pull_offset = lerpf(shown_pull_offset, pull_offset, 1.0 - exp(-18.0 * delta)) if hand_held else 0.0
	preview.position = Vector3(delivery_x, 0, -delivery_y + shown_pull_offset)
	shown_camera_x = lerpf(shown_camera_x, delivery_x if sliding else 0.0, 1.0 - exp(-12.0 * delta)) if aiming else 0.0
	hand.position = preview.position
	hand.visible = aiming and hand_held
	preview.visible = aiming
	var heading := delivery_heading()
	hand.rotation.y = atan2(-heading.x, -heading.z)
	preview.rotation.y = hand.rotation.y - float(turn) * PI / 6.0
	brush.visible = running and sweep and has_followed
	brush_time += delta if brush.visible else 0.0
	selection.visible = running and has_followed and sweep_target >= 0
	selection.position = followed
	var direction: Vector2 = selected_stone.get("velocity", Vector2.UP).normalized()
	var right := Vector2(direction.y, -direction.x)
	var lateral := float(brush_input.get("lateral_mm", 0)) / 1000.0
	var ahead := float(brush_input.get("ahead_mm", 180)) / 1000.0
	# Accessible hold animates at the centered brush; scrub follows the pointer.
	if brush_input.get("steady", true): lateral += sin(brush_time * 24.0) * .10
	var offset := direction * ahead + right * lateral
	brush.position = followed + Vector3(offset.x, 0, -offset.y)
	brush.rotation.y = atan2(direction.x, direction.y)
	var selected: String = MODES[mode]
	if selected == "Auto": selected = "Sweeper" if running and has_followed else ("Delivery" if aiming else "House")
	if selected == "Sweeper" and not has_followed: selected = "Delivery"
	set_camera(selected, followed)
func delivery_heading() -> Vector3:
	# Match the native release ray from the held origin to the selected broom.
	return (broom.position + Vector3(float(delivery_aim_mm) / 1000.0, 0, 0) - Vector3(delivery_x, 0, -delivery_y)).normalized()
func set_camera(selected: String, followed: Vector3) -> void:
	current_camera = selected
	# The roof stays in the static reflection even when the overhead camera
	# looks through it. Global visibility would also hide it from the probe.
	camera.set_cull_mask_value(3, selected != "House")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if selected == "House" else Camera3D.PROJECTION_PERSPECTIVE
	if selected == "House":
		camera.size = 6.5
		camera.position = Vector3(0, 9, 0)
		camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	elif selected == "Skip":
		camera.position = Vector3(1.2, 1.65, -3.8)
		camera.look_at(Vector3(0, .1, 5))
	elif selected == "Sweeper":
		camera.position = followed + Vector3(.55, 1.6, 2.6)
		camera.look_at(followed + Vector3(0, .08, -.8))
	else:
		var origin := Vector3(shown_camera_x, 0, -delivery_y)
		var heading := (broom.position - origin).normalized()
		camera.position = origin - heading * 1.1 + Vector3(0, .9, 0)
		camera.look_at(origin + heading * 1.4 + Vector3(0, .18, 0))
func handle_point() -> Vector2:
	return position + camera.unproject_position(preview.position + Vector3(0, .184, 0)) if camera != null else Vector2.ZERO
func broom_point() -> Vector2:
	return position + camera.unproject_position(broom.position + Vector3(0, .05, 0)) if camera != null else Vector2.ZERO
func aim_x(screen: Vector2) -> float:
	var hit = ice_point(screen)
	return clampf(hit.x, -2.2, 2.2) if hit != null else broom.position.x
func ice_point(screen: Vector2) -> Variant:
	if camera == null or not get_global_rect().has_point(screen): return null
	var local := (screen - global_position) * Vector2(view.size) / size
	var hit = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(local), camera.project_ray_normal(local))
	return Vector2(hit.x, -hit.z) if hit != null else null
func ice_screen_point(ice: Vector2) -> Vector2:
	return global_position + camera.unproject_position(Vector3(ice.x, 0, -ice.y)) * size / Vector2(view.size)
func stone_point(id: int) -> Vector2:
	if not stones.has(id) or camera.is_position_behind(stones[id].position): return Vector2.INF
	return global_position + camera.unproject_position(stones[id].position + Vector3(0, .15, 0)) * size / Vector2(view.size)
