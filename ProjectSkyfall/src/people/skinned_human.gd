class_name SkinnedHuman
extends Node3D
## One fully skinned person for close-up roles: the player in third person, the character
## creation preview, news anchors and reporters, portraits. The high-resolution HumanMesh is
## bound to an 18-bone Skeleton3D with smooth weights across every joint (no rigid segments),
## dressed by the same human shader as the crowds, and animated by keyframed clips (idle,
## walk, run, sit, talk, wave...) that blend into each other. Facing -Z, feet at y = 0.

enum B { ROOT, HIPS, SPINE, CHEST, NECK, HEAD, UARM_L, FARM_L, HAND_L, UARM_R, FARM_R, HAND_R,
	THIGH_L, SHIN_L, FOOT_L, THIGH_R, SHIN_R, FOOT_R }
const BONES := [
	["root", -1, Vector3(0, 0, 0)], ["hips", 0, Vector3(0, 0.93, 0)], ["spine", 1, Vector3(0, 1.08, 0)],
	["chest", 2, Vector3(0, 1.26, 0)], ["neck", 3, Vector3(0, 1.50, 0)], ["head", 4, Vector3(0, 1.62, 0.004)],
	["upperarm_L", 3, Vector3(-0.192, 1.415, 0)], ["forearm_L", 6, Vector3(-0.205, 1.145, 0.01)], ["hand_L", 7, Vector3(-0.21, 0.895, -0.005)],
	["upperarm_R", 3, Vector3(0.192, 1.415, 0)], ["forearm_R", 9, Vector3(0.205, 1.145, 0.01)], ["hand_R", 10, Vector3(0.21, 0.895, -0.005)],
	["thigh_L", 1, Vector3(-0.092, 0.93, 0)], ["shin_L", 12, Vector3(-0.095, 0.50, -0.01)], ["foot_L", 13, Vector3(-0.095, 0.085, 0.01)],
	["thigh_R", 1, Vector3(0.092, 0.93, 0)], ["shin_R", 15, Vector3(0.095, 0.50, -0.01)], ["foot_R", 16, Vector3(0.095, 0.085, 0.01)],
]
## clip name -> [length s, loops, face pose id for the shader (mouth, blinking)]
const CLIPS := {
	"idle": [8.0, true, 0], "walk": [1.1, true, 1], "run": [0.72, true, 4], "sit": [8.0, true, 2],
	"talk": [4.0, true, 7], "sit_talk": [4.0, true, 15], "wave": [1.2, true, 11], "film": [4.0, true, 14],
	"grief": [6.0, true, 18], "point": [3.0, true, 0], "salute": [2.0, false, 0], "sit_read": [8.0, true, 16],
}
const WALK_SPEED := 1.35
const RUN_SPEED := 3.3

static var _mesh: ArrayMesh = null
static var _library: AnimationLibrary = null

var skeleton: Skeleton3D
var body: MeshInstance3D
var mat: ShaderMaterial
var anim: AnimationPlayer
var look := {}
var clip := ""
var head_yaw := 0.0          ## radians, added to the neck on top of the clip (look at something)
var head_pitch := 0.0
var _speed := 0.0


func _init() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for i in BONES.size():
		skeleton.add_bone(String(BONES[i][0]))
	for i in BONES.size():
		var parent: int = BONES[i][1]
		skeleton.set_bone_parent(i, parent)
		var p: Vector3 = BONES[i][2]
		var pp: Vector3 = BONES[parent][2] if parent >= 0 else Vector3.ZERO
		skeleton.set_bone_rest(i, Transform3D(Basis(), p - pp))
	skeleton.reset_bone_poses()
	body = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = SkinnedHuman.skinned_mesh()
	# own material: the skinned switch and appearance must be plain uniforms so every render
	# pass (depth prepass, shadows, colour) deforms the mesh identically
	mat = ShaderMaterial.new()
	mat.shader = Crowd.material().shader
	mat.set_shader_parameter("skinned", true)
	body.material_override = mat
	skeleton.add_child(body)
	body.skeleton = NodePath("..")
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	add_child(anim)
	anim.root_node = NodePath("..")
	anim.add_animation_library("", SkinnedHuman.library())
	var hl := HeadLook.new()
	hl.human = self
	skeleton.add_child(hl)
	setup({})
	play("idle", 0.0)


