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
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	view = SubViewport.new()
	view.size = Vector2i(size)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	view.msaa_3d = Viewport.MSAA_2X
	add_child(view)
	world = Node3D.new()
	view.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("17272c")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c6d8de")
	settings.ambient_light_energy = .55
	environment.environment = settings
	world.add_child(environment)
	build_club()
	camera = Camera3D.new()
	camera.near = .05
	camera.far = 100
	camera.fov = 62
	world.add_child(camera)
	camera.current = true
	broom = Node3D.new()
	world.add_child(broom)
	box(broom, Vector3(.34, .045, .10), Vector3(0, .04, 0), material("e9bb61"))
	var shaft := cylinder(broom, .018, 1.1, Vector3(.10, .57, 0), material("253b43"))
	shaft.rotation.z = -.18
	brush = Node3D.new()
	world.add_child(brush)
	box(brush, Vector3(.30, .05, .09), Vector3(0, .04, 0), material("e9bb61"))
	var brush_shaft := cylinder(brush, .013, .8, Vector3(.30, .34, 0), material("d8e5e5"))
	brush_shaft.rotation.z = -.8
	hand = Node3D.new()
	world.add_child(hand)
	box(hand, Vector3(.095, .045, .11), Vector3(0, .305, .015), material("384849"))
	var sleeve := cylinder(hand, .055, .48, Vector3(.10, .355, .26), material("203c4a"))
	sleeve.rotation_degrees = Vector3(90, 16, 0)
	hand.visible = false
	preview = stone_mesh(0)
	world.add_child(preview)
	preview.position = Vector3(0, 0, 29)
	set_camera("Delivery", Vector3.ZERO)
func material(color: String, roughness := .65) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.roughness = roughness
	return mat
func mesh(parent: Node3D, shape: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.position = pos
	instance.material_override = mat
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
func build_club() -> void:
	var ice := material("c4d7dc", .45)
	var wood := material("554840")
	box(world, Vector3(18, .2, 47), Vector3(0, -.16, 17.2), material("25363b"))
	for lane in [-6.0, 0.0, 6.0]:
		box(world, Vector3(4.75, .06, 43), Vector3(lane, -.03, 17.3), ice)
		for tee in [0.0, 34.75]:
			var layer := .004
			for ring in [[1.829, "37768d"], [1.219, "ecf1ec"], [.610, "b86660"], [.152, "ecf1ec"]]:
				cylinder(world, ring[0], .002, Vector3(lane, layer, tee), material(ring[1], .4))
				layer += .003
			box(world, Vector3(4.75, .002, .013), Vector3(lane, .02, tee), material("647d83"))
		for hog in [6.350, 28.400]: box(world, Vector3(4.75, .005, .102), Vector3(lane, .006, hog), material("aa5252"))
		for back in [-1.8225, 36.5725]: box(world, Vector3(4.75, .004, .013), Vector3(lane, .006, back), material("647d83"))
		box(world, Vector3(.013, .002, 42), Vector3(lane, .021, 17.3), material("82999d"))
		for end in [-3.658, 38.408]:
			for x in [-.17, .17]: box(world, Vector3(.14, .06, .22), Vector3(lane + x, .03, end), material("263437"))
		for edge in [-2.48, 2.48]: box(world, Vector3(.15, .18, 43.2), Vector3(lane + edge, .07, 17.3), wood)
	box(world, Vector3(18, 3.6, .25), Vector3(0, 1.8, -4.5), material("344c53"))
	for side in [-9.0, 9.0]: box(world, Vector3(.25, 3.6, 47), Vector3(side, 1.8, 17.2), material("344c53"))
	ceiling = Node3D.new()
	world.add_child(ceiling)
	for z in range(-2, 42, 6):
		box(ceiling, Vector3(18, .16, .18), Vector3(0, 3.6, z), material("526569"))
		var lamp := material("fff1cf")
		lamp.emission_enabled = true
		lamp.emission = Color("fff1cf")
		box(ceiling, Vector3(3.0, .05, .18), Vector3(0, 3.48, z), lamp)
		# Eight overlapping indoor fixtures, below the beams. Keep the light
		# nodes outside the ceiling group so House view hides only its meshes.
		var light := SpotLight3D.new()
		light.position = Vector3(0, 3.40, z)
		light.rotation_degrees.x = -90
		light.light_color = Color("fff4e4")
		light.light_energy = .24
		light.light_specular = .15
		light.spot_range = 12.0
		light.spot_angle = 72.0
		light.spot_attenuation = .5
		light.spot_angle_attenuation = .4
		light.shadow_enabled = true
		light.shadow_opacity = .22
		light.shadow_blur = 1.5
		world.add_child(light)
	var sign := Label3D.new()
	sign.text = "PEBBLE & GRANITE"
	sign.font_size = 70
	sign.pixel_size = .008
	sign.position = Vector3(0, 2.2, -4.34)
	sign.modulate = Color("ebcf97")
	world.add_child(sign)
func stone_mesh(team: int) -> Node3D:
	var stone := Node3D.new()
	stone.set_meta("team", team)
	var granite := SphereMesh.new()
	granite.radius = .142
	granite.height = .22
	granite.radial_segments = 32
	granite.rings = 12
	mesh(stone, granite, Vector3(0, .11, 0), material("839096", .38))
	cylinder(stone, .105, .027, Vector3(0, .213, 0), material("cad4d4", .3))
	var color := material("e9bb61" if team == 0 else "64cdd1", .28)
	for x in [-.065, .065]: cylinder(stone, .018, .045, Vector3(x, .245, 0), color)
	box(stone, Vector3(.16, .027, .035), Vector3(0, .274, 0), color)
	if team == 1: box(stone, Vector3(.025, .008, .042), Vector3(0, .293, 0), material("173942"))
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
		if id == frame.get("delivered", -1) and data.active:
			followed = node.position
			has_followed = true
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
	brush.position = followed + Vector3(sin(brush_time * 24.0) * .13, 0, -.25)
	var selected: String = MODES[mode]
	if selected == "Auto": selected = "Sweeper" if running and has_followed else ("Delivery" if aiming else "House")
	if selected == "Sweeper" and not has_followed: selected = "Delivery"
	set_camera(selected, followed)
func delivery_heading() -> Vector3:
	# Match the native release ray from the held origin to the selected broom.
	return (broom.position + Vector3(float(delivery_aim_mm) / 1000.0, 0, 0) - Vector3(delivery_x, 0, -delivery_y)).normalized()
func set_camera(selected: String, followed: Vector3) -> void:
	current_camera = selected
	ceiling.visible = selected != "House"
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
	return position + camera.unproject_position(preview.position + Vector3(0, .274, 0)) if camera != null else Vector2.ZERO
func broom_point() -> Vector2:
	return position + camera.unproject_position(broom.position + Vector3(0, .05, 0)) if camera != null else Vector2.ZERO
func aim_x(screen: Vector2) -> float:
	if camera == null: return 0.0
	var local := screen - position
	var hit = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(local), camera.project_ray_normal(local))
	return clampf(hit.x, -2.2, 2.2) if hit != null else broom.position.x
