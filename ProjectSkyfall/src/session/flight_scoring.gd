class_name FlightScoring
extends RefCounted
## Turns everything that happened on a flight into a debrief: category scores, a grade,
## remarks, pay and reputation consequences.

static func evaluate(d: Dictionary) -> Dictionary:
	var notes := []
	var cats := {}
	var td: Dictionary = d.get("touchdown", {})
	var rec: FlightRecorder = d.get("recorder")
	var outcome := String(d.get("outcome", "landed"))
	# ---- landing
	var landing := 0.0
	if not td.is_empty():
		var vs := absf(float(td.get("vs_fpm", 0.0)))
		var vs_s := 100.0 if vs < 240.0 else (88.0 if vs < 360.0 else (66.0 if vs < 480.0 else (40.0 if vs < 600.0 else 12.0)))
		if vs < 60.0:
			vs_s = 85.0
			notes.append("Very soft touchdown (%d fpm) - watch for floating long." % int(vs))
		elif vs < 240.0:
			notes.append("Smooth touchdown at %d fpm." % int(vs))
		elif vs >= 480.0:
			notes.append("Hard landing at %d fpm - a maintenance inspection is required." % int(vs))
		var cl := absf(float(td.get("centerline", 0.0)))
		var cl_s := 100.0 if cl < 2.0 else (85.0 if cl < 5.0 else (60.0 if cl < 10.0 else 25.0))
		if cl >= 5.0:
			notes.append("Touched down %.1f m from the centreline." % cl)
		var dist := float(td.get("dist_from_thr", 400.0))
		var tdz := 100.0 if dist > 150.0 and dist < 650.0 else (70.0 if dist < 950.0 and dist > 60.0 else 35.0)
		if dist >= 950.0:
			notes.append("Long landing: %d m beyond the threshold." % int(dist))
		elif dist < 60.0 and dist > -900.0:
			notes.append("Landed short: only %d m past the threshold." % int(dist))
		landing = vs_s * 0.55 + cl_s * 0.25 + tdz * 0.2
	elif outcome in ["crashed", "ditched"]:
		landing = 0.0
	else:
		landing = 50.0
	cats.landing = landing
	# ---- approach stability (1000 ft to 500 ft above the runway)
	var appr := 100.0
	var unstable := int(d.get("unstable_points", 0))
	if unstable > 0:
		appr -= minf(unstable * 6.0, 60.0)
		notes.append("Approach was not stabilised at 1000 ft.")
	var gas := int(d.get("go_arounds", 0))
	if gas > 0:
		notes.append("%d go-around(s) flown." % gas)
		appr -= 5.0 * gas
	cats.approach = clampf(appr, 0.0, 100.0)
	# ---- procedures
	var cl_frac: Array = d.get("checklists", [])
	var proc := 0.0
	for f in cl_frac:
		proc += float(f)
	proc = proc / maxf(cl_frac.size(), 1) * 100.0 if not cl_frac.is_empty() else 70.0
	if proc < 60.0:
		notes.append("Several checklists were skipped or incomplete.")
	cats.procedures = proc
	# ---- ATC compliance
	var atc := 100.0
	for dv in d.get("deviations", []):
		atc -= float(dv.severity) * 60.0
		notes.append("ATC: %s." % dv.text)
	cats.atc = clampf(atc, 0.0, 100.0)
	# ---- passenger comfort
	var comfort := 100.0
	if rec:
		comfort -= clampf((rec.max_nz - 1.45) * 60.0, 0.0, 40.0)
		comfort -= clampf((0.55 - rec.min_nz) * 60.0, 0.0, 40.0)
		comfort -= clampf((rec.max_bank - 32.0) * 2.0, 0.0, 30.0)
		if rec.max_bank > 40.0:
			notes.append("Bank angle reached %d degrees - passengers noticed." % int(rec.max_bank))
	var mood := float(d.get("mood", 1.0))
	comfort = comfort * 0.6 + mood * 40.0
	cats.comfort = clampf(comfort, 0.0, 100.0)
	# ---- efficiency and punctuality
	var late := float(d.get("late_min", 0.0))
	var eff := 100.0 - clampf(late - 5.0, 0.0, 60.0) * 1.2
	var fuel_ratio := float(d.get("fuel_ratio", 1.0))
	eff -= clampf((fuel_ratio - 1.08) * 150.0, 0.0, 30.0)
	if late > 15.0:
		notes.append("Arrived %d minutes behind schedule." % int(late))
	elif late < 3.0:
		notes.append("On-time arrival.")
	cats.efficiency = clampf(eff, 0.0, 100.0)
	# ---- safety and decision making
	var safety := 100.0
	for inc in d.get("incidents", []):
		match String(inc):
			"tailstrike":
				safety -= 35.0
				notes.append("Tail strike on rotation or landing.")
			"hard_landing":
				safety -= 20.0
			"gear_collapse":
				safety -= 60.0
			"wingstrike", "engine_strike":
				safety -= 40.0
			"overstress":
				safety -= 30.0
				notes.append("Airframe load limits were exceeded.")
			"runway_excursion":
				safety -= 50.0
	for ev in d.get("events", []):
		var sev := float(ev.get("severity", 0.0))
		if sev >= 0.5:
			if bool(d.get("emergency_declared", false)):
				safety += 5.0
			else:
				safety -= 10.0
				notes.append("%s handled without declaring an emergency." % String(ev.get("label", "Emergency")))
	if outcome == "crashed":
		safety = 0.0
	cats.safety = clampf(safety, 0.0, 100.0)
	var weights := {"landing": 0.22, "approach": 0.14, "procedures": 0.12, "atc": 0.14, "comfort": 0.12, "efficiency": 0.1, "safety": 0.16}
	var score := 0.0
	for k in weights.keys():
		score += float(cats.get(k, 0.0)) * float(weights[k])
	if outcome == "crashed":
		score = minf(score, 5.0)
	var grade := "A" if score >= 88.0 else ("B" if score >= 76.0 else ("C" if score >= 62.0 else ("D" if score >= 48.0 else "F")))
	var hours := float(d.get("block_hours", 1.0))
	var rate := float(d.get("pay_rate", 60.0))
	var pay := rate * hours
	var bonus := 0.0
	if score >= 85.0 and outcome == "landed":
		bonus = pay * 0.15
	var rep := clampf((score - 68.0) / 6.0, -6.0, 4.0)
	if outcome == "diverted":
		rep = minf(rep, 1.0)
	return {"score": score, "grade": grade, "categories": cats, "notes": notes, "pay": pay, "bonus": bonus,
		"reputation": rep, "hours": hours, "outcome": outcome}