## look: top (Color), outfit (Crowd.Outfit), seed (hair style + fraction), flags (Crowd.FLAG_*),
## build 0..1, scale, skin 0..6 and hair_color 0..6 (pin the tones; -1 = from the seed),
## airline (uniform colours). Crowd.appearance_for / staff_appearance results work directly.
func setup(l: Dictionary) -> void:
	look = l
	var al := String(l.get("airline", ""))
	if al != "":
		var uc := Crowd.uniform_colors(al)
		body.set_instance_shader_parameter("uniform_color", uc[0])
		body.set_instance_shader_parameter("uniform_trim", uc[1])
	var skin := float(l.get("skin", -1))
	var hair := float(l.get("hair_color", -1))
	body.set_instance_shader_parameter("skin_override", (skin + 0.5) / 7.0 if skin >= 0.0 else -1.0)
	body.set_instance_shader_parameter("hair_override", (hair + 0.5) / 7.0 if hair >= 0.0 else -1.0)
	var top: Color = l.get("top", Color(0.85, 0.85, 0.82))
	mat.set_shader_parameter("s_color", Color(top.r, top.g, top.b, (float(l.get("outfit", 0)) + 0.01) / 16.0))
	var sc := float(l.get("scale", 1.0))
	skeleton.scale = Vector3.ONE * sc
	_apply_face(int(CLIPS.get(clip, [0, 0, 0])[2]))


## The player's own pilot, from the career profile, in the airline's uniform.
## As a passenger the same person wears their own clothes.
static func player_look(passenger: bool = false) -> Dictionary:
	var p: Dictionary = Game.player
	var a: Dictionary = p.get("appearance", {})
	var al := String(p.get("airline", "SKF"))
	if passenger:
		return {"top": Color(0.18, 0.32, 0.52), "outfit": Crowd.Outfit.CIVIL, "seed": float(int(a.get("hair", 1))) + 0.37,
			"flags": Crowd.FLAG_BACKPACK, "build": float(a.get("build", 0.8 if String(p.get("gender", "m")) == "f" else 0.2)),
			"skin": int(a.get("skin", 2)), "hair_color": int(a.get("hair_color", 1)), "scale": 0.97 if String(p.get("gender", "m")) == "f" else 1.0}
	return {"top": Color(0.95, 0.95, 0.97), "outfit": Crowd.Outfit.FLIGHT, "seed": float(int(a.get("hair", 1))) + 0.37,
		"flags": Crowd.FLAG_TIE, "build": float(a.get("build", 0.8 if String(p.get("gender", "m")) == "f" else 0.2)),
		"skin": int(a.get("skin", 2)), "hair_color": int(a.get("hair_color", 1)), "airline": al if al != "" else "SKF",
		"scale": 0.97 if String(p.get("gender", "m")) == "f" else 1.0}


func play(name: String, blend: float = 0.25) -> void:
	if not CLIPS.has(name) or name == clip:
		return
	clip = name
	anim.play(name, blend)
	_apply_face(int(CLIPS[name][2]))


## Drives idle / walk / run from a ground speed (m/s) with matching cadence.
func set_motion(speed: float, delta: float = 0.016) -> void:
	_speed = lerpf(_speed, speed, clampf(delta * 8.0, 0.0, 1.0))
	if _speed < 0.12:
		play("idle", 0.3)
		anim.speed_scale = 1.0
	elif _speed < 2.1:
		play("walk", 0.25)
		anim.speed_scale = clampf(_speed / WALK_SPEED, 0.45, 1.6)
	else:
		play("run", 0.2)
		anim.speed_scale = clampf(_speed / RUN_SPEED, 0.7, 1.4)


func _apply_face(pose_id: int) -> void:
	var seed_v := float(look.get("seed", 1.37))
	var flags := int(look.get("flags", 0))
	mat.set_shader_parameter("s_custom", Vector4(float(pose_id) + 0.25, 0.25, seed_v, float(flags) + clampf(float(look.get("build", 0.5)), 0.0, 0.99)))


