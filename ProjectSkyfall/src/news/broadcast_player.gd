class_name BroadcastPlayer
extends Control
## In-engine video player. Composes each frame at 1280x720 from the active set (studio, field,
## press room, memorial - each rendered in its own world) and the broadcast graphics, speaks
## the narration with text-to-speech while showing captions, plays the music beds, stings and
## ambience, and offers real controls: play/pause, scrub with chapter marks, time, volume,
## captions, speed and camera (replays), fullscreen and close. Embeds anywhere (news, debrief,
## library) and can go fullscreen over everything.

signal closed
signal finished

const FRAME := Vector2i(1280, 720)
const PHONE_W := 406.0
const STAGE_SCRIPTS := {"studio": "res://src/news/stages/studio_stage.gd", "world": "res://src/news/stages/world_stage.gd",
	"press": "res://src/news/stages/press_stage.gd", "memorial": "res://src/news/stages/memorial_stage.gd", "airport": "res://src/news/stages/world_stage.gd"}
const REPLAY_CAMS := ["director", "chase", "orbit", "tower", "cockpit", "flyby", "analysis"]

var program: Dictionary = {}
var duration := 1.0
var t := 0.0
var playing := false
var volume := 0.85
var muted := false
var captions := true
var speed := 1.0
var cam_override := ""
var allow_close := true
var autoplay := true
var loaded := false
var stages := {}
var stage_vps := {}
var frame_vp: SubViewport
var gfx: BroadcastGraphics
var _frame_root: Control
var _stage_rects := {}
var _phone_center: TextureRect
var _phone_bg: TextureRect
var _phone_atlas: AtlasTexture
var _phone_mat: ShaderMaterial
var _blur_mat: ShaderMaterial
var _active := ""
var _seg_i := -1
var _load_t := 0.0
var _end_shown := false
var _fullscreen := false
var _home_parent: Node = null
var _home_index := 0
var _home_layout := {}
var _layer: CanvasLayer = null
var _idle := 0.0
var _voices := {}
var _tts_ok := false
var _music: AudioStreamPlayer
var _amb: AudioStreamPlayer
var _sfx: Array = []
var _music_name := ""
var _amb_name := ""
# ui
var _screen: TextureRect
var _bar: Control
var _seek: SeekBar
var _play_btn: Button
var _time_lbl: Label
var _chap_lbl: Label
var _cc_btn: Button
var _vol: HSlider
var _vol_btn: Button
var _fs_btn: Button
var _big: Button
var _loading: Control
var _load_bar: ProgressBar
var _title_lbl: Label
var _end_panel: Control
var _top: Control


# ================================================================== setup
## opts: autoplay, closable, start, muted, captions, title
func open(prog: Dictionary, opts: Dictionary = {}) -> void:
	program = prog
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UIStyle.theme()
	clip_contents = true
	autoplay = bool(opts.get("autoplay", true))
	allow_close = bool(opts.get("closable", true))
	muted = bool(opts.get("muted", false))
	captions = bool(opts.get("captions", Game.settings.get("subtitles", true)))
	t = float(opts.get("start", 0.0))
	duration = maxf(float(prog.get("duration", 1.0)), 1.0)
	_prepare_shots()
	NewsAudio.prepare()
	_init_tts()
	_build_frame()
	_build_stages()
	_build_ui(String(opts.get("title", prog.get("title", ""))))
	_build_audio()
	mouse_filter = Control.MOUSE_FILTER_STOP


func _prepare_shots() -> void:
	## Each shot learns how long it lasts (until the next cut or the end of its segment).
	for s in program.get("segments", []):
		var shots: Array = s.get("shots", [])
		if shots.is_empty():
			shots.append({"cam": "default", "t": 0.0})
			s.shots = shots
		var d := float(s.t1) - float(s.t0)
		for i in shots.size():
			var nxt := float(shots[i + 1].t) if i + 1 < shots.size() else d
			shots[i].dur = maxf(nxt - float(shots[i].t), 0.1)


