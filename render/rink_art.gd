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

static func rounded_pad(dimensions: Vector3, radius: float, bevel: float) -> ArrayMesh:
	# A low rounded housing/pad, with a flat face and smooth perimeter bevel.
	var half := Vector2(dimensions.x, dimensions.z) * .5
	var r := minf(radius, minf(half.x, half.y) * .98)
	var b := minf(bevel, minf(dimensions.y * .49, r * .5))
	var centers := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const PERIMETER := 36
	for row in range(6):
		var angle := float(row % 3 - 2 if row < 3 else row % 3) * PI / 4.0
		var y := (-dimensions.y * .5 + b if row < 3 else dimensions.y * .5 - b) + b * sin(angle)
		var inset := b * (1.0 - cos(angle))
		for corner in range(4):
			var center: Vector2 = centers[corner] * (half - Vector2.ONE * r)
			for step in range(9):
				var turn := (float(corner) + float(step) / 8.0) * PI * .5
				var radial := Vector2(cos(turn), sin(turn))
				var point := center + radial * (r - inset)
				vertices.append(Vector3(point.x, y, point.y))
				normals.append(Vector3(radial.x * cos(angle), sin(angle), radial.y * cos(angle)))
				uvs.append(point / (half * 2.0) + Vector2.ONE * .5)
	for row in range(5):
		for column in range(PERIMETER):
			var a := row * PERIMETER + column
			var next := row * PERIMETER + (column + 1) % PERIMETER
			indices.append_array(PackedInt32Array([a, next, a + PERIMETER, next, next + PERIMETER, a + PERIMETER]))
	for end in [-1.0, 1.0]:
		var center := vertices.size()
		vertices.append(Vector3(0, end * dimensions.y * .5, 0))
		normals.append(Vector3.UP * end)
		uvs.append(Vector2.ONE * .5)
		var ring := 0 if end < 0 else PERIMETER * 5
		for column in range(PERIMETER):
			var next := (column + 1) % PERIMETER
			indices.append_array(PackedInt32Array([center, ring + next, ring + column] if end < 0 else [center, ring + column, ring + next]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

static func steel_beam(length: float) -> ArrayMesh:
	# One mesh for the existing roof member, with a visible web and flanges.
	var profile := PackedVector2Array([
		Vector2(-.08, -.15), Vector2(.08, -.15), Vector2(.08, -.125),
		Vector2(.009, -.125), Vector2(.009, .125), Vector2(.08, .125),
		Vector2(.08, .15), Vector2(-.08, .15), Vector2(-.08, .125),
		Vector2(-.009, .125), Vector2(-.009, -.125), Vector2(-.08, -.125)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(profile.size()):
		var next := (index + 1) % profile.size()
		var edge := profile[next] - profile[index]
		var normal := Vector2(edge.y, -edge.x).normalized()
		for vertex in [[index, -1], [index, 1], [next, -1], [next, -1], [index, 1], [next, 1]]:
			var point: Vector2 = profile[vertex[0]]
			plank_vertex(surface, Vector3(point.x, point.y, vertex[1] * length * .5),
				Vector3(normal.x, normal.y, 0), Vector2(float(vertex[0]) / profile.size(), (vertex[1] + 1) * .5), true)
	var triangles := Geometry2D.triangulate_polygon(profile)
	for end in [-1.0, 1.0]:
		for triangle in range(0, triangles.size(), 3):
			for corner in [0, 2, 1] if end > 0 else [0, 1, 2]:
				var point := profile[triangles[triangle + corner]]
				plank_vertex(surface, Vector3(point.x, point.y, end * length * .5),
					Vector3(0, 0, end), point / Vector2(.16, .30) + Vector2.ONE * .5, true)
	return surface.commit()

static func rounded_plank(dimensions: Vector3, radius: float) -> ArrayMesh:
	# Round the four long edges within the original timber's exact bounds.
	# Three segments per corner keep the silhouette soft at normal game scale.
	var along_x := dimensions.x > dimensions.z
	var width := dimensions.z if along_x else dimensions.x
	var length := dimensions.x if along_x else dimensions.z
	var half := Vector2(width, dimensions.y) * .5
	var r := minf(radius, minf(half.x, half.y) * .8)
	var profile := PackedVector2Array()
	var normals := PackedVector2Array()
	var centers := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for corner in range(4):
		var center: Vector2 = centers[corner] * (half - Vector2.ONE * r)
		for step in range(4):
			var angle := (float(corner) + float(step) / 3.0) * PI * .5
			var normal := Vector2(cos(angle), sin(angle))
			profile.append(center + normal * r)
			normals.append(normal)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(profile.size()):
		var next := (index + 1) % profile.size()
		for vertex in [[index, -1], [index, 1], [next, -1], [next, -1], [index, 1], [next, 1]]:
			var p: Vector2 = profile[vertex[0]]
			var n: Vector2 = normals[vertex[0]]
			plank_vertex(surface, Vector3(p.x, p.y, vertex[1] * length * .5),
				Vector3(n.x, n.y, 0), Vector2(float(vertex[0]) / profile.size(), (vertex[1] + 1) * .5), along_x)
		for end in [-1.0, 1.0]:
			var cap_normal := Vector3(0, 0, end)
			plank_vertex(surface, Vector3(0, 0, end * length * .5), cap_normal, Vector2(.5, .5), along_x)
			for point in [next, index] if end > 0 else [index, next]:
				var p := profile[point]
				plank_vertex(surface, Vector3(p.x, p.y, end * length * .5), cap_normal, p / (half * 2) + Vector2.ONE * .5, along_x)
	return surface.commit()

static func plank_vertex(surface: SurfaceTool, point: Vector3, normal: Vector3, uv: Vector2, along_x: bool) -> void:
	if along_x:
		point = Vector3(point.z, point.y, -point.x)
		normal = Vector3(normal.z, normal.y, -normal.x)
	surface.set_normal(normal)
	surface.set_uv(uv)
	surface.add_vertex(point)

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

static func jacket_sleeve(length: float) -> ArrayMesh:
	# Soft diagonal folds near the cuff, rather than concentric hard ridges.
	# This is only the existing first-person prop; no animation/input changes.
	const RINGS := 64
	const SIDES := 48
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for row in range(RINGS + 1):
		var t := float(row) / RINGS
		for column in range(SIDES + 1):
			var angle := float(column) / SIDES * TAU
			var point := sleeve_point(length, t, angle)
			vertices.append(point)
			var radius := Vector2(point.x, point.z / .92).length()
			var compression := clampf((lerpf(.074, .038, t) - radius) / .006, 0.0, 1.0)
			var shade := lerpf(1.0, .86, compression)
			colors.append(Color(shade, shade, shade))
			var along := sleeve_point(length, t + .001, angle) - sleeve_point(length, t - .001, angle)
			var around := sleeve_point(length, t, angle + .001) - sleeve_point(length, t, angle - .001)
			normals.append(along.cross(around).normalized())
			uvs.append(Vector2(float(column) / SIDES, t))
			if row < RINGS and column < SIDES:
				var a := row * (SIDES + 1) + column
				var b := a + SIDES + 1
				indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

static func sleeve_point(length: float, t: float, angle: float) -> Vector3:
	var taper := lerpf(.074, .038, t)
	var folds := smoothstep(.38, .66, t) * (1.0 - smoothstep(.94, 1.0, t))
	var crease := sin(t * 39.0 + sin(angle * 2.0) * 1.8) * .0014
	crease += sin(t * 27.0 - angle * 3.0) * .0009
	# Local diagonal compression folds, with loose cloth beside each valley.
	for fold: Vector3 in [Vector3(.62, .055, .5), Vector3(.79, .05, 2.7), Vector3(.91, .035, 4.4)]:
		var offset := t - fold.x - sin(angle + fold.z) * .045
		var weight := .25 + .75 * pow(sin(angle * .5 + fold.z), 2.0)
		crease -= exp(-pow(offset / fold.y, 2.0)) * .007 * weight
		crease += exp(-pow((offset + .045) / (fold.y * 1.3), 2.0)) * .004 * weight
	var radius := taper + folds * crease
	return Vector3(cos(angle) * radius, (t - .5) * length, sin(angle) * radius * .92)

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