## Turns the neck on top of whatever clip plays (looking at the camera, at a colleague...).
class HeadLook extends SkeletonModifier3D:
	var human: SkinnedHuman

	func _process_modification() -> void:
		if human == null or (absf(human.head_yaw) < 0.001 and absf(human.head_pitch) < 0.001):
			return
		var sk := get_skeleton()
		var q := sk.get_bone_pose_rotation(B.NECK)
		sk.set_bone_pose_rotation(B.NECK, Quaternion(Vector3.UP, clampf(human.head_yaw, -1.2, 1.2)) * q * Quaternion(Vector3.RIGHT, clampf(human.head_pitch, -0.6, 0.5)))


## World transform of a bone (for attaching props or aiming a camera at the face).
func bone_global(bone: int) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone)


# ================================================================== mesh and weights
static func skinned_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var src := HumanMesh.get_mesh(-1)
	var arr := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var n := verts.size()
	var bones := PackedInt32Array()
	bones.resize(n * 4)
	var weights := PackedFloat32Array()
	weights.resize(n * 4)
	var rest := PackedFloat32Array()
	rest.resize(n * 3)
	for i in n:
		var p := verts[i]
		rest[i * 3] = p.x
		rest[i * 3 + 1] = p.y
		rest[i * 3 + 2] = p.z
		var acc := {}
		for bw in _weights(int(uv2[i].x + 0.5), p):
			if float(bw[1]) > 0.0005:
				acc[int(bw[0])] = float(acc.get(int(bw[0]), 0.0)) + float(bw[1])
		var ks := acc.keys()
		ks.sort_custom(func(a, b): return float(acc[a]) > float(acc[b]))
		var total := 0.0
		for k in mini(4, ks.size()):
			total += float(acc[ks[k]])
		for k in 4:
			if k < ks.size():
				bones[i * 4 + k] = int(ks[k])
				weights[i * 4 + k] = float(acc[ks[k]]) / maxf(total, 0.0001)
			else:
				bones[i * 4 + k] = 0
				weights[i * 4 + k] = 0.0
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	arr[Mesh.ARRAY_CUSTOM0] = rest
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	_mesh.custom_aabb = AABB(Vector3(-1.2, -0.4, -1.4), Vector3(2.4, 2.6, 2.8))
	return _mesh


static func _ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x) if a < b else 1.0 - smoothstep(b, a, x)


static func _blend(base: Array, bone: int, w: float) -> Array:
	if w <= 0.0:
		return base
	var out := []
	for bw in base:
		out.append([bw[0], float(bw[1]) * (1.0 - w)])
	out.append([bone, w])
	return out


static func _spine(y: float) -> Array:
	if y < 0.98:
		return [[B.HIPS, 1.0]]
	if y < 1.12:
		var t := _ss(0.98, 1.12, y)
		return [[B.HIPS, 1.0 - t], [B.SPINE, t]]
	if y < 1.27:
		var t2 := _ss(1.12, 1.27, y)
		return [[B.SPINE, 1.0 - t2], [B.CHEST, t2]]
	return [[B.CHEST, 1.0]]


