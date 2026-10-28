extends ScreenBase
## Free flight lives on the WORLD MAP now; this name is kept so Game.goto("free") still works.


func setup(params: Dictionary) -> void:
	Game.goto("world_map", params)
