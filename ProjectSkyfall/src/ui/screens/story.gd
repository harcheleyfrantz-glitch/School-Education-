extends ScreenBase
## STORY MODE: "Wings of Calderra", five chapters in order. Each opens with an in-engine cutscene,
## flies its mission and closes with a scene of its own. A chapter's flight result arrives here
## (story_result): success plays the closing scene and unlocks the next chapter.


func setup(params: Dictionary) -> void:
	if params.has("story_result"):
		var act: Dictionary = params.story_result
		var ch := Story.chapter_of(String(act.get("id", "")))
		if ch >= 0 and bool(act.get("complete", false)):
			Story.mark_done(ch)
			Game.goto("cutscene", {"chapter": ch, "part": "outro"})
			return
		elif ch >= 0:
			Game.notify("Chapter %s not complete - give it another go." % String(Story.CHAPTERS[ch].num), "warning")
	page("menu", "soft")
	var root := UIStyle.vbox(14)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(root)
	var head := UIStyle.vbox(2)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	head.add_child(UIStyle.caps("Story mode", 13, UIStyle.ACCENT, 800, 3))
	head.add_child(UIStyle.title(Story.TITLE, 40, Color.WHITE))
	var sub := UIStyle.label("From your first solo to the first ever arrival at the biggest airport in the world. %d of %d chapters complete." % [Story.done_count(), Story.CHAPTERS.size()], 15, UIStyle.DIM)
	head.add_child(sub)
	var row := UIStyle.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(row)
	for i in Story.CHAPTERS.size():
		row.add_child(_chapter_card(i))


func _chapter_card(i: int) -> Control:
	var ch: Dictionary = Story.CHAPTERS[i]
	var open := Story.unlocked(i)
	var done := Story.is_done(i)
	var col := UIStyle.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var opts := {"icon_name": "star" if done else ("play" if open else "lock")}
	if done:
		opts.ribbon = "COMPLETE"
		opts.ribbon_color = UIStyle.GREEN
	elif open:
		opts.ribbon = "PLAY"
		opts.ribbon_color = UIStyle.ACCENT
	else:
		opts.ribbon = "LOCKED"
		opts.ribbon_color = UIStyle.DIM
	var card := ImageCard.make("%s. %s" % [String(ch.num), String(ch.title)], String(ch.place), "scn:" + String(ch.id),
		func(): _play(i), opts)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(card)
	var syn := UIStyle.label(String(ch.synopsis) if open else "Complete chapter %s to unlock." % String(Story.CHAPTERS[i - 1].num), 13, UIStyle.DIM)
	syn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	syn.custom_minimum_size = Vector2(0, 54)
	col.add_child(syn)
	var h := UIStyle.hbox(6)
	col.add_child(h)
	var play := UIStyle.button("Play" if not done else "Play again", func(): _play(i), 0, UIStyle.ACCENT)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.disabled = not open
	h.add_child(play)
	if done:
		var ending := UIStyle.button("Ending", func(): Game.goto("cutscene", {"chapter": i, "part": "outro"}), 0)
		h.add_child(ending)
	elif open:
		var fly := UIStyle.button("Skip scene", func(): Activities.launch(Activities.get_scenario(String(ch.id))), 0)
		h.add_child(fly)
	return col


func _play(i: int) -> void:
	if not Story.unlocked(i):
		Game.notify("Finish chapter %s first." % String(Story.CHAPTERS[i - 1].num), "info")
		return
	Game.goto("cutscene", {"chapter": i, "part": "intro"})