## Bone weights for a rest-pose vertex of HumanMesh part `part` (see HumanMesh.Part).
static func _weights(part: int, p: Vector3) -> Array:
	var y := p.y
	var left := p.x < 0.0
	match part:
		0, 18, 19:
			var out := _spine(y)
			if part == 0:
				out = _blend(out, B.UARM_L if left else B.UARM_R, 0.35 * _ss(0.12, 0.19, absf(p.x)) * _ss(1.28, 1.40, y))
				out = _blend(out, B.THIGH_L if left else B.THIGH_R, 0.5 * _ss(0.95, 0.84, y) * _ss(0.0, 0.07, absf(p.x)))
			return out
		1:
			if y > 1.6:
				return [[B.HEAD, 1.0]]
			var wh := _ss(1.50, 1.60, y)
			return _blend([[B.HEAD, wh], [B.NECK, 1.0 - wh]], B.CHEST, _ss(1.47, 1.40, y))
		2, 13, 14, 15, 16, 20, 21:
			return [[B.HEAD, 1.0]]
		3, 5:
			var ua := B.UARM_L if part == 3 else B.UARM_R
			var fa := B.FARM_L if part == 3 else B.FARM_R
			var wf := 0.5 * _ss(1.21, 1.145, y)
			return _blend([[ua, 1.0 - wf], [fa, wf]], B.CHEST, 0.3 * _ss(1.36, 1.44, y))
		4, 6:
			var ua2 := B.UARM_L if part == 4 else B.UARM_R
			var fa2 := B.FARM_L if part == 4 else B.FARM_R
			var hd := B.HAND_L if part == 4 else B.HAND_R
			var wu := 0.5 * _ss(1.10, 1.165, y)
			var whd := _ss(0.93, 0.885, y)
			return [[fa2, (1.0 - wu) * (1.0 - whd)], [ua2, wu * (1.0 - whd)], [hd, whd]]
		12:
			return [[B.HAND_R, 1.0]]
		7, 9:
			var th := B.THIGH_L if part == 7 else B.THIGH_R
			var sh := B.SHIN_L if part == 7 else B.SHIN_R
			var ws := 0.5 * _ss(0.58, 0.49, y)
			var wp := 0.45 * _ss(0.84, 0.97, y)
			return [[th, 1.0 - ws - wp], [sh, ws], [B.HIPS, wp]]
		8, 10:
			var th2 := B.THIGH_L if part == 8 else B.THIGH_R
			var sh2 := B.SHIN_L if part == 8 else B.SHIN_R
			var ft := B.FOOT_L if part == 8 else B.FOOT_R
			var wt := 0.5 * _ss(0.45, 0.52, y)
			var wfo := _ss(0.14, 0.09, y)
			return [[sh2, (1.0 - wt) * (1.0 - wfo)], [th2, wt * (1.0 - wfo)], [ft, wfo]]
		17:
			var wsk := _ss(0.98, 0.62, y) * (1.0 if p.z < 0.0 else 0.35) * 0.9
			return [[B.HIPS, 1.0 - wsk], [B.THIGH_L if left else B.THIGH_R, wsk]]
		11:
			return [[B.ROOT, 1.0]]
	return [[B.HIPS, 1.0]]


# ================================================================== animation clips
static func library() -> AnimationLibrary:
	if _library != null:
		return _library
	_library = AnimationLibrary.new()
	for name in CLIPS:
		var spec: Array = CLIPS[name]
		var length: float = spec[0]
		var a := Animation.new()
		a.length = length
		a.loop_mode = Animation.LOOP_LINEAR if bool(spec[1]) else Animation.LOOP_NONE
		var keys := 24 if length > 2.0 else 16
		var rot_tracks := {}
		for b in [B.HIPS, B.SPINE, B.CHEST, B.NECK, B.UARM_L, B.FARM_L, B.HAND_L, B.UARM_R, B.FARM_R, B.HAND_R,
				B.THIGH_L, B.SHIN_L, B.FOOT_L, B.THIGH_R, B.SHIN_R, B.FOOT_R]:
			var ti := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(ti, NodePath("Skeleton3D:" + String(BONES[b][0])))
			a.track_set_interpolation_type(ti, Animation.INTERPOLATION_CUBIC)
			rot_tracks[b] = ti
		var pos_track := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(pos_track, NodePath("Skeleton3D:hips"))
		a.track_set_interpolation_type(pos_track, Animation.INTERPOLATION_CUBIC)
		var hips_rest: Vector3 = BONES[B.HIPS][2]
		for k in keys + (1 if not bool(spec[1]) else 0):
			var t := length * float(k) / float(keys)
			var pose := _pose(String(name), t, length)
			for b in rot_tracks:
				var e: Vector3 = pose.get(b, Vector3.ZERO)
				var q := (Basis(Vector3.UP, e.y) * Basis(Vector3.BACK, e.z) * Basis(Vector3.RIGHT, e.x)).get_rotation_quaternion()
				a.rotation_track_insert_key(rot_tracks[b], t, q)
			a.position_track_insert_key(pos_track, t, hips_rest + (pose.get("hips_off", Vector3.ZERO) as Vector3))
		_library.add_animation(name, a)
	return _library


