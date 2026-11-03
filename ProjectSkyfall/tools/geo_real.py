# Real-world region data (lon, lat) for Project Skyfall, compressed 1:5 onto the game map.
import math

LON0, LAT0, SCALE = -40.0, 45.0, 5.0
KX = 111320.0 * math.cos(math.radians(LAT0)) / SCALE   # m per deg lon
KZ = 110574.0 / SCALE                                  # m per deg lat
ORIGIN_Z = 1300000.0

def ll(lon, lat):
    """lon/lat -> world metres (x east, z south)"""
    return ((lon - LON0) * KX, ORIGIN_Z + (LAT0 - lat) * KZ)

def km(lon, lat):
    x, z = ll(lon, lat)
    return (x / 1000.0, z / 1000.0)

GRID_X0, GRID_X1 = -1360000.0, 952000.0
GRID_Z0, GRID_Z1 = 696000.0, 1832000.0
CELL = 8000.0

# ------------------------------------------------------------------ coastlines (lon, lat)
NORTH_AMERICA = [
 (-135,70),(-133,58),(-130.5,54.5),(-128.5,51.5),(-125.5,49.5),(-124.7,48.4),(-124.1,46.2),(-124.0,43.3),
 (-124.3,41.5),(-123.8,39.5),(-123.05,38.0),(-122.62,37.8),(-122.52,37.4),(-121.9,36.6),(-121.3,35.6),(-120.6,34.6),(-119.2,34.25),
 (-118.55,34.02),(-118.45,33.75),(-117.9,33.6),(-117.2,32.7),(-116.7,31.8),(-115.8,30.4),(-114.2,28.0),
 (-112.2,25.5),(-109.9,22.9),(-109.6,23.6),(-110.6,24.4),(-112.0,26.8),(-113.5,29.0),(-114.8,31.6),
 (-113.0,31.2),(-111.0,29.0),(-109.5,27.0),(-108.0,25.4),(-106.4,23.2),(-105.3,21.0),(-104.5,19.2),
 (-102.0,17.9),(-100.0,17.0),(-96.0,15.7),(-94.5,16.2),(-94.5,18.2),(-96.1,19.2),(-97.4,21.0),(-97.8,22.3),
 (-97.5,24.5),(-97.2,25.9),(-97.4,27.8),(-96.0,28.6),(-94.8,29.3),(-93.0,29.7),(-91.0,29.2),(-89.2,29.0),
 (-89.6,30.2),(-88.0,30.4),(-86.5,30.4),(-85.4,29.7),(-84.3,30.0),(-83.0,29.1),(-82.7,27.9),(-82.1,26.6),
 (-81.6,25.9),(-81.0,25.15),(-80.25,25.1),(-79.75,25.75),(-79.75,26.7),(-80.45,28.4),(-81.2,29.8),(-81.4,30.4),
 (-81.0,31.8),(-80.0,32.7),(-78.6,33.8),(-77.9,34.1),(-76.6,34.7),(-75.5,35.2),(-75.7,36.5),(-76.0,36.95),
 (-75.6,37.7),(-75.1,38.4),(-75.05,38.8),(-74.9,38.95),(-74.4,39.4),(-74.0,40.1),(-73.95,40.45),(-73.5,40.55),
 (-72.6,40.8),(-71.86,41.07),(-72.3,41.15),(-71.4,41.45),(-70.65,41.55),(-69.95,41.65),(-70.05,42.05),(-70.6,42.0),
 (-70.95,42.33),(-70.75,42.65),(-70.7,43.1),(-70.2,43.65),(-69.0,44.0),(-68.2,44.35),(-67.0,44.8),(-66.0,45.25),
 (-64.5,45.7),(-65.7,44.7),(-66.1,43.8),(-65.3,43.5),(-63.6,44.6),(-61.5,45.1),(-60.0,45.9),(-60.6,47.0),
 (-61.5,45.9),(-64.2,46.2),(-64.9,47.5),(-64.3,48.5),(-65.7,49.1),(-68.0,48.8),(-70.0,47.5),(-69.5,48.3),
 (-67.5,49.3),(-66.4,50.2),(-64.0,50.25),(-61.0,50.2),(-58.0,51.2),(-56.5,51.6),(-55.8,52.5),(-56.0,53.7),
 (-57.5,54.6),(-59.5,55.3),(-61.5,56.5),(-62.5,58.0),(-64.4,60.3),(-66.0,59.0),(-67.6,58.4),(-69.3,59.1),
 (-69.6,60.9),(-71.5,61.2),(-73.5,62.0),(-77.5,62.5),(-78.0,60.5),(-77.0,58.0),(-76.7,56.0),(-77.7,55.0),
 (-78.9,53.5),(-79.3,52.0),(-79.9,51.3),(-81.0,52.5),(-82.3,53.0),(-82.2,55.0),(-85.0,55.3),(-87.5,55.9),
 (-90.5,57.1),(-92.5,57.2),(-94.2,58.7),(-94.8,60.0),(-94.0,61.5),(-92.5,62.8),(-90.8,63.6),(-87.0,64.5),
 (-86.5,66.5),(-90.0,68.5),(-95.0,68.0),(-100.0,67.8),(-108.0,68.0),(-115.0,67.5),(-125.0,69.0),(-135.0,69.5),
]
BAFFIN = [(-65.5,61.9),(-64.2,63.3),(-65.0,64.8),(-62.5,66.5),(-61.8,67.2),(-64.0,68.0),(-67.0,69.5),(-69.5,70.6),
 (-72.0,72.5),(-80.0,72.5),(-82.0,70.0),(-80.0,68.6),(-74.0,67.4),(-72.5,66.4),(-71.5,64.0),(-68.0,63.0)]
GREENLAND = [(-43.5,59.8),(-45.5,60.6),(-48.0,61.0),(-50.5,63.0),(-51.7,64.2),(-52.8,65.6),(-53.7,66.9),(-53.0,68.5),
 (-51.2,69.2),(-54.5,70.3),(-55.0,71.5),(-56.5,72.6),(-60.0,76.0),(-20.0,76.0),(-21.5,72.0),(-22.0,70.5),
 (-24.5,69.5),(-27.5,68.5),(-32.0,68.2),(-35.5,66.0),(-38.5,65.5),(-40.5,64.0),(-41.5,62.8),(-42.5,61.0)]
ICELAND = [(-22.72,63.80),(-22.85,64.05),(-22.35,64.10),(-21.95,64.15),(-21.75,64.35),(-22.3,64.55),(-23.0,64.72),(-24.1,64.85),
 (-23.3,65.0),(-22.3,65.1),(-24.4,65.5),(-23.5,66.2),(-22.4,66.4),(-21.0,66.1),(-19.5,66.1),(-18.0,66.2),(-16.0,66.5),
 (-14.6,66.3),(-14.5,65.5),(-13.6,65.1),(-14.5,64.4),(-15.5,64.2),(-16.8,63.8),(-18.5,63.4),(-20.2,63.5),(-21.4,63.82)]
NEWFOUNDLAND = [(-52.65,47.55),(-53.2,46.65),(-54.0,46.85),(-55.5,47.1),(-56.2,47.6),(-59.3,47.6),(-59.0,48.5),(-58.0,49.5),
 (-57.2,50.8),(-55.6,51.6),(-55.6,50.0),(-54.0,49.5),(-53.5,48.7),(-53.0,48.0)]
