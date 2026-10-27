class_name CockpitDisplays
extends Control
## Paints every flight-deck screen into one atlas texture (a SubViewport). Each cell is a
## Rect2 in pixels with a display kind; the cockpit maps quads onto the cells.

var ac: Aircraft
var cells: Array = []        # [{kind, rect}]
var nd_range := 40.0
var sd_page := "CRUISE"
var traffic: Array = []
var powered := true


func _draw() -> void:
	if ac == null:
		return
	for c in cells:
		var r: Rect2 = c.rect
		if not powered:
			draw_rect(r, Color(0.01, 0.012, 0.014))
			continue
		match String(c.kind):
			"pfd":
				InstrumentPainter.pfd(self, r, ac)
			"nd":
				InstrumentPainter.nd(self, r, ac, nd_range, traffic)
			"eicas":
				InstrumentPainter.eicas(self, r, ac)
			"sd":
				InstrumentPainter.sd(self, r, ac, _auto_page())
			"mcp":
				InstrumentPainter.mcp(self, r, ac)
			"isis":
				InstrumentPainter.pfd(self, r, ac, false)
			"ga":
				InstrumentPainter.ga_panel(self, r, ac)
			"ga_engine":
				InstrumentPainter.ga_engine(self, r, ac)
			"mcdu":
				_mcdu(r)
			"radio":
				_radio(r)


func _auto_page() -> String:
	if sd_page != "AUTO":
		return sd_page
	if ac.fdm.on_ground and ac.sys.running_engines() == 0:
		return "DOOR"
	if ac.fdm.on_ground and ac.fdm.ground_speed() > 3.0:
		return "WHEEL"
	return "CRUISE"


func _mcdu(r: Rect2) -> void:
	draw_rect(r, Color(0.01, 0.012, 0.014))
	var fs := int(r.size.y * 0.075)
	var g := InstrumentPainter.GREEN
	var w := InstrumentPainter.WHITE
	var cy := InstrumentPainter.CYAN
	var f := InstrumentPainter.mono()
	InstrumentPainter.text(self, r.position + Vector2(r.size.x * 0.5, fs), "F-PLN", fs, w, HORIZONTAL_ALIGNMENT_CENTER, -1.0, f)
	var plan: Array = ac.ap.plan
	var y := r.position.y + fs * 2.6
	var n := ac.nav_state()
	for i in range(ac.ap.leg, mini(ac.ap.leg + 5, plan.size())):
		var wp: Dictionary = plan[i]
		var d := U.dist2d(float(n.x), float(n.z), float(wp.x), float(wp.z)) / U.NM
		InstrumentPainter.text(self, Vector2(r.position.x + 6, y), String(wp.name), fs, g if i == ac.ap.leg else w, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f)
		InstrumentPainter.text(self, Vector2(r.end.x - 6, y), "%d NM" % int(d), fs, cy, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, f)
		y += fs * 1.6
	InstrumentPainter.text(self, Vector2(r.position.x + 6, r.end.y - fs * 2.2), "FOB %.1f T" % (ac.sys.fuel_total() / 1000.0), fs, g, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f)
	InstrumentPainter.text(self, Vector2(r.end.x - 6, r.end.y - fs * 2.2), "GW %.1f T" % (ac.total_mass() / 1000.0), fs, g, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, f)
	InstrumentPainter.text(self, Vector2(r.position.x + r.size.x * 0.5, r.end.y - fs * 0.8), "CRZ FL%03d" % int(ac.ap.alt_sel / U.FT / 100.0), fs, cy, HORIZONTAL_ALIGNMENT_CENTER, -1.0, f)


func _radio(r: Rect2) -> void:
	draw_rect(r, Color(0.0, 0.0, 0.0))
	var fs := int(r.size.y * 0.5)
	var amber := Color(1.0, 0.6, 0.12)
	var freq := String(ac.get_meta("com1", "121.500"))
	var sq := String(ac.sys.squawk)
	InstrumentPainter.text(self, r.position + Vector2(r.size.x * 0.27, r.size.y * 0.5), freq, fs, amber, HORIZONTAL_ALIGNMENT_CENTER, -1.0, InstrumentPainter.mono())
	InstrumentPainter.text(self, r.position + Vector2(r.size.x * 0.78, r.size.y * 0.5), sq, fs, amber, HORIZONTAL_ALIGNMENT_CENTER, -1.0, InstrumentPainter.mono())