## Joint angles (x swing, y twist, z abduction - same convention as the crowd shader) for clip
## `name` at time t, plus "hips_off" (hip position offset).
static func _pose(name: String, t: float, length: float) -> Dictionary:
	var ph := TAU * t / length
	var o := {}
	# relaxed defaults: arms a little away from the body, soft elbows
	o[B.UARM_L] = Vector3(0.0, 0.0, -0.08)
	o[B.UARM_R] = Vector3(0.0, 0.0, 0.08)
	o[B.FARM_L] = Vector3(0.12, 0.0, 0.0)
	o[B.FARM_R] = Vector3(0.12, 0.0, 0.0)
	o[B.THIGH_L] = Vector3(0.0, 0.0, -0.03)
	o[B.THIGH_R] = Vector3(0.0, 0.0, 0.03)
	o["hips_off"] = Vector3.ZERO
	match name:
		"idle":
			o[B.CHEST] = Vector3(0.014 * sin(ph * 2.0), 0.0, 0.0)
			o[B.SPINE] = Vector3(0.0, 0.035 * sin(ph), 0.008 * sin(ph))
			o[B.NECK] = Vector3(0.035 * sin(ph * 2.0 + 0.6), 0.22 * sin(ph + 0.4), 0.0)
			o[B.UARM_L] = Vector3(0.02 * sin(ph * 2.0), 0.0, -0.09)
			o[B.UARM_R] = Vector3(0.02 * sin(ph * 2.0 + 1.0), 0.0, 0.09)
			o[B.HIPS] = Vector3(0.0, 0.0, 0.015 * sin(ph))
			o[B.THIGH_L] = Vector3(0.0, 0.0, -0.03 - 0.015 * sin(ph))
			o[B.THIGH_R] = Vector3(0.0, 0.0, 0.03 - 0.015 * sin(ph))
			o["hips_off"] = Vector3(0.006 * sin(ph), 0.0, 0.0)
		"walk", "run":
			var run := name == "run"
			var sw := sin(ph)
			var amp := 0.72 if run else 0.42
			var kb := 1.5 if run else 0.85
			var kl := -(0.06 + kb * maxf(0.0, cos(ph - 0.3)))
			var kr := -(0.06 + kb * maxf(0.0, cos(ph - 0.3 + PI)))
			o[B.THIGH_L] = Vector3(amp * sw, 0.0, -0.03)
			o[B.THIGH_R] = Vector3(-amp * sw, 0.0, 0.03)
			o[B.SHIN_L] = Vector3(kl, 0.0, 0.0)
			o[B.SHIN_R] = Vector3(kr, 0.0, 0.0)
			# feet stay roughly level with the ground, toe-off after push
			o[B.FOOT_L] = Vector3(-(amp * sw + kl) * 0.75 + 0.18 * maxf(0.0, -cos(ph + 0.6)), 0.0, 0.0)
			o[B.FOOT_R] = Vector3(-(-amp * sw + kr) * 0.75 + 0.18 * maxf(0.0, cos(ph + 0.6)), 0.0, 0.0)
			var aamp := 0.7 if run else 0.34
			o[B.UARM_L] = Vector3(-aamp * sw, 0.0, -0.1)
			o[B.UARM_R] = Vector3(aamp * sw, 0.0, 0.1)
			o[B.FARM_L] = Vector3(1.3 if run else 0.28 + 0.14 * maxf(0.0, -sw), 0.0, 0.0)
			o[B.FARM_R] = Vector3(1.3 if run else 0.28 + 0.14 * maxf(0.0, sw), 0.0, 0.0)
			o[B.HIPS] = Vector3(0.0, -0.07 * sw, 0.03 * cos(ph))
			o[B.SPINE] = Vector3(-0.12 if run else -0.03, 0.05 * sw, -0.02 * cos(ph))
			o[B.CHEST] = Vector3(-0.08 if run else -0.01, 0.06 * sw, 0.0)
			o[B.NECK] = Vector3(0.1 if run else 0.03, -0.1 * sw, 0.0)
			o["hips_off"] = Vector3(0.012 * cos(ph), -(0.05 if run else 0.024) * absf(sw) + (0.03 if run else 0.008), 0.0)
		"sit", "sit_talk", "sit_read":
			o[B.THIGH_L] = Vector3(1.45, 0.0, -0.06)
			o[B.THIGH_R] = Vector3(1.45, 0.0, 0.06)
			o[B.SHIN_L] = Vector3(-1.32, 0.0, 0.0)
			o[B.SHIN_R] = Vector3(-1.38, 0.0, 0.0)
			o[B.FOOT_L] = Vector3(-0.1, 0.0, 0.0)
			o[B.FOOT_R] = Vector3(-0.07, 0.0, 0.0)
			o[B.SPINE] = Vector3(0.06, 0.0, 0.0)
			o[B.CHEST] = Vector3(0.04 + 0.01 * sin(ph * 2.0), 0.0, 0.0)
			o[B.UARM_L] = Vector3(0.38, 0.0, -0.1)
			o[B.UARM_R] = Vector3(0.38, 0.0, 0.1)
			o[B.FARM_L] = Vector3(1.05, 0.0, 0.0)
			o[B.FARM_R] = Vector3(1.05, 0.0, 0.0)
			o[B.NECK] = Vector3(-0.05 + 0.04 * sin(ph), 0.25 * sin(ph + 1.0), 0.0)
			o["hips_off"] = Vector3(0.0, -0.43, 0.04)
			if name == "sit_talk":
				o[B.FARM_R] = Vector3(1.1 + 0.35 * sin(ph * 3.0), 0.0, 0.0)
				o[B.UARM_R] = Vector3(0.5 + 0.18 * sin(ph * 2.0), 0.0, 0.12)
				o[B.NECK] = Vector3(0.05 * sin(ph * 4.0), 0.45 + 0.1 * sin(ph), 0.0)
			elif name == "sit_read":
				o[B.UARM_L] = Vector3(0.75, 0.0, 0.12)
				o[B.UARM_R] = Vector3(0.75, 0.0, -0.12)
				o[B.FARM_L] = Vector3(1.45, 0.0, 0.0)
				o[B.FARM_R] = Vector3(1.45, 0.0, 0.0)
				o[B.NECK] = Vector3(-0.38, 0.0, 0.0)
		"talk":
			o[B.FARM_L] = Vector3(1.15 + 0.35 * sin(ph * 3.0), 0.0, 0.0)
			o[B.FARM_R] = Vector3(1.0 + 0.4 * sin(ph * 2.0 + 1.0), 0.0, 0.0)
			o[B.UARM_L] = Vector3(0.3 + 0.15 * sin(ph * 2.0), 0.0, -0.15)
			o[B.UARM_R] = Vector3(0.35 + 0.2 * sin(ph + 2.0), 0.0, 0.15)
			o[B.HAND_L] = Vector3(0.0, 0.3 * sin(ph * 3.0), 0.0)
			o[B.HAND_R] = Vector3(0.0, -0.3 * sin(ph * 2.0), 0.0)
			o[B.NECK] = Vector3(0.08 * sin(ph * 4.0), 0.15 * sin(ph), 0.04 * sin(ph * 2.0))
			o[B.CHEST] = Vector3(0.015 * sin(ph * 2.0), 0.04 * sin(ph), 0.0)
		"wave":
			o[B.UARM_R] = Vector3(0.15, 0.0, 2.55 + 0.28 * sin(ph * 2.0))
			o[B.FARM_R] = Vector3(0.35, 0.0, 0.0)
			o[B.HAND_R] = Vector3(0.0, 0.0, 0.25 * sin(ph * 2.0))
			o[B.NECK] = Vector3(0.0, 0.2, 0.0)
		"film":
			o[B.UARM_R] = Vector3(1.35, 0.0, 0.12)
			o[B.FARM_R] = Vector3(0.85, 0.0, 0.0)
			o[B.NECK] = Vector3(-0.06, 0.05 * sin(ph), 0.0)
		"grief":
			o[B.NECK] = Vector3(-0.45, 0.0, 0.0)
			o[B.SPINE] = Vector3(-0.08 + 0.02 * sin(ph * 2.0), 0.0, 0.0)
			o[B.UARM_L] = Vector3(1.75, 0.0, 0.32)
			o[B.UARM_R] = Vector3(1.75, 0.0, -0.32)
			o[B.FARM_L] = Vector3(2.2, 0.0, 0.0)
			o[B.FARM_R] = Vector3(2.2, 0.0, 0.0)
		"point":
			o[B.UARM_R] = Vector3(1.45, 0.0, 0.25)
			o[B.FARM_R] = Vector3(0.08, 0.0, 0.0)
			o[B.NECK] = Vector3(0.0, -0.3, 0.0)
			o[B.CHEST] = Vector3(0.0, -0.12, 0.0)
		"salute":
			var up := clampf(t / 0.4, 0.0, 1.0) * clampf((length - t) / 0.4, 0.0, 1.0)
			o[B.UARM_R] = Vector3(0.9 * up, 0.0, 0.08 + 1.2 * up)
			o[B.FARM_R] = Vector3(0.12 + 2.25 * up, 0.0, 0.0)
	return o
