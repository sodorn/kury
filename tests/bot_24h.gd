extends Node
## BOT 24 H - pomiar balansu, nie test zaliczeniowy.
##
## Rozgrywa pierwsza dobe nowej farmy na prawdziwej logice gry
## (Simulation.advance + akcje Game, tak jak przyciski w panelach). Gracz
## gra sesjami wedlug profilu, pomiedzy sesjami gra liczy sie w tle - jak
## w przegladarce. Bot podejmuje "rozsadne decyzje" (zasady w _decide).
##
##   godot --headless --path . tests/bot_24h.tscn
##   godot --headless --path . tests/bot_24h.tscn -- /sciezka/do/starych/danych
##
## Drugi wariant wczytuje balance.json i breeds.json z podanego katalogu -
## tak porownuje sie nowa ekonomie ze stara. Trwa kilka minut.

const PROBY := 8
## Co ile sekund zegara bot patrzy na gre w czasie sesji.
const KROK := 2.0
## Reakcja gracza na lisa (s) i tempo klikania (trafien na sekunde).
const REAKCJA_NA_LISA := 4.0
const KLIKI_NA_SEKUNDE := 2.5
## Pasze trzymamy na tyle minut gry przy aktywnej sesji.
const ZAPAS_PASZY_MIN := 12.0

## Profile: nazwa, lista sesji [start w minutach od 8:00, dlugosc w minutach].
var PROFILE := [
	["zaangazowany (sesja 20 min co 1,5 h, 4 h gry)", _co(90.0, 20.0, 60.0, 15.0 * 60.0)],
	["niedzielny (5 sesji, 1,5 h gry)", [[0.0, 30.0], [240.0, 15.0], [480.0, 15.0], [660.0, 15.0], [840.0, 15.0]]],
	["maniak (16 h bez przerwy)", [[0.0, 16.0 * 60.0]]],
]

var _state: FarmState
var _log := {}
var _first := {}
var _fox_seen := 0.0
var _taps_carry := 0.0
var _attacks := 0


static func _co(every: float, length: float, first: float, until: float) -> Array:
	var out := [[0.0, first]]
	var t := first + every - length
	while t < until:
		out.append([t, length])
		t += every
	return out


func _ready() -> void:
	Cloud.use_test_server()
	var args := OS.get_cmdline_user_args()
	if args.has("debug"):
		DEBUG = true
		args.erase("debug")
	if not args.is_empty():
		_load_data(String(args[0]))
	print("")
	print("BOT 24 H  -  %d prob na profil, dane: %s" % [PROBY,
			"res://data" if args.is_empty() else String(args[0])])
	for profil: Array in PROFILE:
		_run_profile(profil)
	get_tree().quit(0)


func _load_data(dir: String) -> void:
	var bal: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/balance.json"))
	var br: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/breeds.json"))
	GameData._ensure_loaded()
	if bal is Dictionary:
		# Od 12.22 poziomy budynkow siedza w rozbudowy.json; starsze katalogi
		# maja je jeszcze w balance.json i pliku rozbudow nie maja.
		if FileAccess.file_exists(dir + "/rozbudowy.json"):
			var roz: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/rozbudowy.json"))
			if roz is Dictionary:
				GameData.apply_upgrades(bal, roz)
		GameData._balance = bal
	if br is Array:
		GameData._breeds = br
	elif br is Dictionary:
		GameData._breeds = (br as Dictionary).get("breeds", [])


# --- profil -----------------------------------------------------------


