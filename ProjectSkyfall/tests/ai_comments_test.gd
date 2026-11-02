extends Node
## AI comments without the network: checks the request we would send, parses canned Messages
## API responses (success, refusal, errors) and fills a comment section from a mocked reply.

func _ready() -> void:
	Game.settings.tts = false
	Game.settings.ai_comments = true
	Game.settings.ai_key = "sk-ant-TEST"
	Game.settings.ai_model = "claude-opus-5-5"
	WorldSim.clock = U.date_to_clock(2027, 6, 14, 15.0)
	var art := News.publish("skyline", "breaking", "BREAKING: Liberty Atlantic jet makes emergency landing at New York JFK",
		"A Liberty Atlantic W-350 from London returned safely after an engine failure.", ["Nobody was hurt."], {"importance": 2, "tags": ["incident"]})
	var req := AIComments.build_request("hello", {"type": "object"}, 6000)
	var pl: Dictionary = req[0]
	var hd: PackedStringArray = req[1]
	print("model ", pl.model, " effort ", pl.output_config.effort, " format ", pl.output_config.format.type, " fallbacks ", pl.get("fallbacks", "-"))
	for h in hd:
		print("  header ", h if not h.begins_with("x-api-key") else "x-api-key: (hidden)")
	print("  temperature sent: ", pl.has("temperature"))
	var good := {"id": "msg_1", "type": "message", "role": "assistant", "model": "claude-opus-5-5", "stop_reason": "end_turn",
		"content": [{"type": "thinking", "thinking": "", "signature": "x"}, {"type": "text", "text": JSON.stringify({"comments": [
			{"name": "Dana Ruiz", "handle": "@danaflies", "text": "Glad everyone walked off that one. Engine failures happen, the crew clearly trained for it.", "tone": "expert", "likes": 812,
				"replies": [{"name": "Tom Hale", "handle": "@tomh", "text": "Exactly. Twin engines exist for a reason.", "likes": 77}]},
			{"name": "Priya Nair", "handle": "priya_n", "text": "My sister was on this flight!! She says the captain was so calm.", "tone": "local", "likes": 1430, "replies": []}]})}]}
	print("parse ok: ", AIComments.parse_response(HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify(good).to_utf8_buffer()).slice(0, 1))
	print("refusal: ", AIComments.parse_response(HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({"stop_reason": "refusal", "content": []}).to_utf8_buffer())[2])
	print("401: ", AIComments.parse_response(HTTPRequest.RESULT_SUCCESS, 401, JSON.stringify({"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}}).to_utf8_buffer())[2])
	print("network: ", AIComments.parse_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())[2])
	AIComments.mock_body = JSON.stringify(good)
	var done := {"ok": false}
	AIComments.comments_for(art, 15, func(ok: bool, err: String): done.ok = ok; print("comments_for -> ", ok, " ", err))
	for i in 5:
		await get_tree().process_frame
	print("cached AI comments: ", (art.get("ai_comments", []) as Array).size(), " first handle ", art.ai_comments[1].handle if art.has("ai_comments") else "")
	# the comment section shows them, and the player's comment gets Claude replies
	var cs := CommentSection.new()
	add_child(cs)
	cs.setup(art)
	AIComments.mock_body = JSON.stringify({"stop_reason": "end_turn", "content": [{"type": "text", "text": JSON.stringify({"replies": [
		{"name": "Ana", "handle": "@ana", "text": "@you agreed, total pros.", "likes": 12}, {"name": "Ben", "handle": "@ben", "text": "Not sure I'd fly that type again though.", "likes": 3}]})}]})
	cs._input.text = "Massive respect to that crew."
	cs._post()
	for i in 5:
		await get_tree().process_frame
	var pc: Dictionary = art.player_comments[0]
	print("player comment replies from Claude: ", (pc.get("ai_replies", []) as Array).size(), "  cards in section: ", cs._list.get_child_count())
	print("AI COMMENTS TEST DONE")
	get_tree().quit()
