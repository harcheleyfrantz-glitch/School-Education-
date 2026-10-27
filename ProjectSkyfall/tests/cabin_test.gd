extends Node
## Prints the computed cabin layout of every type (headless).

func _ready() -> void:
	for t in AircraftTypes.ORDER:
		var lay := CabinLayout.get_layout(t)
		var spec := AircraftTypes.get_type(t)
		var exp := AircraftTypes.seat_count(t)
		var first = lay.seats[0] if lay.seats.size() > 0 else {}
		var last = lay.seats[lay.seats.size() - 1] if lay.seats.size() > 0 else {}
		print("%s: seats %d (expected %d) floor %.2f ceil %.2f nose %.1f ck_back %.1f cabin %.1f..%.1f aisles %s" % [
			t, lay.seats.size(), exp, lay.floor_y, lay.ceil_y, lay.nose_z, lay.cockpit.back_z, lay.get("cabin_front", 0.0), lay.get("cabin_back", 0.0), str(lay.aisles)])
		if not first.is_empty():
			print("   first %s at z=%.2f x=%.2f  last %s at z=%.2f x=%.2f   rows=%d windows=%d" % [first.id, first.pos.z, first.pos.x, last.id, last.pos.z, last.pos.x, lay.rows.size(), lay.windows.size()])
		for d in lay.doors:
			if d.side < 0:
				print("   door %s z=%.2f x=%.2f kind=%s" % [d.name, d.z, d.x, d.kind])
		for r in lay.rows:
			if r.exit or r.row <= 1:
				print("   row %d z %.2f..%.2f pitch %.2f seat_w %.2f aisles %s exit=%s" % [r.row, r.z0, r.z1, r.pitch, r.seat_w, str(r.aisles), str(r.exit)])
	get_tree().quit()