func _run_profile(profil: Array) -> void:
	print("")
	print("=== %s ===" % profil[0])
	var wyniki: Array[Dictionary] = []
	for p in PROBY:
		seed(1000 + p)
		wyniki.append(_one_day(profil[1]))
	# Mediana godzinowa z prob (wartosc farmy).
	print("%-6s %12s %12s %7s %6s %6s %6s %6s %5s" % ["godz", "gotowka", "wartosc", "ptaki",
			"kurn", "magaz", "inkub", "plot", "pies"])
	for h in [1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24]:
		var row: Array[Dictionary] = []
		for w in wyniki:
			row.append(w["godz"][h])
		row.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["wartosc"] < b["wartosc"])
		var m: Dictionary = row[row.size() / 2]
		print("%-6s %12s %12s %7d %6d %6d %6d %6d %5d" % ["%02d:00" % ((8 + h) % 24),
				NumberFormat.money(m["gotowka"]), NumberFormat.money(m["wartosc"]),
				m["ptaki"], m["kurnik"], m["magazyn"], m["inkub"], m["plot"], m["pies"]])
	# Sumy z calej doby (mediany).
	print("")
	for key: String in ["sesje_min", "jaja_sprzedane", "przychod_jaja", "przychod_ptaki",
			"pasza_kg", "pasza_zl", "jaja_przepadly", "jaja_zgnily", "lisy", "lisy_plot",
			"lisy_przegonione", "kury_lis", "kury_glod", "kury_choroba", "wyklute", "koguty_sprzedane",
			"kupione_kury", "wydane_ulepszenia", "wygrana_godz"]:
		var vals: Array[float] = []
		for w in wyniki:
			vals.append(float(w["sumy"].get(key, 0.0)))
		vals.sort()
		print("  %-20s mediana %12s   (min %s, max %s)" % [key, _fmt(key, vals[vals.size() / 2]),
				_fmt(key, vals[0]), _fmt(key, vals[vals.size() - 1])])
	# Kiedy pierwszy raz kupione - mediana godziny.
	print("")
	print("  pierwszy zakup (mediana godziny od startu):")
	var keys: Array = []
	for w in wyniki:
		for k in w["pierwsze"].keys():
			if not keys.has(k):
				keys.append(k)
	keys.sort_custom(func(a: String, b: String) -> bool: return _median_first(wyniki, a) < _median_first(wyniki, b))
	for k in keys:
		var ile := 0
		for w in wyniki:
			if w["pierwsze"].has(k):
				ile += 1
		print("    %-24s %5.1f h   (%d/%d prob)" % [k, _median_first(wyniki, k), ile, PROBY])


func _median_first(wyniki: Array[Dictionary], key: String) -> float:
	var v: Array[float] = []
	for w in wyniki:
		v.append(float(w["pierwsze"].get(key, 99.0)))
	v.sort()
	return v[v.size() / 2]


func _fmt(key: String, v: float) -> String:
	if key.begins_with("przychod") or key.ends_with("_zl") or key.begins_with("wydane"):
		return NumberFormat.money(v)
	if key == "wygrana_godz":
		return "-" if v >= 99.0 else "%.1f h" % v
	return NumberFormat.grouped(int(v))


# --- jedna doba ----------------------------------------------------------


func _one_day(sesje: Array) -> Dictionary:
	_state = FarmState.from_start_config(GameData.balance().get("start", {}))
	Game.state = _state
	_log = {"wygrana_godz": 99.0}
	_first = {}
	_attacks = 0
	var scale := GameData.time_scale()
	var godz := {}
	var t := 0.0
	var koniec := 24.0 * 3600.0
	var nastepna_godz := 1
	var sesja_i := 0
	while t < koniec:
		var w_sesji := false
		var sesja_konc := 0.0
		if sesja_i < sesje.size():
			var s: Array = sesje[sesja_i]
			var start := float(s[0]) * 60.0
			sesja_konc = start + float(s[1]) * 60.0
			if t >= start and t < sesja_konc:
				w_sesji = true
			elif t >= sesja_konc:
				sesja_i += 1
				continue
		_now = t
		if w_sesji:
			# W trakcie sesji pasze dokupuje sie na biezaco; odkladamy na przerwe.
			_reserve_minutes = minf(sesja_konc - t, 600.0) / 60.0 \
					+ _away_after(sesje, sesja_i, sesja_konc, koniec) / 60.0 + 10.0
			var out := Simulation.advance(_state, KROK * scale)
			_count(out)
			_decide(KROK)
			t += KROK
			_log["sesje_min"] = float(_log.get("sesje_min", 0.0)) + KROK / 60.0
			if t >= sesja_konc:
				_before_leaving(_away_after(sesje, sesja_i, t, koniec))
		else:
			# Przerwa: do poczatku nastepnej sesji (albo do konca doby).
			var nast := koniec
			if sesja_i < sesje.size():
				nast = minf(koniec, float(sesje[sesja_i][0]) * 60.0)
			var gap := minf(nast, float(nastepna_godz) * 3600.0) - t
			if gap <= 0.0:
				gap = 1.0
			var f0 := _state.feed
			var b0 := _state.chickens.size()
			var out := Simulation.advance(_state, gap * scale, true)
			if DEBUG and _now < 4.0 * 3600.0:
				print("    tlo %5.2f h +%.0f s: pasza %.0f -> %.0f, ptaki %d -> %d, piskleta %d, na min %.2f" % [
						_now / 3600.0, gap, f0, _state.feed, b0, _state.chickens.size(), _state.chicks.size(),
						_state.feed_per_minute()])
			_count(out)
			t += gap
		while t >= float(nastepna_godz) * 3600.0 and nastepna_godz <= 24:
			godz[nastepna_godz] = _snapshot()
			nastepna_godz += 1
		if _state.money >= float(GameData.balance().get("win", {}).get("money", 1e12)) \
				and float(_log["wygrana_godz"]) >= 99.0:
			_log["wygrana_godz"] = t / 3600.0
	return {"godz": godz, "sumy": _log, "pierwsze": _first}


