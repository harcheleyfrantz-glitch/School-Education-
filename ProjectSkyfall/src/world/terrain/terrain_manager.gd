class_name TerrainManager
extends Node3D
## Quadtree terrain streaming. Chunks are generated on worker threads and swapped in only when a
## complete, crack-free cover is available. Fine chunks also carry forests and buildings.

const ROOT_SIZE := 8192000.0     # covers Calderra and the real-world region (Americas to Japan)
const MAX_LEVEL := 13            # 8192 km / 2^13 = 1 km leaves
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
static var _birch_mesh: ArrayMesh
static var _pine_mesh: ArrayMesh
static var _palm_mesh: ArrayMesh
static var _house_mesh: ArrayMesh
static var _tower_mesh: ArrayMesh
static var _city_meshes := {}      # CityMeshes name -> ArrayMesh (built on the main thread)

const CityStyles := preload("res://src/data/city_styles.gd")
const CityMeshes := preload("res://src/world/models/city/city_meshes.gd")
## visibility range per city mesh: small houses fade first, towers stay on the skyline
const CITY_RANGE := {"plate": 5200.0, "house3": 3600.0, "wood_house3": 3600.0, "hip_house3": 3600.0, "villa": 3600.0,
	"terrace": 5200.0, "canal": 5200.0, "shop_row": 5200.0, "shed": 6000.0, "tower_glass": 14000.0, "tower_res": 12000.0}


func setup(world_view: Node) -> void:
	view = world_view
	lod_factor = float(Game.q("lod"))
	min_leaf = float(Game.q("min_leaf"))
	tree_density = float(Game.q("trees"))
	building_density = float(Game.q("buildings"))
	if Game.is_mobile:
		uploads_per_frame = 2
	if String(Game.settings.quality) in ["low", "potato"]:
		res = 24
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	material.set_shader_parameter("noise_tex", TexGen.noise_tex(256, 0.03, 4, 5))
	material.set_shader_parameter("detail", 1.0 if not Game.is_mobile else 0.6)
	_refresh_local(cam_x, cam_z)
	tree_material = ShaderMaterial.new()
	tree_material.shader = load("res://shaders/tree.gdshader")
	building_material = ShaderMaterial.new()
	building_material.shader = load("res://shaders/building.gdshader")
	_ensure_meshes()
	CityStyles.prepare(Geo.cities)