CUBA = [(-84.95,21.9),(-83.5,22.9),(-82.4,23.15),(-81.0,23.1),(-80.0,22.95),(-78.0,22.3),(-77.0,21.6),(-75.6,21.1),
 (-74.15,20.2),(-74.6,19.9),(-75.8,19.95),(-77.7,19.85),(-77.3,20.7),(-79.0,21.6),(-80.4,21.8),(-81.5,22.1),
 (-82.5,22.3),(-83.5,21.9),(-84.4,21.75)]
BRITAIN = [(-5.7,50.05),(-5.0,50.0),(-4.2,50.35),(-3.6,50.25),(-3.4,50.6),(-2.45,50.6),(-1.6,50.7),(-1.0,50.75),
 (0.25,50.75),(1.0,50.95),(1.4,51.15),(1.45,51.4),(0.9,51.55),(1.3,51.8),(1.75,52.45),(1.65,52.95),(0.9,52.97),
 (0.35,52.85),(0.35,53.1),(0.3,53.5),(-0.05,53.65),(-0.2,54.1),(-0.6,54.5),(-1.2,54.7),(-1.45,55.05),(-1.6,55.6),
 (-2.05,55.85),(-2.5,56.05),(-2.6,56.3),(-2.5,56.6),(-2.1,57.15),(-1.8,57.5),(-2.5,57.7),(-3.6,57.65),(-4.1,57.6),
 (-3.8,57.85),(-3.05,58.6),(-3.4,58.65),(-5.0,58.6),(-5.3,58.25),(-5.7,57.85),(-5.65,57.3),(-5.8,56.8),(-5.6,56.5),
 (-5.5,56.0),(-5.7,55.35),(-5.0,55.5),(-4.9,55.85),(-4.6,55.4),(-5.05,55.0),(-5.0,54.65),(-4.4,54.75),(-3.6,54.95),
 (-3.4,54.5),(-3.0,54.1),(-3.05,53.75),(-3.0,53.4),(-3.6,53.3),(-4.6,53.4),(-4.6,52.85),(-4.1,52.6),(-4.2,52.25),
 (-4.7,52.05),(-5.3,51.85),(-5.0,51.6),(-4.2,51.55),(-3.2,51.4),(-2.7,51.55),(-3.0,51.2),(-3.6,51.2),(-4.2,51.2),
 (-4.6,50.95),(-5.0,50.55)]
IRELAND = [(-9.8,51.45),(-8.5,51.6),(-7.5,51.95),(-6.4,52.17),(-6.0,52.95),(-6.05,53.33),(-6.2,53.9),(-5.45,54.25),
 (-5.5,54.6),(-5.8,55.0),(-6.25,55.2),(-7.4,55.38),(-8.0,55.2),(-8.6,54.95),(-8.3,54.55),(-9.2,54.3),(-10.1,54.25),
 (-9.9,53.6),(-10.2,53.4),(-9.0,53.2),(-9.5,52.7),(-10.4,52.15),(-10.2,51.8)]
EUROPE = [(-5.6,36.0),(-6.3,36.5),(-7.4,37.2),(-8.0,37.0),(-8.95,37.0),(-8.8,38.0),(-9.5,38.75),(-9.0,39.6),(-8.7,41.2),
 (-8.9,42.1),(-9.3,42.9),(-8.4,43.4),(-7.7,43.75),(-5.8,43.6),(-3.8,43.45),(-1.8,43.4),(-1.5,43.6),(-1.25,44.6),(-1.2,45.7),
 (-1.4,46.2),(-2.1,46.8),(-2.5,47.3),(-3.2,47.5),(-4.4,47.8),(-4.75,48.35),(-4.2,48.65),(-3.0,48.8),(-2.0,48.65),(-1.6,48.75),
 (-1.85,49.7),(-1.2,49.4),(-0.2,49.3),(0.1,49.48),(0.6,49.85),(1.6,50.25),(1.6,50.75),(1.85,50.95),(2.55,51.08),(3.25,51.35),
 (3.7,51.45),(4.05,51.95),(4.5,52.35),(4.7,52.95),(6.0,53.45),(7.2,53.55),(8.0,53.6),(8.7,53.9),(8.85,54.4),(8.3,55.0),
 (8.15,55.6),(8.1,56.5),(8.6,57.1),(10.6,57.75),(10.5,57.2),(10.3,56.5),(10.9,56.4),(9.7,55.5),(9.9,54.85),(10.9,54.4),
 (11.0,54.0),(12.1,54.15),(13.4,54.6),(14.2,53.95),(15.6,54.2),(16.9,54.6),(18.6,54.8),(18.65,54.4),(19.6,54.45),(20.5,54.95),
 (21.1,55.7),(21.0,56.5),(21.6,57.4),(22.6,57.75),(24.1,57.0),(24.4,58.4),(23.4,58.8),(23.4,59.3),(24.7,59.45),(28.0,59.5),
 (30.3,59.95),(29.0,60.2),(26.9,60.4),(25.0,60.15),(22.9,59.85),(21.4,60.6),(21.3,61.5),(21.6,63.0),(23.5,64.0),(25.3,65.0),
 (24.2,65.8),(22.1,65.6),(21.0,64.6),(19.2,63.6),(17.6,62.4),(17.3,61.0),(17.4,60.6),(18.6,60.15),(18.9,59.6),(18.1,59.3),
 (16.8,58.7),(16.6,57.9),(16.4,56.65),(15.6,56.2),(14.3,55.5),(12.9,55.35),(12.7,56.05),(12.5,56.6),(11.9,57.7),(11.2,58.4),
 (11.1,59.0),(10.7,59.9),(10.2,59.0),(9.6,59.0),(8.0,58.15),(6.6,58.05),(5.6,58.9),(5.0,59.6),(5.0,60.4),(4.8,61.2),(5.1,62.0),
 (6.2,62.6),(7.7,63.1),(9.0,63.7),(10.5,64.4),(11.4,65.0),(12.5,66.0),(13.4,67.0),(14.4,67.3),(15.4,68.3),(16.5,69.0),
 (18.9,69.65),(21.0,70.1),(23.7,70.7),(25.8,71.15),(28.0,71.0),(31.0,70.3),(40.0,68.0),(40.0,42.0),(29.0,41.0),(26.5,40.2),
 (24.0,40.8),(23.0,40.6),(22.6,40.0),(23.0,39.3),(22.9,38.6),(23.6,38.0),(23.1,37.4),(22.5,36.45),(22.1,37.0),(21.7,36.8),
 (21.1,37.8),(21.4,38.3),(20.9,38.9),(20.2,39.5),(19.4,40.4),(19.5,41.3),(19.2,41.9),(18.5,42.45),(17.0,43.0),(15.9,43.6),
 (15.2,44.2),(14.5,45.2),(13.6,44.9),(13.75,45.65),(12.3,45.4),(12.3,44.6),(12.6,44.05),(13.6,43.5),(14.2,42.45),(15.0,42.0),
 (16.15,41.9),(16.9,41.1),(18.0,40.6),(18.5,40.1),(18.35,39.8),(17.3,40.45),(16.6,40.0),(16.5,39.4),(17.15,39.0),(16.5,38.4),
 (15.65,37.95),(15.7,38.25),(16.0,38.7),(15.9,39.5),(15.6,40.05),(14.9,40.3),(14.25,40.8),(13.75,41.25),(12.85,41.4),
 (12.2,41.72),(11.8,42.1),(11.15,42.45),(10.5,42.95),(10.3,43.55),(10.1,44.05),(8.9,44.4),(8.1,43.9),(7.5,43.75),(7.0,43.55),
 (6.2,43.1),(5.35,43.3),(4.6,43.4),(3.6,43.3),(3.05,42.55),(3.25,41.95),(2.2,41.35),(1.1,41.05),(0.85,40.7),(-0.3,39.45),
 (0.2,38.75),(-0.5,38.3),(-0.75,37.6),(-1.6,37.25),(-2.2,36.7),(-3.5,36.7),(-4.4,36.7),(-5.35,36.15)]
