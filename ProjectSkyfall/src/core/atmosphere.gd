class_name Atmo
## International Standard Atmosphere with temperature deviation.

const R := 287.053
const GAMMA := 1.4
const T0 := 288.15
const P0 := 101325.0
const RHO0 := 1.225
const LAPSE := 0.0065


static func temperature(alt_m: float, isa_dev: float = 0.0) -> float:
	if alt_m < 11000.0:
		return T0 - LAPSE * alt_m + isa_dev
	return 216.65 + isa_dev


static func pressure(alt_m: float) -> float:
	if alt_m < 11000.0:
		return P0 * pow(1.0 - LAPSE * alt_m / T0, 5.25588)
	return 22632.06 * exp(-0.000157688 * (alt_m - 11000.0))


static func density(alt_m: float, isa_dev: float = 0.0) -> float:
	return pressure(alt_m) / (R * temperature(alt_m, isa_dev))


static func speed_of_sound(alt_m: float, isa_dev: float = 0.0) -> float:
	return sqrt(GAMMA * R * temperature(alt_m, isa_dev))


static func tas_to_ias(tas: float, alt_m: float, isa_dev: float = 0.0) -> float:
	return tas * sqrt(density(alt_m, isa_dev) / RHO0)


static func ias_to_tas(ias: float, alt_m: float, isa_dev: float = 0.0) -> float:
	return ias / sqrt(maxf(density(alt_m, isa_dev), 0.01) / RHO0)


static func mach_to_tas(mach: float, alt_m: float, isa_dev: float = 0.0) -> float:
	return mach * speed_of_sound(alt_m, isa_dev)


static func pressure_altitude_ft(alt_m: float, qnh_hpa: float) -> float:
	# Height above the 1013.25 hPa surface, simplified (27 ft per hPa near sea level).
	return alt_m / U.FT - (qnh_hpa - 1013.25) * 27.0
