class_name TerrainManager
extends Node3D
## Quadtree terrain streaming. Chunks are generated on worker threads and swapped in only when a
## complete, crack-free cover is available. Fine chunks also carry forests and buildings.

const ROOT_SIZE := 1024000.0
const MAX_LEVEL := 10            # 1024 km / 2^10 = 1 km leaves
const DETAIL_SIZE := 2100.0       # chunks this size or smaller get trees/buildings

var view: Node = null             # WorldView (provides origin)
var material: ShaderMaterial
var tree_material: ShaderMaterial
var building_material: ShaderMaterial
var lod_factor := 1.8
var min_leaf := 1000.0
var tree_density := 1.0
var building_density := 1.0
var res := 32
var uploads_per_frame := 4
var cam_x := 0.0
var cam_z := 0.0
var cam_alt := 1000.0
var cam_agl := 1000.0

var chunks := {}        # Vector3i -> {mi, trees, buildings, ready, empty, last}
var displayed := {}     # Vector3i -> true
var _pending := {}      # Vector3i -> true
var _results := []
var _mutex := Mutex.new()
var _update_timer := 0.0
var _clock := 0.0
var _gen := 0
var _tasks: Array[int] = []

static var _tree_mesh: ArrayMesh
static var _conifer_mesh: ArrayMesh
static var _building_mesh: ArrayMesh


func setup(world_view: Node) -> void:
	view = world_view
	lod_factor = float(Game.q("lod"))
	min_leaf = float(Game.q("min_leaf"))
	tree_density = float(Game.q("trees"))
	building_density = float(Game.q("buildings"))
	if Game.is_mobile:
		uploads_per_frame = 2
	if String(Game.settings.quality) == "low":
		res = 24
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	material.set_shader_parameter("noise_tex", TexGen.noise_tex(256, 0.03, 4, 5))
	material.set_shader_parameter("detail", 1.0 if not Game.is_mobile else 0.6)
	tree_material = ShaderMaterial.new()
	tree_material.shader = load("res://shaders/tree.gdshader")
	building_material = ShaderMaterial.new()
	building_material.shader = load("res://shaders/building.gdshader")
	_ensure_meshes()


static func _ensure_meshes() -> void:
	if _tree_mesh != null:
		return
	# broadleaf: trunk + lumpy canopy (alpha 1 marks canopy for tinting)
	var mb := MeshBuilder.new()
	mb.add_cylinder(Vector3(0, -0.5, 0), Vector3(0, 3.2, 0), 0.32, 0.22, 5, Color(0.30, 0.22, 0.15, 0.0), false)
	mb.add_sphere(Vector3(0, 5.0, 0), Vector3(2.6, 2.4, 2.6), 6, 4, Color(0.17, 0.29, 0.11, 1.0))
	mb.add_sphere(Vector3(0.9, 6.3, 0.4), Vector3(1.7, 1.6, 1.7), 5, 3, Color(0.2, 0.32, 0.13, 1.0))
	_tree_mesh = mb.commit()
	var mc := MeshBuilder.new()
	mc.add_cylinder(Vector3(0, -0.5, 0), Vector3(0, 2.2, 0), 0.28, 0.2, 5, Color(0.28, 0.2, 0.13, 0.0), false)
	mc.add_cone(Vector3(0, 1.6, 0), Vector3(0, 7.0, 0), 2.4, 7, Color(0.09, 0.2, 0.11, 1.0))
	mc.add_cone(Vector3(0, 4.2, 0), Vector3(0, 9.6, 0), 1.7, 7, Color(0.1, 0.22, 0.12, 1.0))
	_conifer_mesh = mc.commit()
	# unit building: 1 x 1 x 1 box sitting on y = 0 (scaled per instance)
	var bb := MeshBuilder.new()
	bb.add_box(Vector3(0, 0.5, 0), Vector3(1, 1, 1), Color(1, 1, 1, 1))
	_building_mesh = bb.commit()


func set_camera(x: float, z: float, alt: float, agl: float) -> void:
	cam_x = x
	cam_z = z
	cam_alt = alt
	cam_agl = agl


func _exit_tree() -> void:
	# never let a worker outlive the manager it reports to
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


func _process(delta: float) -> void:
	_clock += delta
	if _tasks.size() > 64:
		var still: Array[int] = []
		for t in _tasks:
			if WorkerThreadPool.is_task_completed(t):
				WorkerThreadPool.wait_for_task_completion(t)
			else:
				still.append(t)
		_tasks = still
	_collect_results()
	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = 0.12
		_update_cover()
		_evict()


