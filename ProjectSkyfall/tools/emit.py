import math, random
from geo_real import *
SEA_CHANNELS = ['Golden Gate']

def v2(p):
    return "Vector2(%.1f, %.1f)" % p

def ap_pos_m(a):
    x, z = ll(a["lon"], a["lat"])
    return round(x + a["nudge"][0] * 1000.0, -1), round(z + a["nudge"][1] * 1000.0, -1)

out = []
w = out.append
w("class_name RealWorld")
w("## The real-world region: North America, the North Atlantic and Europe, compressed 1:5 onto the")
w("## game map south of Calderra (New York to London is about 1,100 km). Generated from latitude /")
w("## longitude outlines by tools/geo_real.py; positions are world km (x east, z south) unless noted.")
w("")
w("const LON0 := %.1f" % LON0)
w("const LAT0 := %.1f" % LAT0)
w("const KX := %.2f        # metres per degree of longitude" % KX)
w("const KZ := %.2f        # metres per degree of latitude" % KZ)
w("const ORIGIN_Z := %.1f" % ORIGIN_Z)
w("const GRID_X0 := %.1f" % GRID_X0)
w("const GRID_Z0 := %.1f" % GRID_Z0)
w("const GRID_NX := %d" % int((GRID_X1 - GRID_X0) / CELL))
w("const GRID_NZ := %d" % int((GRID_Z1 - GRID_Z0) / CELL))
w("const CELL := %.1f" % CELL)
w("")
w("const POLY_NAMES := %s" % ("[" + ", ".join('"%s"' % n for n, _ in POLYS) + "]"))
w("const POLYS := [")
for n, poly in POLYS:
    pts = [v2(km(*p)) for p in poly]
    lines = []
    for i in range(0, len(pts), 8):
        lines.append("\t\t" + ", ".join(pts[i:i + 8]) + ",")
    w("\t[  # " + n)
    out.extend(lines)
    w("\t],")
w("]")
w("const ISLANDS := [")
for lo, la, rx, rz in ISLANDS:
    w("\t[%s, Vector2(%.1f, %.1f)]," % (v2(km(lo, la)), rx, rz))
w("]")
w("const RISES := [")
for lo, la, rx, rz, pk in RISES:
    w("\t[%s, Vector2(%.1f, %.1f), %.1f]," % (v2(km(lo, la)), rx, rz, pk))
w("]")
w("const RANGES := [")
for a0, a1, b0, b1, r, pk in RANGES:
    w("\t[%s, %s, %.1f, %.1f]," % (v2(km(a0, a1)), v2(km(b0, b1)), r, pk))
w("]")

# lakes (metres) + city bays
lakes = []
for n, lo, la, rx, rz, lev in LAKES:
    x, z = ll(lo, la)
    lakes.append((n, x, z, rx * 1000.0, rz * 1000.0, float(lev)))
rivers = []
for n, wd, pts in RIVERS:
    rivers.append((n, wd, [km(*p) for p in pts]))
parks = []
landmarks = []
city_rivers_m = {}
for a in AIRPORTS:
    ax, az = ap_pos_m(a)
    cx, cz = ax + a["city_off"][0], az + a["city_off"][1]
    for n, wd, pts in CITY_RIVERS.get(a["icao"], []):
        pm = [(cx + p[0], cz + p[1]) for p in pts]
        city_rivers_m.setdefault(a["icao"], []).append(pm)
        rivers.append((n, wd, [(p[0] / 1000.0, p[1] / 1000.0) for p in pm]))
    for n, dx, dz, rx, rz in CITY_BAYS.get(a["icao"], []):
        lakes.append((n, cx + dx, cz + dz, rx, rz, -1.0))
    for n, dx, dz, hw, hd in CITY_PARKS.get(a["icao"], []):
        parks.append((n, cx + dx, cz + dz, hw, hd))
    for lid, n, kind, dx, dz, yaw in CITY_LANDMARKS.get(a["icao"], []):
        x, z = cx + dx, cz + dz
        if kind.startswith("bridge"):
            best = None
            for pm in city_rivers_m.get(a["icao"], []):
                for i in range(len(pm) - 1):
                    (x0, z0), (x1, z1) = pm[i], pm[i + 1]
                    vx, vz = x1 - x0, z1 - z0
                    t = max(0.0, min(1.0, ((x - x0) * vx + (z - z0) * vz) / max(vx * vx + vz * vz, 1.0)))
                    px, pz = x0 + vx * t, z0 + vz * t
                    d = math.hypot(px - x, pz - z)
                    if best is None or d < best[0]:
                        best = (d, px, pz, vx, vz)
            if best:
                _, x, z, vx, vz = best
                # deck runs across the river: heading of the perpendicular
                # heading of the deck: perpendicular to the river (-vz, vx), heading = atan2(dx, -dz)
                yaw = math.degrees(math.atan2(-vz, -vx)) % 360.0
        landmarks.append((lid, n, kind, x, z, yaw, a["icao"], a["city"]))