static func _ensure_meshes() -> void:
	if _city_meshes.is_empty():
		_city_meshes = CityMeshes.build_all()
	if _tree_mesh != null:
		return
	# Trees: vertex alpha 1 marks foliage (tinted per instance), 0 bark. Low-poly but with
	# layered, irregular crowns so stands of them read as real woodland from the air.
	var mb := MeshBuilder.new()
	mb.add_cylinder(Vector3(0, -0.5, 0), Vector3(0, 3.4, 0), 0.34, 0.22, 6, Color(0.30, 0.22, 0.15, 0.0), false)
	mb.add_cylinder(Vector3(0, 2.6, 0), Vector3(1.1, 4.6, 0.3), 0.14, 0.08, 4, Color(0.30, 0.22, 0.15, 0.0), false)
	for lobe in [[Vector3(0, 5.4, 0), Vector3(2.9, 2.3, 2.8), 0.16], [Vector3(1.4, 6.3, 0.6), Vector3(1.9, 1.7, 1.9), 0.2],
			[Vector3(-1.3, 6.0, -0.7), Vector3(2.0, 1.8, 1.9), 0.13], [Vector3(0.2, 7.3, -0.3), Vector3(1.6, 1.3, 1.6), 0.24],
			[Vector3(-0.4, 4.6, 1.5), Vector3(1.7, 1.4, 1.6), 0.11]]:
		mb.add_sphere(lobe[0], lobe[1], 7, 5, Color(0.16 + float(lobe[2]) * 0.2, 0.28 + float(lobe[2]) * 0.25, 0.1, 1.0))
	_tree_mesh = mb.commit()
	# spruce: four whorls of drooping cones
	var mc := MeshBuilder.new()
	mc.add_cylinder(Vector3(0, -0.5, 0), Vector3(0, 3.0, 0), 0.3, 0.2, 6, Color(0.28, 0.2, 0.13, 0.0), false)
	for w in [[1.4, 6.0, 2.7], [3.8, 8.6, 2.1], [6.2, 11.0, 1.55], [8.6, 13.4, 1.0]]:
		mc.add_cone(Vector3(0, float(w[0]), 0), Vector3(0, float(w[1]), 0), float(w[2]), 8, Color(0.08, 0.19, 0.1, 1.0))
	_conifer_mesh = mc.commit()
	# birch: slim white trunk, narrow oval crown of light leaves
	var bi := MeshBuilder.new()
	bi.add_cylinder(Vector3(0, -0.5, 0), Vector3(0, 7.5, 0), 0.2, 0.1, 6, Color(0.82, 0.8, 0.76, 0.0), false)
	bi.add_sphere(Vector3(0, 7.2, 0), Vector3(1.6, 3.0, 1.6), 7, 6, Color(0.3, 0.42, 0.16, 1.0))
	bi.add_sphere(Vector3(0.5, 8.9, 0.2), Vector3(1.0, 1.6, 1.0), 6, 4, Color(0.34, 0.46, 0.18, 1.0))
	_birch_mesh = bi.commit()
	# Scots pine: tall bare trunk with a flat, umbrella crown
	var pn := MeshBuilder.new()
	pn.add_cylinder(Vector3(0, -0.5, 0), Vector3(0, 10.5, 0), 0.32, 0.18, 6, Color(0.42, 0.25, 0.15, 0.0), false)
	pn.add_sphere(Vector3(0, 11.0, 0), Vector3(2.6, 1.3, 2.4), 7, 4, Color(0.1, 0.2, 0.1, 1.0))
	pn.add_sphere(Vector3(1.2, 10.2, 0.5), Vector3(1.4, 0.8, 1.3), 6, 3, Color(0.11, 0.22, 0.11, 1.0))
	_pine_mesh = pn.commit()
	# palm: leaning segmented trunk, drooping fronds
	var pa := MeshBuilder.new()
	var top := Vector3.ZERO
	for k in 6:
		var a := Vector3(0.12 * k * k * 0.12, k * 1.5 - 0.4, 0)
		var b := Vector3(0.12 * (k + 1) * (k + 1) * 0.12, (k + 1) * 1.5 - 0.4, 0)
		pa.add_cylinder(a, b, 0.24 - k * 0.012, 0.22 - k * 0.012, 6, Color(0.45, 0.36, 0.26, 0.0), false)
		top = b
	for f in 8:
		var ang := float(f) / 8.0 * TAU
		var d := Vector3(cos(ang), 0, sin(ang))
		var mid := top + d * 1.8 + Vector3(0, 0.5, 0)
		var tip := top + d * 3.4 + Vector3(0, -0.9, 0)
		var side := d.cross(Vector3.UP) * 0.42
		pa.add_quad(top, mid + side, tip, mid - side, Color(0.2, 0.36, 0.12, 1.0))
		pa.add_quad(top, mid - side, tip, mid + side, Color(0.2, 0.36, 0.12, 1.0))
	_palm_mesh = pa.commit()
	# Buildings: unit footprint, height 1, scaled per instance. Vertex colour r = facade kind
	# (1 office/flats windows, 0.5 glass curtain wall, 0.2 house), a = surface (1 wall,
	# 0.5 pitched roof, 0.25 rooftop plant, 0 flat roof).
	var bb := MeshBuilder.new()
	bb.add_box(Vector3(0, 0.5, 0), Vector3(1, 1, 1), Color(1, 1, 1, 1))
	bb.add_box(Vector3(0, 1.0, 0), Vector3(0.98, 0.02, 0.98), Color(1, 1, 1, 0.0))
	bb.add_box(Vector3(0.22, 1.03, -0.18), Vector3(0.22, 0.05, 0.16), Color(1, 1, 1, 0.25))
	bb.add_box(Vector3(-0.25, 1.025, 0.2), Vector3(0.12, 0.04, 0.3), Color(1, 1, 1, 0.25))
	_building_mesh = bb.commit()
	var hs := MeshBuilder.new()
	hs.add_box(Vector3(0, 0.31, 0), Vector3(1, 0.62, 1), Color(0.2, 1, 1, 1))
	# gable roof with eaves, ridge along z
	var e := 0.07
	var y0 := 0.62
	var y1 := 1.0
	var rc := Color(0.2, 1, 1, 0.5)
	hs.add_quad(Vector3(-0.5 - e, y0 - 0.03, -0.5 - e), Vector3(-0.5 - e, y0 - 0.03, 0.5 + e), Vector3(0, y1, 0.5 + e), Vector3(0, y1, -0.5 - e), rc)
	hs.add_quad(Vector3(0.5 + e, y0 - 0.03, 0.5 + e), Vector3(0.5 + e, y0 - 0.03, -0.5 - e), Vector3(0, y1, -0.5 - e), Vector3(0, y1, 0.5 + e), rc)
	var gc := Color(0.2, 1, 1, 1)
	hs.add_tri_idx(hs.add_vertex(Vector3(0.5, y0, -0.5), Vector3(0, 0, -1), gc, Vector2.ZERO), hs.add_vertex(Vector3(0, y1, -0.5), Vector3(0, 0, -1), gc, Vector2.ZERO), hs.add_vertex(Vector3(-0.5, y0, -0.5), Vector3(0, 0, -1), gc, Vector2.ZERO))
	hs.add_tri_idx(hs.add_vertex(Vector3(-0.5, y0, 0.5), Vector3(0, 0, 1), gc, Vector2.ZERO), hs.add_vertex(Vector3(0, y1, 0.5), Vector3(0, 0, 1), gc, Vector2.ZERO), hs.add_vertex(Vector3(0.5, y0, 0.5), Vector3(0, 0, 1), gc, Vector2.ZERO))
	hs.add_box(Vector3(0.22, 0.95, 0.25), Vector3(0.08, 0.2, 0.08), Color(0.2, 1, 1, 0.25))
	_house_mesh = hs.commit()
	# tower: podium, setback shaft, crown
	var tw := MeshBuilder.new()
	tw.add_box(Vector3(0, 0.06, 0), Vector3(1, 0.12, 1), Color(1, 1, 1, 1))
	tw.add_box(Vector3(0, 0.12 + 0.58 * 0.5, 0), Vector3(0.82, 0.58, 0.82), Color(0.5, 1, 1, 1))
	tw.add_box(Vector3(0, 0.7 + 0.27 * 0.5, 0), Vector3(0.62, 0.27, 0.62), Color(0.5, 1, 1, 1))
	tw.add_box(Vector3(0, 0.975, 0), Vector3(0.5, 0.05, 0.5), Color(1, 1, 1, 0.25))
	tw.add_box(Vector3(0, 0.12, 0), Vector3(0.84, 0.004, 0.84), Color(1, 1, 1, 0.0))
	tw.add_box(Vector3(0, 0.7, 0), Vector3(0.64, 0.004, 0.64), Color(1, 1, 1, 0.0))
	tw.add_cylinder(Vector3(0.1, 1.0, 0.1), Vector3(0.1, 1.12, 0.1), 0.01, 0.004, 4, Color(1, 1, 1, 0.25), false)
	_tower_mesh = tw.commit()


func set_camera(x: float, z: float, alt: float, agl: float) -> void:
	cam_x = x
	cam_z = z
	cam_alt = alt
	cam_agl = agl
	if Vector2(x, z).distance_to(_local_at) > 60000.0:
		_refresh_local(x, z)


var _local_at := Vector2(INF, INF)