# ------------------------------------------------------------------ quadtree logic
func _size(level: int) -> float:
	return ROOT_SIZE / float(1 << level)


func _center(key: Vector3i) -> Vector2:
	var s := _size(key.x)
	return Vector2(-ROOT_SIZE * 0.5 + (key.y + 0.5) * s, -ROOT_SIZE * 0.5 + (key.z + 0.5) * s)


func _should_split(key: Vector3i) -> bool:
	var s := _size(key.x)
	if key.x >= MAX_LEVEL or s <= min_leaf * 1.01:
		return false
	var c := _center(key)
	var dx := maxf(absf(cam_x - c.x) - s * 0.5, 0.0)
	var dz := maxf(absf(cam_z - c.y) - s * 0.5, 0.0)
	var dy := maxf(cam_agl, 0.0)
	var d := sqrt(dx * dx + dz * dz + dy * dy)
	return d < s * lod_factor


func _children(key: Vector3i) -> Array:
	var l := key.x + 1
	return [Vector3i(l, key.y * 2, key.z * 2), Vector3i(l, key.y * 2 + 1, key.z * 2),
		Vector3i(l, key.y * 2, key.z * 2 + 1), Vector3i(l, key.y * 2 + 1, key.z * 2 + 1)]


func _parent(key: Vector3i) -> Vector3i:
	return Vector3i(key.x - 1, key.y / 2, key.z / 2)


func _is_ready(key: Vector3i) -> bool:
	return chunks.has(key) and chunks[key].ready


func _request(key: Vector3i) -> void:
	if chunks.has(key) or _pending.has(key):
		return
	_pending[key] = true
	var s := _size(key.x)
	var c := _center(key)
	var detail := s <= DETAIL_SIZE
	var job := {"key": key, "size": s, "cx": c.x, "cz": c.y, "res": res if key.x >= 4 else 16,
		"detail": detail, "trees": tree_density, "buildings": building_density, "gen": _gen}
	_tasks.append(WorkerThreadPool.add_task(_build_task.bind(job), false, "terrain chunk"))


func _update_cover() -> void:
	if displayed.is_empty():
		var root := Vector3i(0, 0, 0)
		if _is_ready(root):
			_show(root)
		else:
			_request(root)
		return
	var to_split := []
	var parents_to_merge := {}
	for key in displayed.keys():
		if _should_split(key):
			to_split.append(key)
		elif key.x > 0 and not _should_split(_parent(key)):
			parents_to_merge[_parent(key)] = true
	# prioritise splits closest to the camera
	to_split.sort_custom(func(a, b): return a.x > b.x)
	for key in to_split:
		var kids := _children(key)
		var all_ready := true
		for k in kids:
			if not _is_ready(k):
				all_ready = false
				_request(k)
		if all_ready:
			_hide(key)
			for k in kids:
				_show(k)
	for pk in parents_to_merge.keys():
		var kids2 := _children(pk)
		var all_shown := true
		for k in kids2:
			if not displayed.has(k):
				all_shown = false
				break
		if not all_shown:
			continue
		if _is_ready(pk):
			for k in kids2:
				_hide(k)
			_show(pk)
		else:
			_request(pk)


func _show(key: Vector3i) -> void:
	displayed[key] = true
	var ch: Dictionary = chunks[key]
	ch.last = _clock
	if ch.mi:
		ch.mi.visible = true
	for n in ch.extras:
		n.visible = true


func _hide(key: Vector3i) -> void:
	displayed.erase(key)
	if not chunks.has(key):
		return
	var ch: Dictionary = chunks[key]
	ch.last = _clock
	if ch.mi:
		ch.mi.visible = false
	for n in ch.extras:
		n.visible = false


func _evict() -> void:
	if chunks.size() < 420:
		return
	var victims := []
	for key in chunks.keys():
		if not displayed.has(key) and _clock - float(chunks[key].last) > 8.0:
			victims.append(key)
	victims.sort_custom(func(a, b): return chunks[a].last < chunks[b].last)
	for i in mini(victims.size(), chunks.size() - 300):
		_free_chunk(victims[i])


func _free_chunk(key: Vector3i) -> void:
	var ch: Dictionary = chunks[key]
	if ch.mi:
		ch.mi.queue_free()
	for n in ch.extras:
		n.queue_free()
	chunks.erase(key)


func clear_all() -> void:
	_gen += 1
	for key in chunks.keys():
		_free_chunk(key)
	displayed.clear()
	_pending.clear()


