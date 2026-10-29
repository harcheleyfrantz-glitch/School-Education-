class_name NewsStage
extends Node3D
## A set a broadcast cuts to (studio, crash site, press room, memorial). Each lives in its own
## SubViewport with its own world; the player activates one at a time and poses it for the
## current segment and shot as a pure function of time, so videos can be scrubbed freely.

var program: Dictionary = {}
var player: Node = null
var cam: Camera3D
var attrs: CameraAttributesPractical
var people: Crowd
var heroes: Array = []
var hero_slots := {}
var env: Environment


func build(prog: Dictionary) -> void:
	program = prog


func is_ready() -> bool:
	return true


## seg: the segment being shown, shot: the current cut, lt: seconds since the segment started,
## st: seconds since the cut, delta: frame time (0 while paused).
func apply(seg: Dictionary, shot: Dictionary, lt: float, st: float, delta: float) -> void:
	pass


func enter(_seg: Dictionary) -> void:
	pass


func _make_camera() -> void:
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 400.0
	cam.fov = 40.0
	attrs = CameraAttributesPractical.new()
	attrs.auto_exposure_enabled = false
	cam.attributes = attrs
	add_child(cam)
	cam.current = true


## Shallow depth of field: focus on a subject at `dist` metres. Off unless DOF_SETS is set: the
## bokeh pass blurs the subject itself in sub-viewports (seen on lavapipe), so sets stay sharp.
func _dof(on: bool, dist: float = 3.0, amount: float = 0.06) -> void:
	on = on and OS.get_environment("DOF_SETS") == "1"
	attrs.dof_blur_far_enabled = on
	attrs.dof_blur_far_distance = dist + 1.2
	attrs.dof_blur_far_transition = maxf(dist * 0.9, 2.0)
	attrs.dof_blur_amount = amount
	attrs.dof_blur_near_enabled = false


func _look(from: Vector3, at: Vector3, fov: float) -> void:
	cam.global_position = from
	if from.distance_to(at) > 0.001:
		cam.look_at(at, Vector3.UP)
	cam.fov = fov


## Smooth 0..1 ramp.
static func ease01(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## Hand-held camera wobble (deterministic in time): small rotation offsets in degrees.
static func handheld(t: float, amount: float, seed_v: float = 0.0) -> Vector2:
	var x := sin(t * 1.7 + seed_v) * 0.6 + sin(t * 4.3 + seed_v * 2.0) * 0.25 + sin(t * 11.1 + seed_v * 3.0) * 0.08
	var y := sin(t * 1.3 + seed_v * 1.5) * 0.6 + sin(t * 3.7 + seed_v * 0.5) * 0.3 + sin(t * 9.7 + seed_v) * 0.08
	return Vector2(x, y) * amount


static func unshaded(col: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emission
	return m


static func vcolor_mat(rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	return m


static func mesh_node(mb: MeshBuilder, mat: Material, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func label3d(text: String, size_px: int, pixel: float, col: Color, font: Font = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size_px
	l.pixel_size = pixel
	l.modulate = col
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	if font:
		l.font = font
	return l


## A person of the crowd placed at a world-space position, facing a heading (radians, 0 = -Z).
func _person(i: int, pos: Vector3, yaw: float, pose: String, outfit: int, id: int, extra_flags: int = 0, top: Color = Color(-1, 0, 0), rate: float = 0.5, gender: String = "") -> void:
	var ap: Dictionary
	if outfit == Crowd.Outfit.CIVIL or outfit == Crowd.Outfit.SUIT:
		var p := WorldSim.person(id)
		if gender != "":
			p.gender = gender
		if outfit == Crowd.Outfit.SUIT or (id >= 30000 and id < 31000) or gender != "":
			p.age = 26 + absi(id) % 30
		ap = Crowd.appearance_for(p)
		if outfit == Crowd.Outfit.SUIT:
			ap.outfit = Crowd.Outfit.SUIT
			ap.top = [Color(0.09, 0.1, 0.13), Color(0.16, 0.18, 0.22), Color(0.1, 0.12, 0.22), Color(0.22, 0.2, 0.2)][absi(id) % 4]
			if String(p.gender) != "f":
				ap.flags = int(ap.flags) | Crowd.FLAG_TIE
	else:
		ap = Crowd.staff_appearance(outfit, id, gender)
	if top.r >= 0.0:
		ap.top = top
	var sc := float(ap.get("scale", 1.0))
	# the people who speak to camera (anchors, reporters, witnesses, the press-conference
	# speaker) are fully skinned characters; everyone else stays in the crowd batch
	if pose == "talk" or (pose == "sit" and gender != ""):
		var h := SkinnedHuman.new()
		people.get_parent().add_child(h)
		h.transform = people.transform * Transform3D(Basis(Vector3.UP, yaw), pos)
		h.setup(ap)
		h.play("talk" if pose == "talk" else "sit_talk", 0.0)
		h.anim.seek(float(U.hash_ints(id, 5) % 1000) / 1000.0 * 4.0, true)
		heroes.append(h)
		hero_slots[i] = h
		# the crowd slot keeps the position (cameras frame people by slot) but draws nothing
		people.set_person(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), pos), 0, 0.0, 0.0, ap.top, int(ap.outfit), float(ap.seed), int(ap.flags), float(ap.build))
		return
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), pos)
	people.set_person(i, xf, int(HumanMesh.POSES.get(pose, 0)), float(U.hash_ints(id, 5) % 1000) / 1000.0, rate, ap.top, int(ap.outfit),
		float(ap.seed), int(ap.flags) | extra_flags, float(ap.build))