func _away_after(sesje: Array, i: int, t: float, koniec: float) -> float:
	if i + 1 < sesje.size():
		return float(sesje[i + 1][0]) * 60.0 - t
	return koniec - t


func _snapshot() -> Dictionary:
	var value := _state.money + _state.eggs_value()
	for hen: Chicken in _state.chickens:
		value += FarmState.hen_sell_price(hen.breed_id, false, hen.is_rooster)
	return {"gotowka": _state.money, "wartosc": value, "ptaki": _state.chickens.size(),
			"kurnik": _state.coop_level, "magazyn": _state.storage_level,
			"inkub": _state.incubator_level, "plot": _state.guard_level, "pies": _state.dog_level}


var DEBUG := false
func _count(out: Dictionary) -> void:
	if DEBUG and int(out.get("died_hunger", 0)) > 0:
		print("  glod %5.2f h: padlo %d, pasza %.0f kg, kasa %.0f, ptaki %d, piskleta %d, jaja %d" % [_now / 3600.0,
				int(out["died_hunger"]), _state.feed, _state.money, _state.chickens.size(),
				_state.chicks.size(), _state.egg_count()])
	for pair in [["eggs_lost", "jaja_przepadly"], ["eggs_spoiled", "jaja_zgnily"],
			["fox_took", "kury_lis"], ["died_hunger", "kury_glod"], ["died_disease", "kury_choroba"],
			["fox_arrived", "lisy"], ["fox_blocked", "lisy_plot"], ["hatched", "wyklute"]]:
		_log[pair[1]] = float(_log.get(pair[1], 0.0)) + float(out.get(pair[0], 0))
	if int(out.get("fox_arrived", 0)) > 0 or int(out.get("fox_took", 0)) > 0:
		_attacks += int(out.get("fox_arrived", 0))


## Zapamietuje godzine (od startu doby) pierwszego zakupu danej rzeczy.
func _mark(key: String) -> void:
	_first[key] = minf(float(_first.get(key, INF)), _now / 3600.0)


## Biezacy czas doby w sekundach (do _mark).
var _now := 0.0


# --- decyzje gracza ---------------------------------------------------------


