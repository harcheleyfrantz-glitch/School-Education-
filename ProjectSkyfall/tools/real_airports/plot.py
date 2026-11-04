import json, sys, base64, numpy as np
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon as MP
from matplotlib.collections import PolyCollection, LineCollection
def f32(s): return np.frombuffer(base64.b64decode(s), dtype="<f4")
def i32(s): return np.frombuffer(base64.b64decode(s), dtype="<i4")
src, icao, out = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open("%s/%s.json" % (src, icao)))
fig, ax = plt.subplots(figsize=(14, 14), dpi=110)
pv = f32(d["pave_v"]).reshape(-1, 2); pi = i32(d["pave_i"]).reshape(-1, 3)
ax.add_collection(PolyCollection(pv[pi], facecolor="#9a9a9a", edgecolor="none"))
for r in d["runways"]:
    a, b = np.array(r["a"]), np.array(r["b"]); dv = (b - a) / np.linalg.norm(b - a); n = np.array([-dv[1], dv[0]]) * r["wid"] / 2
    ax.add_patch(MP([a + n, b + n, b - n, a - n], color="#222"))
    ax.text(*a, r["id"].split("/")[0], color="red", fontsize=9)
nodes = f32(d["nodes"]).reshape(-1, 2); kinds = i32(d["kinds"]); ed = i32(d["edges"]).reshape(-1, 3)
segs = [[nodes[e[0]], nodes[e[1]]] for e in ed]
cols = ["#d4a000" if not d["names"][e[2]].startswith("RWY") else "#ff3333" for e in ed]
ax.add_collection(LineCollection(segs, colors=cols, linewidths=0.6))
h = nodes[kinds == 1]; ax.scatter(h[:, 0], h[:, 1], s=6, c="red", zorder=5)
for b in d["buildings"]:
    p = f32(b["p"]).reshape(-1, 2)
    ax.add_patch(MP(p, closed=True, facecolor={"terminal": "#ff9933", "garage": "#6666cc", "hangar": "#33aa66", "hotel": "#cc33cc", "cargo": "#888833"}.get(b["k"], "#8b5a2b"), edgecolor="black", lw=0.3, alpha=0.9))
for s in d["stands"]:
    f = np.array(s["f"]); n = np.array(s["d"])
    ax.plot([f[0], f[0] + n[0] * 50], [f[1], f[1] + n[1] * 50], color="blue" if s["br"] else "cyan", lw=0.8)
    ax.text(f[0] + n[0] * 55, f[1] + n[1] * 55, s["n"], fontsize=4, color="navy")
if d["tower"]: ax.scatter([d["tower"][0]], [d["tower"][1]], marker="*", s=200, c="red", zorder=6)
o = np.array(d["outline"]); ax.plot(np.r_[o[:, 0], o[0, 0]], np.r_[o[:, 1], o[0, 1]], "g--", lw=0.8)
ax.set_aspect("equal"); ax.invert_yaxis(); ax.autoscale()
ax.set_title(icao)
plt.savefig(out, bbox_inches="tight")
