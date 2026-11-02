class_name AIComments
extends RefCounted
## Optional AI-written comment sections. With the player's own Anthropic API key (Options >
## News), Claude writes fresh comment threads under an article and answers the player's own
## comments. Requests go straight from the game to the Claude Messages API over HTTPS; results
## are cached in the article so each costs one request. Without a key the game keeps its
## built-in comment generator.

const URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2026-10-21"
const MODELS := [["claude-opus-5-5", "Claude Opus 5.5 (best writing)"], ["claude-sonnet-5-5", "Claude Sonnet 5.5 (balanced)"],
	["claude-haiku-5-5", "Claude Haiku 5.5 (cheapest, fastest)"]]
const TONES := ["sad", "angry", "curious", "expert", "funny", "local", "sceptical", "kind"]

static var _busy := {}         # article id -> true while a request is out


static func enabled() -> bool:
	return bool(Game.settings.get("ai_comments", false)) and api_key() != ""


static func api_key() -> String:
	return String(Game.settings.get("ai_key", "")).strip_edges()


static func model() -> String:
	var m := String(Game.settings.get("ai_model", "claude-opus-5-5"))
	for row in MODELS:
		if row[0] == m:
			return m
	return "claude-opus-5-5"


static func busy(art: Dictionary) -> bool:
	return _busy.has(String(art.get("id", "")))


## Fresh comment threads for an article. done(ok: bool, error: String) runs when finished;
## the comments land in art["ai_comments"].
static func comments_for(art: Dictionary, count: int, done: Callable) -> void:
	var id := String(art.get("id", ""))
	if _busy.has(id):
		return
	_busy[id] = true
	var reply_item := {"type": "object", "additionalProperties": false, "required": ["name", "handle", "text", "likes"],
		"properties": {"name": {"type": "string"}, "handle": {"type": "string"}, "text": {"type": "string"}, "likes": {"type": "integer"}}}
	var schema := {"type": "object", "additionalProperties": false, "required": ["comments"], "properties": {
		"comments": {"type": "array", "items": {"type": "object", "additionalProperties": false,
			"required": ["name", "handle", "text", "tone", "likes", "replies"],
			"properties": {"name": {"type": "string"}, "handle": {"type": "string"}, "text": {"type": "string"},
				"tone": {"type": "string", "enum": TONES}, "likes": {"type": "integer"}, "replies": {"type": "array", "items": reply_item}}}}}}
	var prompt := "%s\n\nWrite %d top-level comments for this story's comment section. About a third should have 1 to 3 replies from other readers (agreeing, arguing, adding detail or correcting someone). Mix the voices: grieving or sympathetic readers when people were hurt, angry or sceptical ones, curious questions, a pilot or engineer with a measured technical view, locals who saw or heard something, and light humour only when nobody was hurt. Vary the length from a few words to three sentences. Likes: popular comments in the hundreds or thousands, most under fifty." % [_story_brief(art), count]
	_request(prompt, schema, 6000, func(ok: bool, data: Dictionary, err: String):
		_busy.erase(id)
		if ok:
			var out: Array = art.get("ai_comments", [])
			var t0 := float(art.get("t", WorldSim.clock))
			var k := 0
			for c in data.get("comments", []):
				if typeof(c) != TYPE_DICTIONARY or String(c.get("text", "")).strip_edges() == "":
					continue
				k += 1
				var reps := []
				for rp in c.get("replies", []):
					if typeof(rp) == TYPE_DICTIONARY and String(rp.get("text", "")) != "":
						reps.append({"name": _clean(String(rp.get("name", "Reader")), 40), "handle": _handle(String(rp.get("handle", ""))),
							"text": _clean(String(rp.get("text", "")), 600), "likes": clampi(int(rp.get("likes", 0)), 0, 99999)})
				out.append({"name": _clean(String(c.get("name", "Reader")), 40), "handle": _handle(String(c.get("handle", ""))),
					"text": _clean(String(c.get("text", "")), 700), "tone": String(c.get("tone", "kind")), "likes": clampi(int(c.get("likes", 0)), 0, 999999),
					"replies": reps, "t": minf(t0 + 300.0 + k * 517.0, maxf(WorldSim.clock, t0 + 60.0))})
			art["ai_comments"] = out
		if done.is_valid():
			done.call(ok, err))


