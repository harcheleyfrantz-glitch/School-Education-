#!/usr/bin/env python3
"""Builds one-to-one airport layouts for Project Skyfall from open data.

Inputs (see fetch.py / extract.py):
  runways.csv            OurAirports runways (public domain): runway ends, widths, surfaces
  apt.dat.gz             FlightGear airport database (X-Plane format, GPL): pavement outlines, tower
  ovt/ICAO_infra.json    Overture Maps infrastructure (OpenStreetMap, ODbL): taxiways with names,
                         aprons, gates, aerodrome boundary
  ovt/ICAO_bldg.json     Overture Maps buildings (OpenStreetMap and others, ODbL): footprints, heights

Output: data/real_airports/ICAO.json per airport (airport-local metres, x = east, z = south),
big arrays packed as base64 float32/int32, plus runways.json for src/data/airports.gd.

Usage: python3 convert.py SRC_DIR OUT_DIR ICAO[,ICAO...]
"""
import base64, csv, gzip, json, math, os, re, sys
import numpy as np
import shapely
from shapely.geometry import shape, LineString, Polygon, MultiPolygon, Point, MultiLineString, box
from shapely.ops import unary_union, transform, nearest_points
from shapely.strtree import STRtree
import mapbox_earcut as earcut

SRC, OUT = sys.argv[1], sys.argv[2]
APS = sys.argv[3].split(",")
os.makedirs(OUT, exist_ok=True)


def mpd(lat):
    la = math.radians(lat)
    mlat = 111132.92 - 559.82 * math.cos(2 * la) + 1.175 * math.cos(4 * la)
    mlon = 111412.84 * math.cos(la) - 93.5 * math.cos(3 * la)
    return mlat, mlon


def b64f(a):
    return base64.b64encode(np.asarray(a, dtype="<f4").tobytes()).decode()


def b64i(a):
    return base64.b64encode(np.asarray(a, dtype="<i4").tobytes()).decode()


# ------------------------------------------------------------------ OurAirports runways
OA = {}
for r in csv.DictReader(open(os.path.join(SRC, "runways.csv"), encoding="utf-8")):
    if r["airport_ident"] in APS:
        OA.setdefault(r["airport_ident"], []).append(r)


# ------------------------------------------------------------------ apt.dat pavement + tower
def load_aptdat(icaos):
    out = {a: {"pave": [], "vp": None} for a in icaos}
    cur = None
    feat = None      # current pavement feature: list of rings, each ring list of nodes
    ring = None

    def flush():
        nonlocal feat, ring
        if cur and feat is not None:
            if ring:
                feat.append(ring)
            if feat:
                out[cur]["pave"].append(feat)
        feat = None
        ring = None

    with gzip.open(os.path.join(SRC, "apt.dat.gz"), "rt", encoding="latin-1") as f:
        for line in f:
            p = line.split()
            if not p:
                continue
            c = p[0]
            if c in ("1", "16", "17", "99"):
                flush()
                cur = p[4] if len(p) > 4 and p[4] in icaos else None
                continue
            if not cur:
                continue
            if c == "110":
                flush()
                feat = []
                ring = []
                try:
                    sc = int(p[1])
                except ValueError:
                    sc = 1
                feat.append("concrete" if sc == 2 or 50 <= sc <= 57 else "asphalt")
            elif c in ("120", "130"):
                flush()
            elif c in ("111", "112", "113", "114", "115", "116") and feat is not None:
                lat, lon = float(p[1]), float(p[2])
                if c in ("112", "114", "116"):
                    node = (lat, lon, float(p[3]), float(p[4]))
                else:
                    node = (lat, lon, None, None)
                ring.append(node)
                if c in ("113", "114"):
                    feat.append(ring)
                    ring = []
            elif c == "14":
                flush()
                out[cur]["vp"] = (float(p[1]), float(p[2]), float(p[3]) * 0.3048)
            else:
                flush()
    flush()
    return out