AFRICA = [(-5.9,35.8),(-6.2,35.1),(-6.8,34.0),(-7.6,33.6),(-8.5,33.2),(-9.25,32.3),(-9.8,31.4),(-9.6,30.4),(-10.2,29.4),
 (-11.5,28.2),(-13.0,27.6),(-14.5,26.1),(-15.9,23.8),(-16.9,21.3),(-16.5,19.0),(-17.0,14.7),(-15.0,10.0),(40.0,10.0),
 (32.3,31.3),(30.0,31.4),(25.0,31.6),(23.0,32.5),(21.5,32.9),(20.0,32.1),(19.5,30.5),(18.0,30.8),(16.5,31.2),(15.2,32.3),
 (13.2,32.9),(11.5,33.2),(10.8,33.8),(10.1,34.2),(10.8,34.8),(11.1,35.5),(10.6,35.9),(11.05,36.85),(10.3,36.85),(9.8,37.35),
 (8.6,36.95),(7.8,36.9),(6.5,37.1),(5.1,36.8),(3.1,36.8),(1.3,36.5),(-0.65,35.75),(-1.9,35.15),(-3.0,35.3),(-4.4,35.25),(-5.3,35.9)]
POLYS = [("North America", NORTH_AMERICA), ("Baffin Island", BAFFIN), ("Greenland", GREENLAND), ("Iceland", ICELAND),
         ("Newfoundland", NEWFOUNDLAND), ("Cuba", CUBA), ("Great Britain", BRITAIN), ("Ireland", IRELAND),
         ("Europe", EUROPE), ("Africa", AFRICA)]

# [lon, lat, rx_km, rz_km]  (game km radii)
ISLANDS = [(11.95,55.5,13,9),(10.4,55.3,5,5),(2.95,39.6,10,7.5),(9.05,42.15,8.3,18.3),(9.0,40.05,12,27),(14.1,37.55,28,19),(-16.6,28.3,6,5),(-15.55,27.95,5,5),
 (-14.0,28.4,5,10),(-25.45,37.78,13,3.2),(-27.2,38.7,3.5,2.5),(-28.4,38.5,5,2.5),(-16.95,32.72,11,4.6),(-64.75,32.32,7.5,3.2),
 (-6.9,62.05,7.5,11),(-1.25,60.3,3,14),(-3.0,59.0,5,4),(-7.0,57.8,3,20),(-4.5,54.2,2.5,3.3),(11.8,55.5,12,10),(10.3,55.3,6,6),
 (18.5,57.5,5,13),(14.9,55.1,3,2.5),(-63.3,46.4,22,3),(-62.9,49.45,22,5.5),(-78.5,26.6,9.6,1.8),(-77.9,24.4,6,15),
 (-77.4,25.05,2.2,1.2),(-70.6,41.4,2.5,1.0),(-70.05,41.28,2.5,1.0),(-5.95,57.25,3,5),(-6.2,56.4,3,3),(-2.15,49.21,1.8,1.2)]

# rises [lon, lat, rx_km, rz_km, peak]
RISES = [(-101.0,40.0,90,140,950),(-115.2,36.1,30,30,620),(11.6,48.3,35,25,420),(8.3,47.3,22,14,380),(-84.4,33.9,40,30,230),(-97.1,32.9,35,35,120),(-103.4,39.8,30,30,700),(11.0,60.3,20,18,170),(-9.1,38.8,8,8,90),(-86.0,41.0,90,60,190),(-72.0,51.5,110,70,450),(-63.0,54.0,50,40,500),
 (-102.0,24.0,70,80,1600),(-116.5,39.5,50,60,1300),(-110.5,37.0,50,40,1500),(-92.5,36.5,25,18,350),(-99.0,30.5,35,25,400),
 (-3.8,40.2,55,50,640),(3.0,45.3,20,18,900),(2.5,48.8,40,30,95),(-4.5,57.2,25,20,750),(-3.7,52.4,12,15,450),(-2.2,54.3,8,25,420),
 (-18.5,64.9,35,15,1100),(-42.0,67.5,65,120,2600),(15.5,63.0,40,60,450),(26.0,63.0,35,45,150),(10.0,50.5,40,25,420),
 (14.5,49.8,25,20,450),(19.5,43.0,30,30,1100),(5.0,28.0,150,80,400),(-80.5,39.5,35,30,350),(-68.0,68.0,40,30,1200),
 (9.05,42.15,6,12,1500),(9.0,40.0,8,18,850),(15.0,37.75,6,6,2600),(-24.2,65.7,8,6,500),(-16.6,28.3,4,4,2400),
 (-16.95,32.75,7,3,1300),(-25.4,37.8,8,2,700),(-6.9,62.05,5,8,600),(-93.0,47.5,60,40,300),(-79.5,44.6,40,25,260)]
# ranges [lon_a, lat_a, lon_b, lat_b, radius_km, peak]
RANGES = [(-106.0,33.0,-106.5,39.5,45,2600),(-106.5,39.5,-110.5,44.5,45,2600),(-110.5,44.5,-115.5,49.5,45,2400),
 (-115.5,49.5,-120.0,54.5,40,2400),(-120.0,54.5,-127.0,60.0,40,2000),(-118.0,35.3,-121.3,40.3,18,2800),
 (-121.3,40.3,-121.5,49.0,18,2200),(-120.5,35.4,-123.5,40.0,8,800),(-119.4,34.75,-116.6,34.45,7,1200),
 (-84.5,34.5,-79.5,38.0,22,1100),(-79.5,38.0,-75.8,41.4,16,650),(-74.2,42.3,-71.5,44.6,16,1000),(-75.0,46.3,-70.6,47.6,22,700),
 (-64.0,58.0,-63.0,60.0,15,1300),(-104.0,21.0,-108.5,30.0,35,2200),(-99.5,21.0,-101.5,26.0,25,2000),
 (6.8,44.0,7.8,46.0,22,3000),(7.8,46.0,10.5,46.6,22,3100),(10.5,46.6,13.5,47.2,22,2800),(13.5,47.2,16.0,47.6,15,1500),
 (-1.8,43.0,2.9,42.5,12,2400),(-7.5,43.0,-3.5,43.1,10,1700),(-4.0,37.0,-2.5,37.1,8,2300),(8.5,44.4,11.5,43.8,9,1500),
 (11.5,43.8,14.4,42.1,8,1900),(14.4,42.1,16.2,39.0,9,1600),(14.5,45.5,19.5,42.0,15,1700),(6.5,59.0,9.5,62.5,30,1800),
 (9.5,62.5,14.5,66.5,25,1500),(14.5,66.5,20.0,69.0,22,1400),(-9.5,30.8,-4.5,32.5,22,3000),(-4.5,32.5,3.0,35.0,18,2000),
 (3.0,35.0,9.0,35.8,15,1500)]

# lakes [name, lon, lat, rx_km, rz_km, level]
LAKES = [("Lake Superior",-87.6,47.65,54,22,183),("Lake Michigan",-87.0,44.0,17,47,176),("Lake Huron",-82.4,44.85,27,22,176),
 ("Lake Erie",-81.2,42.15,37,8,174),("Lake Ontario",-77.7,43.55,27,6.5,75),("Lake Okeechobee",-80.83,26.95,5,5,4),
 ("Great Salt Lake",-112.5,41.1,7,9,1280),("Lake Winnipeg",-97.5,52.2,9,38,217),("Lake Geneva",6.55,46.45,7,1.6,372),
 ("Lake Vänern",13.2,58.9,13,7,44),("Lake Vättern",14.5,58.3,2.6,12,88),("IJsselmeer",5.45,52.9,6,6,0),
 ("Lake Champlain",-73.3,44.5,1.8,12,30),("Lake Balaton",17.7,46.85,7,1.2,104)]

