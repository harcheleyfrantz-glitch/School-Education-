extends Node
## Loads every script and shader in the project so parse/compile errors surface in one run.

func _ready() -> void:
	var files := []
	_collect("res://src", files)
	_collect("res://tests", files)
	_collect("res://shaders", files)
	var bad := 0
	for f in files:
		var res: Resource = load(f)
		if res == null:
			bad += 1
			print("FAILED: ", f)
		elif res is GDScript and not (res as GDScript).can_instantiate():
			bad += 1
			print("CANNOT INSTANTIATE: ", f)
	print("COMPILE CHECK DONE: ", files.size(), " files, ", bad, " failed")
	get_tree().quit()

func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".gdshader"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)
