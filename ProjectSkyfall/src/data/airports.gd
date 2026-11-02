class_name Airports
## Airport database: the Calderra / Westmark region and the real-world region (North America,
## the North Atlantic and Europe, compressed 1:5 - see RealWorld).
## Positions are world metres (x = east, z = south). Runway "hdg" is the true heading of the
## first-named runway end; "off" shifts the runway sideways (positive = right of hdg).

const ORDER := ["SKPC", "SKRV", "SKNG", "SKHP", "SKOF", "SKWF", "SKIM", "SKSB", "WMIA", "WMSK",
	"KJFK", "KBOS", "KIAD", "KORD", "CYYZ", "KMIA", "KLAX", "KSFO", "EGLL", "LFPG", "EHAM", "EIDW", "LEMD", "LIRF",
	"BIKF", "TXKF", "LPPD", "LPMA", "EKVG", "CYQX", "BGGH"]
## The fictional home region and the real-world region (see RealWorld).
const CALDERRA := ["SKPC", "SKRV", "SKNG", "SKHP", "SKOF", "SKWF", "SKIM", "SKSB", "WMIA", "WMSK"]

const DATA := {
	"SKPC": {
		"iata": "PCI", "name": "Port Calder International", "short": "Port Calder", "city": "Port Calder",
		"country": "Calderra", "x": -40000.0, "z": 0.0, "elev": 8.0, "size": "hub",
		"runways": [
			{"id": "09L/27R", "hdg": 90.0, "len": 3800.0, "wid": 60.0, "off": -700.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "09R/27L", "hdg": 90.0, "len": 3300.0, "wid": 45.0, "off": 700.0, "along": 300.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": true, "side": 1, "gates": 14, "style": "hub"},
		"freq": {"atis": "128.050", "del": "121.900", "gnd": "121.750", "twr": "118.300", "app": "119.450", "dep": "124.350"},
		"city_info": {"dx": -9000.0, "dz": 11000.0, "radius": 9500.0, "pop": 2400000, "tall": 1.0, "coastal": true},
		"desc": "Calderra's busy coastal hub with twin parallel runways and a sweeping glass terminal.",
		"arff": 9, "fuel": true, "pax_per_day": 68000,
	},
	"SKRV": {
		"iata": "RVM", "name": "Rivermouth Regional", "short": "Rivermouth", "city": "Rivermouth",
		"country": "Calderra", "x": -30000.0, "z": -120000.0, "elev": 6.0, "size": "regional",
		"runways": [
			{"id": "14/32", "hdg": 140.0, "len": 2600.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 5, "style": "regional"},
		"freq": {"atis": "127.200", "del": "121.650", "gnd": "121.650", "twr": "118.700", "app": "120.300", "dep": "120.300"},
		"city_info": {"dx": -6000.0, "dz": -7000.0, "radius": 4800.0, "pop": 340000, "tall": 0.45, "coastal": true},
		"desc": "A port city at the mouth of the Calder river. Sea fog rolls in on summer mornings.",
		"arff": 7, "fuel": true, "pax_per_day": 6200,
	},
	"SKNG": {
		"iata": "NGT", "name": "Northgate International", "short": "Northgate", "city": "Northgate",
		"country": "Calderra", "x": 30000.0, "z": -260000.0, "elev": 125.0, "size": "hub",
		"runways": [
			{"id": "18/36", "hdg": 180.0, "len": 3500.0, "wid": 60.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "06/24", "hdg": 60.0, "len": 2400.0, "wid": 45.0, "off": 1500.0, "along": -500.0, "ils": [false, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": -1, "gates": 9, "style": "hub"},
		"freq": {"atis": "126.400", "del": "121.800", "gnd": "121.700", "twr": "119.100", "app": "125.250", "dep": "125.250"},
		"city_info": {"dx": 9000.0, "dz": -8000.0, "radius": 7000.0, "pop": 820000, "tall": 0.75, "coastal": false},
		"desc": "Industrial northern hub and home of Northwind Cargo. Harsh winters and gusty crosswinds.",
		"arff": 9, "fuel": true, "pax_per_day": 21000,
	},
	"SKHP": {
		"iata": "HPS", "name": "Highpass Regional", "short": "Highpass", "city": "Highpass",
		"country": "Calderra", "x": 230000.0, "z": -170000.0, "elev": 1150.0, "size": "regional",
		"runways": [
			{"id": "06/24", "hdg": 62.0, "len": 2500.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, false], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 4, "style": "regional"},
		"freq": {"atis": "127.650", "del": "121.600", "gnd": "121.600", "twr": "118.950", "app": "119.850", "dep": "119.850"},
		"city_info": {"dx": 6000.0, "dz": -5000.0, "radius": 2600.0, "pop": 45000, "tall": 0.25, "coastal": false},
		"desc": "A high mountain valley airport. Terrain on all sides, a one-way ILS and notorious downdrafts.",
		"arff": 6, "fuel": true, "pax_per_day": 2100,
	},
	"SKOF": {
		"iata": "OFL", "name": "Oren Falls Airport", "short": "Oren Falls", "city": "Oren Falls",
		"country": "Calderra", "x": 180000.0, "z": 60000.0, "elev": 215.0, "size": "regional",
		"runways": [
			{"id": "13/31", "hdg": 128.0, "len": 2900.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": -1, "gates": 6, "style": "regional"},
		"freq": {"atis": "126.850", "del": "121.850", "gnd": "121.850", "twr": "118.450", "app": "121.100", "dep": "121.100"},
		"city_info": {"dx": 6000.0, "dz": 11000.0, "radius": 5200.0, "pop": 510000, "tall": 0.55, "coastal": false},
		"desc": "Lakeside city airport beside the great Lake Oren. Calm mornings, thunderstorms on summer afternoons.",
		"arff": 7, "fuel": true, "pax_per_day": 8800,
	},
	"SKWF": {
		"iata": "WLF", "name": "Willow Field", "short": "Willow Field", "city": "Willowbrook",
		"country": "Calderra", "x": 40000.0, "z": 70000.0, "elev": 45.0, "size": "ga",
		"runways": [
			{"id": "03/21", "hdg": 30.0, "len": 1250.0, "wid": 25.0, "off": 0.0, "along": 0.0, "ils": [false, false], "surface": "asphalt"},
			{"id": "12/30", "hdg": 120.0, "len": 750.0, "wid": 30.0, "off": 380.0, "along": 150.0, "ils": [false, false], "surface": "grass"},
		],
		"terminal": {"between": false, "side": -1, "gates": 0, "style": "ga"},
		"freq": {"atis": "124.100", "del": "122.800", "gnd": "122.800", "twr": "122.800", "app": "119.450", "dep": "119.450"},
		"city_info": {"dx": 5000.0, "dz": 5000.0, "radius": 1800.0, "pop": 18000, "tall": 0.15, "coastal": false},
		"desc": "A friendly general aviation field and home of the Horizon Flight Academy.",
		"arff": 2, "fuel": true, "pax_per_day": 0,
	},
	"SKIM": {
		"iata": "IMR", "name": "Isla Marea Airport", "short": "Isla Marea", "city": "Marea",
		"country": "Calderra", "x": -20000.0, "z": 250000.0, "elev": 5.0, "size": "regional",
		"runways": [
			{"id": "11/29", "hdg": 110.0, "len": 2000.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [false, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 3, "style": "island"},
		"freq": {"atis": "127.000", "del": "121.700", "gnd": "121.700", "twr": "118.150", "app": "119.000", "dep": "119.000"},
		"city_info": {"dx": -5000.0, "dz": 4000.0, "radius": 2400.0, "pop": 60000, "tall": 0.3, "coastal": true},
		"desc": "A short island runway that ends at the sea. Trade winds bring strong crosswinds every afternoon.",
		"arff": 6, "fuel": true, "pax_per_day": 3200,
	},
	"SKSB": {
		"iata": "SBY", "name": "Sable Bay International", "short": "Sable Bay", "city": "Sable Bay",
		"country": "Calderra", "x": 160000.0, "z": 255000.0, "elev": 12.0, "size": "regional",
		"runways": [
			{"id": "16/34", "hdg": 160.0, "len": 2700.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 6, "style": "resort"},
		"freq": {"atis": "126.200", "del": "121.750", "gnd": "121.750", "twr": "118.800", "app": "124.700", "dep": "124.700"},
		"city_info": {"dx": 10000.0, "dz": 7000.0, "radius": 4200.0, "pop": 210000, "tall": 0.6, "coastal": true},
		"desc": "Resort city on a sheltered southern bay. Charter season keeps the ramp full of business jets.",
		"arff": 7, "fuel": true, "pax_per_day": 9800,
	},
	"WMIA": {
		"iata": "ALD", "name": "Aldmoor Westmark International", "short": "Aldmoor", "city": "Aldmoor",
		"country": "Westmark", "x": -420000.0, "z": -80000.0, "elev": 30.0, "size": "hub",
		"runways": [
			{"id": "08/26", "hdg": 80.0, "len": 4000.0, "wid": 60.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "17/35", "hdg": 170.0, "len": 2800.0, "wid": 45.0, "off": 1600.0, "along": 900.0, "ils": [true, false], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 12, "style": "hub"},
		"freq": {"atis": "128.650", "del": "121.950", "gnd": "121.800", "twr": "118.550", "app": "120.800", "dep": "127.900"},
		"city_info": {"dx": 12000.0, "dz": -10000.0, "radius": 9000.0, "pop": 1900000, "tall": 0.95, "coastal": false},
		"desc": "Westmark's gateway across the Western Sea, a long four-kilometre runway and a grand old terminal.",
		"arff": 9, "fuel": true, "pax_per_day": 52000,
	},
	"WMSK": {
		"iata": "SKR", "name": "Skerra Airport", "short": "Skerra", "city": "Skerra",
		"country": "Westmark", "x": -470000.0, "z": 60000.0, "elev": 18.0, "size": "regional",
		"runways": [
			{"id": "04/22", "hdg": 40.0, "len": 1900.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, false], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": -1, "gates": 3, "style": "regional"},
		"freq": {"atis": "127.400", "del": "121.600", "gnd": "121.600", "twr": "118.200", "app": "120.100", "dep": "120.100"},
		"city_info": {"dx": -4000.0, "dz": 6000.0, "radius": 2800.0, "pop": 75000, "tall": 0.3, "coastal": true},
		"desc": "A windswept fishing town airport on Westmark's rugged western coast.",
		"arff": 6, "fuel": true, "pax_per_day": 1800,
	},
	"KJFK": {
		"iata": "JFK", "name": "John F. Kennedy International", "short": "New York JFK", "city": "New York",
		"country": "United States", "x": -531800.0, "z": 1394420.0, "elev": 4.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "04L/22R", "hdg": 44.0, "len": 3460.0, "wid": 60.0, "off": -800.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "04R/22L", "hdg": 44.0, "len": 2560.0, "wid": 60.0, "off": 800.0, "along": -300.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "13R/31L", "hdg": 134.0, "len": 4420.0, "wid": 60.0, "off": -2650.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": true, "side": 1, "gates": 32, "style": "hub"},
		"freq": {"atis": "118.050", "del": "125.100", "gnd": "125.100", "twr": "126.800", "app": "128.075", "dep": "125.700"},
		"city_info": {"dx": -6500.0, "dz": -5200.0, "radius": 13000.0, "pop": 8300000, "tall": 1.60, "coastal": true},
		"desc": "The gateway to America: four runways, a vast terminal complex and Manhattan's skyline on the horizon.",
		"arff": 10, "fuel": true, "pax_per_day": 170000,
	},
	"KBOS": {
		"iata": "BOS", "name": "Boston Logan International", "short": "Boston", "city": "Boston",
		"country": "United States", "x": -490690.0, "z": 1358880.0, "elev": 6.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "04R/22L", "hdg": 40.0, "len": 3050.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "15R/33L", "hdg": 150.0, "len": 3070.0, "wid": 45.0, "off": 1900.0, "along": 300.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": -1, "gates": 16, "style": "hub"},
		"freq": {"atis": "119.450", "del": "118.600", "gnd": "118.600", "twr": "121.025", "app": "126.050", "dep": "121.050"},
		"city_info": {"dx": -6000.0, "dz": -1500.0, "radius": 7000.0, "pop": 680000, "tall": 0.95, "coastal": true},
		"desc": "A harbour airport hemmed in by water on three sides, with the city's towers a stone's throw away.",
		"arff": 9, "fuel": true, "pax_per_day": 60000,
	},
	"KIAD": {
		"iata": "IAD", "name": "Washington Dulles International", "short": "Washington Dulles", "city": "Washington",
		"country": "United States", "x": -589730.0, "z": 1433790.0, "elev": 95.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "01R/19L", "hdg": 10.0, "len": 3500.0, "wid": 45.0, "off": 800.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "01C/19C", "hdg": 10.0, "len": 3500.0, "wid": 45.0, "off": -800.0, "along": 200.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "12/30", "hdg": 120.0, "len": 3200.0, "wid": 45.0, "off": -2900.0, "along": -1800.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": true, "side": 1, "gates": 20, "style": "hub"},
		"freq": {"atis": "119.175", "del": "128.450", "gnd": "128.450", "twr": "118.700", "app": "134.800", "dep": "132.025"},
		"city_info": {"dx": 17000.0, "dz": 1200.0, "radius": 8000.0, "pop": 690000, "tall": 0.40, "coastal": false},
		"desc": "The capital's international gateway in the Virginia countryside, a short drive from the Capitol and the Mall.",
		"arff": 9, "fuel": true, "pax_per_day": 66000,
	},
	"KORD": {
		"iata": "ORD", "name": "Chicago O'Hare International", "short": "Chicago O'Hare", "city": "Chicago",
		"country": "United States", "x": -760090.0, "z": 1367790.0, "elev": 205.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "10L/28R", "hdg": 100.0, "len": 3960.0, "wid": 45.0, "off": -800.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "10C/28C", "hdg": 100.0, "len": 3290.0, "wid": 60.0, "off": 800.0, "along": 250.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "04R/22L", "hdg": 40.0, "len": 2460.0, "wid": 45.0, "off": -2600.0, "along": 1200.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": true, "side": 1, "gates": 28, "style": "hub"},
		"freq": {"atis": "121.025", "del": "132.700", "gnd": "132.700", "twr": "126.025", "app": "128.100", "dep": "124.450"},
		"city_info": {"dx": 10000.0, "dz": 2000.0, "radius": 11000.0, "pop": 2700000, "tall": 1.35, "coastal": true},
		"desc": "One of the busiest airports on earth: a web of parallel runways on the prairie beside Lake Michigan.",
		"arff": 10, "fuel": true, "pax_per_day": 150000,
	},
	"CYYZ": {
		"iata": "YYZ", "name": "Toronto Pearson International", "short": "Toronto", "city": "Toronto",
		"country": "Canada", "x": -626900.0, "z": 1327690.0, "elev": 173.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "05/23", "hdg": 57.0, "len": 3390.0, "wid": 60.0, "off": -750.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "06L/24R", "hdg": 57.0, "len": 2960.0, "wid": 60.0, "off": 750.0, "along": 300.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": true, "side": 1, "gates": 20, "style": "hub"},
		"freq": {"atis": "124.650", "del": "120.650", "gnd": "120.650", "twr": "119.700", "app": "134.125", "dep": "119.700"},
		"city_info": {"dx": 13000.0, "dz": -1500.0, "radius": 9000.0, "pop": 2800000, "tall": 1.15, "coastal": true},
		"desc": "Canada's biggest airport, with the CN Tower and the lakefront skyline twenty minutes away.",
		"arff": 9, "fuel": true, "pax_per_day": 120000,
	},
	"KMIA": {
		"iata": "MIA", "name": "Miami International", "short": "Miami", "city": "Miami",
		"country": "United States", "x": -634290.0, "z": 1724830.0, "elev": 3.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "08R/26L", "hdg": 87.0, "len": 3200.0, "wid": 61.0, "off": 650.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "09/27", "hdg": 90.0, "len": 3960.0, "wid": 61.0, "off": -650.0, "along": -300.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": true, "side": 1, "gates": 20, "style": "resort"},
		"freq": {"atis": "119.650", "del": "132.800", "gnd": "132.800", "twr": "121.350", "app": "119.700", "dep": "118.750"},
		"city_info": {"dx": 3000.0, "dz": 1000.0, "radius": 7500.0, "pop": 450000, "tall": 1.05, "coastal": true},
		"desc": "Sun, thunderstorms and the gateway to the Caribbean, with Miami Beach glittering just across the bay.",
		"arff": 9, "fuel": true, "pax_per_day": 110000,
	},
	"KLAX": {
		"iata": "LAX", "name": "Los Angeles International", "short": "Los Angeles", "city": "Los Angeles",
		"country": "United States", "x": -1231910.0, "z": 1544590.0, "elev": 38.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "06R/24L", "hdg": 69.0, "len": 3135.0, "wid": 45.0, "off": -750.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "07L/25R", "hdg": 69.0, "len": 3685.0, "wid": 60.0, "off": 750.0, "along": 250.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": true, "side": 1, "gates": 30, "style": "hub"},
		"freq": {"atis": "126.300", "del": "121.550", "gnd": "121.550", "twr": "134.650", "app": "127.700", "dep": "127.350"},
		"city_info": {"dx": 11000.0, "dz": -6000.0, "radius": 14000.0, "pop": 3900000, "tall": 1.00, "coastal": true},
		"desc": "Approaches over the ocean, departures over the Pacific, and the hills of Hollywood beyond the city.",
		"arff": 10, "fuel": true, "pax_per_day": 180000,
	},
	"KSFO": {
		"iata": "SFO", "name": "San Francisco International", "short": "San Francisco", "city": "San Francisco",
		"country": "United States", "x": -1294910.0, "z": 1463210.0, "elev": 4.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "28L/10R", "hdg": 280.0, "len": 3620.0, "wid": 60.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "01R/19L", "hdg": 10.0, "len": 2640.0, "wid": 60.0, "off": 1700.0, "along": 600.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": -1, "gates": 18, "style": "hub"},
		"freq": {"atis": "121.050", "del": "124.175", "gnd": "124.175", "twr": "120.900", "app": "132.250", "dep": "128.550"},
		"city_info": {"dx": -1500.0, "dz": -10500.0, "radius": 6500.0, "pop": 810000, "tall": 1.05, "coastal": true},
		"desc": "Fog rolling in under the Golden Gate, a bayside runway and one of the most beautiful approaches anywhere.",
		"arff": 9, "fuel": true, "pax_per_day": 110000,
	},
	"EGLL": {
		"iata": "LHR", "name": "London Heathrow", "short": "London Heathrow", "city": "London",
		"country": "United Kingdom", "x": 622640.0, "z": 1156920.0, "elev": 25.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "09L/27R", "hdg": 90.0, "len": 3900.0, "wid": 50.0, "off": -720.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "09R/27L", "hdg": 90.0, "len": 3660.0, "wid": 50.0, "off": 720.0, "along": 200.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": true, "side": 1, "gates": 32, "style": "hub"},
		"freq": {"atis": "132.050", "del": "125.950", "gnd": "125.950", "twr": "127.250", "app": "119.600", "dep": "126.125"},
		"city_info": {"dx": 12500.0, "dz": -1000.0, "radius": 13000.0, "pop": 8900000, "tall": 0.80, "coastal": false},
		"desc": "Europe's great hub: two long parallel runways, endless stacks over the city and the Thames winding past Big Ben.",
		"arff": 10, "fuel": true, "pax_per_day": 220000,
	},
	"LFPG": {
		"iata": "CDG", "name": "Paris Charles de Gaulle", "short": "Paris CDG", "city": "Paris",
		"country": "France", "x": 669870.0, "z": 1211320.0, "elev": 119.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "09L/27R", "hdg": 87.0, "len": 4200.0, "wid": 60.0, "off": -1400.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "09R/27L", "hdg": 87.0, "len": 4200.0, "wid": 45.0, "off": 1400.0, "along": 300.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": true, "side": 1, "gates": 30, "style": "hub"},
		"freq": {"atis": "118.850", "del": "125.100", "gnd": "125.100", "twr": "127.450", "app": "119.650", "dep": "132.300"},
		"city_info": {"dx": -6000.0, "dz": 11000.0, "radius": 10000.0, "pop": 2100000, "tall": 0.45, "coastal": false},
		"desc": "France's front door: four runways, futuristic terminals and the Eiffel Tower on the skyline.",
		"arff": 10, "fuel": true, "pax_per_day": 200000,
	},
	"EHAM": {
		"iata": "AMS", "name": "Amsterdam Schiphol", "short": "Amsterdam", "city": "Amsterdam",
		"country": "Netherlands", "x": 706160.0, "z": 1138340.0, "elev": 2.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "18C/36C", "hdg": 183.0, "len": 3300.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "18R/36L", "hdg": 183.0, "len": 3800.0, "wid": 60.0, "off": 2600.0, "along": -600.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "06/24", "hdg": 58.0, "len": 3500.0, "wid": 45.0, "off": -1500.0, "along": -2500.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": -1, "gates": 24, "style": "hub"},
		"freq": {"atis": "127.700", "del": "125.900", "gnd": "125.900", "twr": "125.750", "app": "127.050", "dep": "119.200"},
		"city_info": {"dx": 8500.0, "dz": -5500.0, "radius": 6500.0, "pop": 900000, "tall": 0.40, "coastal": true},
		"desc": "Below sea level and famously flat: windmills, canals and the long taxi out to the Polderbaan.",
		"arff": 9, "fuel": true, "pax_per_day": 190000,
	},
	"EIDW": {
		"iata": "DUB", "name": "Dublin Airport", "short": "Dublin", "city": "Dublin",
		"country": "Ireland", "x": 530010.0, "z": 1113790.0, "elev": 74.0, "size": "regional", "region": "world",
		"runways": [
			{"id": "10R/28L", "hdg": 100.0, "len": 3110.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "16/34", "hdg": 160.0, "len": 2070.0, "wid": 45.0, "off": 1700.0, "along": 500.0, "ils": [true, false], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 14, "style": "hub"},
		"freq": {"atis": "118.950", "del": "127.900", "gnd": "127.900", "twr": "134.050", "app": "124.800", "dep": "132.850"},
		"city_info": {"dx": 1500.0, "dz": 6500.0, "radius": 6500.0, "pop": 590000, "tall": 0.35, "coastal": true},
		"desc": "The first landfall after the Atlantic crossing, Atlantic weather and a city on the River Liffey.",
		"arff": 8, "fuel": true, "pax_per_day": 90000,
	},
	"LEMD": {
		"iata": "MAD", "name": "Madrid-Barajas", "short": "Madrid", "city": "Madrid",
		"country": "Spain", "x": 573680.0, "z": 1400180.0, "elev": 610.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "18L/36R", "hdg": 180.0, "len": 3500.0, "wid": 60.0, "off": -900.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "18R/36L", "hdg": 180.0, "len": 4350.0, "wid": 60.0, "off": 900.0, "along": -300.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": true, "side": 1, "gates": 26, "style": "hub"},
		"freq": {"atis": "125.000", "del": "127.250", "gnd": "127.250", "twr": "126.850", "app": "127.350", "dep": "120.750"},
		"city_info": {"dx": -8000.0, "dz": 5500.0, "radius": 9500.0, "pop": 3300000, "tall": 0.60, "coastal": false},
		"desc": "High on the Spanish plateau: hot summers, crisp winters and long runways for thin air.",
		"arff": 9, "fuel": true, "pax_per_day": 170000,
	},
	"LIRF": {
		"iata": "FCO", "name": "Rome Fiumicino", "short": "Rome", "city": "Rome",
		"country": "Italy", "x": 825070.0, "z": 1369770.0, "elev": 4.0, "size": "hub", "region": "world",
		"runways": [
			{"id": "16R/34L", "hdg": 160.0, "len": 3900.0, "wid": 60.0, "off": 800.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "16L/34R", "hdg": 160.0, "len": 3900.0, "wid": 45.0, "off": -800.0, "along": 500.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": true, "side": 1, "gates": 22, "style": "hub"},
		"freq": {"atis": "124.100", "del": "119.550", "gnd": "119.550", "twr": "118.150", "app": "121.400", "dep": "126.550"},
		"city_info": {"dx": 10000.0, "dz": -8500.0, "radius": 9000.0, "pop": 2800000, "tall": 0.30, "coastal": true},
		"desc": "Beside the sea where the Tiber meets it, a short hop from the Colosseum and St Peter's.",
		"arff": 9, "fuel": true, "pax_per_day": 120000,
	},
	"BIKF": {
		"iata": "KEF", "name": "Keflavik International", "short": "Reykjavik", "city": "Reykjavik",
		"country": "Iceland", "x": 273610.0, "z": 880040.0, "elev": 52.0, "size": "regional", "region": "world",
		"runways": [
			{"id": "01/19", "hdg": 10.0, "len": 3050.0, "wid": 60.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "10/28", "hdg": 100.0, "len": 3060.0, "wid": 60.0, "off": 1600.0, "along": 700.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 10, "style": "island"},
		"freq": {"atis": "128.200", "del": "119.125", "gnd": "119.125", "twr": "127.400", "app": "120.450", "dep": "128.200"},
		"city_info": {"dx": 11500.0, "dz": -1800.0, "radius": 3800.0, "pop": 135000, "tall": 0.25, "coastal": true},
		"desc": "Lava fields, howling crosswinds and the northern lights: the mid-Atlantic stop between two continents.",
		"arff": 8, "fuel": true, "pax_per_day": 24000,
	},
	"TXKF": {
		"iata": "BDA", "name": "L.F. Wade International", "short": "Bermuda", "city": "Hamilton",
		"country": "Bermuda", "x": -388540.0, "z": 1579530.0, "elev": 4.0, "size": "regional", "region": "world",
		"runways": [
			{"id": "12/30", "hdg": 120.0, "len": 2960.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 5, "style": "island"},
		"freq": {"atis": "121.100", "del": "126.350", "gnd": "126.350", "twr": "134.400", "app": "119.125", "dep": "120.175"},
		"city_info": {"dx": -4500.0, "dz": 1200.0, "radius": 2200.0, "pop": 64000, "tall": 0.20, "coastal": true},
		"desc": "A tiny coral island alone in the middle of the Atlantic: pink beaches and nowhere else to land for a thousand kilometres.",
		"arff": 7, "fuel": true, "pax_per_day": 4000,
	},
	"LPPD": {
		"iata": "PDL", "name": "Ponta Delgada", "short": "Azores", "city": "Ponta Delgada",
		"country": "Portugal", "x": 225130.0, "z": 1460330.0, "elev": 79.0, "size": "regional", "region": "world",
		"runways": [
			{"id": "12/30", "hdg": 120.0, "len": 2490.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 5, "style": "island"},
		"freq": {"atis": "132.125", "del": "134.175", "gnd": "134.175", "twr": "118.550", "app": "124.250", "dep": "118.100"},
		"city_info": {"dx": 3000.0, "dz": 1200.0, "radius": 2400.0, "pop": 68000, "tall": 0.20, "coastal": true},
		"desc": "Volcanic islands in mid-ocean, crater lakes and Atlantic gales. A favourite diversion airport.",
		"arff": 7, "fuel": true, "pax_per_day": 5000,
	},
	"LPMA": {
		"iata": "FNC", "name": "Madeira Airport", "short": "Madeira", "city": "Funchal",
		"country": "Portugal", "x": 365550.0, "z": 1572010.0, "elev": 58.0, "size": "regional", "region": "world",
		"runways": [
			{"id": "05/23", "hdg": 50.0, "len": 2780.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": -1, "gates": 6, "style": "island"},
		"freq": {"atis": "132.300", "del": "126.650", "gnd": "126.650", "twr": "125.750", "app": "120.900", "dep": "128.750"},
		"city_info": {"dx": -5000.0, "dz": 600.0, "radius": 2600.0, "pop": 105000, "tall": 0.25, "coastal": true},
		"desc": "A runway built out over the sea on stilts beneath steep mountains: one of the world's most demanding approaches.",
		"arff": 7, "fuel": true, "pax_per_day": 9000,
	},
	"EKVG": {
		"iata": "FAE", "name": "Vagar Airport", "short": "Faroe Islands", "city": "Torshavn",
		"country": "Faroe Islands", "x": 515110.0, "z": 922720.0, "elev": 85.0, "size": "regional", "region": "world",
		"runways": [
			{"id": "12/30", "hdg": 120.0, "len": 1800.0, "wid": 30.0, "off": 0.0, "along": 0.0, "ils": [true, false], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 3, "style": "island"},
		"freq": {"atis": "134.650", "del": "134.850", "gnd": "134.850", "twr": "118.500", "app": "126.400", "dep": "126.400"},
		"city_info": {"dx": 5500.0, "dz": 1500.0, "radius": 1800.0, "pop": 22000, "tall": 0.15, "coastal": true},
		"desc": "A short runway in a fjord valley ringed by sea cliffs, sheep and sideways rain.",
		"arff": 5, "fuel": true, "pax_per_day": 1800,
	},
	"CYQX": {
		"iata": "YQX", "name": "Gander International", "short": "Gander", "city": "Gander",
		"country": "Canada", "x": -229380.0, "z": 1212870.0, "elev": 151.0, "size": "regional", "region": "world",
		"runways": [
			{"id": "03/21", "hdg": 30.0, "len": 3200.0, "wid": 60.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "13/31", "hdg": 130.0, "len": 2130.0, "wid": 45.0, "off": 1500.0, "along": 300.0, "ils": [true, false], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 6, "style": "regional"},
		"freq": {"atis": "118.150", "del": "119.550", "gnd": "119.550", "twr": "134.400", "app": "119.150", "dep": "127.125"},
		"city_info": {"dx": 4500.0, "dz": -2500.0, "radius": 2200.0, "pop": 12000, "tall": 0.15, "coastal": false},
		"desc": "The legendary North Atlantic waypoint where dozens of airliners once diverted in a single day.",
		"arff": 7, "fuel": true, "pax_per_day": 1500,
	},
	"BGGH": {
		"iata": "GOH", "name": "Nuuk Airport", "short": "Nuuk", "city": "Nuuk",
		"country": "Greenland", "x": -180880.0, "z": 875620.0, "elev": 86.0, "size": "regional", "region": "world",
		"runways": [
			{"id": "05/23", "hdg": 50.0, "len": 2200.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 3, "style": "island"},
		"freq": {"atis": "119.000", "del": "119.300", "gnd": "119.300", "twr": "132.025", "app": "132.100", "dep": "128.075"},
		"city_info": {"dx": 1500.0, "dz": 2500.0, "radius": 1800.0, "pop": 19000, "tall": 0.15, "coastal": true},
		"desc": "Greenland's capital between ice cap and fjord. Icebergs float past the end of the runway.",
		"arff": 5, "fuel": true, "pax_per_day": 1200,
	},
}

const CENTER_FREQ := {"Calderra": "128.200", "Westmark": "131.450", "Oceanic": "126.950", "United States": "132.450",
	"Canada": "133.300", "United Kingdom": "127.825", "Ireland": "131.150", "France": "128.325", "Netherlands": "124.875",
	"Spain": "133.950", "Italy": "125.500", "Iceland": "119.700", "Portugal": "132.150", "Bermuda": "128.700",
	"Greenland": "125.200", "Faroe Islands": "126.300"}


static func get_ap(icao: String) -> Dictionary:
	return DATA.get(icao, {})


static func all_icao() -> Array:
	return ORDER.duplicate()


static func pos2(icao: String) -> Vector2:
	var a: Dictionary = DATA[icao]
	return Vector2(a.x, a.z)


static func distance_m(a: String, b: String) -> float:
	return pos2(a).distance_to(pos2(b))


static func distance_nm(a: String, b: String) -> float:
	return distance_m(a, b) / U.NM


static func nearest(x: float, z: float, exclude: String = "", min_runway: float = 0.0) -> String:
	var best := ""
	var bd := INF
	for icao in ORDER:
		if icao == exclude:
			continue
		if longest_runway(icao) < min_runway:
			continue
		var a: Dictionary = DATA[icao]
		var d := U.dist2d(x, z, a.x, a.z)
		if d < bd:
			bd = d
			best = icao
	return best


static func longest_runway(icao: String) -> float:
	var best := 0.0
	for r in DATA[icao].runways:
		if r.surface == "asphalt":
			best = maxf(best, r.len)
	return best


## Returns a list of runway ends: each {name, rwy_index, hdg, thr_x, thr_z, end_x, end_z, len, wid, ils, elev, surface}
static func runway_ends(icao: String) -> Array:
	var a: Dictionary = DATA[icao]
	var out := []
	var idx := 0
	for r in a.runways:
		var names: PackedStringArray = String(r.id).split("/")
		var dir := Vector2(sin(deg_to_rad(r.hdg)), -cos(deg_to_rad(r.hdg)))
		var right := Vector2(-dir.y, dir.x)
		var c := Vector2(a.x, a.z) + right * float(r.off) + dir * float(r.along)
		var half := float(r.len) * 0.5
		var t1 := c - dir * half
		var t2 := c + dir * half
		out.append({"name": names[0], "rwy": idx, "hdg": float(r.hdg), "thr_x": t1.x, "thr_z": t1.y,
			"end_x": t2.x, "end_z": t2.y, "len": float(r.len), "wid": float(r.wid), "ils": bool(r.ils[0]),
			"elev": float(a.elev), "surface": r.surface, "airport": icao})
		out.append({"name": names[1], "rwy": idx, "hdg": U.wrap_deg(float(r.hdg) + 180.0), "thr_x": t2.x, "thr_z": t2.y,
			"end_x": t1.x, "end_z": t1.y, "len": float(r.len), "wid": float(r.wid), "ils": bool(r.ils[1]),
			"elev": float(a.elev), "surface": r.surface, "airport": icao})
		idx += 1
	return out


static func runway_end(icao: String, name: String) -> Dictionary:
	for e in runway_ends(icao):
		if e.name == name:
			return e
	return {}


## Picks the runway end best aligned with the wind (largest headwind), preferring paved runways.
static func best_runway(icao: String, wind_from_deg: float, wind_kt: float, min_len: float = 0.0) -> Dictionary:
	var best := {}
	var best_score := -INF
	for e in runway_ends(icao):
		if e.surface != "asphalt" and min_len > 900.0:
			continue
		var head := cos(deg_to_rad(wind_from_deg - e.hdg)) * wind_kt
		var score = head * 2.0 + (e.len / 1000.0) + (3.0 if e.ils else 0.0)
		if e.len < min_len:
			score -= 100.0
		if e.surface != "asphalt":
			score -= 20.0
		if score > best_score:
			best_score = score
			best = e
	return best


static func city_center(icao: String) -> Vector2:
	var a: Dictionary = DATA[icao]
	return Vector2(a.x + a.city_info.dx, a.z + a.city_info.dz)