def bez_ring(nodes):
    """apt.dat ring (lat, lon, bz_lat, bz_lon) -> list of (lon, lat) with bezier curves sampled."""
    pts = []
    n = len(nodes)
    for i in range(n):
        a = nodes[i]
        b = nodes[(i + 1) % n]
        p0 = np.array([a[1], a[0]])
        p3 = np.array([b[1], b[0]])
        c1 = np.array([a[3], a[2]]) if a[2] is not None else p0
        c2 = np.array([2 * b[1] - b[3], 2 * b[0] - b[2]]) if b[2] is not None else p3
        if a[2] is None and b[2] is None:
            pts.append(tuple(p0))
            continue
        for k in range(8):
            t = k / 8.0
            q = (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * c1 + 3 * (1 - t) * t * t * c2 + t ** 3 * p3
            pts.append(tuple(q))
    return pts


APT = load_aptdat(APS)


# ------------------------------------------------------------------ helpers
def name_of(tags):
    for k in ("ref", "name"):
        v = tags.get(k)
        if v:
            v = re.sub(r"(?i)^(taxiway|taxilane|twy)\s+", "", v.strip())
            return v[:8]
    return ""


def fnum(v, d):
    try:
        return float(re.findall(r"[\d.]+", str(v))[0])
    except Exception:
        return d


def polys(g):
    if g is None or g.is_empty:
        return []
    if isinstance(g, Polygon):
        return [g]
    if isinstance(g, MultiPolygon):
        return list(g.geoms)
    if hasattr(g, "geoms"):
        out = []
        for x in g.geoms:
            out += polys(x)
        return out
    return []


def ring_xy(r):
    c = list(r.coords)
    if len(c) > 1 and c[0] == c[-1]:
        c = c[:-1]
    return c


def tri(poly):
    """Triangulate a polygon with holes; returns (verts Nx2, indices)."""
    rings = [ring_xy(poly.exterior)] + [ring_xy(h) for h in poly.interiors]
    rings = [r for r in rings if len(r) >= 3]
    verts = np.array([p for r in rings for p in r], dtype=np.float64)
    ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
    idx = earcut.triangulate_float64(verts, ends)
    return verts, idx


# ------------------------------------------------------------------ one airport
def convert(icao):
    infra = json.load(open(os.path.join(SRC, "ovt", icao + "_infra.json")))
    bldg = json.load(open(os.path.join(SRC, "ovt", icao + "_bldg.json")))
    # ---- runways (OurAirports), paved and open, at least 1000 m
    rws = []
    for r in OA.get(icao, []):
        if r["closed"] == "1":
            continue
        try:
            a = (float(r["le_latitude_deg"]), float(r["le_longitude_deg"]))
            b = (float(r["he_latitude_deg"]), float(r["he_longitude_deg"]))
        except ValueError:
            continue
        surf = r["surface"].upper()
        if not any(s in surf for s in ("ASP", "CON", "PEM", "BIT", "TAR")):
            continue
        rws.append({"le": r["le_ident"], "he": r["he_ident"], "a": a, "b": b, "wid_ft": fnum(r["width_ft"], 150), "len_ft": fnum(r["length_ft"], 0)})
    lat0 = (min(min(r["a"][0], r["b"][0]) for r in rws) + max(max(r["a"][0], r["b"][0]) for r in rws)) * 0.5
    lon0 = (min(min(r["a"][1], r["b"][1]) for r in rws) + max(max(r["a"][1], r["b"][1]) for r in rws)) * 0.5
    mlat, mlon = mpd(lat0)

    def P(lon, lat):
        return ((np.asarray(lon) - lon0) * mlon, (lat0 - np.asarray(lat)) * mlat)

    def pj(g):
        return transform(lambda x, y, z=None: P(x, y), g)

    # ---- OSM features
    osm_rw, taxi, aprons, gates, aerodrome = [], [], [], [], []
    for row in infra:
        tg = row.get("source_tags") or {}
        cl = row.get("class")
        g = shape(row["geom"])
        aw = tg.get("aeroway", "")
        if cl == "runway" and g.geom_type == "LineString":
            osm_rw.append(pj(g))
        elif cl in ("taxiway", "taxilane") and g.geom_type == "LineString":
            w = fnum(tg.get("width"), 23.0 if cl == "taxiway" else 16.0)
            taxi.append({"g": pj(g), "name": name_of(tg), "w": min(max(w, 10.0), 45.0), "lane": cl == "taxilane"})
        elif (cl == "apron" or aw == "apron" or (cl == "taxiway" and g.geom_type in ("Polygon", "MultiPolygon"))):
            aprons += polys(pj(g))
        elif cl == "airport_gate" and g.geom_type == "Point":
            ref = tg.get("ref") or row.get("names") or ""
            if ref:
                gates.append({"p": pj(g), "ref": str(ref).strip()[:6]})
        elif aw == "aerodrome" and g.geom_type in ("Polygon", "MultiPolygon"):
            aerodrome += polys(pj(g))
    aero = max(aerodrome, key=lambda q: q.area) if aerodrome else None
    # ---- runway geometry: OurAirports ends, aligned to the OSM centreline the taxiways meet
    runways = []
    for r in rws:
        ax, az = P(r["a"][1], r["a"][0])
        bx, bz = P(r["b"][1], r["b"][0])
        A = np.array([float(ax), float(az)])
        B = np.array([float(bx), float(bz)])
        d = (B - A) / np.linalg.norm(B - A)
        mid = (A + B) * 0.5
        best = None
        for ol in osm_rw:
            c = np.array(ol.coords)
            od = c[-1] - c[0]
            if np.linalg.norm(od) < 100:
                continue
            od /= np.linalg.norm(od)
            if abs(float(np.dot(od, d))) < 0.998:
                continue
            dist = ol.distance(Point(mid))
            if dist < 120 and (best is None or dist < best[0]):
                best = (dist, c[0], od)
        if best is not None:
            o, od = best[1], best[2]
            if np.dot(od, d) < 0:
                od = -od
            A = o + od * np.dot(A - o, od)
            B = o + od * np.dot(B - o, od)
        length = float(np.linalg.norm(B - A))
        if length < 1000:
            continue
        wid = max(30.0, min(75.0, r["wid_ft"] * 0.3048))
        runways.append({"id": "%s/%s" % (r["le"], r["he"]), "a": A, "b": B, "wid": round(wid, 1), "len": length})
    runways.sort(key=lambda q: -q["len"])
    rw_lines = [LineString([tuple(r["a"]), tuple(r["b"])]) for r in runways]
    # ---- terminal candidates and buildings
    zone = (aero.buffer(250) if aero is not None else box(*unary_union(rw_lines).buffer(3000).bounds))
    blds = []
    for row in bldg:
        try:
            g = pj(shape(row["geom"]))
        except Exception:
            continue
        for pg in polys(g):
            if pg.area < 150 or not pg.is_valid:
                continue
            if not zone.contains(pg.representative_point()):
                continue
            blds.append({"g": pg, "row": row})
    btree = STRtree([b["g"] for b in blds]) if blds else None
    # ---- pavement: OSM aprons + buffered taxiways + apt.dat pavement
    pv = list(aprons)
    for t in taxi:
        pv.append(t["g"].buffer(t["w"] * 0.5 + 3.0, quad_segs=3, cap_style="round", join_style="round"))
    apt_conc = []
    for feat in APT[icao]["pave"]:
        surf, feat = feat[0], feat[1:]
        if not feat:
            continue
        try:
            outer = [P(q[0], q[1]) for q in bez_ring(feat[0])]
            holes = [[P(q[0], q[1]) for q in bez_ring(h)] for h in feat[1:] if len(h) >= 3]
            outer = [(float(x), float(z)) for x, z in outer]
            holes = [[(float(x), float(z)) for x, z in h] for h in holes]
            pg = Polygon(outer, holes)
            if not pg.is_valid:
                pg = pg.buffer(0)
            pv += polys(pg)
            if surf == "concrete":
                apt_conc += polys(pg)
        except Exception:
            pass
    pave = unary_union([q for q in pv if q.is_valid and q.area > 20]).simplify(0.6)
    if aero is not None:
        pave = pave.intersection(aero.buffer(400))
    pave_polys = [q for q in polys(pave) if q.area > 200]
    # ---- taxi network: noded OSM taxiway lines + runway centrelines
    lines = [t["g"] for t in taxi]
    tlines = STRtree(lines) if lines else None
    # close small gaps: dangling ends within 8 m of another line get a connector
    extra = []
    all_lines = lines + rw_lines
    atree = STRtree(all_lines)
    for i, ln in enumerate(lines):
        for end in (Point(ln.coords[0]), Point(ln.coords[-1])):
            near = [j for j in atree.query(end.buffer(8.0)) if j != i]
            touching = any(all_lines[j].distance(end) < 0.05 for j in near)
            if touching or not near:
                continue
            j = min(near, key=lambda k: all_lines[k].distance(end))
            q = nearest_points(end, all_lines[j])[1]
            if end.distance(q) > 0.01:
                extra.append(LineString([end.coords[0], q.coords[0]]))
    noded = unary_union(MultiLineString(lines + rw_lines + extra))
    pieces = list(noded.geoms) if hasattr(noded, "geoms") else [noded]
    nodes = []
    key = {}

    def node_at(x, z):
        kx, kz = int(round(x * 2.0)), int(round(z * 2.0))
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                n = key.get((kx + dx, kz + dz))
                if n is not None and math.hypot(nodes[n][0] - x, nodes[n][1] - z) < 0.9:
                    return n
        nodes.append([x, z])
        key[(kx, kz)] = len(nodes) - 1
        return len(nodes) - 1

    edges = []      # [a, b, name, kind, runway]
    for pc in pieces:
        if pc.length < 0.5:
            continue
        mid = pc.interpolate(0.5, normalized=True)
        rwi = -1
        for k, rl in enumerate(rw_lines):
            if rl.distance(mid) < 1.5 and pc.hausdorff_distance(rl) < max(2.0, rl.length):
                if rl.distance(Point(pc.coords[0])) < 1.5 and rl.distance(Point(pc.coords[-1])) < 1.5:
                    rwi = k
                    break
        if rwi >= 0:
            nm, kind = "RWY " + runways[rwi]["id"], "rwy"
        else:
            cand = tlines.query(mid.buffer(2.0)) if tlines is not None else []
            if len(cand) == 0:
                nm, kind = "", "taxi"
            else:
                j = min(cand, key=lambda k: lines[k].distance(mid))
                nm = taxi[j]["name"]
                kind = "lane" if taxi[j]["lane"] else "taxi"
        sp = pc.simplify(1.2) if rwi < 0 else LineString([pc.coords[0], pc.coords[-1]])
        cs = list(sp.coords)
        prev = node_at(*cs[0])
        for c in cs[1:]:
            cur = node_at(*c)
            if cur != prev:
                edges.append([prev, cur, nm, kind, rwi])
            prev = cur
    # node kinds
    nk = ["taxi"] * len(nodes)
    nrw = [-1] * len(nodes)
    for e in edges:
        if e[3] == "rwy":
            for n in (e[0], e[1]):
                nk[n] = "rwy"
                nrw[n] = e[4]
    lane_only = [True] * len(nodes)
    for e in edges:
        if e[3] != "lane":
            lane_only[e[0]] = False
            lane_only[e[1]] = False
    for i in range(len(nodes)):
        if nk[i] == "taxi" and lane_only[i]:
            nk[i] = "apron"
    # nodes that sit on a runway centreline but were reached only by taxiway pieces
    for i, (x, z) in enumerate(nodes):
        if nk[i] == "rwy":
            continue
        for k, rl in enumerate(rw_lines):
            if rl.distance(Point(x, z)) < 1.0:
                nk[i] = "rwy"
                nrw[i] = k
    adj = [[] for _ in nodes]
    for ei, e in enumerate(edges):
        adj[e[0]].append(ei)
        adj[e[1]].append(ei)

    def split_edge(ei, x, z, kind):
        a, b, nm, k, rwi = edges[ei]
        nodes.append([x, z])
        nk.append(kind)
        nrw.append(-1)
        adj.append([])
        w = len(nodes) - 1
        edges[ei] = [a, w, nm, k, rwi]
        edges.append([w, b, nm, k, rwi])
        adj[b] = [q if q != ei else len(edges) - 1 for q in adj[b]]
        adj[w] += [ei, len(edges) - 1]
        return w

    # ---- holding points on every taxiway leg that reaches a runway
    holds = []
    for rn in range(len(nodes)):
        if nk[rn] != "rwy":
            continue
        rk = nrw[rn]
        if rk < 0:
            continue
        rl = rw_lines[rk]
        hd = runways[rk]["wid"] * 0.5 + (62.0 if runways[rk]["wid"] >= 44 else 45.0)
        for ei in list(adj[rn]):
            e = edges[ei]
            if e[3] == "rwy":
                continue
            prev, cur, eidx = rn, (e[1] if e[0] == rn else e[0]), ei
            steps = 0
            while steps < 40:
                steps += 1
                dc = rl.distance(Point(nodes[cur]))
                if dc >= hd:
                    dp = rl.distance(Point(nodes[prev]))
                    t = (hd - dp) / max(dc - dp, 0.01)
                    x = nodes[prev][0] + (nodes[cur][0] - nodes[prev][0]) * t
                    z = nodes[prev][1] + (nodes[cur][1] - nodes[prev][1]) * t
                    w = split_edge(eidx, x, z, "hold")
                    nrw[w] = rk
                    holds.append(w)
                    break
                if nk[cur] in ("rwy", "hold"):
                    break
                nxt = [q for q in adj[cur] if q != eidx and edges[q][3] != "rwy"]
                if len(nxt) != 1:
                    # junction before the hold distance: hold at the junction-side end of this leg
                    if nk[cur] == "taxi":
                        nk[cur] = "hold"
                        nrw[cur] = rk
                        holds.append(cur)
                    break
                eidx = nxt[0]
                e2 = edges[eidx]
                prev, cur = cur, (e2[1] if e2[0] == cur else e2[0])
    # ---- stands from OSM gates
    gates.sort(key=lambda g: (len(g["ref"]), g["ref"]))
    kept = []
    for g in gates:
        if all(g["p"].distance(k["p"]) > 12.0 for k in kept):
            kept.append(g)
    pave_u = unary_union(pave_polys) if pave_polys else None
    stands = []
    term_ids = set()
    why = {}

    def rej(k):
        why[k] = why.get(k, 0) + 1
    for g in kept:
        if btree is None:
            break
        cand = [i for i in btree.query(g["p"].buffer(70.0)) if blds[i]["g"].area > 1500]
        if not cand:
            rej("no_building")
            continue
        bi = min(cand, key=lambda i: blds[i]["g"].exterior.distance(g["p"]))
        pg = blds[bi]["g"]
        if pg.exterior.distance(g["p"]) > 70.0:
            rej("too_far")
            continue
        ext = pg.exterior
        s = ext.project(g["p"])
        f = ext.interpolate(s)
        f2 = ext.interpolate(min(s + 1.0, ext.length))
        f1 = ext.interpolate(max(s - 1.0, 0.0))
        tx, tz = f2.x - f1.x, f2.y - f1.y
        tl = math.hypot(tx, tz)
        if tl < 1e-6:
            continue
        nx, nz = -tz / tl, tx / tl
        if pg.contains(Point(f.x + nx * 1.5, f.y + nz * 1.5)):
            nx, nz = -nx, -nz
        # the stand must open onto pavement, clear of other buildings
        probe = Point(f.x + nx * 40.0, f.y + nz * 40.0)
        if pave_u is not None and pave_u.distance(probe) > 6.0 and any(ap.distance(g["p"]) < 250.0 for ap in aprons):
            rej("no_pavement")
            continue
        hit_b = [i for i in btree.query(probe.buffer(12.0)) if blds[i]["g"].distance(probe) < 10.0 and blds[i]["g"].area > 700]
        if hit_b:
            rej("blocked")
            continue
        stands.append({"ref": g["ref"], "f": (f.x, f.y), "n": (nx, nz), "b": bi, "gd": pg.exterior.distance(g["p"])})
        term_ids.add(bi)
    # stands whose aircraft would overlap: keep the one closest to its gate marker
    stands.sort(key=lambda s: s["gd"])
    clean = []
    for s in stands:
        px, pz = s["f"][0] + s["n"][0] * 30.0, s["f"][1] + s["n"][1] * 30.0
        if all(math.hypot(px - (c["f"][0] + c["n"][0] * 30.0), pz - (c["f"][1] + c["n"][1] * 30.0)) > 26.0 for c in clean):
            clean.append(s)
        else:
            rej("overlap")
    stands = clean
    # wingspan limit from the spacing to the neighbouring stands on the same facade
    for s in stands:
        dmin = 1e9
        for o in stands:
            if o is s or (s["n"][0] * o["n"][0] + s["n"][1] * o["n"][1]) < 0.8:
                continue
            dmin = min(dmin, math.hypot(s["f"][0] - o["f"][0], s["f"][1] - o["f"][1]))
        s["span"] = 65.0 if dmin > 1e8 else max(24.0, min(80.0, dmin - 5.0))
    # ---- lead-in: where the line from each stand meets the taxi network
    seg_geoms = [LineString([nodes[e[0]], nodes[e[1]]]) for e in edges]
    stree = STRtree(seg_geoms)
    hits = {}
    for si, s in enumerate(stands):
        fx, fz = s["f"]
        nx, nz = s["n"]
        ray = LineString([(fx + nx * 38.0, fz + nz * 38.0), (fx + nx * 260.0, fz + nz * 260.0)])
        best = None
        for ei in stree.query(ray):
            if edges[ei][3] == "rwy" or nk[edges[ei][0]] == "rwy" and nk[edges[ei][1]] == "rwy":
                continue
            ip = ray.intersection(seg_geoms[ei])
            if ip.is_empty or ip.geom_type != "Point":
                continue
            d = math.hypot(ip.x - fx, ip.y - fz)
            if best is None or d < best[0]:
                best = (d, ei, ip.x, ip.y)
        s["hit"] = best
        if best is not None:
            hits.setdefault(best[1], []).append(si)
    for ei, sis in hits.items():
        a, b = edges[ei][0], edges[ei][1]
        ax, az = nodes[a]
        def tpar(si):
            h = stands[si]["hit"]
            return math.hypot(h[2] - ax, h[3] - az)
        sis.sort(key=tpar)
        cur_e = ei
        last = None
        for si in sis:
            h = stands[si]["hit"]
            if last is not None and math.hypot(nodes[last][0] - h[2], nodes[last][1] - h[3]) < 4.0:
                stands[si]["lead"] = last
                continue
            w = split_edge(cur_e, h[2], h[3], "apron" if nk[a] != "taxi" else "taxi")
            stands[si]["lead"] = w
            last = w
            cur_e = len(edges) - 1     # the far half carries on to b
    taxi_nodes = [i for i in range(len(nodes)) if nk[i] in ("taxi", "apron")]
    for s in stands:
        if "lead" in s:
            continue
        fx, fz = s["f"]
        nx, nz = s["n"]
        lx, lz = fx + nx * 95.0, fz + nz * 95.0
        best = min(taxi_nodes, key=lambda i: (nodes[i][0] - lx) ** 2 + (nodes[i][1] - lz) ** 2) if taxi_nodes else None
        if best is None or math.hypot(nodes[best][0] - lx, nodes[best][1] - lz) > 450.0:
            continue
        nodes.append([lx, lz])
        nk.append("apron")
        nrw.append(-1)
        adj.append([])
        w = len(nodes) - 1
        edges.append([w, best, "", "lane", -1])
        s["lead"] = w
    why["no_lead"] = sum(1 for s in stands if "lead" not in s)
    stands = [s for s in stands if "lead" in s]
    # stand pads: pavement from the facade out to the lead-in line, a wingspan wide
    pads = []
    for s in stands:
        fx, fz = s["f"]
        nx, nz = s["n"]
        lx, lz = nodes[s["lead"]]
        reach = max(70.0, math.hypot(lx - fx, lz - fz) + 12.0)
        hw = max(s["span"], 36.0) * 0.5 + 4.0
        ax, az = -nz, nx
        pads.append(Polygon([(fx + ax * hw, fz + az * hw), (fx - ax * hw, fz - az * hw),
            (fx - ax * hw + nx * reach, fz - az * hw + nz * reach), (fx + ax * hw + nx * reach, fz + az * hw + nz * reach)]))
    if pads:
        pave = unary_union([pave] + pads).simplify(0.6)
        pave_polys = [q for q in polys(pave) if q.area > 200]
    conc = unary_union([q for q in aprons + apt_conc + pads if q.is_valid and q.area > 20]).intersection(pave).simplify(0.6)
    conc_polys = [q for q in polys(conc) if q.area > 150]
    asph = pave.difference(conc.buffer(0.05)).simplify(0.6)
    asph_polys = [q for q in polys(asph) if q.area > 150]
    # stand nodes
    for s in stands:
        fx, fz = s["f"]
        nx, nz = s["n"]
        nodes.append([fx + nx * 14.0, fz + nz * 14.0])
        nk.append("stand")
        nrw.append(-1)
        adj.append([])
        s["node"] = len(nodes) - 1
        edges.append([s["lead"], s["node"], "stand " + s["ref"], "stand", -1])
    # ---- keep the network that reaches the runways
    par = list(range(len(nodes)))

    def fnd(x):
        while par[x] != x:
            par[x] = par[par[x]]
            x = par[x]
        return x
    for e in edges:
        ra, rb = fnd(e[0]), fnd(e[1])
        if ra != rb:
            par[ra] = rb
    score = {}
    for i in range(len(nodes)):
        if nk[i] in ("rwy", "stand"):
            score[fnd(i)] = score.get(fnd(i), 0) + 1
    main = max(score, key=score.get) if score else None
    keep = [fnd(i) == main for i in range(len(nodes))]
    remap = {}
    out_nodes = []
    for i in range(len(nodes)):
        if keep[i]:
            remap[i] = len(out_nodes)
            out_nodes.append(i)
    out_edges = [e for e in edges if keep[e[0]] and keep[e[1]]]
    why["cut_off"] = sum(1 for s in stands if not keep[s["node"]])
    stands = [s for s in stands if keep[s["node"]]]
    names = sorted({e[2] for e in out_edges})
    name_ix = {n: i for i, n in enumerate(names)}
    kinds = {"taxi": 0, "hold": 1, "rwy": 2, "apron": 3, "stand": 4}
    # ---- buildings: classify and pack
    tower = None
    out_b = []
    # footprints on runways or taxiways are stale (built over since) or misdetected: drop them
    rw_zone = unary_union([rl.buffer(runways[k]["wid"] * 0.5 + 75.0) for k, rl in enumerate(rw_lines)])
    twy_zone = unary_union([t["g"].buffer(t["w"] * 0.5) for t in taxi]) if taxi else None
    for i, b in enumerate(blds):
        row = b["row"]
        pg = b["g"]
        if i not in term_ids and (pg.intersects(rw_zone) or (twy_zone is not None and pg.intersection(twy_zone).area > 0.12 * pg.area)):
            continue
        nm = (row.get("names") or "") or ""
        cl = (row.get("class") or "") or ""
        h = row.get("height")
        nf = row.get("num_floors")
        low = nm.lower()
        if re.search(r"tower|torre|turm|tour de contr|kontrol kulesi|管制", low) and pg.area < 3000 and (h or 0) > 25:
            if tower is None or (h or 0) > tower[2]:
                c = pg.centroid
                tower = (c.x, c.y, float(h))
            continue
        if i in term_ids or re.search(r"terminal|concourse|pier|satellite|gate|航站|ターミナル|터미널", low):
            kind = "terminal"
        elif cl in ("parking", "garage", "garages") or re.search(r"park|garage|parkhaus|parking", low):
            kind = "garage"
        elif cl == "hotel" or "hotel" in low:
            kind = "hotel"
        elif cl == "hangar" or "hangar" in low or "maintenance" in low:
            kind = "hangar"
        elif cl in ("warehouse", "industrial") or "cargo" in low or "freight" in low:
            kind = "cargo"
        else:
            kind = "other"
        if not h:
            h = float(nf) * 3.6 + 2.0 if nf else {"terminal": 20.0, "garage": 14.0, "hotel": 30.0, "hangar": 24.0, "cargo": 13.0}.get(kind, 9.0)
        h = max(4.0, min(float(h), 120.0))
        mh = max(0.0, float(row.get("min_height") or 0.0))
        if kind == "other" and pg.area < 400:
            continue
        if kind == "other" and pg.area < 900 and any(blds[j]["g"].distance(pg) < 2.5 for j in term_ids):
            continue
        g2 = pg.simplify(0.35)
        if g2.is_empty or not isinstance(g2, Polygon) or g2.area < 100:
            continue
        g2 = shapely.geometry.polygon.orient(g2, 1.0)
        holes_r = [hh for hh in g2.interiors if Polygon(hh).area > 60]
        g2 = Polygon(g2.exterior, holes_r)
        ext = ring_xy(g2.exterior)
        holes = [ring_xy(hh) for hh in holes_r]
        try:
            _, ri = tri(g2)
        except Exception:
            continue
        mrr = g2.minimum_rotated_rectangle
        rc = list(mrr.exterior.coords)[:4]
        e0 = np.array(rc[1]) - np.array(rc[0])
        e1 = np.array(rc[2]) - np.array(rc[1])
        if np.linalg.norm(e0) < np.linalg.norm(e1):
            e0, e1 = e1, e0
        ln, dp = float(np.linalg.norm(e0)), float(np.linalg.norm(e1))
        axv = e0 / max(ln, 1e-6)
        cen = mrr.centroid
        out_b.append({"k": kind, "n": nm[:40], "h": round(h, 1), "mh": round(mh, 1), "t": i in term_ids,
            "p": b64f(np.array(ext).ravel()), "holes": [b64f(np.array(hh).ravel()) for hh in holes], "ri": b64i(ri),
            "obb": [round(cen.x, 1), round(cen.y, 1), round(float(axv[0]), 4), round(float(axv[1]), 4), round(ln, 1), round(dp, 1)],
            "fill": round(g2.area / max(mrr.area, 1.0), 3)})
    if tower is None and APT[icao]["vp"] is not None:
        la, lo, hm = APT[icao]["vp"]
        x, z = P(lo, la)
        tower = (float(x), float(z), max(hm, 40.0))
    if tower is None and term_ids:
        tc = unary_union([blds[i]["g"] for i in term_ids]).centroid
        rl = min(rw_lines, key=lambda q: q.distance(tc))
        rp = nearest_points(tc, rl)[1]
        occupied = unary_union([b["g"] for b in blds] + pave_polys)
        tower = None
        for f in (0.45, 0.35, 0.55, 0.25, 0.65):
            for side in (0.0, 120.0, -120.0, 240.0, -240.0):
                dx, dz = rp.x - tc.x, rp.y - tc.y
                ln = math.hypot(dx, dz) or 1.0
                px = tc.x + dx * f - dz / ln * side
                pz = tc.y + dz * f + dx / ln * side
                if occupied.distance(Point(px, pz)) > 12.0 and min(q.distance(Point(px, pz)) for q in rw_lines) > 170.0:
                    tower = (px, pz, 85.0)
                    break
            if tower:
                break
    # ---- pavement triangles
    def mesh(pl):
        pv_v, pv_i, base = [], [], 0
        for pg in pl:
            try:
                v, idx = tri(pg)
            except Exception:
                continue
            pv_v.append(v)
            pv_i.append(np.asarray(idx, dtype=np.int64) + base)
            base += len(v)
        return (np.vstack(pv_v) if pv_v else np.zeros((0, 2))), (np.concatenate(pv_i) if pv_i else np.zeros(0))
    pa_v, pa_i = mesh(conc_polys)
    pt_v, pt_i = mesh(asph_polys)
    pv_i = np.concatenate([pa_i, pt_i])
    # ---- outline for the airport fence: hull of pavement, runways and terminals
    parts = [pave] + [rl.buffer(runways[k]["wid"]) for k, rl in enumerate(rw_lines)] + [blds[i]["g"] for i in term_ids]
    hull = unary_union(parts).convex_hull.simplify(5.0)
    outline = ring_xy(hull.exterior) if isinstance(hull, Polygon) else []
    fence = hull.buffer(30.0) if isinstance(hull, Polygon) else None
    if fence is not None:
        def inside(bb):
            f = np.frombuffer(base64.b64decode(bb["p"]), dtype="<f4").reshape(-1, 2)
            return fence.contains(Point(float(f[:, 0].mean()), float(f[:, 1].mean())))
        out_b = [bb for bb in out_b if bb["t"] or inside(bb)]
    res = {
        "icao": icao, "ref": [lat0, lon0],
        "runways": [{"id": r["id"], "a": [round(float(r["a"][0]), 2), round(float(r["a"][1]), 2)], "b": [round(float(r["b"][0]), 2), round(float(r["b"][1]), 2)], "wid": r["wid"]} for r in runways],
        "nodes": b64f(np.array([nodes[i] for i in out_nodes]).ravel()),
        "kinds": b64i([kinds.get(nk[i], 0) for i in out_nodes]),
        "nrw": b64i([nrw[i] for i in out_nodes]),
        "edges": b64i(np.array([[remap[e[0]], remap[e[1]], name_ix[e[2]]] for e in out_edges]).ravel()),
        "names": names,
        "stands": [{"n": s["ref"], "f": [round(s["f"][0], 2), round(s["f"][1], 2)], "d": [round(s["n"][0], 4), round(s["n"][1], 4)],
            "lead": remap[s["lead"]], "node": remap[s["node"]], "span": round(s["span"], 1), "br": bool(s["gd"] < 40.0)} for s in stands],
        "pa_v": b64f(pa_v.ravel()), "pa_i": b64i(pa_i), "pt_v": b64f(pt_v.ravel()), "pt_i": b64i(pt_i),
        "buildings": out_b,
        "tower": [round(tower[0], 1), round(tower[1], 1), round(tower[2], 1)] if tower else None,
        "outline": [[round(p[0], 1), round(p[1], 1)] for p in outline],
    }
    json.dump(res, open(os.path.join(OUT, icao + ".json"), "w"), separators=(",", ":"))
    n_term = sum(1 for b in out_b if b["k"] == "terminal")
    print("%s rw %d nodes %d edges %d holds %d stands %d bld %d (term %d) pave %d tris tower %s  %.0f KB" % (
        icao, len(runways), len(out_nodes), len(out_edges), sum(1 for i in out_nodes if nk[i] == "hold"), len(stands), len(out_b), n_term,
        len(pv_i) // 3, "yes" if tower else "no", os.path.getsize(os.path.join(OUT, icao + ".json")) / 1024), "gates", len(kept), why, flush=True)
    return res


for a in APS:
    try:
        convert(a)
    except Exception as ex:
        import traceback
        traceback.print_exc()
        print("FAILED", a, ex)
