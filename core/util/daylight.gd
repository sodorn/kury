class_name Daylight
extends RefCounted
## 13.0 (wlasciciel 26.11): NOC wedlug polskiego czasu astronomicznego.
## Slonce ponizej -0,833 stopnia nad horyzontem w srodku Polski (okolice
## Warszawy) = noc. Kury w nocy siedza zamkniete w kurniku: nie chodza po
## wybiegu i NIE JEDZA (zero paszy, glod tez stoi), ale dalej znosza jaja,
## a inkubator dziala. Wzor: przyblizenie NOAA/Almanachu, blad rzedu minut.

const LAT := 52.23
const LON := 21.01

## Do testow: -1 = wedlug slonca, 0 = zawsze dzien, 1 = zawsze noc.
static var force := -1


## Wysokosc slonca w stopniach w chwili `unix` (sekundy UTC).
static func sun_altitude(unix: float) -> float:
	var d := unix / 86400.0 + 2440587.5 - 2451545.0
	var g := deg_to_rad(fposmod(357.529 + 0.98560028 * d, 360.0))
	var q := fposmod(280.459 + 0.98564736 * d, 360.0)
	var l := deg_to_rad(q + 1.915 * sin(g) + 0.020 * sin(2.0 * g))
	var e := deg_to_rad(23.439 - 0.00000036 * d)
	var ra := atan2(cos(e) * sin(l), cos(l))
	var dec := asin(sin(e) * sin(l))
	var gmst := fposmod(18.697374558 + 24.06570982441908 * d, 24.0) * 15.0
	var h := deg_to_rad(gmst + LON) - ra
	var lat := deg_to_rad(LAT)
	return rad_to_deg(asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h)))


static func is_night(unix: float) -> bool:
	if force >= 0:
		return force == 1
	return sun_altitude(unix) < -0.833


static func is_night_now() -> bool:
	return is_night(Time.get_unix_time_from_system())
