extends Node
## Renders the debrief screen for sample passenger and pilot results.


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.32, 0.45)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var r := U.rng(5)
	var reviews := []
	var ctx := {"landing_fpm": 150.0, "late_min": 3.0, "bumps": 1, "go_arounds": 0, "smooth": 88.0, "arr_city": "Rivermouth"}
	for i in 4:
		var p := Names.person(r, 20, 70)
		p.id = i * 31 + 7
		p.trait = ["chatty", "grumpy", "anxious", "cheerful"][i]
		reviews.append({"name": "%s %s." % [p.first, String(p.last).left(1)], "age": int(p.age), "home": p.home, "text": Dialogue.review(p, ctx)})
	var samples := {
		"pax": {"mode": "passenger", "outcome": "landed", "grade": "A", "score": 91.0, "hours": 0.62, "callsign": "Skyfall 451", "type": "s320",
			"reg": "CR-SKA", "dep": "SKPC", "arr": "SKRV", "ratings": {"smoothness": 86.0, "landing": 96.0, "punctuality": 95.0, "cabin": 88.0},
			"notes": ["A feather-light touchdown - a few people actually applauded.", "The flight was bumpy at times; the seat-belt sign came on once.", "On time."],
			"reviews": reviews},
		"pilot": {"mode": "pilot", "outcome": "landed", "grade": "B", "score": 82.0, "hours": 0.7, "callsign": "Skyfall 451", "type": "s320",
			"reg": "CR-SKA", "dep": "SKPC", "arr": "SKRV", "categories": {"landing": 92, "approach": 84, "procedures": 61, "atc": 90, "comfort": 88, "efficiency": 75, "safety": 95},
			"touchdown": {"vs_fpm": -160.0, "centerline": 1.2, "dist_from_thr": 420.0, "g": 1.12}, "notes": ["Smooth touchdown at 160 fpm.", "Several checklists were skipped or incomplete."],
			"pay": 412.0, "bonus": 50.0},
	}
	var dv_script: GDScript = load("res://src/ui/debrief_view.gd")
	for k in samples.keys():
		var dv: Control = dv_script.new()
		add_child(dv)
		dv.call("show_result", samples[k])
		for i in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("debrief_%s.png" % k))
		print("shot ", k)
		dv.queue_free()
	get_tree().quit()
