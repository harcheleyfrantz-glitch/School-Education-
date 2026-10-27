extends Node
## News system (placeholder, replaced by the full implementation).

var incidents := []
var articles := []

func on_clock(_t0: float, _t1: float) -> void:
	pass

func background_story(_kind: String, _f: Dictionary, _t: float, _seed: int) -> void:
	pass

func serialize() -> Dictionary:
	return {}

func deserialize(_d: Dictionary) -> void:
	pass

func reset() -> void:
	incidents.clear()
	articles.clear()