func _build_frame() -> void:
	frame_vp = SubViewport.new()
	frame_vp.size = FRAME
	frame_vp.disable_3d = true
	frame_vp.transparent_bg = false
	frame_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(frame_vp)
	_frame_root = Control.new()
	_frame_root.size = Vector2(FRAME)
	_frame_root.theme = UIStyle.theme()
	frame_vp.add_child(_frame_root)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(FRAME)
	_frame_root.add_child(bg)


func _build_stages() -> void:
	var needed := {}
	for s in program.get("segments", []):
		needed[String(s.stage)] = true
	for name in needed.keys():
		var path := String(STAGE_SCRIPTS.get(name, ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var scr: GDScript = load(path)
		var st: NewsStage = scr.new()
		var vp := SubViewport.new()
		vp.size = FRAME
		vp.own_world_3d = true
		vp.transparent_bg = false
		vp.audio_listener_enable_3d = false
		var q := String(Game.settings.get("quality", "high"))
		vp.msaa_3d = Viewport.MSAA_4X if q in ["high", "ultra"] else (Viewport.MSAA_2X if q == "medium" else Viewport.MSAA_DISABLED)
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == "low" else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_debanding = true
		vp.positional_shadow_atlas_size = 2048
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		st.player = self
		st.set_meta("stage_name", name)
		vp.add_child(st)
		st.build(program)
		stages[name] = st
		stage_vps[name] = vp
		var tr := TextureRect.new()
		tr.texture = vp.get_texture()
		tr.size = Vector2(FRAME)
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.visible = false
		_frame_root.add_child(tr)
		_stage_rects[name] = tr
	# vertical phone footage: the centre of the field picture, with a blurred fill either side
	if stages.has("world") and _has_phone():
		_phone_atlas = AtlasTexture.new()
		_phone_atlas.atlas = (stage_vps["world"] as SubViewport).get_texture()
		_phone_atlas.region = Rect2((FRAME.x - PHONE_W) * 0.5, 0, PHONE_W, FRAME.y)
		_phone_bg = TextureRect.new()
		_phone_bg.texture = _phone_atlas
		_phone_bg.size = Vector2(FRAME)
		_phone_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_phone_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_blur_mat = ShaderMaterial.new()
		_blur_mat.shader = load("res://src/news/blur_fill.gdshader")
		_phone_bg.material = _blur_mat
		_phone_bg.visible = false
		_frame_root.add_child(_phone_bg)
		_phone_center = TextureRect.new()
		_phone_center.texture = _phone_atlas
		_phone_center.position = Vector2((FRAME.x - PHONE_W) * 0.5, 0)
		_phone_center.size = Vector2(PHONE_W, FRAME.y)
		_phone_center.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_phone_center.stretch_mode = TextureRect.STRETCH_SCALE
		_phone_mat = ShaderMaterial.new()
		_phone_mat.shader = load("res://src/news/phone_video.gdshader")
		_phone_mat.set_shader_parameter("region", Vector4((FRAME.x - PHONE_W) * 0.5 / FRAME.x, 0.0, (FRAME.x + PHONE_W) * 0.5 / FRAME.x, 1.0))
		_phone_center.material = _phone_mat
		_phone_center.visible = false
		_frame_root.add_child(_phone_center)
	gfx = BroadcastGraphics.new()
	gfx.size = Vector2(FRAME)
	gfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gfx.setup(program)
	gfx.captions = captions
	gfx.phone_rect = Rect2((FRAME.x - PHONE_W) * 0.5, 0, PHONE_W, FRAME.y)
	if stages.has("studio"):
		var ss: Node = stages["studio"]
		var wv: SubViewport = ss.get("wall_vp")
		if wv:
			gfx.wall_tex = wv.get_texture()
	_frame_root.add_child(gfx)


var _cctv_mat: ShaderMaterial


func _cctv_material() -> ShaderMaterial:
	if _cctv_mat == null:
		_cctv_mat = ShaderMaterial.new()
		_cctv_mat.shader = load("res://src/news/cctv_video.gdshader")
	return _cctv_mat


func _has_phone() -> bool:
	for s in program.get("segments", []):
		if String(s.kind) == "phone":
			return true
	return false


func _all_ready() -> bool:
	for k in stages.keys():
		if not (stages[k] as NewsStage).is_ready():
			return false
	return true


# ================================================================== helpers shared with stages and graphics
static func sample_at(samples: Array, tt: float) -> Array:
	if samples.is_empty():
		return []
	if tt <= float(samples[0][0]):
		return samples[0]
	var hi := samples.size() - 1
	if tt >= float(samples[hi][0]):
		return samples[hi]
	var lo := 0
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if float(samples[mid][0]) <= tt:
			lo = mid
		else:
			hi = mid
	var a: Array = samples[lo]
	var b: Array = samples[hi]
	var f := (tt - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
	var out := []
	for k in a.size():
		if k == 8:
			out.append(float(a[k]) + U.angle_diff_deg(float(b[k]), float(a[k])) * f)
		elif typeof(a[k]) == TYPE_FLOAT or typeof(a[k]) == TYPE_INT:
			out.append(lerpf(float(a[k]), float(b[k]), f))
		else:
			out.append(a[k])
	return out


## Recorder time a segment shows at local time lt (-1 when it shows no flight data).
static func seg_sample_time(seg: Dictionary, lt: float, samples: Array) -> float:
	var rc: Dictionary = seg.get("recon", {})
	if rc.is_empty() or samples.is_empty():
		return -1.0
	var t_end := float(samples[samples.size() - 1][0])
	var t_start := float(samples[0][0])
	if bool(rc.get("freeze", false)):
		return maxf(t_end - 100.0, t_start)
	if bool(rc.get("after", false)):
		return t_end + lt
	return maxf(t_end - float(rc.get("span", 0.0)), t_start) + lt


func segment_at(tt: float) -> int:
	var segs: Array = program.get("segments", [])
	for i in segs.size():
		if tt < float(segs[i].t1) or i == segs.size() - 1:
			return i
	return -1


# ================================================================== per frame
func _process(delta: float) -> void:
	if not loaded:
		_load_t += delta
		if _load_bar:
			_load_bar.value = minf(_load_t / 6.0, 0.95) * 100.0
		_render(0.0)
		if (_all_ready() and _load_t > 0.4) or _load_t > 16.0:
			loaded = true
			_loading.visible = false
			if autoplay:
				set_playing(true)
			else:
				_big.visible = true
		return
	if playing:
		var nt := minf(t + delta * speed, duration)
		_fire_events(t, nt)
		t = nt
		if t >= duration:
			set_playing(false)
			_show_end()
	_render(delta * speed if playing else 0.0)
	_update_ui(delta)


func _render(delta: float) -> void:
	var segs: Array = program.get("segments", [])
	if segs.is_empty():
		return
	var i := segment_at(t)
	var seg: Dictionary = segs[i]
	if i != _seg_i:
		_seg_i = i
		_enter_segment(seg)
	var lt := t - float(seg.t0)
	var shots: Array = seg.shots
	var shot: Dictionary = shots[0]
	for sh in shots:
		if float(sh.t) <= lt:
			shot = sh
	if cam_override != "" and String(seg.kind) == "replay":
		shot = {"cam": cam_override, "t": 0.0, "dur": 1e9}
	var st: NewsStage = stages.get(String(seg.stage), null)
	if st:
		st.apply(seg, shot, lt, lt - float(shot.t), delta)
	seg["_cam"] = String(shot.cam)
	seg["_shot_t0"] = float(seg.t0) + float(shot.t)
	gfx.t = t
	gfx.seg = seg
	gfx.seg_i = i
	gfx.captions = captions
	gfx.cam_label = String(shot.cam) if cam_override == "" else cam_override
	gfx.queue_redraw()
	if _phone_mat and String(seg.kind) == "phone":
		_phone_mat.set_shader_parameter("time", t)
	if _cctv_mat and String(seg.get("variant", "")) == "cctv":
		_cctv_mat.set_shader_parameter("time", t)
	Game.crowd_clock_override = t + 100.0


func _enter_segment(seg: Dictionary) -> void:
	var name := String(seg.stage)
	if name != _active:
		for k in stage_vps.keys():
			(stage_vps[k] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS if k == name else SubViewport.UPDATE_DISABLED
			(_stage_rects[k] as TextureRect).visible = k == name
		_active = name
	var phone := String(seg.kind) == "phone" and not bool(seg.get("landscape", false))
	if _phone_center:
		_phone_center.visible = phone
		_phone_bg.visible = phone
		if _stage_rects.has("world"):
			(_stage_rects["world"] as TextureRect).visible = name == "world" and not phone
	if _stage_rects.has("world"):
		(_stage_rects["world"] as TextureRect).material = _cctv_material() if String(seg.get("variant", "")) == "cctv" and String(seg.kind) == "phone" else null
	var st: NewsStage = stages.get(name, null)
	if st:
		st.enter(seg)
	_segment_audio(seg)
	if _chap_lbl:
		_chap_lbl.text = NewsScript._chapter_name(seg)


func _fire_events(a: float, b: float) -> void:
	if speed > 1.01 or speed < 0.99:
		return
	for l in program.get("lines", []):
		var lt0 := float(l.t0)
		if lt0 > a and lt0 <= b and bool(l.get("speak", false)):
			_speak(l)
	for c in program.get("cues", []):
		var ct := float(c.t)
		if ct > a and ct <= b:
			_play_sfx(String(c.sfx), float(c.get("db", 0.0)))
	# stings fire when a segment that carries one is entered from its start
	for s in program.get("segments", []):
		if String(s.get("music", "")) == "sting" and float(s.t0) >= a and float(s.t0) < b + 0.001 and a <= float(s.t0):
			_play_sfx("sting", -2.0)


# ================================================================== playback control
func set_playing(on: bool) -> void:
	if on and t >= duration - 0.05:
		seek(0.0)
	if on and not playing and t <= 0.05:
		_fire_events(-1.0, 0.0)
	playing = on
	_end_shown = false
	if _end_panel:
		_end_panel.visible = false
	if _big:
		_big.visible = not on and loaded
	if _play_btn:
		_set_icon(_play_btn, "pause" if on else "play")
	if _tts_ok:
		if on:
			DisplayServer.tts_resume()
		else:
			DisplayServer.tts_pause()
	if _music:
		_music.stream_paused = not on
	if _amb:
		_amb.stream_paused = not on


func seek(to: float) -> void:
	t = clampf(to, 0.0, duration)
	if _tts_ok:
		DisplayServer.tts_stop()
	_seg_i = -1
	_end_shown = false
	if _end_panel:
		_end_panel.visible = false
	for s in stages.values():
		if s.has_method("on_seek"):
			s.call("on_seek")


func toggle() -> void:
	set_playing(not playing)


func _show_end() -> void:
	if _end_shown:
		return
	_end_shown = true
	if _end_panel:
		_end_panel.visible = true
	if _tts_ok:
		DisplayServer.tts_stop()
	finished.emit()


func set_fullscreen(on: bool) -> void:
	if on == _fullscreen:
		return
	_fullscreen = on
	if on:
		_home_parent = get_parent()
		_home_index = get_index()
		_home_layout = {"al": anchor_left, "at": anchor_top, "ar": anchor_right, "ab": anchor_bottom, "ol": offset_left, "ot": offset_top,
			"or": offset_right, "ob": offset_bottom, "min": custom_minimum_size, "h": size_flags_horizontal, "v": size_flags_vertical}
		_layer = CanvasLayer.new()
		_layer.layer = 95
		get_tree().root.add_child(_layer)
		var holder := ColorRect.new()
		holder.color = Color.BLACK
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_layer.add_child(holder)
		reparent(holder, false)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		if is_instance_valid(_home_parent):
			reparent(_home_parent, false)
			_home_parent.move_child(self, mini(_home_index, _home_parent.get_child_count() - 1))
			anchor_left = _home_layout.al
			anchor_top = _home_layout.at
			anchor_right = _home_layout.ar
			anchor_bottom = _home_layout.ab
			offset_left = _home_layout.ol
			offset_top = _home_layout.ot
			offset_right = _home_layout["or"]
			offset_bottom = _home_layout.ob
			custom_minimum_size = _home_layout["min"]
			size_flags_horizontal = _home_layout.h
			size_flags_vertical = _home_layout.v
		if is_instance_valid(_layer):
			_layer.queue_free()
		_layer = null
	if _fs_btn:
		_set_icon(_fs_btn, "shrink" if on else "expand")


func close() -> void:
	if _tts_ok:
		DisplayServer.tts_stop()
	if _fullscreen:
		set_fullscreen(false)
	closed.emit()


func capture_frame() -> Image:
	return frame_vp.get_texture().get_image()


func _exit_tree() -> void:
	Game.crowd_clock_override = -1.0
	if _tts_ok:
		DisplayServer.tts_stop()
	if is_instance_valid(_layer) and not _fullscreen:
		_layer.queue_free()


# ================================================================== speech
func _init_tts() -> void:
	_tts_ok = DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) and bool(Game.settings.get("tts", true))
	if not _tts_ok:
		return
	var ids := DisplayServer.tts_get_voices_for_language("en")
	if ids.is_empty():
		_tts_ok = false
		return
	var roles := ["anchor", "reporter", "witness", "official", "narrator", "analyst", "vo", "interview"]
	for i in roles.size():
		_voices[roles[i]] = ids[(i * 2 + U.hash_str(String(program.get("title", "")))) % ids.size()]
	_voices.vo = _voices.anchor
	_voices.interview = _voices.witness


func _speak(l: Dictionary) -> void:
	if not _tts_ok or muted or volume <= 0.01:
		return
	var role := String(l.get("voice", "anchor"))
	var vid := String(_voices.get(role, _voices.get("anchor", "")))
	var vol := int(clampf(volume * float(Game.settings.get("voice_volume", 1.0)) * float(Game.settings.get("master_volume", 0.85)) * 100.0, 0.0, 100.0))
	var g := _gender_of(String(l.get("name", "")))
	var pitch := 1.08 if g == "f" else (0.9 if g == "m" else 1.0)
	DisplayServer.tts_speak(String(l.text), vid, vol, pitch, 1.0, 0, false)


func _gender_of(n: String) -> String:
	for st in NewsStyle.STYLES.values():
		for a in st.anchors + st.reporters:
			if String(a[0]) == n:
				return String(a[1])
	var first := n.split(" ")[0]
	if first in Names.FIRST_F:
		return "f"
	if first in Names.FIRST_M:
		return "m"
	return "x"


# ================================================================== sound
func _build_audio() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = "Music" if AudioServer.get_bus_index("Music") != -1 else "Master"
	add_child(_music)
	_amb = AudioStreamPlayer.new()
	_amb.bus = "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
	add_child(_amb)
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = _amb.bus
		add_child(p)
		_sfx.append(p)
	Audio.music(false)


func _gain(db: float) -> float:
	return db + linear_to_db(maxf(volume * (0.0 if muted else 1.0), 0.0001))


func _segment_audio(seg: Dictionary) -> void:
	var m := String(seg.get("music", ""))
	if m == "bed_out":
		m = "bed"
	if m == "sting":
		m = ""
	if m != _music_name:
		_music_name = m
		var s := NewsAudio.stream(m) if m != "" else null
		if s:
			_music.stream = s
			_music.play()
		else:
			_music.stop()
	var a := String(seg.get("amb", ""))
	if a != _amb_name:
		_amb_name = a
		var s2 := NewsAudio.stream(a) if a != "" else null
		if s2:
			_amb.stream = s2
			_amb.play()
		else:
			_amb.stop()
	_apply_volume()


func _apply_volume() -> void:
	var mdb := {"bed": -17.0, "tension": -15.0, "somber": -13.0}.get(_music_name, -16.0)
	_music.volume_db = _gain(float(mdb))
	_amb.volume_db = _gain(-9.0 if _amb_name in ["heli", "sirens"] else -12.0)
	_music.stream_paused = not playing
	_amb.stream_paused = not playing


func _play_sfx(name: String, db: float) -> void:
	var s := NewsAudio.stream(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _sfx[0]
	_sfx.push_back(_sfx.pop_front())
	p.stream = s
	p.volume_db = _gain(db)
	p.play()


# ================================================================== controls
func _build_ui(title: String) -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_screen = TextureRect.new()
	_screen.texture = frame_vp.get_texture()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	# top title bar
	_top = Control.new()
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.offset_bottom = 52
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	var tg := TextureRect.new()
	tg.texture = _grad(true)
	tg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tg.stretch_mode = TextureRect.STRETCH_SCALE
	tg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(tg)
	_title_lbl = UIStyle.label(title, 17, Color.WHITE, true)
	_title_lbl.position = Vector2(16, 12)
	_title_lbl.clip_text = true
	_title_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title_lbl.offset_left = 16
	_title_lbl.offset_top = 12
	_title_lbl.offset_right = -60
	_top.add_child(_title_lbl)
	if allow_close:
		var cb := _flat("@close", func(): close(), 40)
		cb.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		cb.offset_left = -52
		cb.offset_top = 6
		cb.offset_right = -8
		cb.offset_bottom = 46
		_top.add_child(cb)
	# bottom bar
	_bar = Control.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_top = -78
	add_child(_bar)
	var bgr := TextureRect.new()
	bgr.texture = _grad(false)
	bgr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bgr.stretch_mode = TextureRect.STRETCH_SCALE
	bgr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(bgr)
	_seek = SeekBar.new()
	_seek.player = self
	_seek.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_seek.offset_left = 14
	_seek.offset_right = -14
	_seek.offset_top = 8
	_seek.offset_bottom = 26
	_bar.add_child(_seek)
	var row := UIStyle.hbox(6)
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 10
	row.offset_right = -10
	row.offset_top = -48
	row.offset_bottom = -6
	_bar.add_child(row)
	_play_btn = _flat("@play", func(): toggle(), 44)
	row.add_child(_play_btn)
	row.add_child(_flat("@replay", func():
		seek(0.0)
		set_playing(true), 40))
	_vol_btn = _flat("@volume", func():
		muted = not muted
		_set_icon(_vol_btn, "mute" if muted else "volume")
		_apply_volume(), 40)
	row.add_child(_vol_btn)
	_vol = HSlider.new()
	_vol.min_value = 0.0
	_vol.max_value = 1.0
	_vol.step = 0.01
	_vol.value = volume
	_vol.custom_minimum_size = Vector2(80, 30)
	_vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vol.focus_mode = Control.FOCUS_NONE
	_vol.value_changed.connect(func(v):
		volume = v
		_apply_volume())
	row.add_child(_vol)
	_time_lbl = UIStyle.label("0:00 / 0:00", 14, Color.WHITE)
	_time_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_time_lbl)
	_chap_lbl = UIStyle.label("", 14, Color(1, 1, 1, 0.7))
	_chap_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chap_lbl.clip_text = true
	_chap_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_chap_lbl)
	if String(program.get("kind", "")) == "replay":
		row.add_child(ScreenBase.option(["0.5×", "1×", "2×", "4×", "8×", "16×"], 1, func(i):
			speed = [0.5, 1.0, 2.0, 4.0, 8.0, 16.0][i]
			if _tts_ok:
				DisplayServer.tts_stop()))
		row.add_child(ScreenBase.option(["Director", "Chase", "Orbit", "Tower", "Cockpit", "Flyby", "Flight path"], 0, func(i):
			cam_override = "" if i == 0 else String(REPLAY_CAMS[i])))
	_cc_btn = _flat("CC", func():
		captions = not captions
		_cc_btn.modulate = Color.WHITE if captions else Color(1, 1, 1, 0.45), 44)
	_cc_btn.modulate = Color.WHITE if captions else Color(1, 1, 1, 0.45)
	row.add_child(_cc_btn)
	_fs_btn = _flat("@expand", func(): set_fullscreen(not _fullscreen), 44)
	row.add_child(_fs_btn)
	# big centre play button
	_big = Button.new()
	_big.text = "▶"
	_big.add_theme_font_size_override("font_size", 46)
	_big.add_theme_stylebox_override("normal", UIStyle.box(Color(0, 0, 0, 0.55), 48, Color(1, 1, 1, 0.8), 2, 10))
	_big.add_theme_stylebox_override("hover", UIStyle.box(Color(0.8, 0.1, 0.1, 0.8), 48, Color.WHITE, 2, 10))
	_big.custom_minimum_size = Vector2(96, 96)
	_big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_big.offset_left = -48
	_big.offset_top = -48
	_big.offset_right = 48
	_big.offset_bottom = 48
	_big.focus_mode = Control.FOCUS_NONE
	_big.visible = false
	_big.pressed.connect(func(): set_playing(true))
	add_child(_big)
	# end of video
	_end_panel = VBoxContainer.new()
	_end_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end_panel.offset_left = -120
	_end_panel.offset_right = 120
	_end_panel.offset_top = -50
	_end_panel.offset_bottom = 50
	_end_panel.add_child(UIStyle.button("↻  Watch again", func():
		seek(0.0)
		set_playing(true), 240, UIStyle.ACCENT))
	if allow_close:
		_end_panel.add_child(UIStyle.button("Close", func(): close(), 240))
	_end_panel.visible = false
	add_child(_end_panel)
	# loading slate
	_loading = PanelContainer.new()
	_loading.add_theme_stylebox_override("panel", UIStyle.box(Color(0, 0, 0, 0.78), 0, Color(0, 0, 0, 0), 0, 20))
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var lv := UIStyle.vbox(10)
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading.add_child(lv)
	var st := NewsStyle.get_style(String(program.get("outlet", "skyline")))
	var ll := UIStyle.label(String(st.name).to_upper(), 22, NewsStyle.col(String(program.get("outlet", "skyline")), "primary").lightened(0.3), true)
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(ll)
	var l2 := UIStyle.label("Preparing video…", 15, Color(1, 1, 1, 0.75))
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(l2)
	_load_bar = ProgressBar.new()
	_load_bar.custom_minimum_size = Vector2(260, 6)
	_load_bar.show_percentage = false
	_load_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lv.add_child(_load_bar)
	add_child(_loading)


## Flat control-bar button; text "@name" gives a drawn UIIcon instead of a glyph.
func _flat(text: String, cb: Callable, w: float) -> Button:
	var icon := ""
	if text.begins_with("@"):
		icon = text.substr(1)
		text = ""
	var b := UIStyle.button(text, cb, w)
	if icon != "":
		var ic := UIIcon.make(icon, 20.0, Color.WHITE, 2.2)
		ic.name = "Icon"
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ic.offset_left = -10
		ic.offset_top = -10
		ic.offset_right = 10
		ic.offset_bottom = 10
		b.add_child(ic)
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", UIStyle.box(Color(1, 1, 1, 0.12), 8, Color(0, 0, 0, 0), 0, 6))
	b.add_theme_stylebox_override("pressed", UIStyle.box(Color(1, 1, 1, 0.2), 8, Color(0, 0, 0, 0), 0, 6))
	b.add_theme_font_size_override("font_size", 18)
	return b


func _set_icon(b: Button, kind: String) -> void:
	var ic := b.get_node_or_null("Icon") as UIIcon
	if ic:
		ic.set_icon(kind)
		ic.queue_redraw()


static var _grad_cache := {}


static func _grad(top: bool) -> GradientTexture2D:
	if _grad_cache.has(top):
		return _grad_cache[top]
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0) if not top else Color(0, 0, 0, 0.7))
	g.set_color(1, Color(0, 0, 0, 0.8) if not top else Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	_grad_cache[top] = gt
	return gt


func _update_ui(delta: float) -> void:
	_time_lbl.text = "%s / %s" % [_mmss(t), _mmss(duration)]
	_seek.queue_redraw()
	_idle += delta
	var show := not playing or _idle < 2.6 or _seek.dragging
	var a := 1.0 if show else maxf(_bar.modulate.a - delta * 3.0, 0.0)
	_bar.modulate.a = a
	_top.modulate.a = a
	mouse_default_cursor_shape = Control.CURSOR_ARROW


static func _mmss(x: float) -> String:
	return "%d:%02d" % [int(x) / 60, int(x) % 60]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_idle = 0.0
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_idle = 0.0
		if (event as InputEventMouseButton).double_click:
			set_fullscreen(not _fullscreen)
		elif loaded and (event as InputEventMouseButton).position.y < size.y - 80.0:
			toggle()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		_idle = 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not loaded:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE, KEY_K:
			toggle()
		KEY_LEFT, KEY_J:
			seek(t - 5.0)
		KEY_RIGHT, KEY_L:
			seek(t + 5.0)
		KEY_F:
			set_fullscreen(not _fullscreen)
		KEY_C:
			captions = not captions
		KEY_M:
			muted = not muted
			_apply_volume()
		KEY_ESCAPE:
			if _fullscreen:
				set_fullscreen(false)
			elif allow_close:
				close()
		_:
			return
	_idle = 0.0
	get_viewport().set_input_as_handled()


## Progress bar with chapter marks, hover time and dragging.
class SeekBar extends Control:
	var player: BroadcastPlayer
	var dragging := false
	var hover_x := -1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_exited.connect(func():
			hover_x = -1.0
			queue_redraw())

	func _draw() -> void:
		if player == null:
			return
		var h := 5.0 if hover_x < 0.0 and not dragging else 8.0
		var y := size.y * 0.5 - h * 0.5
		var f := player.t / maxf(player.duration, 0.01)
		draw_rect(Rect2(0, y, size.x, h), Color(1, 1, 1, 0.25))
		var col := NewsStyle.col(String(player.program.get("outlet", "skyline")), "primary").lightened(0.1)
		draw_rect(Rect2(0, y, size.x * f, h), col)
		for ch in player.program.get("chapters", []):
			var cx := float(ch.t) / player.duration * size.x
			if cx > 2.0:
				draw_rect(Rect2(cx - 1.5, y - 1, 3, h + 2), Color(0, 0, 0, 0.8))
		draw_circle(Vector2(size.x * f, size.y * 0.5), 7.0 if hover_x >= 0.0 or dragging else 5.0, col.lightened(0.3))
		if hover_x >= 0.0:
			var ht := hover_x / maxf(size.x, 1.0) * player.duration
			var lab := BroadcastPlayer._mmss(ht)
			for ch2 in player.program.get("chapters", []):
				if float(ch2.t) <= ht:
					lab = "%s · %s" % [BroadcastPlayer._mmss(ht), String(ch2.label)]
			var fnt := UIStyle.font(true)
			var w := fnt.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0
			var bx := clampf(hover_x - w * 0.5, 0.0, size.x - w)
			draw_rect(Rect2(bx, -26, w, 22), Color(0, 0, 0, 0.85))
			draw_string(fnt, Vector2(bx + 7, -10), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			hover_x = (event as InputEventMouseMotion).position.x
			if dragging:
				player.seek(hover_x / maxf(size.x, 1.0) * player.duration)
			player._idle = 0.0
			queue_redraw()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			dragging = (event as InputEventMouseButton).pressed
			if dragging:
				player.seek((event as InputEventMouseButton).position.x / maxf(size.x, 1.0) * player.duration)
			accept_event()