# rivers [name, width_m, [(lon,lat)...]]  (must end at the sea)
RIVERS = [("Mississippi",900,[(-95.2,47.2),(-93.2,45.0),(-91.2,43.0),(-90.6,41.5),(-91.1,40.0),(-90.2,38.6),(-89.3,37.0),
  (-90.0,35.1),(-91.1,33.0),(-91.4,31.5),(-91.2,30.4),(-90.1,29.95),(-89.4,29.25)]),
 ("St. Lawrence",1600,[(-76.4,44.15),(-75.0,44.9),(-73.55,45.5),(-72.5,46.3),(-71.2,46.8),(-70.2,47.35)]),
 ("Rhine",500,[(7.6,47.55),(7.6,48.6),(8.4,49.5),(8.25,50.0),(7.6,50.35),(6.95,50.95),(6.65,51.45),(5.9,51.85),(4.6,51.92),(4.15,51.95)]),
 ("Danube",600,[(8.5,48.0),(12.0,49.0),(14.3,48.3),(16.4,48.2),(17.1,48.15),(18.9,47.8),(19.05,47.5),(18.9,46.0),(20.3,45.2),(22.5,44.4)]),
 ("Loire",300,[(4.0,45.5),(2.9,47.2),(1.9,47.9),(0.7,47.4),(-0.55,47.45),(-1.55,47.2),(-2.3,47.27)]),
 ("Tagus",300,[(-2.5,40.4),(-4.0,39.85),(-6.0,39.65),(-7.5,39.4),(-8.9,38.8),(-9.3,38.68)]),
 ("Po",260,[(7.7,45.05),(9.2,45.15),(10.8,45.05),(12.0,44.95),(12.5,44.95)]),
 ("Rhône",300,[(4.8,45.75),(4.8,44.0),(4.65,43.35)]),
 ("Columbia",700,[(-118.9,46.2),(-121.0,45.65),(-122.9,45.9),(-123.95,46.25)]),
 ("Colorado",160,[(-109.0,38.6),(-111.6,36.1),(-114.0,36.0),(-114.6,35.0),(-114.6,33.6),(-114.85,31.75)]),
 ("Elbe",350,[(14.4,50.5),(12.4,51.6),(11.6,52.6),(10.0,53.55),(8.8,53.9)])]

LABELS = [("NORTH AMERICA",-98,47),("UNITED STATES",-95,38),("CANADA",-100,58),("GREENLAND",-41,70),("ICELAND",-19,65.2),
 ("ATLANTIC OCEAN",-40,38),("NORTH SEA",3.5,56),("GULF OF MEXICO",-90,25.3),("HUDSON BAY",-86,59),("MEDITERRANEAN SEA",6,38.2),
 ("EUROPE",14,52),("UNITED KINGDOM",-2.2,53.5),("FRANCE",2.5,46.8),("SPAIN",-3.8,40.0),("ITALY",12.5,43.0),("IRELAND",-8.0,53.2),
 ("AFRICA",0,28),("GERMANY",10.4,51.2),("NORWAY",9.0,61.6),("SWEDEN",15.6,61.8),("DENMARK",9.2,56.1),("SWITZERLAND",8.2,46.75),("AUSTRIA",14.4,47.55),("BELGIUM",4.6,50.6),("PORTUGAL",-8.1,39.7),("BALTIC SEA",19.0,57.0),("TEXAS",-99.0,31.0),("ROCKY MOUNTAINS",-108.5,42.0),("PACIFIC OCEAN",-125,33),("CARIBBEAN",-78,21.6)]

