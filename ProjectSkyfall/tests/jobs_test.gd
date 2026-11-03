extends Node
func _ready() -> void:
	for h in [300.0, 1500.0, 4000.0, 9000.0]:
		var p := {"hours": h, "reputation": 70.0, "safety": 80.0, "airline": "CLK", "rank": "First Officer", "ratings": ["t172", "tp72"]}
		var o := CareerRules.hiring_offers(p)
		var caps := o.filter(func(x): return x.rank == "Captain").size()
		var usa := o.filter(func(x): return Airports.get_ap(String(x.base)).get("country", "") == "United States").size()
		print("JOBS %5.0fh: %d offers (%d captain, %d in the USA), e.g. %s" % [h, o.size(), caps, usa, str(o.slice(0, 3).map(func(x): return "%s %s %s" % [x.airline, x.rank, x.type]))])
	get_tree().quit()
