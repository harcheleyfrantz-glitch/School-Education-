extends Node
func _ready() -> void:
	print("bank lines: ", CommentBank.count())
	var day: Array = WorldSim.schedule_for_day(WorldSim.day_index())
	News.background_story("bird_strike_return", day[8], WorldSim.clock - 7200.0, 9)
	var art: Dictionary = News.articles[News.articles.size() - 1]
	for c in NewsComments.page(art, "top", 0, 8):
		print("  ", c.text)
	for txt in ["RIP to everyone, so sad", "Why did they turn back?", "The airline should be ashamed", "lol bird vs plane"]:
		var pc := {"name": "Maya Okafor", "text": txt, "t": WorldSim.clock - 7200.0}
		print("ME: ", txt)
		for r in NewsComments.player_replies(art, pc):
			print("   └ %s: %s" % [r.author.name, r.text])
	get_tree().quit()