## Zasady "rozsadnego gracza":
##  1. lis na wybiegu -> po REAKCJA_NA_LISA s klika 2,5 razy na sekunde,
##  2. zbiera jaja z wybiegu, leczy chore (albo oddaje do skupu tanie),
##  3. trzyma pasze na ZAPAS_PASZY_MIN minut,
##  4. wylega jaja najdrozszej rasy, ktora ma (inkubator pelny),
##  5. sprzedaje jaja i wyhodowane nadmiarowe ptaki (koguty ponad jednego
##     na rase od razu - sa po 250%),
##  6. kupuje wg kolejnosci: kogut dla rasy bez koguta, obrona po pierwszym
##     lisie, kurnik/inkubator/magazyn gdy sie zapychaja, potem kury
##     najdrozszej dostepnej rasy na hodowle i najlepsze nioski do pelna.
func _decide(dt: float) -> void:
	var game := Game
	# 1. Lis.
	if _state.fox_visit_left > 0.0:
		_fox_seen += dt
		if _fox_seen > REAKCJA_NA_LISA:
			_taps_carry += KLIKI_NA_SEKUNDE * dt
			while _taps_carry >= 1.0 and _state.fox_visit_left > 0.0:
				_taps_carry -= 1.0
				if game.poke_fox():
					_log["lisy_przegonione"] = float(_log.get("lisy_przegonione", 0.0)) + 1.0
	else:
		_fox_seen = 0.0
		_taps_carry = 0.0
	# 2. Jaja z wybiegu i choroby.
	for breed_id: String in _state.eggs_on_ground.duplicate():
		if not game.collect_egg_of_breed(breed_id):
			break
	_doctor()
	# 3. Pasza na zapas.
	_keep_feed(ZAPAS_PASZY_MIN)
	# 4-5. Wyleg, sprzedaz.
	_incubate()
	_sell_surplus_birds()
	_sell_all_eggs()
	# 6. Zakupy.
	_shop()


func _doctor() -> void:
	# Leku nie ma (12.20): chora jest stracona, wiec bot od razu sprzedaje ja
	# do McDonalda — 5 zl lepsze niz trup.
	for i in range(_state.chickens.size() - 1, -1, -1):
		if i >= _state.chickens.size():
			continue
		var hen: Chicken = _state.chickens[i]
		if hen.sick:
			Game.cull_hen(hen.breed_id, hen.is_rooster)
	# Szczepienie: gdy stado przekroczy 15 sztuk albo wlasnie trwa ognisko.
	var worth_it := _state.hen_count() >= 15 or _state.outbreak_on
	if worth_it and _state.unvaccinated_count() >= 3 \
			and _state.money > Game.vaccine_price() * 2.0:
		Game.buy_vaccine()
		_mark("szczepienie")


## Ile paszy zje stado przez `minutes` minut zegara. Liczymy tez ptaki
## w drodze (jaja w inkubatorze i piskleta) - w czasie przerwy dorosna
## i zaczna jesc. Bez tego bot kupowal pasze na 11 ptakow, a wracal do 29.
func _feed_need(minutes: float) -> float:
	var per_hen := float(GameData.balance()["economy"].get("feed_per_hen_minute", 0.3))
	var mouths := _state.chickens.size() + _state.chicks.size() + _state.incubating.size()
	return per_hen * mouths * minutes * GameData.time_scale()


func _keep_feed(minutes_real: float) -> void:
	var need := _feed_need(minutes_real) - _state.feed
	if need <= 0.0:
		return
	var pack := _state.feed_pack()
	var packs := int(ceil(need / float(pack["size"])))
	var spent := 0.0
	while packs > 0:
		var n := mini(packs, 10)
		if not Game.buy_feed(n):
			if not Game.buy_feed(1):
				break
			n = 1
		packs -= n
		spent += float(pack["price"]) * n
		_log["pasza_kg"] = float(_log.get("pasza_kg", 0.0)) + float(pack["size"]) * n
	_log["pasza_zl"] = float(_log.get("pasza_zl", 0.0)) + spent


## Przed wyjsciem: sprzedaj jaja, kup paszy na cala przerwe (ile sie da).
func _before_leaving(away_seconds: float) -> void:
	_sell_all_eggs()
	var before := _state.feed
	_keep_feed(away_seconds / 60.0 + 5.0)
	if DEBUG:
		print("  wyjscie %5.2f h na %.0f min: pasza %.0f -> %.0f kg (potrzeba %.0f), kasa %.0f" % [
				_now / 3600.0, away_seconds / 60.0, before, _state.feed,
				_feed_need(away_seconds / 60.0 + 5.0), _state.money])