# ------------------------------------------------------------------ airports
# real airport positions, nudged where the 1:5 coastline needs it (km east, km south)
AIRPORTS = [
 dict(icao="KJFK", iata="JFK", name="John F. Kennedy International", short="New York JFK", city="New York", country="United States",
      lon=-73.78, lat=40.64, nudge=(0,-2.0), elev=4, size="hub", gates=32, between=True, side=1, style="hub",
      runways=[("04L/22R",44,3460,60,-800,0,(True,True)),("04R/22L",44,2560,60,800,-300,(True,True)),("13R/31L",134,4420,60,-2650,0,(True,True))],
      city_off=(-6500,-5200), radius=13000, pop=8300000, tall=1.6, coastal=True,
      desc="The gateway to America: four runways, a vast terminal complex and Manhattan's skyline on the horizon.", arff=10, ppd=170000),
 dict(icao="KBOS", iata="BOS", name="Boston Logan International", short="Boston", city="Boston", country="United States",
      lon=-71.01, lat=42.36, nudge=(-2.5,0.5), elev=6, size="hub", gates=16, between=False, side=-1, style="hub",
      runways=[("04R/22L",40,3050,45,0,0,(True,True)),("15R/33L",150,3070,45,1900,300,(True,True))],
      city_off=(-6000,-1500), radius=7000, pop=680000, tall=0.95, coastal=True,
      desc="A harbour airport hemmed in by water on three sides, with the city's towers a stone's throw away.", arff=9, ppd=60000),
 dict(icao="KIAD", iata="IAD", name="Washington Dulles International", short="Washington Dulles", city="Washington", country="United States",
      lon=-77.46, lat=38.95, nudge=(0,0), elev=95, size="hub", gates=20, between=True, side=1, style="hub",
      runways=[("01R/19L",10,3500,45,800,0,(True,True)),("01C/19C",10,3500,45,-800,200,(True,True)),("12/30",120,3200,45,-2900,-1800,(True,True))],
      city_off=(17000,1200), radius=8000, pop=690000, tall=0.4, coastal=False,
      desc="The capital's international gateway in the Virginia countryside, a short drive from the Capitol and the Mall.", arff=9, ppd=66000),
 dict(icao="KORD", iata="ORD", name="Chicago O'Hare International", short="Chicago O'Hare", city="Chicago", country="United States",
      lon=-87.90, lat=41.98, nudge=(-6.0,1.0), elev=205, size="hub", gates=28, between=True, side=1, style="hub",
      runways=[("10L/28R",100,3960,45,-800,0,(True,True)),("10C/28C",100,3290,60,800,250,(True,True)),("04R/22L",40,2460,45,-2600,1200,(True,True))],
      city_off=(10000,2000), radius=11000, pop=2700000, tall=1.35, coastal=True,
      desc="One of the busiest airports on earth: a web of parallel runways on the prairie beside Lake Michigan.", arff=10, ppd=150000),
 dict(icao="CYYZ", iata="YYZ", name="Toronto Pearson International", short="Toronto", city="Toronto", country="Canada",
      lon=-79.63, lat=43.68, nudge=(-3.0,-1.5), elev=173, size="hub", gates=20, between=True, side=1, style="hub",
      runways=[("05/23",57,3390,60,-750,0,(True,True)),("06L/24R",57,2960,60,750,300,(True,True))],
      city_off=(13000,-1500), radius=9000, pop=2800000, tall=1.15, coastal=True,
      desc="Canada's biggest airport, with the CN Tower and the lakefront skyline twenty minutes away.", arff=9, ppd=120000),
 dict(icao="KMIA", iata="MIA", name="Miami International", short="Miami", city="Miami", country="United States",
      lon=-80.29, lat=25.79, nudge=(0,0), elev=3, size="hub", gates=20, between=True, side=1, style="resort",
      runways=[("08R/26L",87,3200,61,650,0,(True,True)),("09/27",90,3960,61,-650,-300,(True,True))],
      city_off=(3000,1000), radius=7500, pop=450000, tall=1.05, coastal=True,
      desc="Sun, thunderstorms and the gateway to the Caribbean, with Miami Beach glittering just across the bay.", arff=9, ppd=110000),
 dict(icao="KLAX", iata="LAX", name="Los Angeles International", short="Los Angeles", city="Los Angeles", country="United States",
      lon=-118.41, lat=33.94, nudge=(2.5,0), elev=38, size="hub", gates=30, between=True, side=1, style="hub",
      runways=[("06R/24L",69,3135,45,-750,0,(True,True)),("07L/25R",69,3685,60,750,250,(True,True))],
      city_off=(11000,-6000), radius=14000, pop=3900000, tall=1.0, coastal=True,
      desc="Approaches over the ocean, departures over the Pacific, and the hills of Hollywood beyond the city.", arff=10, ppd=180000),
 dict(icao="KSFO", iata="SFO", name="San Francisco International", short="San Francisco", city="San Francisco", country="United States",
      lon=-122.38, lat=37.62, nudge=(2.0,0), elev=4, size="hub", gates=18, between=False, side=-1, style="hub",
      runways=[("28L/10R",280,3620,60,0,0,(True,True)),("01R/19L",10,2640,60,1700,600,(True,True))],
      city_off=(-1500,-10500), radius=6500, pop=810000, tall=1.05, coastal=True,
      desc="Fog rolling in under the Golden Gate, a bayside runway and one of the most beautiful approaches anywhere.", arff=9, ppd=110000),
 dict(icao="EGLL", iata="LHR", name="London Heathrow", short="London Heathrow", city="London", country="United Kingdom",
      lon=-0.45, lat=51.47, nudge=(0,0), elev=25, size="hub", gates=32, between=True, side=1, style="hub",
      runways=[("09L/27R",90,3900,50,-720,0,(True,True)),("09R/27L",90,3660,50,720,200,(True,True))],
      city_off=(12500,-1000), radius=13000, pop=8900000, tall=0.8, coastal=False,
      desc="Europe's great hub: two long parallel runways, endless stacks over the city and the Thames winding past Big Ben.", arff=10, ppd=220000),
 dict(icao="LFPG", iata="CDG", name="Paris Charles de Gaulle", short="Paris CDG", city="Paris", country="France",
      lon=2.55, lat=49.01, nudge=(0,0), elev=119, size="hub", gates=30, between=True, side=1, style="hub",
      runways=[("09L/27R",87,4200,60,-1400,0,(True,True)),("09R/27L",87,4200,45,1400,300,(True,True))],
      city_off=(-6000,11000), radius=10000, pop=2100000, tall=0.45, coastal=False,
      desc="France's front door: four runways, futuristic terminals and the Eiffel Tower on the skyline.", arff=10, ppd=200000),
 dict(icao="EHAM", iata="AMS", name="Amsterdam Schiphol", short="Amsterdam", city="Amsterdam", country="Netherlands",
      lon=4.76, lat=52.31, nudge=(1.5,0), elev=2, size="hub", gates=24, between=False, side=-1, style="hub",
      runways=[("18C/36C",183,3300,45,0,0,(True,True)),("18R/36L",183,3800,60,2600,-600,(True,True)),("06/24",58,3500,45,-1500,-2500,(True,True))],
      city_off=(8500,-5500), radius=6500, pop=900000, tall=0.4, coastal=True,
      desc="Below sea level and famously flat: windmills, canals and the long taxi out to the Polderbaan.", arff=9, ppd=190000),
 dict(icao="EIDW", iata="DUB", name="Dublin Airport", short="Dublin", city="Dublin", country="Ireland",
      lon=-6.27, lat=53.42, nudge=(-1.0,0), elev=74, size="regional", gates=14, between=False, side=1, style="hub",
      runways=[("10R/28L",100,3110,45,0,0,(True,True)),("16/34",160,2070,45,1700,500,(True,False))],
      city_off=(1500,6500), radius=6500, pop=590000, tall=0.35, coastal=True,
      desc="The first landfall after the Atlantic crossing, Atlantic weather and a city on the River Liffey.", arff=8, ppd=90000),
 dict(icao="LEMD", iata="MAD", name="Madrid-Barajas", short="Madrid", city="Madrid", country="Spain",
      lon=-3.56, lat=40.47, nudge=(0,0), elev=610, size="hub", gates=26, between=True, side=1, style="hub",
      runways=[("18L/36R",180,3500,60,-900,0,(True,True)),("18R/36L",180,4350,60,900,-300,(True,True))],
      city_off=(-8000,5500), radius=9500, pop=3300000, tall=0.6, coastal=False,
      desc="High on the Spanish plateau: hot summers, crisp winters and long runways for thin air.", arff=9, ppd=170000),
 dict(icao="LIRF", iata="FCO", name="Rome Fiumicino", short="Rome", city="Rome", country="Italy",
      lon=12.25, lat=41.80, nudge=(2.5,-1.0), elev=4, size="hub", gates=22, between=True, side=1, style="hub",
      runways=[("16R/34L",160,3900,60,800,0,(True,True)),("16L/34R",160,3900,45,-800,500,(True,True))],
      city_off=(10000,-8500), radius=9000, pop=2800000, tall=0.3, coastal=True,
      desc="Beside the sea where the Tiber meets it, a short hop from the Colosseum and St Peter's.", arff=9, ppd=120000),
 dict(icao="BIKF", iata="KEF", name="Keflavik International", short="Reykjavik", city="Reykjavik", country="Iceland",
      lon=-22.62, lat=63.99, nudge=(0,0), elev=52, size="regional", gates=10, between=False, side=1, style="island",
      runways=[("01/19",10,3050,60,0,0,(True,True)),("10/28",100,3060,60,1600,700,(True,True))],
      city_off=(11500,-1800), radius=3800, pop=135000, tall=0.25, coastal=True,
      desc="Lava fields, howling crosswinds and the northern lights: the mid-Atlantic stop between two continents.", arff=8, ppd=24000),
 dict(icao="TXKF", iata="BDA", name="L.F. Wade International", short="Bermuda", city="Hamilton", country="Bermuda",
      lon=-64.68, lat=32.36, nudge=(0,0), elev=4, size="regional", gates=5, between=False, side=1, style="island",
      runways=[("12/30",120,2960,45,0,0,(True,True))],
      city_off=(-4500,1200), radius=2200, pop=64000, tall=0.2, coastal=True,
      desc="A tiny coral island alone in the middle of the Atlantic: pink beaches and nowhere else to land for a thousand kilometres.", arff=7, ppd=4000),
 dict(icao="LPPD", iata="PDL", name="Ponta Delgada", short="Azores", city="Ponta Delgada", country="Portugal",
      lon=-25.70, lat=37.75, nudge=(0,0), elev=79, size="regional", gates=5, between=False, side=1, style="island",
      runways=[("12/30",120,2490,45,0,0,(True,True))],
      city_off=(3000,1200), radius=2400, pop=68000, tall=0.2, coastal=True,
      desc="Volcanic islands in mid-ocean, crater lakes and Atlantic gales. A favourite diversion airport.", arff=7, ppd=5000),
 dict(icao="LPMA", iata="FNC", name="Madeira Airport", short="Madeira", city="Funchal", country="Portugal",
      lon=-16.78, lat=32.70, nudge=(0,0), elev=58, size="regional", gates=6, between=False, side=-1, style="island",
      runways=[("05/23",50,2780,45,0,0,(True,True))],
      city_off=(-5000,600), radius=2600, pop=105000, tall=0.25, coastal=True,
      desc="A runway built out over the sea on stilts beneath steep mountains: one of the world's most demanding approaches.", arff=7, ppd=9000),
 dict(icao="EKVG", iata="FAE", name="Vagar Airport", short="Faroe Islands", city="Torshavn", country="Faroe Islands",
      lon=-7.28, lat=62.06, nudge=(0,0), elev=85, size="regional", gates=3, between=False, side=1, style="island",
      runways=[("12/30",120,1800,30,0,0,(True,False))],
      city_off=(5500,1500), radius=1800, pop=22000, tall=0.15, coastal=True,
      desc="A short runway in a fjord valley ringed by sea cliffs, sheep and sideways rain.", arff=5, ppd=1800),
 dict(icao="CYQX", iata="YQX", name="Gander International", short="Gander", city="Gander", country="Canada",
      lon=-54.57, lat=48.94, nudge=(0,0), elev=151, size="regional", gates=6, between=False, side=1, style="regional",
      runways=[("03/21",30,3200,60,0,0,(True,True)),("13/31",130,2130,45,1500,300,(True,False))],
      city_off=(4500,-2500), radius=2200, pop=12000, tall=0.15, coastal=False,
      desc="The legendary North Atlantic waypoint where dozens of airliners once diverted in a single day.", arff=7, ppd=1500),
 dict(icao="BGGH", iata="GOH", name="Nuuk Airport", short="Nuuk", city="Nuuk", country="Greenland",
      lon=-51.68, lat=64.19, nudge=(3.0,0), elev=86, size="regional", gates=3, between=False, side=1, style="island",
      runways=[("05/23",50,2200,45,0,0,(True,True))],
      city_off=(1500,2500), radius=1800, pop=19000, tall=0.15, coastal=True,
      desc="Greenland's capital between ice cap and fjord. Icebergs float past the end of the runway.", arff=5, ppd=1200),

 # ---- United States (second wave)
 dict(icao="KATL", iata="ATL", name="Hartsfield-Jackson Atlanta International", short="Atlanta", city="Atlanta", country="United States",
      lon=-84.43, lat=33.64, nudge=(0,0), elev=330, size="hub", gates=32, between=True, side=1, style="hub",
      runways=[("08L/26R",90,2740,45,-1250,0,(True,True)),("09L/27R",90,3780,45,1250,400,(True,True))],
      city_off=(1500,-11500), radius=7000, pop=6100000, tall=1.25, coastal=False,
      desc="The busiest airport on the planet: a conveyor belt of arrivals on parallel runways and the Atlanta skyline rising to the north.", arff=9, ppd=270000),
 dict(icao="KDFW", iata="DFW", name="Dallas/Fort Worth International", short="Dallas/Fort Worth", city="Dallas", country="United States",
      lon=-97.04, lat=32.90, nudge=(0,0), elev=175, size="hub", gates=32, between=True, side=1, style="hub",
      runways=[("17C/35C",180,4085,60,-1000,0,(True,True)),("17R/35L",180,4085,60,1000,-300,(True,True))],
      city_off=(9500,6500), radius=7500, pop=7600000, tall=1.15, coastal=False,
      desc="A Texas giant bigger than some cities: long parallel runways, big skies and supercell storms rolling in off the plains.", arff=9, ppd=200000),
 dict(icao="KDEN", iata="DEN", name="Denver International", short="Denver", city="Denver", country="United States",
      lon=-104.67, lat=39.86, nudge=(22.0,0), elev=1655, size="hub", gates=28, between=True, side=1, style="hub",
      runways=[("16R/34L",172,4880,60,-1100,0,(True,True)),("17L/35R",172,3660,45,1100,600,(True,True))],
      city_off=(-7000,7500), radius=6000, pop=2900000, tall=1.0, coastal=False,
      desc="The Mile High City: thin air, very long runways and the Rocky Mountains filling the windscreen to the west.", arff=8, ppd=190000),
 dict(icao="KSEA", iata="SEA", name="Seattle-Tacoma International", short="Seattle", city="Seattle", country="United States",
      lon=-122.31, lat=47.45, nudge=(-13.0,0), elev=95, size="hub", gates=26, between=True, side=1, style="hub",
      runways=[("16L/34R",162,3630,45,-900,0,(True,True)),("16R/34L",162,2870,45,900,200,(True,True))],
      city_off=(-1000,-9500), radius=5500, pop=4000000, tall=1.1, coastal=False,
      desc="Rain, evergreen hills and the Cascades towering over the approach. Coffee is mandatory.", arff=8, ppd=140000),
 dict(icao="KLAS", iata="LAS", name="Harry Reid International", short="Las Vegas", city="Las Vegas", country="United States",
      lon=-115.15, lat=36.08, nudge=(0,0), elev=580, size="hub", gates=24, between=True, side=1, style="resort",
      runways=[("08L/26R",82,4420,45,-900,0,(True,True)),("08R/26L",82,3200,45,900,300,(True,True))],
      city_off=(-1500,-8500), radius=5500, pop=2300000, tall=1.2, coastal=False,
      desc="Neon in the desert: the Strip's towers glitter beside the runway and the mountains glow red at sunset.", arff=8, ppd=150000),
 dict(icao="KMSY", iata="MSY", name="Louis Armstrong New Orleans International", short="New Orleans", city="New Orleans", country="United States",
      lon=-90.26, lat=29.99, nudge=(0,0), elev=6, size="regional", gates=16, between=False, side=1, style="regional",
      runways=[("11/29",110,3080,45,0,0,(True,True))],
      city_off=(9500,1500), radius=5500, pop=1200000, tall=0.75, coastal=True,
      desc="Jazz, gumbo and hurricane season: a runway on the edge of the bayou with the Mississippi curling past the French Quarter.", arff=7, ppd=36000),
 dict(icao="KMCO", iata="MCO", name="Orlando International", short="Orlando", city="Orlando", country="United States",
      lon=-81.31, lat=28.43, nudge=(0,0), elev=29, size="hub", gates=24, between=True, side=1, style="resort",
      runways=[("18L/36R",180,3660,60,-1000,0,(True,True)),("17R/35L",180,3660,60,1000,0,(True,True))],
      city_off=(-4000,-8500), radius=5000, pop=2600000, tall=0.6, coastal=False,
      desc="Gateway to the theme parks: families in mouse ears, afternoon thunderstorms like clockwork and long straight runways.", arff=8, ppd=140000),
 # ---- Europe (second wave)
 dict(icao="EDDF", iata="FRA", name="Frankfurt am Main", short="Frankfurt", city="Frankfurt", country="Germany",
      lon=8.57, lat=50.03, nudge=(0,0), elev=125, size="hub", gates=32, between=True, side=1, style="hub",
      runways=[("07L/25R",70,2800,45,-1300,0,(True,True)),("07R/25L",70,4000,45,1300,300,(True,True))],
      city_off=(5500,-6000), radius=5000, pop=2300000, tall=1.35, coastal=False,
      desc="Mainhattan: Germany's banking skyline beside one of Europe's busiest hubs, with the Main river winding through town.", arff=10, ppd=190000),
 dict(icao="EDDM", iata="MUC", name="Munich Franz Josef Strauss", short="Munich", city="Munich", country="Germany",
      lon=11.79, lat=48.35, nudge=(0,0), elev=425, size="hub", gates=28, between=True, side=1, style="hub",
      runways=[("08L/26R",82,4000,60,-1100,0,(True,True)),("08R/26L",82,4000,60,1100,400,(True,True))],
      city_off=(-7000,9000), radius=6000, pop=1500000, tall=0.5, coastal=False,
      desc="Bavaria's gateway: two long runways on the plain, beer gardens in the city and the Alps on the southern horizon.", arff=9, ppd=130000),
 dict(icao="LSZH", iata="ZRH", name="Zurich Airport", short="Zurich", city="Zurich", country="Switzerland",
      lon=8.55, lat=47.46, nudge=(0,0), elev=330, size="regional", gates=20, between=False, side=1, style="regional",
      runways=[("16/34",160,3700,60,0,0,(True,True))],
      city_off=(-500,7500), radius=4500, pop=420000, tall=0.5, coastal=False,
      desc="Clockwork efficiency at the foot of the Alps: snow-capped peaks to the south and the old town on its river.", arff=8, ppd=85000),
 dict(icao="LOWW", iata="VIE", name="Vienna International", short="Vienna", city="Vienna", country="Austria",
      lon=16.57, lat=48.11, nudge=(0,0), elev=100, size="regional", gates=22, between=False, side=1, style="regional",
      runways=[("11/29",115,3500,45,0,0,(True,True))],
      city_off=(-7500,-5000), radius=5500, pop=1900000, tall=0.45, coastal=False,
      desc="Waltzes, coffee houses and the Danube: an elegant capital with the last foothills of the Alps to the west.", arff=8, ppd=85000),
 dict(icao="EKCH", iata="CPH", name="Copenhagen Kastrup", short="Copenhagen", city="Copenhagen", country="Denmark",
      lon=12.65, lat=55.62, nudge=(-5.5,0), elev=5, size="hub", gates=22, between=True, side=1, style="hub",
      runways=[("04L/22R",40,3600,45,-700,0,(True,True)),("04R/22L",40,3300,45,700,300,(True,True))],
      city_off=(-4000,-4000), radius=4500, pop=1300000, tall=0.45, coastal=True,
      desc="Bikes, harbours and Nordic design at the gateway between Scandinavia and the rest of Europe.", arff=8, ppd=80000),
 dict(icao="ENGM", iata="OSL", name="Oslo Gardermoen", short="Oslo", city="Oslo", country="Norway",
      lon=11.10, lat=60.20, nudge=(0,0), elev=125, size="hub", gates=22, between=True, side=1, style="hub",
      runways=[("01L/19R",15,3600,45,-1000,0,(True,True)),("01R/19L",15,2950,45,1000,400,(True,True))],
      city_off=(-5000,5500), radius=4500, pop=1000000, tall=0.45, coastal=True,
      desc="Pine forest, fjords and deep winter: snowploughs in convoy and the northern lights over the runway.", arff=8, ppd=75000),
 dict(icao="ESSA", iata="ARN", name="Stockholm Arlanda", short="Stockholm", city="Stockholm", country="Sweden",
      lon=17.92, lat=59.65, nudge=(0,0), elev=8, size="hub", gates=22, between=True, side=1, style="hub",
      runways=[("01L/19R",10,3300,45,-1000,0,(True,True)),("01R/19L",10,2500,45,1000,300,(True,True))],
      city_off=(0,6000), radius=4500, pop=1600000, tall=0.45, coastal=True,
      desc="A capital built on fourteen islands, with the archipelago stretching out into the Baltic beyond.", arff=8, ppd=70000),
 dict(icao="EDDB", iata="BER", name="Berlin Brandenburg", short="Berlin", city="Berlin", country="Germany",
      lon=13.50, lat=52.37, nudge=(0,0), elev=48, size="hub", gates=26, between=True, side=1, style="hub",
      runways=[("07L/25R",70,3600,45,-1000,0,(True,True)),("07R/25L",70,4000,45,1000,400,(True,True))],
      city_off=(-4000,-9000), radius=6500, pop=3700000, tall=0.6, coastal=False,
      desc="Germany's capital: the TV tower over Alexanderplatz, the Brandenburg Gate and a brand-new airport south of the city.", arff=9, ppd=100000),
 dict(icao="LEBL", iata="BCN", name="Barcelona El Prat", short="Barcelona", city="Barcelona", country="Spain",
      lon=2.08, lat=41.30, nudge=(0,-3.0), elev=12, size="hub", gates=24, between=True, side=1, style="hub",
      runways=[("06L/24R",65,3350,45,-800,0,(True,True)),("06R/24L",65,2660,45,800,400,(True,True))],
      city_off=(4000,-5500), radius=5000, pop=1600000, tall=0.55, coastal=True,
      desc="Gaudi's city by the sea: Sagrada Familia's spires, beaches beside the runway and the Mediterranean sparkling on every approach.", arff=9, ppd=140000),
 dict(icao="EBBR", iata="BRU", name="Brussels Airport", short="Brussels", city="Brussels", country="Belgium",
      lon=4.48, lat=50.90, nudge=(0,0), elev=56, size="hub", gates=24, between=True, side=1, style="hub",
      runways=[("07L/25R",65,3640,45,-800,0,(True,True)),("07R/25L",65,3200,45,800,300,(True,True))],
      city_off=(-5000,3500), radius=5000, pop=1200000, tall=0.55, coastal=False,
      desc="The capital of Europe: the Atomium, chocolate shops and fog that likes to roll in from the North Sea.", arff=8, ppd=70000),
 dict(icao="LPPT", iata="LIS", name="Lisbon Humberto Delgado", short="Lisbon", city="Lisbon", country="Portugal",
      lon=-9.13, lat=38.78, nudge=(0,0), elev=20, size="regional", gates=20, between=False, side=1, style="regional",
      runways=[("03/21",30,3800,45,0,0,(True,True))],
      city_off=(2000,3500), radius=4000, pop=550000, tall=0.4, coastal=True,
      desc="Seven hills, yellow trams and an approach low over the rooftops of the old city on the Tagus.", arff=8, ppd=85000),
 dict(icao="EGCC", iata="MAN", name="Manchester Airport", short="Manchester", city="Manchester", country="United Kingdom",
      lon=-2.27, lat=53.35, nudge=(0,0), elev=78, size="hub", gates=22, between=True, side=1, style="hub",
      runways=[("05L/23R",50,3050,45,-700,0,(True,True)),("05R/23L",50,3200,45,700,300,(True,True))],
      city_off=(1000,-7500), radius=5000, pop=2800000, tall=0.6, coastal=False,
      desc="Rain, football and red-brick mills, with the Pennine hills rising just to the east.", arff=8, ppd=80000),
 dict(icao="EGPH", iata="EDI", name="Edinburgh Airport", short="Edinburgh", city="Edinburgh", country="United Kingdom",
      lon=-3.37, lat=55.95, nudge=(0,0), elev=41, size="regional", gates=12, between=False, side=1, style="regional",
      runways=[("06/24",60,2560,45,0,0,(True,True))],
      city_off=(6500,500), radius=4000, pop=520000, tall=0.35, coastal=True,
      desc="A castle on an extinct volcano above the old town, and the grey waters of the Forth just north of the runway.", arff=7, ppd=40000),
]

