class_name ShotRect
extends Control
## A photo-studio picture that fills its rect (cropped to cover), with a shimmering placeholder
## until the render is ready and a fade-in when it arrives.

var shot_id := ""
var icon_name := "plane"
var priority := false
var _img: TextureRect
var _ph: ImageCard.Placeholder


static func make(id: String, min_size: Vector2 = Vector2.ZERO, prio: bool = false) -> ShotRect:
	var s := ShotRect.new()
	s.shot_id = id
	s.priority = prio
	s.custom_minimum_size = min_size
	return s


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ph = ImageCard.Placeholder.new()
	_ph.icon_name = icon_name
	_ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ph)
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_img)
	if shot_id != "":
		set_shot(shot_id)


func set_shot(id: String) -> void:
	shot_id = id
	if _img == null:
		return
	var t := PhotoStudio.get_shot(id, priority)
	if t:
		_img.texture = t
		_img.modulate.a = 1.0
		_ph.loading = false
	else:
		_img.texture = null
		_img.modulate.a = 0.0
		_ph.loading = true
		_ph.set_process(true)
		var st := PhotoStudio.instance()
		if not st.shot_ready.is_connected(_on_shot):
			st.shot_ready.connect(_on_shot)


func _on_shot(id: String, t: Texture2D) -> void:
	if id != shot_id or not is_instance_valid(_img):
		return
	_img.texture = t
	_ph.loading = false
	create_tween().tween_property(_img, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
