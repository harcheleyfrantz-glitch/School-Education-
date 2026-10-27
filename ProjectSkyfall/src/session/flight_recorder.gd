class_name FlightRecorder
extends RefCounted
## Flight data recorder (twice a second) and cockpit voice transcript. Feeds the debrief
## graphs, accident investigation, news reconstructions and in-engine replays.

var samples: Array = []        # [t, x, z, alt, ias, vs, pitch, bank, hdg, thr, flap, gear, ap, phase_idx, nz, gs]
var events: Array = []         # {t, kind, text}
var cvr: Array = []            # {t, who, text}
var phases: Array = []         # phase names indexed by samples
var t := 0.0
var _acc := 0.0
var max_nz := 1.0
var min_nz := 1.0
var max_bank := 0.0
var max_ias_exceed := 0.0
var max_turb := 0.0


func record(ac: Aircraft, phase: String, dt: float) -> void:
	t += dt
	_acc += dt
	var nz: float = ac.nz_filtered
	max_nz = maxf(max_nz, nz)
	min_nz = minf(min_nz, nz)
	max_bank = maxf(max_bank, absf(ac.fdm.bank_deg()))
	max_turb = maxf(max_turb, ac.turbulence)
	if _acc < 0.5:
		return
	_acc = 0.0
	var pi := phases.find(phase)
	if pi < 0:
		phases.append(phase)
		pi = phases.size() - 1
	var n := ac.nav_state()
	var vmo := float(ac.spec.vmo)
	max_ias_exceed = maxf(max_ias_exceed, float(n.ias_kt) - vmo)
	samples.append([snappedf(t, 0.1), float(n.x), float(n.z), snappedf(float(n.alt), 0.1), snappedf(float(n.ias_kt), 0.1),
		snappedf(float(n.vs), 0.01), snappedf(float(n.pitch), 0.01), snappedf(float(n.bank), 0.01), snappedf(float(n.hdg), 0.1),
		snappedf(ac.throttle_lever, 0.01), ac.sys.flap_lever, 1 if ac.sys.gear_down_cmd else 0, 1 if ac.ap.engaged else 0, pi,
		snappedf(nz, 0.01), snappedf(ac.fdm.ground_speed(), 0.1)])


func mark(kind: String, text: String) -> void:
	events.append({"t": t, "kind": kind, "text": text, "clock": WorldSim.clock})


func voice(who: String, text: String) -> void:
	cvr.append({"t": t, "who": who, "text": text})


func last(n: int) -> Array:
	return samples.slice(maxi(samples.size() - n, 0))


## Compact copy for saving with an accident record (every 4th sample, last 30 minutes full).
func export() -> Dictionary:
	var keep := []
	var cut := samples.size() - 3600
	for i in samples.size():
		if i >= cut or i % 4 == 0:
			keep.append(samples[i])
	return {"samples": keep, "events": events.duplicate(true), "cvr": cvr.slice(maxi(cvr.size() - 200, 0)), "phases": phases.duplicate()}