func _refresh_local(x: float, z: float) -> void:
	## The terrain shader paints the 32 motorways and 16 airports nearest the camera.
	_local_at = Vector2(x, z)
	var here := Vector2(x, z)
	var hw: Array = Geo.highways().duplicate()
	hw.sort_custom(func(a, b): return _seg_dist(here, a) < _seg_dist(here, b))
	var roads: Array = []
	for h in hw.slice(0, 32):
		roads.append(Vector4(h[0], h[1], h[2], h[3]))
		roads.append(Vector4(h[4], 0, 0, 0))
	while roads.size() < 64:
		roads.append(Vector4.ZERO)
	material.set_shader_parameter("roads", roads)
	material.set_shader_parameter("road_count", mini(hw.size(), 32) if not String(Game.settings.quality) in ["low", "potato"] else 0)
	var afl: Array = Geo.airports_flat.duplicate()
	afl.sort_custom(func(a, b): return here.distance_squared_to(Vector2(a[0], a[1])) < here.distance_squared_to(Vector2(b[0], b[1])))
	var aps: Array = []
	for af in afl.slice(0, 16):
		aps.append(Vector4(af[0], af[1], af[3], 0))
	while aps.size() < 16:
		aps.append(Vector4(0, 0, -1, 0))
	material.set_shader_parameter("airports", aps)


static func _seg_dist(p: Vector2, h: Array) -> float:
	var a := Vector2(h[0], h[1])
	var b := Vector2(h[2], h[3])
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
	return p.distance_to(a + ab * t)


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
		"detail": detail, "trees": tree_density, "buildings": building_density, "gen": _gen, "roads": _roads_near(c, s)}
	_tasks.append(WorkerThreadPool.add_task(_build_task.bind(job), false, "terrain chunk"))


func _roads_near(c: Vector2, s: float) -> Array:
	var out := []
	for h in Geo.highways():
		var a := Vector2(h[0], h[1])
		var b := Vector2(h[2], h[3])
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (s + 400.0)
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (s + 400.0)
		if c.x > lo.x and c.x < hi.x and c.y > lo.y and c.y < hi.y:
			out.append(h)
	return out


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
			mmi.material_override = tree_material if mm_data.kind == "tree" else building_material
			mmi.position = pos
			mmi.visible = false
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if mm_data.kind == "building" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = mm_data.range
			mmi.visibility_range_end_margin = mm_data.range * 0.15
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mmi)
			ch.extras.append(mmi)
		if r.has("plates"):
			# city ground plates (streets, pavements, lots) as one plain mesh per chunk
			var pmesh := ArrayMesh.new()
			pmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r.plates)
			var pmi := MeshInstance3D.new()
			pmi.mesh = pmesh
			pmi.material_override = building_material
			pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pmi.position = pos
			pmi.visible = false
			pmi.visibility_range_end = float(CITY_RANGE.plate)
			pmi.visibility_range_end_margin = float(CITY_RANGE.plate) * 0.15
			pmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(pmi)
			ch.extras.append(pmi)
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
	var roads: Array = job.get("roads", [])
	var species := {"broad": PackedFloat32Array(), "spruce": PackedFloat32Array(), "birch": PackedFloat32Array(),
		"pine": PackedFloat32Array(), "palm": PackedFloat32Array()}
	if density > 0.01:
		var spacing := 12.5 / sqrt(density)
		var cells := int(size / spacing)
		for cj in cells:
			for ci in cells:
				var lx := (ci + r.randf()) * spacing
				var lz := (cj + r.randf()) * spacing
				var fx := lx / s
				var fz := lz / s
				var f := _grid_sample(forest_grid, n, fx, fz)
				var p := f * f * 0.95 + 0.008
				var urb := _grid_sample(urban_grid, n, fx, fz)
				if urb > 0.25:
					p = 0.035 * (1.0 - urb) if urb < 0.3 or job.buildings <= 0.01 else 0.0   # city lots plant their own
				if r.randf() > p:
					continue
				var h := _height_sample(hs, w, fx, fz)
				if h < 1.5 or h > 2150.0:
					continue
				if Geo.water_level(x0 + lx, z0 + lz) > h - 0.6:
					continue
				var hx := _height_sample(hs, w, minf(fx + 0.5, n - 0.01), fz) - h
				var hz := _height_sample(hs, w, fx, minf(fz + 0.5, n - 0.01)) - h
				if absf(hx) + absf(hz) > s * 0.45:
					continue
				if not roads.is_empty() and Geo.highway_distance(x0 + lx, z0 + lz, roads) < 26.0:
					continue
				var sc := r.randf_range(0.7, 1.45)
				var rot := r.randf() * TAU
				# species by altitude and patch: spruce and pine up high, birch groves, palms on warm low coasts
				var patch := sin((x0 + lx) * 0.0031 + cos((z0 + lz) * 0.0027) * 2.0)
				var kind := "broad"
				var roll := r.randf()
				if h > 650.0:
					kind = "spruce" if roll < 0.7 else "pine"
				elif h < 12.0 and patch > 0.55 and roll < 0.5 and urb < 0.5:
					kind = "palm"
				elif patch < -0.35:
					kind = "spruce" if roll < 0.55 else ("pine" if roll < 0.8 else "broad")
				elif roll < 0.14:
					kind = "birch"
				elif roll < 0.24:
					kind = "spruce"
				var tint := Color(r.randf_range(0.8, 1.2), r.randf_range(0.85, 1.2), r.randf_range(0.75, 1.1))
				if kind in ["spruce", "pine"]:
					tint = Color(0.9, 1.0, 0.95) * r.randf_range(0.8, 1.15)
				elif kind == "broad" and r.randf() < 0.08:
					tint = Color(1.5, 1.05, 0.6)     # the odd copper beech / early autumn crown
				var arr: PackedFloat32Array = species[kind]
				_push_instance(arr, Vector3(lx - size * 0.5, h, lz - size * 0.5), rot, Vector3(sc, sc * r.randf_range(0.9, 1.25), sc), tint, r.randf())
				species[kind] = arr
	# city blocks in the nearest city's street pattern (they also plant park and garden trees)
	_build_city(result, job, hs, w, n, s, urban_grid, x0, z0, roads, species)
	var meshes := {"broad": _tree_mesh, "spruce": _conifer_mesh, "birch": _birch_mesh, "pine": _pine_mesh, "palm": _palm_mesh}
	for k in species:
		var buf: PackedFloat32Array = species[k]
		if buf.size() > 0:
			result.multimeshes.append({"kind": "tree", "mesh": meshes[k], "count": buf.size() / 16, "buffer": buf, "range": 3000.0 + 1800.0 * density})


