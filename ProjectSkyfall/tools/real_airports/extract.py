import csv, json, os, sys, time, math
from concurrent.futures import ThreadPoolExecutor
import pyarrow.parquet as pq
import shapely.wkb, shapely.geometry
from ovt import list_keys, RangeFile, rg_bboxes, REL
APS = sys.argv[1].split(",")
MARGIN_KM = 2.6
# airport bbox from runway ends (OurAirports)
bb = {}
for r in csv.DictReader(open("runways.csv", encoding="utf-8")):
    a = r["airport_ident"]
    if a not in APS: continue
    for e in ("le", "he"):
        try:
            la = float(r[e + "_latitude_deg"]); lo = float(r[e + "_longitude_deg"])
        except ValueError:
            continue
        b = bb.setdefault(a, [lo, la, lo, la])
        b[0] = min(b[0], lo); b[1] = min(b[1], la); b[2] = max(b[2], lo); b[3] = max(b[3], la)
for a, b in bb.items():
    lat = (b[1] + b[3]) * 0.5
    dlo = MARGIN_KM / (111.32 * math.cos(math.radians(lat))); dla = MARGIN_KM / 110.57
    bb[a] = [b[0] - dlo, b[1] - dla, b[2] + dlo, b[3] + dla]
missing = [a for a in APS if a not in bb]
print("bbox for", len(bb), "missing", missing, flush=True)
json.dump(bb, open("bbox.json", "w"))

def hits(rgb):
    out = []
    for i, r in enumerate(rgb):
        if r is None: continue
        x0, y0, x1, y1, n = r
        for a, b in bb.items():
            if x0 <= b[2] and x1 >= b[0] and y0 <= b[3] and y1 >= b[1]:
                out.append(i); break
    return out

def scan(theme, cols, keep):
    keys = list_keys(REL + theme)
    print(theme, len(keys), "files", flush=True)
    res = {a: [] for a in bb}
    stats = {"rg": 0, "bytes": 0}
    def one(ks):
        k, sz = ks
        f = RangeFile(k, sz)
        pf = pq.ParquetFile(f)
        rgs = hits(rg_bboxes(pf))
        local = {a: [] for a in bb}
        for i in rgs:
            t = pf.read_row_group(i, columns=cols).to_pylist()
            for row in t:
                bx = row["bbox"]
                for a, b in bb.items():
                    if bx["xmin"] <= b[2] and bx["xmax"] >= b[0] and bx["ymin"] <= b[3] and bx["ymax"] >= b[1]:
                        if keep(row):
                            g = shapely.wkb.loads(row["geometry"])
                            row = {k2: v for k2, v in row.items() if k2 not in ("geometry", "bbox")}
                            row["geom"] = shapely.geometry.mapping(g)
                            local[a].append(row)
        return local, len(rgs), f.nbytes
    with ThreadPoolExecutor(12) as ex:
        for local, nrg, nb in ex.map(one, keys):
            stats["rg"] += nrg; stats["bytes"] += nb
            for a in local:
                res[a].extend(local[a])
    print(theme, "row groups read", stats["rg"], "MB", stats["bytes"] / 1e6, flush=True)
    return res

def jsonable(o):
    if isinstance(o, dict): return {k: jsonable(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)): return [jsonable(v) for v in o]
    return o

os.makedirs("ovt", exist_ok=True)
t0 = time.time()
if "infra" in sys.argv[2]:
    inf = scan("theme=base/type=infrastructure/", ["geometry", "bbox", "subtype", "class", "names", "source_tags", "height", "surface", "level"],
        lambda r: r["subtype"] == "airport" or any(k.startswith("aeroway") for k, _ in (r["source_tags"] or [])))
    for a, rows in inf.items():
        for r in rows:
            r["source_tags"] = dict(r["source_tags"] or [])
            nm = r.get("names") or {}
            r["names"] = nm.get("primary") if isinstance(nm, dict) else None
        json.dump(jsonable(rows), open("ovt/%s_infra.json" % a, "w"))
        print(a, "infra", len(rows))
    print("infra done", time.time() - t0, flush=True)
if "bldg" in sys.argv[2]:
    bl = scan("theme=buildings/type=building/", ["geometry", "bbox", "subtype", "class", "names", "height", "num_floors", "roof_shape", "roof_height", "facade_color", "roof_color", "is_underground", "has_parts", "level", "min_height"],
        lambda r: not r.get("is_underground"))
    for a, rows in bl.items():
        for r in rows:
            nm = r.get("names") or {}
            r["names"] = nm.get("primary") if isinstance(nm, dict) else None
        json.dump(jsonable(rows), open("ovt/%s_bldg.json" % a, "w"))
        print(a, "bldg", len(rows))
    print("bldg done", time.time() - t0, flush=True)