func _breed_value(breed_id: String) -> float:
	var price := float(GameData.breed(breed_id).get("price", 0))
	var share := float(GameData.balance().get("incubator", {}).get("rooster_share", 0.0))
	return price * 0.7 * (1.0 - share) + FarmState.hen_sell_price(breed_id, false, true) * share


func _incubate() -> void:
	var best := ""
	var best_v := -1.0
	for breed_id: String in _state.eggs.keys():
		if int(_state.eggs[breed_id]) < Game.eggs_per_chick():
			continue
		var v := _breed_value(breed_id)
		if v > best_v:
			best_v = v
			best = breed_id
	if best.is_empty():
		return
	while Game.can_incubate(best):
		Game.incubate(best)
		_mark("pierwszy wyleg")


func _sell_all_eggs() -> void:
	_log["jaja_sprzedane"] = float(_log.get("jaja_sprzedane", 0.0)) + _state.egg_count()
	var earned := Game.sell_eggs(0)
	if earned > 0.0:
		_log["przychod_jaja"] = float(_log.get("przychod_jaja", 0.0)) + earned


## Najlepsza rasa na hodowle: najdrozsza, na ktora kurnik pozwala.
func _breeding_breed() -> String:
	var best := "leghorn"
	var best_p := 0.0
	for b: Dictionary in GameData.breeds():
		var id := String(b["id"])
		if not Game.breed_allowed(id):
			continue
		var p := float(b.get("price", 0))
		if p > best_p:
			best_p = p
			best = id
	return best


## Najlepsza nioska: najwiekszy zysk z jaj na godzine.
func _best_layer() -> String:
	var best := "leghorn"
	var best_v := -INF
	var feed_kg := float(_state.feed_pack()["per_kg"])
	var per_h := float(GameData.balance()["economy"].get("feed_per_hen_minute", 0.3)) * 60.0 \
			* GameData.time_scale()
	for b: Dictionary in GameData.breeds():
		var id := String(b["id"])
		if not Game.breed_allowed(id):
			continue
		var eggs_h := 3600.0 * GameData.time_scale() / float(b.get("egg_seconds", 99.0))
		var v := eggs_h * float(b.get("egg_value", 0.0)) - per_h * feed_kg
		if v > best_v:
			best_v = v
			best = id
	return best


## Sprzedaje: koguty ponad jednego na rase, kury ponad cel nioski,
## najpierw tanie rasy.
func _sell_surplus_birds() -> void:
	var seen := {}
	for i in range(_state.chickens.size() - 1, -1, -1):
		if i >= _state.chickens.size():
			continue
		var hen: Chicken = _state.chickens[i]
		if not hen.is_rooster or hen.sick:
			continue
		if seen.has(hen.breed_id):
			_sold(Game.sell_hen(hen.breed_id, true))
			_log["koguty_sprzedane"] = float(_log.get("koguty_sprzedane", 0.0)) + 1.0
		else:
			seen[hen.breed_id] = true
	# Miejsce w kurniku na wyleg: tyle, ile slotow inkubatora.
	var reserve := Game.incubator_slots()
	while _state.coop_free() < reserve and _state.hen_count() > 6:
		var cheapest := ""
		var cheapest_p := INF
		var breeding := _breeding_breed()
		for hen: Chicken in _state.chickens:
			if hen.is_rooster or hen.sick:
				continue
			# Nie sprzedajemy ostatnich kur rasy hodowlanej.
			if hen.breed_id == breeding and _state.hens_of_breed(breeding, true) <= 4:
				continue
			var p := float(GameData.breed(hen.breed_id).get("price", 0))
			if p < cheapest_p:
				cheapest_p = p
				cheapest = hen.breed_id
		if cheapest.is_empty():
			break
		_sold(Game.sell_hen(cheapest, false))


func _sold(amount: float) -> void:
	if amount > 0.0:
		_log["przychod_ptaki"] = float(_log.get("przychod_ptaki", 0.0)) + amount


## Rozsadny gracz wie, kiedy wychodzi i na jak dlugo - trzyma pieniadze na
## pasze do konca sesji i na cala nastepna przerwe.
var _reserve_minutes := 20.0
func _spend_ok(price: float) -> bool:
	var need := maxf(0.0, _feed_need(_reserve_minutes) - _state.feed)
	var feed_cost := need * float(_state.feed_pack()["per_kg"])
	return _state.money - price >= feed_cost