# ------------------------------------------------------------------ cities (worker thread, pure data)
static func _build_city(result: Dictionary, job: Dictionary, hs: PackedFloat32Array, w: int, n: int, s: float,
		urban_grid: PackedFloat32Array, x0: float, z0: float, roads: Array, species: Dictionary) -> void:
	## Lays the nearest city's streets out in its own pattern (grid, radial, canal rings, warped
	## old town, strip) and fills each block with that city's kind of buildings. Each block gets
	## a ground plate carrying half the street, the pavement and the lot (or park, plaza, canal).
	var bdens: float = job.buildings
	if bdens <= 0.01 or _city_meshes.is_empty():
		return
	var size: float = job.size
	var city := Geo.nearest_city(float(job.cx), float(job.cz))
	if city.is_empty():
		return
	var st := CityStyles.style_for(city)
	var lots := _city_lots(st, x0, z0, size)
	if lots.is_empty():
		return
	var bufs := {}
	var pmb := MeshBuilder.new()      # ground plates merged into one plain mesh per chunk
	pmb.use_uv2 = true
	var tree_kind := String(st.tree)
	if not species.has(tree_kind):
		tree_kind = "broad"
	var trees: PackedFloat32Array = species[tree_kind]
	var max_slope: float = st.slope
	var strip := String(st.pattern) == "strip"
	var sa := deg_to_rad(float(st.rot))
	var sax := Vector2(cos(sa), sin(sa))
	for lot in lots:
		var wx: float = lot[0]
		var wz: float = lot[1]
		var a: float = lot[2]
		var cw: float = lot[3]
		var cd: float = lot[4]
		var tag: String = lot[5]
		var lx := wx - x0
		var lz := wz - z0
		var u := _grid_sample(urban_grid, n, clampf(lx / s, 0.0, n - 0.001), clampf(lz / s, 0.0, n - 0.001))
		if u < 0.3:
			continue
		var rb := RandomNumberGenerator.new()
		rb.seed = U.hash_ints(int(floor(wx)), int(floor(wz)), 17)
		# the quality setting thins the outskirts; dense districts stay continuous
		var plate_only := rb.randf() > bdens * (0.6 + u * 0.4) + (0.45 if u > 0.6 else 0.0)
		if plate_only and u < 0.6:
			continue
		var ex := Vector2(cos(a), sin(a))
		var ez := Vector2(-sin(a), cos(a))
		var hmin := INF
		var hmax := -INF
		var ok := true
		for k in 4:
			var cp := Vector2(wx, wz) + ex * (cw * (0.5 if k % 2 == 0 else -0.5)) + ez * (cd * (0.5 if k < 2 else -0.5))
			var fx := clampf((cp.x - x0) / s, -0.99, n + 0.99)
			var fz := clampf((cp.y - z0) / s, -0.99, n + 0.99)
			var hh := _height_sample(hs, w, fx, fz)
			hmin = minf(hmin, hh)
			hmax = maxf(hmax, hh)
			if _grid_sample(urban_grid, n, clampf(fx, 0.0, n - 0.001), clampf(fz, 0.0, n - 0.001)) < 0.1:
				ok = false
				break
			if tag != "water" and Geo.water_level(cp.x, cp.y) > hh - 0.6:
				ok = false
				break
		var hc := _height_sample(hs, w, lx / s, lz / s)
		if hc < 1.0 or Geo.water_level(wx, wz) > hc - 0.6:
			continue
		if not ok:
			# waterfront: a tree-lined promenade on the dry half of the block
			if tag == "water" or u < 0.45:
				continue
			cw *= 0.5
			cd *= 0.5
			ok = true
			hmin = hc
			hmax = hc
			for k in 4:
				var cp2 := Vector2(wx, wz) + ex * (cw * (0.5 if k % 2 == 0 else -0.5)) + ez * (cd * (0.5 if k < 2 else -0.5))
				var hh2 := _height_sample(hs, w, clampf((cp2.x - x0) / s, -0.99, n + 0.99), clampf((cp2.y - z0) / s, -0.99, n + 0.99))
				hmin = minf(hmin, hh2)
				hmax = maxf(hmax, hh2)
				if Geo.water_level(cp2.x, cp2.y) > hh2 - 0.6:
					ok = false
					break
			if not ok:
				continue
			tag = "boulevard"
		if hmax - hmin > max_slope:
			continue
		if not roads.is_empty() and Geo.highway_distance(wx, wz, roads) < 30.0 + maxf(cw, cd) * 0.55:
			continue
		var top := lerpf(hc, hmax, 0.6) + 0.25
		var base := hmin - 1.5
		var P := Vector3(lx - size * 0.5, top, lz - size * 0.5)
		# zone: core / mid / edge
		var dn := Vector2(wx - float(st.cx), wz - float(st.cz)).length() / float(st.r)
		var zone := "edge"
		if dn < float(st.core_frac) and u > 0.72:
			zone = "core"
		elif u > 0.58:
			zone = "mid"
		if strip:
			var rel := Vector2(wx - float(st.cx), wz - float(st.cz))
			var off_axis := absf(rel.dot(Vector2(-sax.y, sax.x)))
			if off_axis < 380.0 and absf(rel.dot(sax)) < float(st.r) * 0.85 and u > 0.5:
				zone = "core"
			elif zone == "core":
				zone = "mid"
		var fill := tag
		if fill == "":
			fill = CityStyles.pick_fill(st, zone, rb.randf())
			if rb.randf() < float(st.park_p) and zone != "core":
				fill = "park"
		if plate_only and not fill in ["park", "plaza", "water", "boulevard"]:
			fill = "plaza" if zone == "core" else "lot"
		# ground plate: half the street on each side, then pavement, then the lot
		var ptype := 0
		var lot_col: Color = st.lot
		match fill:
			"park":
				ptype = 1
				lot_col = Color(0.3, 0.42, 0.2)
			"plaza":
				ptype = 2
				lot_col = Color(0.74, 0.7, 0.64)
			"water":
				ptype = 3
				lot_col = Color(0.1, 0.16, 0.17)
			"boulevard":
				ptype = 4
				lot_col = Color(0.62, 0.58, 0.5)
			"houses", "villas", "terrace", "canal":
				lot_col = st.garden
		_plate(pmb, P, a, cw, cd, base, lot_col, ptype)
		var street := clampf(minf(cw, cd) * 0.06, 3.5, 8.0) + 3.0
		var bw := cw - street * 2.0
		var bd := cd - street * 2.0
		if bw < 12.0 or bd < 12.0:
			continue
		_fill_lot(bufs, trees, st, fill, zone, P, a, bw, bd, rb, u)
	species[tree_kind] = trees
	if pmb.vcount() > 0:
		result["plates"] = pmb.arrays()
	for mesh_name in bufs:
		var buf: PackedFloat32Array = bufs[mesh_name]
		if buf.is_empty():
			continue
		result.multimeshes.append({"kind": "plate" if mesh_name == "plate" else "building", "mesh": _city_meshes[mesh_name],
			"count": buf.size() / 16, "buffer": buf, "range": float(CITY_RANGE.get(mesh_name, 7500.0)) * clampf(bdens + 0.3, 0.6, 1.0)})