## Replies from other readers to something the player wrote; they land in pc["ai_replies"].
static func replies_to(art: Dictionary, pc: Dictionary, done: Callable) -> void:
	var schema := {"type": "object", "additionalProperties": false, "required": ["replies"], "properties": {
		"replies": {"type": "array", "items": {"type": "object", "additionalProperties": false, "required": ["name", "handle", "text", "likes"],
			"properties": {"name": {"type": "string"}, "handle": {"type": "string"}, "text": {"type": "string"}, "likes": {"type": "integer"}}}}}}
	var who := String(pc.get("name", "A reader"))
	var prompt := "%s\n\nA reader called %s just posted this comment under the story:\n\"%s\"\n\nWrite 3 to 5 replies from other readers who respond directly to what %s said: some agree, some push back or ask a question, maybe one adds something they know. Keep each reply under three sentences and address %s naturally (by @handle or by name) in at least one of them." % [
		_story_brief(art), who, _clean(String(pc.get("text", "")), 500), who, who]
	pc["ai_pending"] = true
	_request(prompt, schema, 3000, func(ok: bool, data: Dictionary, err: String):
		pc.erase("ai_pending")
		if ok:
			var reps := []
			var k := 0
			for rp in data.get("replies", []):
				if typeof(rp) == TYPE_DICTIONARY and String(rp.get("text", "")) != "":
					k += 1
					reps.append({"name": _clean(String(rp.get("name", "Reader")), 40), "handle": _handle(String(rp.get("handle", ""))),
						"text": _clean(String(rp.get("text", "")), 600), "likes": clampi(int(rp.get("likes", 0)), 0, 99999),
						"t": float(pc.get("t", WorldSim.clock)) + k * 140.0})
			pc["ai_replies"] = reps
		if done.is_valid():
			done.call(ok, err))


## A tiny request to check the key and model work.
static func test_key(done: Callable) -> void:
	var schema := {"type": "object", "additionalProperties": false, "required": ["reply"], "properties": {"reply": {"type": "string"}}}
	_request("Reply with a one-line greeting to a pilot who just switched on AI comments.", schema, 1200, func(ok: bool, data: Dictionary, err: String):
		if done.is_valid():
			done.call(ok, String(data.get("reply", "")) if ok else err))


# ------------------------------------------------------------------ request plumbing
static func _system() -> String:
	return ("You write the reader comments under articles in Project Skyfall, an aviation life simulator. The world mixes the fictional "
		+ "countries of Calderra and Westmark with real cities such as New York, London and Paris; airlines, people and events in the "
		+ "stories are fictional. Commenters are fictional members of the public with invented names and handles. Write like real people "
		+ "on a news site: natural, specific to the story's details, sometimes informal, never like an announcer. Plain text only: no emoji, "
		+ "no markdown, no hashtags except the odd one. Do not name real living people. Be respectful about victims; no slurs or graphic gore.")


static func _story_brief(art: Dictionary) -> String:
	var o: Dictionary = News.OUTLETS.get(String(art.get("outlet", "")), {})
	var lines := ["Story from %s, published %s:" % [String(o.get("name", "a news site")), U.fmt_date(float(art.get("t", WorldSim.clock)))],
		"Headline: " + String(art.get("headline", ""))]
	if String(art.get("lede", "")) != "":
		lines.append("Summary: " + String(art.lede))
	for b in art.get("body", []):
		lines.append("- " + String(b))
	var inc := News.incident(String(art.get("incident", "")))
	if not inc.is_empty():
		var c: Dictionary = inc.get("counts", {})
		var tpl := AircraftTypes.get_type(String(inc.get("type", "s320")))
		lines.append("Facts: flight %s, %s %s, %s; %d aboard, %d killed. Probable cause so far: %s." % [String(inc.get("num", "")),
			String(Airlines.get_al(String(inc.get("airline", ""))).get("name", "")), String(tpl.get("name", "")), String(inc.get("place", "")),
			int(c.get("aboard", 0)), int(c.get("fatal", 0)), String(inc.get("cause", "under investigation")) if String(inc.get("cause", "")) != "" else "under investigation"])
	var tags: Array = art.get("tags", [])
	if not tags.is_empty():
		lines.append("Topics: " + ", ".join(tags.map(func(t): return String(t))))
	return "\n".join(lines)


