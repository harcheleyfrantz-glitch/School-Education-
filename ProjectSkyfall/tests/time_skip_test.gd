extends Node
func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var n0 := News.articles.size()
	for d in 365:
		WorldSim.advance(86400.0)
	print("YEAR SIMULATED in %d ms, %d new articles, year %s" % [Time.get_ticks_msec() - t0, News.articles.size() - n0, str(U.clock_to_date(WorldSim.clock).year)])
	get_tree().quit()