static func _city_lots(st: Dictionary, x0: float, z0: float, size: float) -> Array:
	## Block centres in the city's street pattern whose centre falls inside this chunk:
	## [world x, world z, frame angle (rad), cell width along the frame x, cell depth, tag].
	var lots := []
	var o := Vector2(float(st.cx), float(st.cz))
	var pattern := String(st.pattern)
	var r_in := 0.0
	if pattern == "radial" or pattern == "canal":
		r_in = float(st.inner) * float(st.r)
		_radial_lots(lots, st, o, r_in, x0, z0, size)
	var a := deg_to_rad(float(st.rot))
	var cw: float = st.bx
	var cd: float = st.bz
	var warp: float = st.warp
	if pattern == "hillside":
		warp = maxf(warp, 1.0)
	var amp := 70.0 * warp
	var lam := 480.0
	var ex := Vector2(cos(a), sin(a))
	var ez := Vector2(-sin(a), cos(a))
	var mnu := INF
	var mxu := -INF
	var mnv := INF
	var mxv := -INF
	for k in 4:
		var q := Vector2(x0 + (size if k % 2 == 1 else 0.0), z0 + (size if k >= 2 else 0.0)) - o
		mnu = minf(mnu, q.dot(ex))
		mxu = maxf(mxu, q.dot(ex))
		mnv = minf(mnv, q.dot(ez))
		mxv = maxf(mxv, q.dot(ez))
	var i0 := floori((mnu - amp) / cw) - 1
	var i1 := floori((mxu + amp) / cw) + 1
	var j0 := floori((mnv - amp) / cd) - 1
	var j1 := floori((mxv + amp) / cd) + 1
	var ph := float(U.hash_ints(int(o.x), int(o.y), 5) % 1000) * 0.0063
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var uu := (i + 0.5) * cw
			var vv := (j + 0.5) * cd
			var ang := a
			var cwi := cw
			var cdi := cd
			if warp > 0.0:
				var su := uu + amp * sin(vv / lam + ph)
				var sv := vv + amp * sin(uu / lam + ph * 1.7)
				ang += 0.5 * amp / lam * (cos(uu / lam + ph * 1.7) - cos(vv / lam + ph))
				ang += (float(U.hash_ints(i, j, 23) % 1000) * 0.001 - 0.5) * 0.08 * warp
				uu = su
				vv = sv
				cwi *= 0.97
				cdi *= 0.97
			var p := o + ex * uu + ez * vv
			if p.x < x0 or p.x >= x0 + size or p.y < z0 or p.y >= z0 + size:
				continue
			if r_in > 0.0 and p.distance_to(o) < r_in + maxf(cw, cd) * 0.5 + 10.0:
				continue
			lots.append([p.x, p.y, ang, cwi, cdi, ""])
	return lots


static func _radial_lots(lots: Array, st: Dictionary, o: Vector2, r_in: float, x0: float, z0: float, size: float) -> void:
	## Rings of blocks round the centre with radial avenues (Paris, Moscow, Vienna) or canal rings
	## lined with tree-planted quays (Amsterdam).
	var ring_w: float = st.ring_w
	var arc: float = st.arc
	var canal := String(st.pattern) == "canal"
	var avenues := int(st.avenues)
	var cc := Vector2(clampf(o.x, x0, x0 + size), clampf(o.y, z0, z0 + size))
	var dmin := cc.distance_to(o)
	var dmax := 0.0
	var corners := []
	for k in 4:
		var q := Vector2(x0 + (size if k % 2 == 1 else 0.0), z0 + (size if k >= 2 else 0.0))
		corners.append(q)
		dmax = maxf(dmax, q.distance_to(o))
	if dmin > r_in:
		return
	var full := dmin < 1.0
	var th_c := (Vector2(x0 + size * 0.5, z0 + size * 0.5) - o).angle()
	var dlo := 0.0
	var dhi := 0.0
	if not full:
		for q in corners:
			var d := wrapf((q - o).angle() - th_c, -PI, PI)
			dlo = minf(dlo, d)
			dhi = maxf(dhi, d)
	var k0 := maxi(floori(dmin / ring_w) - 1, 0)
	var k1 := floori(minf(dmax, r_in) / ring_w)
	for k in range(k0, k1 + 1):
		var rk := (k + 0.5) * ring_w
		if rk + ring_w * 0.5 > r_in:
			break
		var nk := maxi(6, int(TAU * rk / arc))
		var dth := TAU / nk
		var off := float(U.hash_ints(k, 77) % 1000) * 0.001 * dth
		var s0 := 0
		var s1 := nk - 1
		if not full:
			var margin := dth + atan2(ring_w, maxf(rk, 1.0))
			s0 = floori((th_c + dlo - margin - off) / dth)
			s1 = floori((th_c + dhi + margin - off) / dth)
			if s1 - s0 >= nk:
				s0 = 0
				s1 = nk - 1
		var water_ring := canal and k >= 2 and k % 3 == 1
		var boulevard_ring := not canal and k >= 3 and k % 7 == 4
		for sidx in range(s0, s1 + 1):
			var th := off + (sidx + 0.5) * dth
			var dir := Vector2(cos(th), sin(th))
			var p := o + dir * rk
			if p.x < x0 or p.x >= x0 + size or p.y < z0 or p.y >= z0 + size:
				continue
			var cw := rk * dth * 1.06
			var a := th + PI * 0.5
			var tag := ""
			if k == 0:
				tag = "plaza"
			elif boulevard_ring:
				tag = "boulevard"
			elif avenues > 0 and k >= 2:
				for m in avenues:
					var am := float(m) * TAU / avenues + 0.2
					if absf(wrapf(th - am, -PI, PI)) * rk < cw * 0.5 + 4.0:
						tag = "boulevard"
						break
			if water_ring:
				var quay := (ring_w - 30.0) * 0.5
				lots.append([p.x, p.y, a, cw, 30.0, "water"])
				var pin := o + dir * (rk - 15.0 - quay * 0.5)
				var pout := o + dir * (rk + 15.0 + quay * 0.5)
				lots.append([pin.x, pin.y, a, cw, quay, "boulevard"])
				lots.append([pout.x, pout.y, a, cw, quay, "boulevard"])
				continue
			lots.append([p.x, p.y, a, cw, ring_w, tag])


