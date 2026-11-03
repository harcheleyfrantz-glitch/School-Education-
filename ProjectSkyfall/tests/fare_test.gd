extends Node
func _ready() -> void:
	for r in [["VTX", "SKOF", "SKPC"], ["SKF", "SKPC", "SKRV"], ["LBA", "KJFK", "EGLL"], ["AUR", "WMSK", "EGLL"], ["APX", "KLAX", "KLAS"], ["SOL", "LEMD", "LEBL"]]:
		var nm := Airports.distance_nm(r[1], r[2])
		print("FARE %s %s-%s %4.0f nm: economy %s  business %s" % [r[0], r[1], r[2], nm, U.fmt_money(Airlines.fare(r[0], nm)), U.fmt_money(Airlines.fare(r[0], nm, "business"))])
	get_tree().quit()
