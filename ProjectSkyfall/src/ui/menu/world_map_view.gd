class_name WorldMapView
extends Control
## Stylised map of the world for free flight, drawn from the same geography the simulator
## flies over: crisp coastlines from the shape definition, shaded relief with hypsometric tint
## and contours from the baked heightfield, a bathymetric sea with a 50 km graticule, rivers,
## lakes, cities and region names, every airport as a pin and the planned route as an animated
## arc. Drag (mouse or finger) to pan, wheel or pinch to zoom, click a pin to pick it.

signal airport_clicked(icao: String, at: Vector2)

const KM := 1000.0

var center := Vector2(-110.0, 10.0)        # km
var px_per_km := 1.0
var dep := ""
var arr := ""
var hover := ""
var _dash := 0.0
var _drag := false
var _moved := 0.0
var _touches := {}
var _pinch0 := 0.0
var _scale0 := 1.0
var _fitted := false
var _min_scale := 0.5
var _layers: Array = []

static var _htex: ImageTexture
static var _land_shader: Shader
static var _sea_shader: Shader


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sea := Layer.new()
	sea.map = self
	sea.kind = "sea"
	sea.material = _material(true)
	var land := Layer.new()
	land.map = self
	land.kind = "land"
	land.material = _material(false)
	var over := Layer.new()
	over.map = self
	over.kind = "over"
	for l in [sea, land, over]:
		(l as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		(l as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		_layers.append(l)
	resized.connect(_on_resized)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.045, 0.085))


func _on_resized() -> void:
	if not _fitted and size.x > 10.0:
		fit_all()
	_redraw()


## Frames every airport (or the two route ends) with margins for the side panel.
func fit_all(left_pad: float = 380.0) -> void:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for icao in Airports.ORDER:
		var p := Airports.pos2(icao) / KM
		mn = mn.min(p)
		mx = mx.max(p)
	mn -= Vector2(40, 50)
	mx += Vector2(40, 50)
	var avail := Vector2(maxf(size.x - left_pad - 40.0, 200.0), maxf(size.y - 120.0, 200.0))
	px_per_km = minf(avail.x / (mx.x - mn.x), avail.y / (mx.y - mn.y))
	_min_scale = px_per_km * 0.7
	var mid := (mn + mx) * 0.5
	center = mid - Vector2((left_pad - 40.0) * 0.5, 0.0) / px_per_km
	_fitted = true


func to_screen(km: Vector2) -> Vector2:
	return (km - center) * px_per_km + size * 0.5


func to_km(sp: Vector2) -> Vector2:
	return (sp - size * 0.5) / px_per_km + center


func _redraw() -> void:
	for l in _layers:
		(l as Control).queue_redraw()