static func _plate(pmb: MeshBuilder, P: Vector3, a: float, cw: float, cd: float, base: float, col: Color, ptype: int) -> void:
	## One ground plate: flat top at P.y with low walls down to base. UV = metres from the plate
	## centre, UV2 = plate size (marks merged plates for the building shader), colour a = type.
	var ex := Vector3(cos(a), 0.0, sin(a))
	var ez := Vector3(-sin(a), 0.0, cos(a))
	var hx := cw * 0.5
	var hz := cd * 0.5
	var c := Color(col.r, col.g, col.b, (float(ptype) + 0.5) / 8.0)
	var size := Vector2(cw, cd)
	var loc := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	var top := []
	var bot := []
	for l in loc:
		var q: Vector2 = l
		var w := Vector3(P.x, 0.0, P.z) + ex * q.x + ez * q.y
		top.append(Vector3(w.x, P.y, w.z))
		bot.append(Vector3(w.x, base, w.z))
	_pquad(pmb, top[0], top[1], top[2], top[3], Vector3.UP, c, loc[0], loc[1], loc[2], loc[3], size)
	for k in 4:
		var k2 := (k + 1) % 4
		var mid: Vector2 = (loc[k] + loc[k2]) * 0.5
		var out := ex * mid.x + ez * mid.y
		_pquad(pmb, bot[k], bot[k2], top[k2], top[k], out, c, loc[k], loc[k2], loc[k2], loc[k], size)


static func _pquad(pmb: MeshBuilder, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, outward: Vector3, c: Color,
		u0: Vector2, u1: Vector2, u2: Vector2, u3: Vector2, size: Vector2) -> void:
	var n := (p1 - p0).cross(p3 - p0).normalized()
	var flip := n.dot(outward) < 0.0
	if flip:
		n = -n
	var i0 := pmb.add_vertex(p0, n, c, u0, size)
	var i1 := pmb.add_vertex(p1, n, c, u1, size)
	var i2 := pmb.add_vertex(p2, n, c, u2, size)
	var i3 := pmb.add_vertex(p3, n, c, u3, size)
	if flip:
		pmb.add_tri_idx(i0, i1, i2)
		pmb.add_tri_idx(i0, i2, i3)
	else:
		pmb.add_tri_idx(i0, i2, i1)
		pmb.add_tri_idx(i0, i3, i2)


static func _city_put(bufs: Dictionary, mesh: String, P: Vector3, a: float, ox: float, oz: float, sc: Vector3,
		col: Color, roof: int, sd: float, yaw: float = 0.0) -> void:
	## One instance at block offset (ox, oz) in the block frame; custom.a packs the roof family
	## (or plate type) with a random seed: (family + seed) / 8.
	var p := Vector2(P.x, P.z) + Vector2(cos(a), sin(a)) * ox + Vector2(-sin(a), cos(a)) * oz
	if not bufs.has(mesh):
		bufs[mesh] = PackedFloat32Array()
	var arr: PackedFloat32Array = bufs[mesh]
	_push_instance(arr, Vector3(p.x, P.y, p.y), -a + yaw, sc, col, (float(roof) + 0.05 + 0.9 * sd) / 8.0)
	bufs[mesh] = arr


static func _city_tree(trees: PackedFloat32Array, P: Vector3, a: float, ox: float, oz: float, rb: RandomNumberGenerator) -> void:
	var p := Vector2(P.x, P.z) + Vector2(cos(a), sin(a)) * ox + Vector2(-sin(a), cos(a)) * oz
	var sc := rb.randf_range(0.8, 1.3)
	_push_instance(trees, Vector3(p.x, P.y - 0.3, p.y), rb.randf() * TAU, Vector3(sc, sc * rb.randf_range(0.9, 1.2), sc),
		Color(rb.randf_range(0.85, 1.15), rb.randf_range(0.9, 1.15), rb.randf_range(0.8, 1.05)), rb.randf())


