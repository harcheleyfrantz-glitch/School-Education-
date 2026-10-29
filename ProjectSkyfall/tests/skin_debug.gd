extends Node
func _ready() -> void:
	var h := SkinnedHuman.new()
	add_child(h)
	h.play("idle", 0.0)
	for i in 10:
		await get_tree().process_frame
	var sk := h.skeleton
	for b in sk.get_bone_count():
		print(b, " ", sk.get_bone_name(b), " pose=", sk.get_bone_global_pose(b).origin, " rest=", sk.get_bone_global_rest(b).origin, " q=", sk.get_bone_pose_rotation(b))
	print("skin: ", h.body.skin, " skel path ", h.body.skeleton)
	get_tree().quit()
