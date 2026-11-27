extends Node
## LABORATORIUM LISA - pomiar, nie test zaliczeniowy.
##
## Rozgrywa na prawdziwej symulacji (Simulation.advance) wiele dni na kilku
## typach farm i liczy: po jakim czasie przychodzi pierwszy lis, ile lisow
## na dobe, ile zawraca plot, ile przegania lub zagryza pies, ile kur ginie.
##
##   godot --headless --path . tests/fox_lab.tscn
##
## Powstalo 24.11 po zgloszeniu: "nowa farma - lis dlugo sie nie pojawia,
## stara (pies + plot) - w ogole". Uruchom przed i po kazdej zmianie
## balance.json -> fox, zeby porownac liczby.

const PROBY := 60
const ZEGAR_GODZ := 24.0          # ile godzin zegara trwa jedna proba

## Farmy do porownania: [nazwa, ptakow, plot, pies]
const FARMY := [
	["start: 3 kury + kogut", 4, 0, 0],
	["jak 272180 (8 ptakow)", 8, 0, 0],
	["23 ptaki, bez obrony", 23, 0, 0],
	["23 ptaki, plot 2", 23, 2, 0],
	["23 ptaki, owczarek", 23, 0, 2],
	["jak 666478 (plot 2 + owczarek)", 23, 2, 2],
]

## Jak gracz gra: [nazwa, minut gry aktywnej, minut przerwy]
const STYLE := [
	["gra bez przerwy", 60.0, 0.0],
	["20 min gry co 2 h", 20.0, 120.0],
]


func _ready() -> void:
	Cloud.use_test_server()
	var fox: Dictionary = GameData.balance()["fox"]
	var dis: Dictionary = GameData.balance()["disease"]
	# Choroba wylaczona na czas pomiaru - mierzymy samego lisa.
	var choroba := float(dis.get("active_chance", 0.0))
	var choroba_off := float(dis.get("offline_chance", 0.0))
	dis["active_chance"] = 0.0
	dis["offline_chance"] = 0.0

	print("")
	print("LABORATORIUM LISA  -  %d prob po %.0f h zegara na kazda farme" % [PROBY, ZEGAR_GODZ])
	print("lis: kostka co %s min gry aktywnej (szansa %.0f%%), co %s h w tle (%.0f%%),"
			% [fox["roll_minutes"], float(fox["chance"]) * 100,
			fox["roll_minutes"], float(fox["chance"]) * 100])
	print("     karencja %s min, minimum %s ptakow, lup %s-%s%% stada"
			% [fox["grace_minutes"], fox["min_hens"], fox["kill_share_min"], fox["kill_share_max"]])
	for styl: Array in STYLE:
		print("")
		print("=== %s ===" % styl[0])
		print("%-32s %9s %8s %7s %7s %7s %8s %8s" % ["farma", "1. lis po", "bez lisa",
				"lisow/d", "zawrocil", "pies", "kur/lisa", "kur/dobe"])
		for farma: Array in FARMY:
			_zmierz(farma, styl)

	dis["active_chance"] = choroba
	dis["offline_chance"] = choroba_off
	get_tree().quit(0)


func _zmierz(farma: Array, styl: Array) -> void:
	var scale := GameData.time_scale()
	var pierwsze: Array[float] = []
	var nigdy := 0
	var wejscia := 0
	var zawrocone := 0
	var pies := 0
	var zabite := 0
	for p in PROBY:
		var s := FarmState.new()
		s.feed = 1.0e9
		s.money = 0.0
		s.guard_level = int(farma[2])
		s.dog_level = int(farma[3])
		_uzupelnij(s, int(farma[1]))
		var t := 0.0
		var pierwszy := -1.0
		var koniec := ZEGAR_GODZ * 3600.0
		while t < koniec:
			# sesja gry aktywnej, krokami po 10 s zegara (jak klatki gry)
			var sesja := float(styl[1]) * 60.0
			var w_sesji := 0.0
			while w_sesji < sesja and t < koniec:
				var out := Simulation.advance(s, 10.0 * scale, false)
				t += 10.0
				w_sesji += 10.0
				if int(out.get("fox_arrived", 0)) > 0 and pierwszy < 0.0:
					pierwszy = t
				wejscia += int(out.get("fox_arrived", 0))
				zawrocone += int(out.get("fox_blocked", 0))
				pies += int(out.get("fox_chased", 0)) + int(out.get("fox_killed", 0))
				zabite += int(out.get("fox_took", 0))
				_uzupelnij(s, int(farma[1]))
			# przerwa: gra rozlicza ja tak jak Game._apply_elapsed
			var przerwa := float(styl[2]) * 60.0
			if przerwa > 0.0 and t < koniec:
				var out2 := Simulation.advance(s, przerwa * scale, true)
				t += przerwa
				if int(out2.get("fox_arrived", 0)) > 0 and pierwszy < 0.0:
					pierwszy = t
				wejscia += int(out2.get("fox_arrived", 0))
				zawrocone += int(out2.get("fox_blocked", 0))
				pies += int(out2.get("fox_chased", 0)) + int(out2.get("fox_killed", 0))
				zabite += int(out2.get("fox_took", 0))
				_uzupelnij(s, int(farma[1]))
		if pierwszy < 0.0:
			nigdy += 1
		else:
			pierwsze.append(pierwszy)
	pierwsze.sort()
	var mediana := "-" if pierwsze.is_empty() else "%.1f h" % (pierwsze[pierwsze.size() / 2] / 3600.0)
	var dob := PROBY * ZEGAR_GODZ / 24.0
	print("%-32s %9s %7.0f%% %7.2f %7d %7d %8.1f %8.2f" % [
		farma[0], mediana, 100.0 * nigdy / PROBY, wejscia / dob, zawrocone, pies,
		0.0 if wejscia == 0 else float(zabite) / wejscia, zabite / dob])


## Stado stale - po stratach dokupujemy, zeby mierzyc tempo, a nie wymieranie.
func _uzupelnij(s: FarmState, ile: int) -> void:
	var koguty := 0
	for c in s.chickens:
		if c.is_rooster:
			koguty += 1
	if koguty == 0:
		s.chickens.append(Chicken.create_rooster("leghorn"))
	while s.chickens.size() < ile:
		s.chickens.append(Chicken.create("leghorn"))