# ------------------------------------------------------------------ city layouts (metres from the city centre)
# rivers through cities: (name, width, [(dx, dz)...]) - the last point must reach the sea / a bay
CITY_RIVERS = {
 "KJFK": [("Hudson River",1150,[(-1800,-60000),(-1600,-30000),(-1700,-9000),(-1850,-3000),(-1900,1500),(-2100,4000)]),
          ("East River",650,[(2400,-6500),(2000,-3000),(1300,500),(-400,4200)])],
 "EGLL": [("Thames",320,[(-34000,2500),(-21000,2600),(-9000,1600),(-4000,1900),(-1500,1300),(0,800),(1800,1500),(3000,2400),(4600,1300),(8000,900),(14000,400),(22000,0),(30000,-600)])],
 "LFPG": [("Seine",240,[(14000,9000),(6000,4000),(2500,1600),(0,300),(-2600,1300),(-4200,600),(-5200,-2200),(-9000,-3500),(-15000,-6500),(-24000,-9000)])],
 "LIRF": [("Tiber",160,[(2500,-16000),(800,-7000),(-1200,-2600),(-1500,400),(-800,2200),(-4500,5000),(-9000,7000)])],
 "KIAD": [("Potomac",520,[(-22000,-14000),(-9000,-5000),(-3500,-1500),(-2200,1200),(-2600,5000),(-1500,12000)])],
 "KSFO": [("Golden Gate",1800,[(5000,-3000),(-1500,-3800),(-9000,-3900),(-15000,-4000)])],
}
# sea-level bays carved into the coast near cities: (name, dx, dz, rx, rz)
CITY_BAYS = {
 "KJFK": [("Upper New York Bay",-1900,6500,3300,3200),("Lower Bay",-2500,11500,6000,4500)],
 "KSFO": [("San Francisco Bay",7000,3000,4000,9000)],
 "KBOS": [("Boston Harbor",3500,1200,3200,2600)],
 "EGLL": [],
}
# parks (no buildings): (name, dx, dz, half_w, half_d)
CITY_PARKS = {
 "KJFK": [("Central Park",100,-4800,420,2000)],
 "EGLL": [("Hyde Park",-3400,-200,900,550),("Regent's Park",-1700,-2600,600,500)],
 "LFPG": [("Champ de Mars",-2800,2450,250,550),("Bois de Boulogne",-5400,-400,1100,1400)],
 "KSFO": [("Golden Gate Park",-2500,1000,2400,350)],
 "KIAD": [("National Mall",-400,300,1700,180)],
 "LIRF": [("Villa Borghese",-200,-1600,500,450)],
 "EDDB": [("Tiergarten",-1800,0,1100,450)],
 "EDDM": [("English Garden",500,-1500,350,1400)],
 "LEBL": [("Montjuic",-1500,1800,700,600)],
 "KMCO": [("Theme Parks",-9000,2500,2200,1800)],
}
# landmarks: (id, name, kind, dx, dz, yaw_deg)
CITY_LANDMARKS = {
 "KJFK": [("liberty","Statue of Liberty","liberty",-2600,6400,40),("esb","Empire State Building","empire",-150,-1400,29),
          ("wtc","One World Trade Center","one_wtc",-900,2700,0),("midtown","Midtown skyline","skyline_midtown",0,-1800,29),
          ("downtown","Lower Manhattan skyline","skyline_downtown",-600,2300,0),("bbridge","Brooklyn Bridge","bridge_brooklyn",1150,1650,75)],
 "EGLL": [("bigben","Big Ben and Parliament","big_ben",-1500,850,0),("eye","London Eye","london_eye",-1100,1400,0),
          ("towerbr","Tower Bridge","bridge_tower",1700,1500,0),("shard","The Shard","shard",1100,1900,0),
          ("city","The City of London","skyline_city",900,600,0),("wharf","Canary Wharf","skyline_wharf",4300,1800,0)],
 "LFPG": [("eiffel","Eiffel Tower","eiffel",-2900,1750,35),("arc","Arc de Triomphe","arc",-2300,-1200,0),
          ("defense","La Defense","skyline_defense",-6300,-3600,0)],
 "KSFO": [("ggb","Golden Gate Bridge","bridge_golden",-4800,-3850,90),("sfdt","Downtown San Francisco","skyline_sf",1500,-500,0)],
 "KLAX": [("hollywood","Hollywood Sign","hollywood",-2500,-4800,0),("ladt","Downtown Los Angeles","skyline_la",1200,600,0)],
 "KORD": [("willis","Willis Tower","willis",300,200,0),("loop","The Loop","skyline_chicago",-300,300,0)],
 "CYYZ": [("cn","CN Tower","cn_tower",-800,900,0),("tordt","Downtown Toronto","skyline_toronto",500,600,0)],
 "KIAD": [("capitol","US Capitol","capitol",1500,300,90),("monument","Washington Monument","obelisk",-500,300,0)],
 "LIRF": [("colosseum","Colosseum","colosseum",700,500,20),("stpeter","St Peter's Basilica","dome_church",-3000,-300,90)],
 "KMIA": [("miadt","Downtown Miami","skyline_miami",400,300,0)],
 "KBOS": [("bosdt","Downtown Boston","skyline_boston",800,200,0)],
 "EHAM": [("mills","Windmills","windmills",-4000,2500,0)],
 "BIKF": [("church","Hallgrimskirkja","church_tower",0,0,0)],
 "LEMD": [("torres","Cuatro Torres","skyline_madrid",500,-3500,0)],
 "KATL": [("atldt","Downtown Atlanta","skyline_atlanta",0,0,0)],
 "KDFW": [("dalldt","Downtown Dallas","skyline_dallas",0,0,0),("reunion","Reunion Tower","reunion",-900,500,0)],
 "KDEN": [("dendt","Downtown Denver","skyline_denver",0,0,0)],
 "KSEA": [("needle","Space Needle","space_needle",-800,-1500,0),("seadt","Downtown Seattle","skyline_seattle",200,0,0)],
 "KLAS": [("strip","The Las Vegas Strip","skyline_vegas",0,1800,0),("strat","Strat Tower","tv_tower",300,-800,0)],
 "KMCO": [("castle","Fairytale Castle","castle",-9000,2000,0)],
 "EDDF": [("fradt","Frankfurt skyline","skyline_frankfurt",0,0,0)],
 "EDDM": [("frauen","Frauenkirche","twin_towers_church",0,0,0)],
 "EDDB": [("tvtower","Berlin TV Tower","tv_tower",800,-300,0),("brandenburg","Brandenburg Gate","brandenburg",-1200,0,0)],
 "LEBL": [("sagrada","Sagrada Familia","sagrada",500,-900,0)],
 "EBBR": [("atomium","Atomium","atomium",-1500,-2500,0)],
 "EGPH": [("edcastle","Edinburgh Castle","castle",-600,0,0)],
}

def point_in_poly(p, poly):
    x, y = p
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]; xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside

def dist_seg(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / max(dx * dx + dy * dy, 1e-9)))
    cx, cy = ax + dx * t, ay + dy * t
    return math.hypot(px - cx, py - cy)

POLYS_KM = [(n, [km(*p) for p in poly]) for n, poly in POLYS]
ISL_KM = [(km(i[0], i[1]), (i[2], i[3])) for i in ISLANDS]

def land_info(xkm, zkm):
    inside = False
    dcoast = 1e9
    for n, poly in POLYS_KM:
        if point_in_poly((xkm, zkm), poly):
            inside = True
        for i in range(len(poly)):
            dcoast = min(dcoast, dist_seg((xkm, zkm), poly[i], poly[(i + 1) % len(poly)]))
    for c, r in ISL_KM:
        q = ((xkm - c[0]) / r[0], (zkm - c[1]) / r[1])
        l = math.hypot(*q)
        if l < 1.0:
            inside = True
        dcoast = min(dcoast, abs((l - 1.0) * min(r)))
    return inside, dcoast