static func _fill_lot(bufs: Dictionary, trees: PackedFloat32Array, st: Dictionary, fill: String, zone: String, P: Vector3,
		a: float, bw: float, bd: float, rb: RandomNumberGenerator, u: float) -> void:
	## Buildings for one block (bw x bd metres inside the pavements), by fill type.
	var along_x := bw >= bd
	var L := maxf(bw, bd)
	var D := minf(bw, bd)
	var yaw := 0.0 if along_x else PI * 0.5
	var hr: Array = st.h_core if zone == "core" else st.h_mid
	var hk := 1.0 if zone != "edge" else 0.75
	var facade: Array = st.facade
	var house_pal: Array = st.house
	var roofs: Array = st.roof
	var tall: float = st.tall
	var Pb := P - Vector3(0, 0.3, 0)
	match fill:
		"court_mansard", "court_pitched", "court_flat", "court":
			var mesh := String(st.court) if fill == "court" else fill
			var eave := rb.randf_range(float(hr[0]), float(hr[1])) * hk
			var hh := eave * (1.0 if mesh == "court_flat" else 1.3)
			var col: Color = U.pick(rb, facade)
			if L > D * 1.7:
				for sgn in [-1.0, 1.0]:
					var o: float = sgn * L * 0.25
					_city_put(bufs, mesh, Pb, a, o if along_x else 0.0, 0.0 if along_x else o,
						Vector3(L * 0.5 - 1.0 if along_x else D, hh * rb.randf_range(0.92, 1.06), D if along_x else L * 0.5 - 1.0), col, int(U.pick(rb, roofs)), rb.randf())
			else:
				_city_put(bufs, mesh, Pb, a, 0.0, 0.0, Vector3(bw, hh, bd), col, int(U.pick(rb, roofs)), rb.randf())
				if rb.randf() < 0.6 and D > 50.0:
					_city_tree(trees, P, a, rb.randf_range(-4.0, 4.0), rb.randf_range(-4.0, 4.0), rb)
		"terrace", "canal":
			var canal := fill == "canal"
			var td := minf(15.0 if canal else 11.0, D * 0.42)
			var seg_target := 40.0 if canal else 66.0
			var nseg := maxi(1, int(round(L / seg_target)))
			var seg := L / nseg
			var col0: Color = U.pick(rb, house_pal if not canal else facade)
			for side in [-1.0, 1.0]:
				var t: float = side * (D * 0.5 - td * 0.5)
				for i in nseg:
					var l := -L * 0.5 + (i + 0.5) * seg
					var col := col0 if rb.randf() < 0.5 else Color(U.pick(rb, house_pal if not canal else facade))
					var hh := rb.randf_range(15.0, 19.0) if canal else rb.randf_range(9.5, 12.0) + (3.0 if zone == "core" else 0.0)
					var y2: float = yaw + (0.0 if side > 0.0 else PI)
					_city_put(bufs, fill, Pb, a, l if along_x else t, t if along_x else l, Vector3(seg - (0.4 if canal else 1.6), hh, td), col, int(U.pick(rb, roofs)), rb.randf(), y2)
			if D - td * 2.0 > 10.0 and rb.randf() < float(st.tree_p):
				for k in 2:
					_city_tree(trees, P, a, rb.randf_range(-L * 0.4, L * 0.4) if along_x else rb.randf_range(-3.0, 3.0), rb.randf_range(-3.0, 3.0) if along_x else rb.randf_range(-L * 0.4, L * 0.4), rb)
		"houses":
			# rows of three detached houses (one instance each) facing the street, gardens behind
			var mesh := String(st.house_mesh) + "3"
			var hd := minf(rb.randf_range(10.0, 13.0), D * 0.4) / 0.82
			var trio_len := rb.randf_range(54.0, 66.0)
			var cnt := clampi(int(round(L / trio_len)), 1, 3)
			for side in [-1.0, 1.0]:
				for i in cnt:
					var l := -L * 0.5 + (i + 0.5) * L / cnt
					var t: float = side * (D * 0.5 - hd * 0.5 - rb.randf_range(2.5, 5.0))
					var hsz := Vector3(L / cnt - 3.0, rb.randf_range(7.0, 9.0) if mesh != "wood_house3" else rb.randf_range(7.5, 10.0), hd)
					var y2: float = yaw + (0.0 if side > 0.0 else PI)
					_city_put(bufs, mesh, Pb, a, l if along_x else t, t if along_x else l, hsz, U.pick(rb, house_pal), int(U.pick(rb, roofs)), rb.randf(), y2)
					if rb.randf() < float(st.tree_p):
						var tt: float = side * maxf(D * 0.5 - hd - 8.0, 2.0)
						var tl := l + rb.randf_range(-L * 0.3, L * 0.3) / cnt
						_city_tree(trees, P, a, tl if along_x else tt, tt if along_x else tl, rb)
		"villas":
			var plot := clampf(D * 0.5, 22.0, 36.0)
			var nx := clampi(int(L / plot), 1, 3)
			var nz := clampi(int(D / plot), 1, 2)
			for i in nx:
				for j in nz:
					var l := -L * 0.5 + (i + 0.5) * L / nx
					var t := -D * 0.5 + (j + 0.5) * D / nz
					var y2: float = yaw + (0.0 if j == nz - 1 else PI)
					_city_put(bufs, "villa", Pb, a, l if along_x else t, t if along_x else l, Vector3(L / nx - 2.0, rb.randf_range(7.5, 9.5), D / nz - 2.0), U.pick(rb, house_pal), 5, rb.randf(), y2)
					if rb.randf() < float(st.tree_p):
						_city_tree(trees, P, a, (l + L / nx * 0.32) if along_x else t, t if along_x else (l + L / nx * 0.32), rb)
		"boxes", "lot_boxes":
			var mesh := String(st.box)
			var cnt := 1 if zone == "core" and rb.randf() < 0.6 else rb.randi_range(1, 4)
			var col0: Color = U.pick(rb, facade)
			for k in cnt:
				var hh := rb.randf_range(float(hr[0]), float(hr[1])) * hk
				if zone == "core" and rb.randf() < 0.25 * minf(tall, 1.2):
					hh += rb.randf_range(15.0, 50.0) * tall
				var col := col0 if rb.randf() < 0.4 else Color(U.pick(rb, facade))
				if cnt == 1:
					_city_put(bufs, mesh, Pb, a, 0.0, 0.0, Vector3(bw, hh, bd), col, 5, rb.randf())
				elif cnt == 2:
					var o := (-0.25 if k == 0 else 0.25) * L
					_city_put(bufs, mesh, Pb, a, o if along_x else 0.0, 0.0 if along_x else o, Vector3(L * 0.5 - 4.0 if along_x else D, hh, D if along_x else L * 0.5 - 4.0), col, 5, rb.randf())
				else:
					var ox := (-0.25 if k % 2 == 0 else 0.25) * bw
					var oz := (-0.25 if k < 2 else 0.25) * bd
					_city_put(bufs, mesh, Pb, a, ox, oz, Vector3(bw * 0.5 - 4.0, hh, bd * 0.5 - 4.0), col, 5, rb.randf())
		"midrise":
			var cnt := 4 if D > 55.0 else 2
			for k in cnt:
				var hh := rb.randf_range(float(hr[0]), float(hr[1])) * hk * 1.2
				var col: Color = U.pick(rb, facade)
				if cnt == 2:
					var o := (-0.25 if k == 0 else 0.25) * L
					_city_put(bufs, "hip_block", Pb, a, o if along_x else 0.0, 0.0 if along_x else o, Vector3(L * 0.5 - 5.0 if along_x else D, hh, D if along_x else L * 0.5 - 5.0), col, int(U.pick(rb, roofs)), rb.randf())
				else:
					_city_put(bufs, "hip_block", Pb, a, (-0.25 if k % 2 == 0 else 0.25) * bw, (-0.25 if k < 2 else 0.25) * bd, Vector3(bw * 0.5 - 5.0, hh, bd * 0.5 - 5.0), col, int(U.pick(rb, roofs)), rb.randf())
		"slabs":
			var hh := rb.randf_range(float(hr[0]), float(hr[1])) * (1.0 if zone != "edge" else 0.8)
			var col: Color = U.pick(rb, facade)
			var depth := 13.0
			var rows := 2 if D > 44.0 else 1
			for k in rows:
				var t := 0.0 if rows == 1 else (-1.0 if k == 0 else 1.0) * (D * 0.5 - depth * 0.5 - 2.0)
				_city_put(bufs, "box_panel", Pb, a, 0.0 if along_x else t, t if along_x else 0.0, Vector3(L * 0.86, hh * rb.randf_range(0.85, 1.1), depth), col, 5, rb.randf(), yaw)
			if rows == 2:
				for k in 3:
					_city_tree(trees, P, a, rb.randf_range(-L * 0.4, L * 0.4) if along_x else rb.randf_range(-4.0, 4.0), rb.randf_range(-4.0, 4.0) if along_x else rb.randf_range(-L * 0.4, L * 0.4), rb)
		"tower":
			var tw := minf(D * 0.85, rb.randf_range(30.0, 48.0))
			var th := rb.randf_range(float(st.tower_h[0]), float(st.tower_h[1])) * (0.6 + 0.4 * minf(tall, 1.6)) * (0.75 + 0.35 * u)
			var o := 0.0
			if L > D * 1.6:
				o = -L * 0.25
				var hh := rb.randf_range(float(hr[0]), float(hr[1]))
				_city_put(bufs, String(st.box), Pb, a, L * 0.25 if along_x else 0.0, 0.0 if along_x else L * 0.25, Vector3(L * 0.5 - 4.0 if along_x else D, hh, D if along_x else L * 0.5 - 4.0), U.pick(rb, facade), 5, rb.randf())
			_city_put(bufs, "tower_glass", Pb, a, o if along_x else 0.0, 0.0 if along_x else o, Vector3(tw * rb.randf_range(0.9, 1.15), th, tw), U.pick(rb, st.glass), 5, rb.randf(), float(rb.randi() % 4) * PI * 0.5)
		"slim":
			var nl := 2 if L > 85.0 else 1
			var nd := 2 if D > 85.0 else 1
			var sz := minf(minf(L / nl, D / nd) - 6.0, rb.randf_range(30.0, 40.0))
			var col: Color = U.pick(rb, facade)
			for i in nl:
				for j in nd:
					var l := -L * 0.5 + (i + 0.5) * L / nl
					var t := -D * 0.5 + (j + 0.5) * D / nd
					var th := rb.randf_range(float(st.tower_h[0]), float(st.tower_h[1])) * rb.randf_range(0.5, 0.8) * (0.7 + 0.3 * minf(tall, 1.6))
					_city_put(bufs, "tower_res", Pb, a, l if along_x else t, t if along_x else l, Vector3(sz, th, sz), col, 5, rb.randf(), yaw)
		"sheds":
			var cnt := 1 if L < 80.0 else 2
			for k in cnt:
				var l := 0.0 if cnt == 1 else (-0.25 if k == 0 else 0.25) * L
				_city_put(bufs, "shed", Pb, a, l if along_x else 0.0, 0.0 if along_x else l, Vector3(L / cnt - 6.0 if along_x else D * 0.8, rb.randf_range(8.0, 12.0), D * 0.8 if along_x else L / cnt - 6.0),
					U.pick(rb, [Color(0.72, 0.74, 0.76), Color(0.6, 0.64, 0.66), Color(0.75, 0.7, 0.62), Color(0.55, 0.62, 0.7), Color(0.8, 0.8, 0.78)]), 5, rb.randf(), yaw)
		"shops":
			var td := minf(14.0, D * 0.42)
			var nseg := maxi(1, int(round(L / 60.0)))
			var seg := L / nseg
			for side in [-1.0, 1.0]:
				var t: float = side * (D * 0.5 - td * 0.5)
				for i in nseg:
					var l := -L * 0.5 + (i + 0.5) * seg
					var y2: float = yaw + (0.0 if side > 0.0 else PI)
					_city_put(bufs, "shop_row", Pb, a, l if along_x else t, t if along_x else l, Vector3(seg - 1.0, rb.randf_range(9.0, 16.0), td), U.pick(rb, facade), int(U.pick(rb, roofs)), rb.randf(), y2)
		"park":
			var nt := clampi(int(bw * bd / 650.0), 3, 14)
			for k in nt:
				_city_tree(trees, P, a, rb.randf_range(-bw, bw) * 0.45, rb.randf_range(-bd, bd) * 0.45, rb)
		"plaza":
			for k in 4:
				_city_tree(trees, P, a, (bw * 0.42) * (1.0 if k % 2 == 0 else -1.0), (bd * 0.42) * (1.0 if k < 2 else -1.0), rb)
		"boulevard":
			var nt := clampi(int(L / 14.0), 1, 10)
			for side in [-1.0, 1.0]:
				for k in nt:
					var l := -L * 0.5 + (k + 0.5) * L / nt
					var t: float = side * D * 0.3
					_city_tree(trees, P, a, l if along_x else t, t if along_x else l, rb)

static func _push_instance(arr: PackedFloat32Array, pos: Vector3, rot_y: float, scale: Vector3, custom: Color, extra: float) -> void:
	var cr := cos(rot_y)
	var sr := sin(rot_y)
	# row-major 3x4 transform: basis columns scaled
	arr.append_array([cr * scale.x, 0.0, sr * scale.z, pos.x,
		0.0, scale.y, 0.0, pos.y,
		-sr * scale.x, 0.0, cr * scale.z, pos.z,
		custom.r, custom.g, custom.b, extra])