func is_settled() -> bool:
	## True when nothing near the camera is still waiting to be refined.
	if displayed.is_empty():
		return false
	for key in displayed.keys():
		if _should_split(key):
			return false
	return true


func pending_count() -> int:
	return _pending.size()


func reposition() -> void:
	## Called after a floating-origin shift: place every chunk from its exact world centre.
	for key in chunks.keys():
		var ch: Dictionary = chunks[key]
		var p: Vector3 = view.world_to_local_xz(ch.cx, ch.cz)
		if ch.mi:
			ch.mi.position = p
		for n in ch.extras:
			n.position = p


# ------------------------------------------------------------------ main thread: upload
func _collect_results() -> void:
	var batch := []
	_mutex.lock()
	var n := mini(_results.size(), uploads_per_frame)
	for i in n:
		batch.append(_results.pop_front())
	_mutex.unlock()
	for r in batch:
		var key: Vector3i = r.key
		_pending.erase(key)
		if int(r.gen) != _gen:
			continue
		var ch := {"key": key, "mi": null, "extras": [], "ready": true, "last": _clock, "cx": r.cx, "cz": r.cz}
		var pos: Vector3 = view.world_to_local_xz(r.cx, r.cz)
		if not r.empty:
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r.arrays)
			mesh.custom_aabb = r.aabb
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if r.size > 9000.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.position = pos
			mi.visible = false
			add_child(mi)
			ch.mi = mi
		for mm_data in r.multimeshes:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = mm_data.mesh
			mm.instance_count = mm_data.count
			mm.buffer = mm_data.buffer
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = tree_material if mm_data.kind != "building" else building_material
			mmi.position = pos
			mmi.visible = false
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if mm_data.kind == "building" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = mm_data.range
			mmi.visibility_range_end_margin = mm_data.range * 0.15
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mmi)
			ch.extras.append(mmi)
		chunks[key] = ch


# ------------------------------------------------------------------ worker thread: build
func _build_task(job: Dictionary) -> void:
	var result := build_chunk(job)
	_mutex.lock()
	_results.append(result)
	_mutex.unlock()


