class_name PilotLevel
extends RefCounted
## Pilot level and experience for the profile: XP from logged hours, flights and landings in the
## career plus completed activities and their medals.

const XP_HOUR := 10.0
const XP_FLIGHT := 40.0
const XP_LANDING := 25.0
const XP_ACTIVITY := 150.0
const XP_MEDAL := {"gold": 250.0, "silver": 150.0, "bronze": 80.0}
const MAX_LEVEL := 99


## Cumulative XP needed to reach a level.
static func xp_for(level: int) -> float:
	if level <= 1:
		return 0.0
	return roundf(400.0 * pow(float(level - 1), 1.5))


static func compute(p: Dictionary = Game.player) -> Dictionary:
	var xp := 0.0
	var hours := 0.0
	if not p.is_empty():
		hours = float(p.get("hours", 0.0))
		xp += hours * XP_HOUR + float(p.get("flights", 0)) * XP_FLIGHT + float(p.get("landings", 0)) * XP_LANDING
	var acts := 0
	var medals := {"gold": 0, "silver": 0, "bronze": 0}
	var recs := Activities.records()
	for id in recs.keys():
		var r: Dictionary = recs[id]
		if int(r.get("done", 0)) > 0:
			acts += 1
			xp += XP_ACTIVITY
			var m := String(r.get("medal", ""))
			if medals.has(m):
				medals[m] = int(medals[m]) + 1
				xp += float(XP_MEDAL[m])
	var level := 1
	while level < MAX_LEVEL and xp >= xp_for(level + 1):
		level += 1
	var a := xp_for(level)
	var b := xp_for(level + 1)
	return {"level": level, "xp": xp, "from": a, "to": b, "progress": clampf((xp - a) / maxf(b - a, 1.0), 0.0, 1.0),
		"hours": hours, "activities": acts, "medals": medals}