func _shop() -> void:
	# a) kogut dla kazdej rasy z kurami bez koguta
	for breed_id: String in _state.breeds_without_rooster():
		if _spend_ok(FarmState.hen_buy_price(breed_id, true)) and _state.coop_has_room():
			if Game.buy_hen(breed_id, true):
				_log["kupione_kury"] = float(_log.get("kupione_kury", 0.0)) + 1
	# b) obrona po napasciach
	if _attacks >= 1:
		_try_building("guard", 1.5, "plot")
	if _attacks >= 2:
		_try_dog(2.0)
	if _state.guard_level >= 1 and _state.dog_level >= 1:
		_try_building("guard", 6.0, "plot")
		_try_dog(6.0)
	# c) kurnik, gdy pelny; inkubator i magazyn rownolegle z kurnikiem
	var cap := _state.coop_capacity()
	if _state.coop_occupied() + _state.coop_reserved() >= int(cap * 0.85):
		_try_building("coop", 1.0, "kurnik")
	if _state.incubator_level <= _state.coop_level:
		_try_incubator()
	if _state.storage_level < _state.coop_level or float(_log.get("jaja_przepadly", 0.0)) > 0.0:
		_try_building("storage", 1.2, "magazyn")
	# d) kury na hodowle: kogut + 4 kury najdrozszej dostepnej rasy
	var breeding := _breeding_breed()
	if not _state.has_rooster(breeding):
		if _spend_ok(FarmState.hen_buy_price(breeding, true) + FarmState.hen_buy_price(breeding) * 4.0) \
				and _state.coop_free() >= 5:
			if Game.buy_hen(breeding, true):
				_mark("rasa: " + breeding)
	while _state.has_rooster(breeding) and _state.hens_of_breed(breeding) < 4 \
			and _state.coop_free() > Game.incubator_slots() \
			and _spend_ok(FarmState.hen_buy_price(breeding)):
		if not Game.buy_hen(breeding):
			break
		_log["kupione_kury"] = float(_log.get("kupione_kury", 0.0)) + 1
	# e) reszta kurnika - najlepsze nioski (z kogutem)
	var layer := _best_layer()
	if not _state.has_rooster(layer) and _spend_ok(FarmState.hen_buy_price(layer, true) * 2.0) \
			and _state.coop_free() > Game.incubator_slots() + 2:
		Game.buy_hen(layer, true)
	while _state.has_rooster(layer) and _state.coop_free() > Game.incubator_slots() \
			and _spend_ok(FarmState.hen_buy_price(layer)):
		if not Game.buy_hen(layer):
			break
		_log["kupione_kury"] = float(_log.get("kupione_kury", 0.0)) + 1


func _try_building(id: String, margin: float, label: String) -> void:
	var up := _state.next_building_upgrade(id)
	if up.is_empty():
		return
	var price := float(up.get("price", 0))
	if _spend_ok(price * margin) and Game.upgrade_building(id):
		_log["wydane_ulepszenia"] = float(_log.get("wydane_ulepszenia", 0.0)) + price
		_mark("%s %d" % [label, _state.building_level(id)])


func _try_incubator() -> void:
	var up := _state.next_incubator_upgrade()
	if up.is_empty():
		return
	var price := float(up.get("price", 0))
	if _spend_ok(price) and Game.upgrade_incubator():
		_log["wydane_ulepszenia"] = float(_log.get("wydane_ulepszenia", 0.0)) + price
		_mark("inkubator %d" % _state.incubator_level)


func _try_dog(margin: float) -> void:
	var up := _state.next_building_upgrade("dog")
	if up.is_empty():
		return
	var price := float(up.get("price", 0))
	if _spend_ok(price * margin) and Game.upgrade_building("dog"):
		_log["wydane_ulepszenia"] = float(_log.get("wydane_ulepszenia", 0.0)) + price
		_mark("pies %d" % _state.dog_level)