w("const LAKES := [")
for n, x, z, rx, rz, lev in lakes:
    w('\t{"x": %.1f, "z": %.1f, "rx": %.1f, "rz": %.1f, "level": %.1f, "name": "%s"},' % (x, z, rx, rz, lev, n))
w("]")
w("const RIVERS := [")
for n, wd, pts in rivers:
    w('\t{"name": "%s", "w": %.1f, "pts": [%s]%s},' % (n, wd, ", ".join(v2(p) for p in pts), ', "sea": true' if n in SEA_CHANNELS else ""))
w("]")
w("## Parks keep the city scatter out: {name, x, z, hw, hd} in metres.")
w("const PARKS := [")
for n, x, z, hw, hd in parks:
    w('\t{"name": "%s", "x": %.1f, "z": %.1f, "hw": %.1f, "hd": %.1f},' % (n, x, z, hw, hd))
w("]")
w("## Landmarks: kind picks the model in Landmarks; x, z metres; yaw = heading of the model's forward axis.")
w("const LANDMARKS := [")
for lid, n, kind, x, z, yaw, icao, city in landmarks:
    w('\t{"id": "%s", "name": "%s", "kind": "%s", "x": %.1f, "z": %.1f, "yaw": %.1f, "icao": "%s", "city": "%s"},' % (lid, n, kind, x, z, yaw, icao, city))
w("]")
w("const LABELS := [")
for t, lo, la in LABELS:
    w('\t["%s", %s],' % (t, v2(km(lo, la))))
w("]")
w('''

## World metres for a real latitude / longitude.
static func to_world(lat: float, lon: float) -> Vector2:
	return Vector2((lon - LON0) * KX, ORIGIN_Z + (LAT0 - lat) * KZ)


## (lon, lat) of a world position.
static func to_lonlat(x: float, z: float) -> Vector2:
	return Vector2(LON0 + x / KX, LAT0 - (z - ORIGIN_Z) / KZ)


static func contains(x: float, z: float) -> bool:
	return x >= GRID_X0 and x <= GRID_X0 + GRID_NX * CELL and z >= GRID_Z0 and z <= GRID_Z0 + GRID_NZ * CELL


## Name of the sea or ocean at a position in the region.
static func sea_name(x: float, z: float) -> String:
	var ll := to_lonlat(x, z)
	var lon := ll.x
	var lat := ll.y
	if lon < -100.0 and lat < 52.0:
		return "the Pacific Ocean"
	if lat > 18.0 and lat < 30.8 and lon > -98.0 and lon < -81.2:
		return "the Gulf of Mexico"
	if lat > 51.0 and lat < 64.5 and lon > -95.5 and lon < -76.5:
		return "Hudson Bay"
	if lat > 49.0 and lat < 51.2 and lon > -6.0 and lon < 2.0:
		return "the English Channel"
	if lat > 51.2 and lat < 55.6 and lon > -6.4 and lon < -2.8:
		return "the Irish Sea"
	if lat > 51.0 and lat < 61.5 and lon > -4.0 and lon < 10.0:
		return "the North Sea"
	if lat > 53.5 and lat < 66.0 and lon > 9.5:
		return "the Baltic Sea"
	if lat > 43.4 and lat < 48.3 and lon > -10.0 and lon < -1.0:
		return "the Bay of Biscay"
	if lon > -5.6 and lon < 40.0 and lat > 30.0 and lat < 46.0:
		return "the Mediterranean Sea"
	if lat > 58.0 and lon > -66.0 and lon < -45.0:
		return "the Labrador Sea"
	if lat > 63.0 and lon > -45.0 and lon < -13.0:
		return "the Denmark Strait" if lon < -25.0 else "the Norwegian Sea"
	if lat < 24.5 and lon > -86.0 and lon < -74.0:
		return "the Caribbean Sea"
	return "the North Atlantic"


## Air traffic control centre for a position in the region.
static func center_name(x: float, z: float, country: String) -> String:
	var ll := to_lonlat(x, z)
	match country:
		"United States":
			if ll.x < -117.0 and ll.y > 44.0:
				return "Seattle Center"
			if ll.x < -112.0:
				return "Los Angeles Center" if ll.y < 37.0 else "Oakland Center"
			if ll.x < -102.0:
				return "Denver Center" if ll.y > 36.5 else "Albuquerque Center"
			if ll.x < -93.5 and ll.y < 36.5:
				return "Fort Worth Center"
			if ll.x < -88.0 and ll.y < 33.0:
				return "Houston Center"
			if ll.x < -80.0 and ll.y < 36.0 and ll.y > 31.0:
				return "Atlanta Center"
			if ll.y < 31.0 and ll.y > 27.0 and ll.x > -84.0:
				return "Jacksonville Center"
			if ll.x < -84.0:
				return "Chicago Center"
			if ll.y < 30.0:
				return "Miami Center"
			if ll.y < 39.6:
				return "Washington Center"
			return "Boston Center" if ll.x > -72.5 else "New York Center"
		"Canada":
			return "Gander Centre" if ll.x > -60.0 else "Toronto Centre"
		"United Kingdom":
			return "London Control" if ll.y < 54.5 else "Scottish Control"
		"Ireland":
			return "Shannon Control"
		"France":
			return "Paris Control"
		"Netherlands":
			return "Amsterdam Radar"
		"Spain":
			return "Madrid Control"
		"Italy":
			return "Roma Control"
		"Iceland", "Greenland":
			return "Reykjavik Control"
		"Portugal":
			return "Lisboa Control" if ll.x > -10.5 else "Santa Maria Oceanic"
		"Germany":
			return "Bremen Radar" if ll.y > 52.0 else ("Langen Radar" if ll.x < 10.5 else "Munich Radar")
		"Switzerland":
			return "Zurich Radar"
		"Austria":
			return "Wien Radar"
		"Denmark":
			return "Copenhagen Control"
		"Norway":
			return "Polaris Control"
		"Sweden":
			return "Stockholm Control"
		"Belgium":
			return "Brussels Control"
		"Bermuda":
			return "New York Oceanic"
		"Faroe Islands":
			return "Scottish Control"
	return "Shanwick Oceanic" if ll.x > -30.0 else "Gander Oceanic"
''')
open("/home/user/School-Education-/ProjectSkyfall/src/data/real_world.gd", "w").write("\n".join(out))