static func build_chunk(job: Dictionary) -> Dictionary:
	var sampler := Geo.Sampler.new()
	var n: int = job.res
	var size: float = job.size
	var cx: float = job.cx
	var cz: float = job.cz
	var s := size / n
	var x0 := cx - size * 0.5
	var z0 := cz - size * 0.5
	var w := n + 3
	var hs := PackedFloat32Array()
	hs.resize(w * w)
	var max_h := -INF
	var min_h := INF
	for j in w:
		for i in w:
			var h := sampler.height(x0 + (i - 1) * s, z0 + (j - 1) * s)
			hs[j * w + i] = h
			if i >= 1 and i <= n + 1 and j >= 1 and j <= n + 1:
				max_h = maxf(max_h, h)
				min_h = minf(min_h, h)
	var result := {"key": job.key, "gen": job.gen, "cx": cx, "cz": cz, "size": size, "empty": false, "multimeshes": []}
	if max_h < -4.0:
		result.empty = true
		return result
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2 := PackedVector2Array()
	var vc := (n + 1) * (n + 1)
	verts.resize(vc)
	normals.resize(vc)
	colors.resize(vc)
	uv2.resize(vc)
	var forest_grid := PackedFloat32Array()
	var urban_grid := PackedFloat32Array()
	forest_grid.resize(vc)
	urban_grid.resize(vc)
	for j in n + 1:
		for i in n + 1:
			var hi := (j + 1) * w + (i + 1)
			var h := hs[hi]
			var nx := hs[hi - 1] - hs[hi + 1]
			var nz := hs[hi - w] - hs[hi + w]
			var nrm := Vector3(nx, 2.0 * s, nz).normalized()
			var wx := x0 + i * s
			var wz := z0 + j * s
			var idx := j * (n + 1) + i
			verts[idx] = Vector3(i * s - size * 0.5, h, j * s - size * 0.5)
			normals[idx] = nrm
			var lu := sampler.landuse_h(wx, wz, h)
			var col := _biome_color(h, nrm.y, lu, sampler, wx, wz)
			colors[idx] = Color(col.r, col.g, col.b, lu.forest)
			uv2[idx] = Vector2(lu.farm, lu.urban)
			forest_grid[idx] = lu.forest
			urban_grid[idx] = lu.urban
	var indices := PackedInt32Array()
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			if (i + j) % 2 == 0:
				indices.append_array([a, b, d, a, d, c])
			else:
				indices.append_array([a, b, c, b, d, c])
	# skirts hide cracks between neighbouring LODs
	var skirt := maxf(s * 0.6, 4.0)
	var edges := [[], [], [], []]
	for i in n + 1:
		edges[0].append(i)
		edges[1].append(n * (n + 1) + (n - i))
		edges[2].append((n - i) * (n + 1))
		edges[3].append(i * (n + 1) + n)
	for e in edges:
		var base := verts.size()
		for vi in e:
			verts.append(verts[vi] - Vector3(0, skirt, 0))
			normals.append(normals[vi])
			colors.append(colors[vi])
			uv2.append(uv2[vi])
		for k in e.size() - 1:
			var t0: int = e[k]
			var t1: int = e[k + 1]
			var b0: int = base + k
			var b1: int = base + k + 1
			indices.append_array([t0, b0, t1, t1, b0, b1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	result.arrays = arrays
	result.aabb = AABB(Vector3(-size * 0.5, min_h - skirt, -size * 0.5), Vector3(size, max_h - min_h + skirt + 40.0, size))
	if job.detail:
		_scatter(result, job, hs, w, n, s, forest_grid, urban_grid, x0, z0)
	return result


static func _biome_color(h: float, ny: float, lu: Dictionary, sampler: Geo.Sampler, wx: float, wz: float) -> Color:
	var c: Color
	if h < 0.6:
		var depth := clampf(-h / 35.0, 0.0, 1.0)
		c = Color(0.62, 0.58, 0.44).lerp(Color(0.08, 0.2, 0.22), depth)
	else:
		var moist: float = clampf(lu.moist * 0.5 + 0.5, 0.0, 1.0)
		c = Color(0.55, 0.53, 0.3).lerp(Color(0.27, 0.42, 0.17), moist)
		if lu.airport > 0.2:
			c = c.lerp(Color(0.38, 0.44, 0.25), lu.airport)
		var beach := 1.0 - U.smooth01((h - 1.0) / 4.0)
		if beach > 0.0 and lu.urban < 0.5:
			c = c.lerp(Color(0.78, 0.72, 0.55), beach * (1.0 - lu.airport))
		var rock := 1.0 - U.smooth01((ny - 0.7) / 0.12)
		rock = maxf(rock, U.smooth01((h - 1500.0) / 500.0) * 0.8)
		c = c.lerp(Color(0.43, 0.4, 0.36), clampf(rock, 0.0, 1.0))
		var snowline: float = Geo.snowline + sampler.n_fine.get_noise_2d(wx, wz) * 220.0
		var snow := U.smooth01((h - snowline) / 160.0) * U.smooth01((ny - 0.62) / 0.15)
		c = c.lerp(Color(0.93, 0.95, 0.98), snow)
	return c.srgb_to_linear()


static func _grid_sample(arr: PackedFloat32Array, n: int, fx: float, fz: float) -> float:
	var i := clampi(int(fx), 0, n - 1)
	var j := clampi(int(fz), 0, n - 1)
	var tx := fx - i
	var tz := fz - j
	var a := arr[j * (n + 1) + i]
	var b := arr[j * (n + 1) + i + 1]
	var c := arr[(j + 1) * (n + 1) + i]
	var d := arr[(j + 1) * (n + 1) + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


static func _height_sample(hs: PackedFloat32Array, w: int, fx: float, fz: float) -> float:
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := hs[(j + 1) * w + i + 1]
	var b := hs[(j + 1) * w + i + 2]
	var c := hs[(j + 2) * w + i + 1]
	var d := hs[(j + 2) * w + i + 2]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


static func _scatter(result: Dictionary, job: Dictionary, hs: PackedFloat32Array, w: int, n: int, s: float,
		forest_grid: PackedFloat32Array, urban_grid: PackedFloat32Array, x0: float, z0: float) -> void:
	var size: float = job.size
	var r := RandomNumberGenerator.new()
	r.seed = U.hash_ints(int(job.cx), int(job.cz), 91)
	var density: float = job.trees
	var trees := PackedFloat32Array()
	var conifers := PackedFloat32Array()
	if density > 0.01:
		var spacing := 17.0 / sqrt(density)
		var cells := int(size / spacing)
		for cj in cells:
			for ci in cells:
				var lx := (ci + r.randf()) * spacing
				var lz := (cj + r.randf()) * spacing
				var fx := lx / s
				var fz := lz / s
				var f := _grid_sample(forest_grid, n, fx, fz)
				var p := f * f * 0.9 + 0.012
				if _grid_sample(urban_grid, n, fx, fz) > 0.25:
					p = 0.01
				if r.randf() > p:
					continue
				var h := _height_sample(hs, w, fx, fz)
				if h < 1.5 or h > 2150.0:
					continue
				var hx := _height_sample(hs, w, minf(fx + 0.5, n - 0.01), fz) - h
				var hz := _height_sample(hs, w, fx, minf(fz + 0.5, n - 0.01)) - h
				if absf(hx) + absf(hz) > s * 0.45:
					continue
				var sc := r.randf_range(0.7, 1.45)
				var rot := r.randf() * TAU
				var conifer := h > 650.0 or r.randf() < 0.18
				var tint := Color(r.randf_range(0.8, 1.2), r.randf_range(0.85, 1.2), r.randf_range(0.75, 1.1))
				if conifer:
					tint = Color(0.9, 1.0, 0.95) * r.randf_range(0.8, 1.15)
				var arr := conifers if conifer else trees
				_push_instance(arr, Vector3(lx - size * 0.5, h, lz - size * 0.5), rot, Vector3(sc, sc * r.randf_range(0.9, 1.2), sc), tint, r.randf())
	if trees.size() > 0:
		result.multimeshes.append({"kind": "tree", "mesh": _tree_mesh, "count": trees.size() / 16, "buffer": trees, "range": 3200.0 + 1800.0 * density})
	if conifers.size() > 0:
		result.multimeshes.append({"kind": "tree", "mesh": _conifer_mesh, "count": conifers.size() / 16, "buffer": conifers, "range": 3200.0 + 1800.0 * density})
	# buildings on the 95 m street grid used by the terrain shader
	var bdens: float = job.buildings
	if bdens > 0.01:
		var blds := PackedFloat32Array()
		var block := 95.0
		var bx0 := int(floor(x0 / block))
		var bz0 := int(floor(z0 / block))
		var nb := int(size / block) + 1
		for bj in nb:
			for bi in nb:
				var gx := (bx0 + bi + 0.5) * block
				var gz := (bz0 + bj + 0.5) * block
				var lx2 := gx - x0
				var lz2 := gz - z0
				if lx2 < 0.0 or lz2 < 0.0 or lx2 >= size or lz2 >= size:
					continue
				var u := _grid_sample(urban_grid, n, lx2 / s, lz2 / s)
				if u < 0.3:
					continue
				var hb := U.hash_ints(bx0 + bi, bz0 + bj, 17)
				var rb := RandomNumberGenerator.new()
				rb.seed = hb
				if rb.randf() > bdens * (0.6 + u * 0.4):
					continue
				var h2 := _height_sample(hs, w, lx2 / s, lz2 / s)
				if h2 < 1.0:
					continue
				var count := 1 if u > 0.75 else rb.randi_range(2, 4)
				for k in count:
					var fw := 66.0 if count == 1 else rb.randf_range(18.0, 30.0)
					var fd := 66.0 if count == 1 else rb.randf_range(16.0, 28.0)
					var ox := 0.0 if count == 1 else (-17.0 if k % 2 == 0 else 17.0)
					var oz := 0.0 if count == 1 else (-17.0 if k < 2 else 17.0)
					var height := rb.randf_range(6.0, 14.0) + u * u * rb.randf_range(4.0, 38.0)
					if u > 0.85 and rb.randf() < 0.3:
						height += rb.randf_range(20.0, 70.0)
					var bcol := U.pick(rb, [Color(0.78, 0.74, 0.68), Color(0.66, 0.62, 0.58), Color(0.82, 0.8, 0.76), Color(0.6, 0.5, 0.42), Color(0.55, 0.6, 0.66), Color(0.86, 0.82, 0.7)])
					_push_instance(blds, Vector3(lx2 - size * 0.5 + ox, h2 - 2.0, lz2 - size * 0.5 + oz), 0.0, Vector3(fw, height + 2.0, fd), bcol, rb.randf())
		if blds.size() > 0:
			result.multimeshes.append({"kind": "building", "mesh": _building_mesh, "count": blds.size() / 16, "buffer": blds, "range": 6500.0})


static func _push_instance(arr: PackedFloat32Array, pos: Vector3, rot_y: float, scale: Vector3, custom: Color, extra: float) -> void:
	var cr := cos(rot_y)
	var sr := sin(rot_y)
	# row-major 3x4 transform: basis columns scaled
	arr.append_array([cr * scale.x, 0.0, sr * scale.z, pos.x,
		0.0, scale.y, 0.0, pos.y,
		-sr * scale.x, 0.0, cr * scale.z, pos.z,
		custom.r, custom.g, custom.b, extra])
