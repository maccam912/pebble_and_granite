extends SceneTree
## Regenerate original club geometry, then finalize a reviewed editor bake.
## See render/club/README.md. Runtime keeps the Compatibility renderer.
const DEST := "res://render/club/"
const SOURCE := "res://build/club-lighting/club.tscn"
var mesh_count := 0

func _initialize() -> void: call_deferred("run")

func own(node: Node, scene: Node) -> void:
	for child in node.get_children():
		child.owner = scene
		own(child, scene)

func stable_names(node: Node) -> void:
	var index := 0
	for child in node.get_children():
		if child.name != "Ceiling": child.name = child.get_class() + str(index).pad_zeros(3)
		stable_names(child)
		index += 1

func unwrap(node: Node3D) -> bool:
	if node is MeshInstance3D:
		var source: Mesh = node.mesh
		var result := ArrayMesh.new()
		for index in range(source.get_surface_count()):
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(index))
			result.surface_set_material(index, source.surface_get_material(index))
		var error := result.lightmap_unwrap(node.global_transform, .25)
		if error != OK:
			push_error("Club UV2 unwrap failed: " + str(node.name) + " " + str(error))
			return false
		node.mesh = result
		node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		mesh_count += 1
	for child in node.get_children():
		if child is Node3D and not unwrap(child): return false
	return true

func save_scene(club: Node3D, path: String) -> int:
	own(club, club)
	var scene := PackedScene.new()
	var error := scene.pack(club)
	return ResourceSaver.save(scene, path) if error == OK else error

func prepare() -> int:
	var rink := CurlRinkView.new()
	rink.prepare_lighting_source = true
	rink.size = Vector2(1200, 582)
	root.add_child(rink)
	var club := Node3D.new()
	club.name = "Club"
	root.add_child(club)
	for node in rink.world.get_children():
		if node in [rink.camera, rink.broom, rink.brush, rink.selection, rink.hand, rink.preview] or node is WorldEnvironment: continue
		var copy := node.duplicate()
		if node == rink.ceiling: copy.name = "Ceiling"
		club.add_child(copy)
		if copy is Light3D:
			copy.light_bake_mode = Light3D.BAKE_STATIC
			copy.light_energy = 1.5
	stable_names(club)
	if not unwrap(club): return ERR_CANT_CREATE
	# All 24 visible fixtures contribute to the offline bake. Only the original
	# eight center fixtures remain active for moving objects in the final scene.
	for node in club.get_children():
		if not node is SpotLight3D: continue
		for x in [-6.0, 6.0]:
			var side := node.duplicate()
			side.name = "BakeOnly" + str(node.name) + ("L" if x < 0 else "R")
			side.position.x = x
			club.add_child(side)
	var lightmap := LightmapGI.new()
	lightmap.name = "LightmapGI"
	lightmap.quality = LightmapGI.BAKE_QUALITY_HIGH
	lightmap.bounces = 4
	lightmap.directional = false
	lightmap.max_texture_size = 2048
	lightmap.interior = true
	lightmap.environment_mode = LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR
	lightmap.environment_custom_color = Color("e0e8eb")
	lightmap.environment_custom_energy = .12
	lightmap.generate_probes_subdiv = LightmapGI.GENERATE_PROBES_SUBDIV_8
	club.add_child(lightmap)
	if ResourceLoader.exists(DEST + "club.lmbake"):
		lightmap.light_data = load(DEST + "club.lmbake")
	DirAccess.make_dir_recursive_absolute("res://build/club-lighting")
	var error := save_scene(club, SOURCE)
	print("CLUB_LIGHTING_SOURCE_OK meshes=", mesh_count, " result=", error)
	return error

func finalize(path: String) -> int:
	var club: Node3D = load(path).instantiate()
	var lightmap: LightmapGI = club.get_node("LightmapGI")
	if lightmap.light_data == null:
		push_error("Bake the lightmap before finalizing")
		return ERR_DOES_NOT_EXIST
	var data: LightmapGIData = lightmap.light_data.duplicate()
	# The serialized user array stores path, UV rectangle, slice, sub-instance.
	# Preserve these public resource properties while excluding reflective ice.
	var users: Array = data.get("user_data")
	var ceiling_name := "Ceiling"
	for child in club.get_children():
		if child.get_class() == "Node3D" and child.get_child_count() > 0:
			ceiling_name = str(child.name)
			child.name = "Ceiling"
	var ice_paths: Array[String] = []
	for child in club.get_children():
		if child is MeshInstance3D and child.material_override is ShaderMaterial:
			if child.material_override.shader.resource_path == "res://render/ice.gdshader":
				ice_paths.append("../" + str(child.name))
	assert(ice_paths.size() == 3)
	data.clear_users()
	for index in range(0, users.size(), 4):
		var user_path := str(users[index])
		if user_path in ice_paths: continue
		user_path = user_path.replace("../" + ceiling_name + "/", "../Ceiling/")
		data.add_user(NodePath(user_path), users[index+1], users[index+2], users[index+3])
	var atlases: Array[TextureLayered] = [load(DEST + "club.exr")]
	data.set_lightmap_textures(atlases)
	data.take_over_path(DEST + "club.lmbake")
	var error := ResourceSaver.save(data, DEST + "club.lmbake")
	if error != OK: return error
	lightmap.light_data = data
	for child in club.get_children():
		if child is Camera3D or child is WorldEnvironment:
			child.free()
		elif child is SpotLight3D:
			if str(child.name).begins_with("BakeOnly") or str(child.name).begins_with("SideLight"):
				child.free()
			else:
				child.light_energy = .15
				child.light_bake_mode = Light3D.BAKE_STATIC
	error = save_scene(club, DEST + "club.tscn")
	print("CLUB_LIGHTING_FINAL_OK baked_meshes=", data.get_user_count(), " result=", error)
	club.free()
	return error

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var error := finalize(args[1] if args.size() > 1 else SOURCE) if "--finalize" in args else prepare()
	quit(0 if error == OK else 1)