# ---------------------------------------------------------------- airport entries
rr = random.Random(7)
def freq():
    return "%d.%03d" % (rr.choice([118, 119, 120, 121, 124, 125, 126, 127, 128, 132, 134]), rr.choice([0, 25, 50, 75, 100, 125, 150, 175, 200, 250, 300, 350, 400, 450, 500, 550, 600, 650, 700, 750, 800, 850, 900, 950]))
lines = []
for a in AIRPORTS:
    x, z = ap_pos_m(a)
    rws = []
    for rid, hdg, ln, wd, off, along, ils in a["runways"]:
        rws.append('\t\t\t{"id": "%s", "hdg": %.1f, "len": %.1f, "wid": %.1f, "off": %.1f, "along": %.1f, "ils": [%s, %s], "surface": "asphalt"},' % (
            rid, hdg, ln, wd, off, along, "true" if ils[0] else "false", "true" if ils[1] else "false"))
    g = freq(); t = freq()
    lines.append('\t"%s": {' % a["icao"])
    lines.append('\t\t"iata": "%s", "name": "%s", "short": "%s", "city": "%s",' % (a["iata"], a["name"], a["short"], a["city"]))
    lines.append('\t\t"country": "%s", "x": %.1f, "z": %.1f, "elev": %.1f, "size": "%s", "region": "world",' % (a["country"], x, z, a["elev"], a["size"]))
    lines.append('\t\t"runways": [')
    lines.extend(rws)
    lines.append('\t\t],')
    lines.append('\t\t"terminal": {"between": %s, "side": %d, "gates": %d, "style": "%s"},' % ("true" if a["between"] else "false", a["side"], a["gates"], a["style"]))
    lines.append('\t\t"freq": {"atis": "%s", "del": "%s", "gnd": "%s", "twr": "%s", "app": "%s", "dep": "%s"},' % (freq(), g, g, t, freq(), freq()))
    lines.append('\t\t"city_info": {"dx": %.1f, "dz": %.1f, "radius": %.1f, "pop": %d, "tall": %.2f, "coastal": %s},' % (
        a["city_off"][0], a["city_off"][1], a["radius"], a["pop"], a["tall"], "true" if a["coastal"] else "false"))
    lines.append('\t\t"desc": "%s",' % a["desc"].replace('"', '\\"'))
    lines.append('\t\t"arff": %d, "fuel": true, "pax_per_day": %d,' % (a["arff"], a["ppd"]))
    lines.append('\t},')
open("airports_snippet.gd", "w").write("\n".join(lines) + "\n")
print("ORDER:", ", ".join('"%s"' % a["icao"] for a in AIRPORTS))
print(len(landmarks), "landmarks;", len(rivers), "rivers;", len(lakes), "lakes;", len(parks), "parks")
for l in landmarks:
    if l[2].startswith("bridge"):
        print(l[0], "%.0f %.0f yaw %.1f" % (l[3], l[4], l[5]))
