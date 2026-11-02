import math
from geo_real import *

LAKES_KM = [(n, km(lo, la), (rx, rz), lev) for n, lo, la, rx, rz, lev in LAKES]

def in_lake(xkm, zkm):
    for n, c, r, lev in LAKES_KM:
        q = ((xkm - c[0]) / r[0]) ** 2 + ((zkm - c[1]) / r[1]) ** 2
        if q < 1.3:
            return n
    return ""

def ap_pos(a):
    x, z = km(a["lon"], a["lat"])
    return x + a["nudge"][0], z + a["nudge"][1]

for a in AIRPORTS:
    x, z = ap_pos(a)
    ins, d = land_info(x, z)
    cx, cz = x + a["city_off"][0] / 1000.0, z + a["city_off"][1] / 1000.0
    cins, cd = land_info(cx, cz)
    # how much of the city disc is land
    land = 0
    tot = 0
    for k in range(24):
        for rr in (0.3, 0.6, 0.9):
            ang = k / 24 * math.tau
            px = cx + math.cos(ang) * a["radius"] / 1000 * rr
            pz = cz + math.sin(ang) * a["radius"] / 1000 * rr
            i2, _ = land_info(px, pz)
            if i2 and not in_lake(px, pz):
                land += 1
            tot += 1
    # runway ends inland?
    worst = 1e9
    for rw in a["runways"]:
        hdg = math.radians(rw[1]); dirx, dirz = math.sin(hdg), -math.cos(hdg)
        rx_, rz_ = -dirz, dirx
        c = (x + (rx_ * rw[4] + dirx * rw[5]) / 1000, z + (rz_ * rw[4] + dirz * rw[5]) / 1000)
        for s in (-1, 1):
            ex = c[0] + dirx * rw[2] / 2000 * s; ez = c[1] + dirz * rw[2] / 2000 * s
            i3, d3 = land_info(ex, ez)
            worst = min(worst, d3 if i3 else -d3)
    print("%s ap %s(%.1f km) lake[%s] rwy-ends min %.1f | city %s(%.1f) lake[%s] land %d%%" % (
        a["icao"], "LAND" if ins else "SEA ", d, in_lake(x, z), worst, "LAND" if cins else "SEA ", cd, in_lake(cx, cz), land * 100 // tot))
