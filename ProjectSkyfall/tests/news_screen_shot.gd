extends Node
## Renders the News screen from a saved news fixture (tests/news_fixture.gd): an accident
## article with its video playing inline, its comment section, the video library and the
## social feed; prints a sample of the generated comments.
## Usage: -- <out_dir> <fixture.json>

var out_dir := "/tmp"


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = a[0] if a.size() > 0 else "/tmp"
	var fx := a[1] if a.size() > 1 else ""
	Game.settings.quality = "medium"
	Game.settings.tts = false
	Game.new_character({"first": "Maya", "last": "Okafor", "name": "Maya Okafor", "gender": "f", "age": 31, "path": "regional_fo"})
	var main_script: GDScript = load("res://src/main.gd")
	var main: Node = main_script.new()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	if fx != "":
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fx))
		News.deserialize(data.news)
		WorldSim.clock = float(data.clock)
	var day: Array = WorldSim.schedule_for_day(WorldSim.day_index())
	News.background_story("bird_strike_return", day[8], WorldSim.clock - 7200.0, 9)
	News.background_story("new_route", day[4], WorldSim.clock - 3600.0 * 30.0, 4)
	var target := {}
	for i in range(News.articles.size() - 1, -1, -1):
		var art: Dictionary = News.articles[i]
		if String(art.get("incident", "")) != "" and not (art.get("video", {}) as Dictionary).is_empty():
			target = art
			if String(art.get("kind", "")) == "breaking":
				break
	for art in [target, News.articles[News.articles.size() - 1]]:
		if art.is_empty():
			continue
		print("== %s | %s comments (of %d) | mood %s" % [art.headline, NewsComments.count(art), NewsComments.total(art), NewsComments.context(art).mood])
		for c in NewsComments.page(art, "top", 0, 14):
			print("  [%s] %s%s: %s  (♥%d, %d replies)" % [c.tone, c.author.name, (" (" + String(c.author.title) + ")") if String(c.author.title) != "" else "", c.text, c.likes, c.replies])
			if int(c.replies) > 0 and String(c.tone) in ["misinfo", "anger", "nervous"]:
				for r in NewsComments.replies(art, c, 0, 4):
					print("      %s└ %s: %s" % ["  " if int(r.depth) > 1 else "", r.author.name, r.text])
	if not target.is_empty():
		Game.goto("news", {"article": String(target.id), "play": true})
		await _wait(14.0)
		_shot("news_article")
		var sc := _scroll(main)
		if sc:
			sc.scroll_vertical = 1100
			await _wait(1.0)
			_shot("news_comments")
			sc.scroll_vertical = 2400
			await _wait(1.0)
			_shot("news_comments2")
	Game.goto("news", {"tab": "videos"})
	await _wait(10.0)
	_shot("news_videos")
	Game.goto("news", {"tab": "social"})
	await _wait(2.0)
	_shot("news_social")
	get_tree().quit()


func _scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer and (n as Control).is_visible_in_tree():
		return n
	for c in n.get_children():
		var s := _scroll(c)
		if s:
			return s
	return null


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
