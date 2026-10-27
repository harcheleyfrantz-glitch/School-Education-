class_name Crowd
extends MultiMeshInstance3D
## A batch of people drawn with one MultiMesh. Callers write per-person state with set_person()
## and the whole buffer is uploaded once per frame in flush().

enum Outfit { CIVIL, SUIT, CABIN, FLIGHT, GROUND, FIRE, MEDIC, POLICE, OFFICIAL }
const FLAG_BAG := 1
const FLAG_PHONE := 2
const FLAG_ELDERLY := 4
const FLAG_SKIRT := 8
const FLAG_HAT := 16
const FLAG_SOOT := 32
const STRIDE := 20   # 12 transform + 4 colour + 4 custom

static var _material: ShaderMaterial

var capacity := 0
var buf := PackedFloat32Array()
var dirty := false


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/human.gdshader")
	return _material


func setup(cap: int, lod: int = 0, airline_code: String = "", shadows: bool = true) -> void:
	capacity = cap
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = HumanMesh.get_mesh(lod)
	mm.instance_count = cap
	mm.visible_instance_count = cap
	multimesh = mm
	material_override = Crowd.material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	buf.resize(cap * STRIDE)
	buf.fill(0.0)
	if airline_code != "":
		var uc := Crowd.uniform_colors(airline_code)
		set_instance_shader_parameter("uniform_color", uc[0])
		set_instance_shader_parameter("uniform_trim", uc[1])
	for i in cap:
		hide_person(i)
	flush()


## pose: HumanMesh.POSES value; phase 0..1 (fraction); rate cycles/s; seed 0..1; build 0 (masculine) .. 1 (feminine)
func set_person(i: int, xf: Transform3D, pose: int, phase: float, rate: float, top: Color, outfit: int,
		seed_v: float, flags: int, build: float) -> void:
	if i < 0 or i >= capacity:
		return
	var o := i * STRIDE
	var b := xf.basis
	buf[o + 0] = b.x.x
	buf[o + 1] = b.y.x
	buf[o + 2] = b.z.x
	buf[o + 3] = xf.origin.x
	buf[o + 4] = b.x.y
	buf[o + 5] = b.y.y
	buf[o + 6] = b.z.y
	buf[o + 7] = xf.origin.y
	buf[o + 8] = b.x.z
	buf[o + 9] = b.y.z
	buf[o + 10] = b.z.z
	buf[o + 11] = xf.origin.z
	buf[o + 12] = top.r
	buf[o + 13] = top.g
	buf[o + 14] = top.b
	buf[o + 15] = (float(outfit) + 0.01) / 16.0
	buf[o + 16] = float(pose) + clampf(phase - floorf(phase), 0.0, 0.999)
	buf[o + 17] = rate
	buf[o + 18] = seed_v
	buf[o + 19] = float(flags) + clampf(build, 0.0, 0.99)
	dirty = true


func set_transform_only(i: int, xf: Transform3D) -> void:
	var o := i * STRIDE
	var b := xf.basis
	buf[o + 0] = b.x.x
	buf[o + 1] = b.y.x
	buf[o + 2] = b.z.x
	buf[o + 3] = xf.origin.x
	buf[o + 4] = b.x.y
	buf[o + 5] = b.y.y
	buf[o + 6] = b.z.y
	buf[o + 7] = xf.origin.y
	buf[o + 8] = b.x.z
	buf[o + 9] = b.y.z
	buf[o + 10] = b.z.z
	buf[o + 11] = xf.origin.z
	dirty = true


func set_pose(i: int, pose: int, phase: float, rate: float) -> void:
	var o := i * STRIDE
	buf[o + 16] = float(pose) + clampf(phase - floorf(phase), 0.0, 0.999)
	buf[o + 17] = rate
	dirty = true


func set_flags(i: int, flags: int) -> void:
	var o := i * STRIDE
	buf[o + 19] = float(flags) + (buf[o + 19] - floorf(buf[o + 19]))
	dirty = true


func get_flags(i: int) -> int:
	return int(floorf(buf[i * STRIDE + 19]))


func hide_person(i: int) -> void:
	var o := i * STRIDE
	for k in 12:
		buf[o + k] = 0.0
	buf[o + 7] = -10000.0
	dirty = true


func flush() -> void:
	if dirty and multimesh:
		multimesh.buffer = buf
		dirty = false


## Appearance helpers -------------------------------------------------------------------------
static func uniform_colors(airline_code: String) -> Array:
	## [jacket, accent] for an airline's cabin crew uniform, derived from the livery.
	var lc := Airlines.livery_colors(airline_code)
	var jacket: Color = lc.get("tail", Color(0.1, 0.14, 0.3))
	var trim: Color = lc.get("stripe", Color(0.8, 0.1, 0.1))
	if jacket.get_luminance() > 0.6:
		jacket = trim
		trim = Color(0.95, 0.95, 0.95)
	jacket = jacket.darkened(0.15)
	return [jacket, trim]

static func appearance_for(p: Dictionary) -> Dictionary:
	## Stable clothing/appearance for a population member.
	var id := int(p.get("id", U.hash_str(String(p.get("name", "x")))))
	var r := U.rng(U.hash_ints(id, 4242))
	var gender := String(p.get("gender", "x"))
	var age := int(p.get("age", 35))
	var build := 0.8 if gender == "f" else (0.15 if gender == "m" else 0.45)
	build = clampf(build + r.randf_range(-0.1, 0.1), 0.0, 0.99)
	var flags := 0
	if age >= 65:
		flags |= FLAG_ELDERLY
	if gender == "f" and r.randf() < 0.35:
		flags |= FLAG_SKIRT
	var tops := [Color(0.85, 0.85, 0.82), Color(0.12, 0.13, 0.15), Color(0.62, 0.12, 0.12), Color(0.15, 0.3, 0.55),
		Color(0.25, 0.45, 0.3), Color(0.82, 0.62, 0.2), Color(0.45, 0.3, 0.5), Color(0.55, 0.55, 0.58), Color(0.9, 0.5, 0.45),
		Color(0.2, 0.55, 0.62), Color(0.35, 0.22, 0.15), Color(0.95, 0.93, 0.85)]
	var top: Color = tops[r.randi() % tops.size()]
	var outfit := Outfit.CIVIL
	var job := String(p.get("job", ""))
	if job in ["lawyer", "banker", "executive", "consultant", "sales manager", "accountant", "politician"] or (String(p.get("purpose", "")) == "business" and r.randf() < 0.6):
		outfit = Outfit.SUIT
		top = [Color(0.1, 0.11, 0.14), Color(0.2, 0.22, 0.26), Color(0.12, 0.14, 0.24)][r.randi() % 3]
	var scale := 1.0
	if age < 18:
		scale = clampf(0.45 + float(age) * 0.033, 0.5, 0.98)
	else:
		scale = (0.95 if gender == "f" else 1.02) + r.randf_range(-0.05, 0.06)
	return {"top": top, "outfit": outfit, "seed": r.randf(), "flags": flags, "build": build, "scale": scale}