func _process(delta: float) -> void:
	if dep != "" and arr != "" and dep != arr:
		_dash = fmod(_dash + delta * 18.0, 1000.0)
		(_layers[2] as Control).queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag = true
				_moved = 0.0
			else:
				_drag = false
				if _moved < 6.0:
					_click(event.position)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_at(event.position, 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
	elif event is InputEventMouseMotion:
		if _drag:
			center -= event.relative / px_per_km
			_moved += event.relative.length()
			_redraw()
		else:
			var h := _pick(event.position)
			if h != hover:
				hover = h
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
				(_layers[2] as Control).queue_redraw()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			_moved = 0.0
		else:
			_touches.erase(event.index)
			if _touches.is_empty() and _moved < 10.0:
				_click(event.position)
		if _touches.size() == 2:
			var pts: Array = _touches.values()
			_pinch0 = (pts[0] as Vector2).distance_to(pts[1])
			_scale0 = px_per_km
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2 and _pinch0 > 1.0:
			var pts2: Array = _touches.values()
			var f := (pts2[0] as Vector2).distance_to(pts2[1]) / _pinch0
			var mid := ((pts2[0] as Vector2) + (pts2[1] as Vector2)) * 0.5
			var keep := to_km(mid)
			px_per_km = clampf(_scale0 * f, _min_scale, 14.0)
			center += keep - to_km(mid)
			_moved += 20.0
		else:
			center -= event.relative / px_per_km
			_moved += event.relative.length()
		_redraw()


func _zoom_at(sp: Vector2, f: float) -> void:
	var keep := to_km(sp)
	px_per_km = clampf(px_per_km * f, _min_scale, 14.0)
	center += keep - to_km(sp)
	_redraw()


func _pick(sp: Vector2) -> String:
	var best := ""
	var bd := 18.0
	for icao in Airports.ORDER:
		var d := to_screen(Airports.pos2(icao) / KM).distance_to(sp)
		if d < bd:
			bd = d
			best = icao
	return best


func _click(sp: Vector2) -> void:
	var a := _pick(sp)
	if a != "":
		UIStyle._click_sound()
		airport_clicked.emit(a, to_screen(Airports.pos2(a) / KM))


# ------------------------------------------------------------------ resources
static func height_tex() -> ImageTexture:
	if _htex == null:
		var n := Geo.GRID
		var img := Image.create(n, n, false, Image.FORMAT_L8)
		for j in n:
			for i in n:
				var h := float(Geo.macro[j * n + i]) if Geo.macro.size() == n * n else -100.0
				var v := clampf((h + 1000.0) / 4000.0, 0.0, 1.0)
				img.set_pixel(i, j, Color(v, v, v))
		_htex = ImageTexture.create_from_image(img)
	return _htex


static func _material(sea: bool) -> ShaderMaterial:
	if _land_shader == null:
		_land_shader = Shader.new()
		_land_shader.code = """shader_type canvas_item;
uniform sampler2D hmap : filter_linear, repeat_disable;
uniform float texel = 0.0078125;
void fragment() {
	float h = texture(hmap, UV).r * 4000.0 - 1000.0;
	float hx = texture(hmap, UV + vec2(texel, 0.0)).r - texture(hmap, UV - vec2(texel, 0.0)).r;
	float hz = texture(hmap, UV + vec2(0.0, texel)).r - texture(hmap, UV - vec2(0.0, texel)).r;
	vec3 n = normalize(vec3(-hx * 42.0, 1.0, -hz * 42.0));
	float shade = clamp(dot(n, normalize(vec3(-0.55, 0.75, -0.6))), 0.0, 1.0);
	float t = max(h, 0.0);
	vec3 c = mix(vec3(0.15, 0.22, 0.16), vec3(0.27, 0.3, 0.21), smoothstep(10.0, 350.0, t));
	c = mix(c, vec3(0.42, 0.39, 0.32), smoothstep(350.0, 1100.0, t));
	c = mix(c, vec3(0.82, 0.83, 0.86), smoothstep(1600.0, 2300.0, t));
	c *= 0.5 + 0.8 * shade;
	float k = t / 200.0;
	float d = abs(fract(k + 0.5) - 0.5) / max(fwidth(k), 0.0001);
	c = mix(c, c * 1.35 + 0.02, (1.0 - min(d, 1.0)) * 0.3 * step(60.0, t));
	COLOR = vec4(c, 1.0);
}
"""
		_sea_shader = Shader.new()
		_sea_shader.code = """shader_type canvas_item;
uniform sampler2D hmap : filter_linear, repeat_disable;
void fragment() {
	float h = texture(hmap, UV).r * 4000.0 - 1000.0;
	float d = clamp(-h / 900.0, 0.0, 1.0);
	vec3 c = mix(vec3(0.075, 0.2, 0.26), vec3(0.018, 0.045, 0.085), smoothstep(0.0, 0.9, d));
	float k = -h / 150.0;
	float bd = abs(fract(k + 0.5) - 0.5) / max(fwidth(k), 0.0001);
	c += (1.0 - min(bd, 1.0)) * 0.025 * step(0.3, k);
	vec2 km = UV * 1024.0 - 512.0;
	vec2 g = abs(fract(km / 50.0 + 0.5) - 0.5) / max(fwidth(km / 50.0), vec2(0.0001));
	c += (1.0 - min(min(g.x, g.y), 1.0)) * 0.04;
	COLOR = vec4(c, 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _sea_shader if sea else _land_shader
	m.set_shader_parameter("hmap", height_tex())
	return m


static func _uv(km: Vector2) -> Vector2:
	return (km * KM + Vector2(Geo.MAP_HALF, Geo.MAP_HALF)) / (Geo.MAP_HALF * 2.0)


static func _ellipse(c: Vector2, r: Vector2, n: int = 28) -> Array:
	var out := []
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return out


static func land_polys() -> Array:
	var polys := [Geo.MAINLAND, Geo.WESTMARK]
	for isl in Geo.ISLANDS:
		polys.append(_ellipse(isl[0], isl[1], 24))
	return polys


## One drawing layer (sea, land, or the overlay of routes, pins and labels).
class Layer extends Control:
	var map: WorldMapView
	var kind := "over"

	func _draw() -> void:
		match kind:
			"sea":
				var a := map.to_screen(Vector2(-512, -512))
				var b := map.to_screen(Vector2(512, 512))
				draw_primitive(PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]), PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]),
					PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
			"land":
				for poly in WorldMapView.land_polys():
					var pts := PackedVector2Array()
					var uvs := PackedVector2Array()
					for p in poly:
						pts.append(map.to_screen(p))
						uvs.append(WorldMapView._uv(p))
					draw_colored_polygon(pts, Color.WHITE, uvs)
			"over":
				_overlay()

	func _overlay() -> void:
		var f := UIStyle.face(600, 1.0, 1)
		var fb := UIStyle.face(800, 1.0, 1)
		var fc := UIStyle.face(700, 1.0, 4)
		var zoom := map.px_per_km
		# coastline
		for poly in WorldMapView.land_polys():
			var pts := PackedVector2Array()
			for p in poly:
				pts.append(map.to_screen(p))
			pts.append(pts[0])
			draw_polyline(pts, Color(0.62, 0.82, 0.92, 0.55), 1.3, true)
		# lakes and rivers
		for lk in Geo.LAKES:
			var lp := PackedVector2Array()
			for q in WorldMapView._ellipse(Vector2(float(lk.x), float(lk.z)) / 1000.0, Vector2(float(lk.rx), float(lk.rz)) / 1000.0 * 1.2, 24):
				lp.append(map.to_screen(q))
			draw_colored_polygon(lp, Color(0.09, 0.24, 0.31))
		for rv in Geo.RIVERS:
			var rp := PackedVector2Array()
			for q2 in rv.pts:
				rp.append(map.to_screen(q2))
			draw_polyline(rp, Color(0.25, 0.5, 0.62, 0.8), maxf(1.0, zoom * 0.5), true)
		# region names
		for r in [["CALDERRA", Vector2(225, -40)], ["WESTMARK", Vector2(-425, -60)], ["WESTERN SEA", Vector2(-225, 150)],
				["CALDER RANGE", Vector2(215, -245)], ["SOUTHERN SEA", Vector2(90, 410)]]:
			var sp := map.to_screen(r[1])
			var fs := int(clampf(zoom * 9.0, 11.0, 22.0))
			var w := fc.get_string_size(r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(fc, sp - Vector2(w * 0.5, 0), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.2))
		# cities
		for c in Geo.cities:
			var cp := map.to_screen(Vector2(float(c.x), float(c.z)) / 1000.0)
			var big := int(c.pop) > 300000
			var cr := 2.5 if big else 1.8
			draw_circle(cp, cr + 1.0, Color(0, 0, 0, 0.5))
			draw_circle(cp, cr, Color(1.0, 0.86, 0.6, 0.85))
			if big or zoom > 2.2:
				draw_string(f, cp + Vector2(6, 4), String(c.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.9, 0.72, 0.65))
		# route
		if map.dep != "" and map.arr != "" and map.dep != map.arr:
			_route()
		# airports
		for icao in Airports.ORDER:
			var ap: Dictionary = Airports.get_ap(icao)
			var p := map.to_screen(Airports.pos2(icao) / 1000.0)
			var is_dep: bool = icao == map.dep
			var is_arr: bool = icao == map.arr
			var hub: bool = String(ap.size) == "hub"
			var col := UIStyle.GREEN if is_dep else (UIStyle.GOLD if is_arr else Color(0.9, 0.95, 1.0))
			var r := 6.5 if hub else 5.0
			if is_dep or is_arr or icao == map.hover:
				draw_circle(p, r + 7.0, Color(col, 0.18))
				draw_arc(p, r + 7.0, 0.0, TAU, 32, Color(col, 0.8), 1.5, true)
			draw_circle(p, r + 1.5, Color(0.0, 0.02, 0.05, 0.85))
			draw_circle(p, r, col)
			draw_circle(p, r * 0.42, Color(0.02, 0.05, 0.1))
			var label: String = icao
			var fs2 := 13
			var lw := fb.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			var lp2 := p + Vector2(-lw * 0.5, r + 17.0)
			draw_rect(Rect2(lp2 + Vector2(-5, -13), Vector2(lw + 10, 17)), Color(0.01, 0.02, 0.04, 0.75))
			draw_string(fb, lp2, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, col if (is_dep or is_arr) else Color.WHITE)
			if icao == map.hover or is_dep or is_arr or zoom > 2.0:
				var nm := String(ap.short)
				var nw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				draw_string(f, p + Vector2(-nw * 0.5, r + 31.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.75))

	func _route() -> void:
		var a := map.to_screen(Airports.pos2(map.dep) / 1000.0)
		var b := map.to_screen(Airports.pos2(map.arr) / 1000.0)
		var mid := (a + b) * 0.5
		var n := (b - a).orthogonal().normalized()
		var ctrl := mid + n * a.distance_to(b) * 0.16
		var pts := PackedVector2Array()
		for i in 49:
			var t := i / 48.0
			pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
		draw_polyline(pts, Color(0, 0, 0, 0.45), 6.0, true)
		draw_polyline(pts, Color(UIStyle.ACCENT, 0.35), 3.0, true)
		# animated dashes along the arc
		var acc := 0.0
		var dash := 14.0
		var gap := 9.0
		var phase := fmod(map._dash, dash + gap)
		for i in pts.size() - 1:
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var seg := p0.distance_to(p1)
			var s := 0.0
			while s < seg:
				var pos := acc + s - phase
				var m := fposmod(pos, dash + gap)
				var step := minf(seg - s, (dash - m) if m < dash else (dash + gap - m))
				if m < dash:
					draw_line(p0.lerp(p1, s / seg), p0.lerp(p1, (s + step) / seg), Color(0.75, 0.92, 1.0), 2.2, true)
				s += maxf(step, 0.5)
			acc += seg
		# the aircraft at the middle of the arc, along the tangent
		var tm := 0.5
		var pm := a.lerp(ctrl, tm).lerp(ctrl.lerp(b, tm), tm)
		var tan := (ctrl - a).lerp(b - ctrl, tm).normalized()
		draw_set_transform(pm, tan.angle() + PI * 0.5, Vector2.ONE)
		UIIcon.draw(self, "plane", Rect2(Vector2(-11, -11), Vector2(22, 22)), Color.WHITE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
