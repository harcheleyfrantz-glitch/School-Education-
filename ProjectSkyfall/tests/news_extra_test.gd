extends Node
## Runs 90 days of the extra news topics and prints headlines and sample comments per mood.
func _ready() -> void:
	Game.settings.tts = false
	WorldSim.clock = U.date_to_clock(2027, 7, 1, 8.0)
	var day0 := int(WorldSim.clock / 86400.0)
	var n0 := News.articles.size()
	for d in 90:
		NewsExtra.daily(day0 + d, U.rng(1000 + d))
	var arts := News.articles.slice(n0)
	print("articles: ", arts.size())
	var moods := {}
	for a in arts:
		var ctx := NewsComments.context(a)
		moods[ctx.mood] = int(moods.get(ctx.mood, 0)) + 1
	print("moods: ", moods)
	var shown := {}
	WorldSim.clock += 86400.0 * 120.0
	for a in arts:
		var m := String(NewsComments.context(a).mood)
		if shown.has(m):
			continue
		shown[m] = true
		print("\n== [%s] %s" % [m, a.headline])
		for c in NewsComments.page(a, "top", 0, 6):
			print("   - (%s) %s" % [c.tone, c.text])
			if String(c.text).contains("{"):
				print("   !! UNFILLED PLACEHOLDER")
	print("\nbank lines: ", CommentBankExtra.count(), " templated: ", CommentBankExtra.templated_count(), " combinations: ", CommentBankExtra.combinations())
	print("daily challenge today: ", Activities.daily_id())
	print("NEWS EXTRA TEST DONE")
	get_tree().quit()