static var mock_body := ""      # tests: answer every request with this body instead of calling out


## The Messages API request: [payload, headers].
static func build_request(prompt: String, schema: Dictionary, max_tokens: int) -> Array:
	var m := model()
	var payload := {
		"model": m,
		"max_tokens": max_tokens,
		"system": _system(),
		"messages": [{"role": "user", "content": prompt}],
		# short creative writing: low effort keeps it quick; the schema guarantees parseable JSON
		"output_config": {"effort": "low", "format": {"type": "json_schema", "schema": schema}},
	}
	var headers := PackedStringArray(["content-type: application/json", "x-api-key: " + api_key(), "anthropic-version: " + API_VERSION])
	if m in ["claude-opus-5-5", "claude-sonnet-5-5"]:
		# if a safety classifier declines, the API re-runs the request on its recommended model
		payload["fallbacks"] = "default"
		headers.append("anthropic-beta: server-side-fallback-2026-07-01")
	return [payload, headers]


## Reads a Messages API response: [ok, parsed JSON output, error message].
static func parse_response(result: int, code: int, body: PackedByteArray) -> Array:
	if result != HTTPRequest.RESULT_SUCCESS:
		return [false, {}, "Couldn't reach the Claude API (network error %d)." % result]
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if code != 200:
		var msg := "The Claude API returned an error (%d)." % code
		if typeof(data) == TYPE_DICTIONARY and typeof(data.get("error")) == TYPE_DICTIONARY:
			msg = String(data.error.get("message", msg))
		match code:
			401:
				msg = "The API key was rejected. Check it in Options > News & AI."
			403:
				msg = "This API key isn't allowed to use %s." % model()
			429:
				msg = "Rate limited by the Claude API. Try again in a minute."
			529:
				msg = "The Claude API is busy right now. Try again shortly."
		return [false, {}, msg]
	if typeof(data) != TYPE_DICTIONARY:
		return [false, {}, "Couldn't read the Claude API response."]
	var stop := String(data.get("stop_reason", ""))
	if stop == "refusal":
		return [false, {}, "Claude declined to write comments for this story."]
	if stop == "max_tokens":
		return [false, {}, "The reply was cut off. Try again."]
	# thinking blocks come first (empty by default); the answer is in the text blocks
	var text := ""
	for blk in data.get("content", []):
		if typeof(blk) == TYPE_DICTIONARY and String(blk.get("type", "")) == "text":
			text += String(blk.get("text", ""))
	var out: Variant = JSON.parse_string(text)
	if typeof(out) != TYPE_DICTIONARY:
		return [false, {}, "Couldn't read the comments Claude wrote."]
	return [true, out, ""]


static func _request(prompt: String, schema: Dictionary, max_tokens: int, done: Callable) -> void:
	if api_key() == "":
		done.call(false, {}, "Add your Anthropic API key in Options > News & AI first.")
		return
	var req := build_request(prompt, schema, max_tokens)
	if mock_body != "":
		var mres := parse_response(HTTPRequest.RESULT_SUCCESS, 200, mock_body.to_utf8_buffer())
		(func(): done.call(mres[0], mres[1], mres[2])).call_deferred()
		return
	var http := HTTPRequest.new()
	http.timeout = 150.0
	Game.add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		var res := parse_response(result, code, body)
		done.call(res[0], res[1], res[2]))
	var err := http.request(URL, req[1], HTTPClient.METHOD_POST, JSON.stringify(req[0]))
	if err != OK:
		http.queue_free()
		done.call(false, {}, "Couldn't start the request (error %d)." % err)


static func _clean(s: String, max_len: int) -> String:
	var t := s.strip_edges().replace("\n\n", "\n")
	return t.substr(0, max_len)


static func _handle(h: String) -> String:
	var t := h.strip_edges().replace(" ", "")
	if t == "":
		t = "reader%d" % (randi() % 9000 + 100)
	return t if t.begins_with("@") else "@" + t
