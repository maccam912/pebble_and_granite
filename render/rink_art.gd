class_name CurlRinkArt
extends RefCounted
## Original meshes and shared materials; no simulation state or downloaded art.

static func shader_material(path: String) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = load(path)
	return result

static func stone_body() -> ArrayMesh:
	# Lathed crown, rounded shoulders and flat running base, in metres.
	var profile := PackedVector2Array([
		Vector2(0.0, .009), Vector2(.075, .009), Vector2(.112, .013),
		Vector2(.132, .026), Vector2(.143, .043), Vector2(.145, .061),
		Vector2(.143, .080), Vector2(.133, .099), Vector2(.113, .115),
		Vector2(.082, .126), Vector2(.04, .130), Vector2(0.0, .130)])
	return lathe(profile)

static func handle_cap() -> ArrayMesh:
	return lathe(PackedVector2Array([Vector2(0, .133), Vector2(.098, .133),
		Vector2(.103, .136), Vector2(.10, .140), Vector2(.086, .145),
		Vector2(.045, .149), Vector2(0, .15)]))

static func lathe(profile: PackedVector2Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const SEGMENTS := 64
	for row in range(profile.size()):
		var tangent := profile[mini(row + 1, profile.size() - 1)] - profile[maxi(row - 1, 0)]
		var normal := Vector2(tangent.y, -tangent.x).normalized()
		for column in range(SEGMENTS + 1):
			var angle := float(column) / SEGMENTS * TAU
			vertices.append(Vector3(cos(angle) * profile[row].x, profile[row].y, sin(angle) * profile[row].x))
			normals.append(Vector3(cos(angle) * normal.x, normal.y, sin(angle) * normal.x))
			uvs.append(Vector2(float(column) / SEGMENTS, float(row) / (profile.size() - 1)))
			if row < profile.size() - 1 and column < SEGMENTS:
				var a := row * (SEGMENTS + 1) + column
				var b := a + SEGMENTS + 1
				indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

static func handle_grip() -> ArrayMesh:
	# A single molded cantilever, rather than the prototype's square bracket.
	var path := PackedVector2Array([Vector2(.039, .145), Vector2(.036, .163),
		Vector2(.028, .186), Vector2(.010, .199), Vector2(-.018, .201),
		Vector2(-.069, .201)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	const SIDES := 16
	const STEPS := 30
	for row in range(STEPS + 1):
		var sample := float(row) / STEPS * (path.size() - 1)
		var index := mini(int(sample), path.size() - 2)
		var t := sample - index
		var a := path[maxi(index - 1, 0)]
		var b := path[index]
		var c := path[index + 1]
		var d := path[mini(index + 2, path.size() - 1)]
		var point := b.cubic_interpolate(c, a, d, t)
		var ahead := b.cubic_interpolate(c, a, d, minf(t + .01, 1.0))
		var direction := (ahead - point).normalized() if t < .999 else (c - b).normalized()
		var perpendicular := Vector2(-direction.y, direction.x)
		var radius := lerpf(.026, .015, smoothstep(0, .40, float(row) / STEPS))
		for column in range(SIDES + 1):
			var angle := float(column) / SIDES * TAU
			var n := Vector3(perpendicular.x * cos(angle), perpendicular.y * cos(angle), sin(angle))
			vertices.append(Vector3(point.x, point.y, 0) + n * radius)
			normals.append(n)
	for row in range(STEPS):
		for column in range(SIDES):
			var a := row * (SIDES + 1) + column
			var b := a + SIDES + 1
			for index in [a, b, a + 1, a + 1, b, b + 1]:
				surface.set_normal(normals[index])
				surface.add_vertex(vertices[index])
	return surface.commit()

static func capsule_between(parent: Node3D, from: Vector3, to: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var shape := CapsuleMesh.new()
	shape.radius = radius
	shape.height = from.distance_to(to) + radius * 2.0
	shape.radial_segments = 16
	shape.rings = 4
	var part := MeshInstance3D.new()
	part.mesh = shape
	part.material_override = mat
	part.position = (from + to) * .5
	part.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	parent.add_child(part)
	return part
