class_name SaveGame
extends RefCounted
## Zapis i odczyt stanu gry.
##
## Stan zamieniamy na zwykly slownik (`to_dict`), ktory idzie w dwa miejsca:
## do pliku `user://save.json` i — jesli wlaczony jest serwer — na serwer.
## Dzieki temu obie drogi zapisuja dokladnie to samo.
##
## Kazdy zapis ma numer wersji. Gdy format sie zmieni, podnosimy VERSION
## i dopisujemy migracje w `_migrate`, zeby stare zapisy dalo sie wczytac.

const PATH := "user://save.json"
## Numer formatu zapisu. Podnosic przy KAZDEJ zmianie ukladu pol.
const VERSION := 6


## Zamienia stan gry na slownik gotowy do zapisu.
##
## `unpaid_seconds` to czas, ktory JUZ uplynal, ale nie zostal jeszcze
## rozliczony w symulacji — tyle uzbieralo sie, gdy okno bylo nieaktywne.
## Odejmujemy go od stempla czasu, bo `saved_at` ma oznaczac ostatnia
## POLICZONA chwile gospodarstwa, a nie moment zapisu na dysk.
##
## Bez tego ginela cala noc: karta stala w tle, gospodarstwo nie liczylo
## nic, a autozapis co osiem sekund wbijal swiezy stempel. Po przeladowaniu
## gra widziala "od ostatniego zapisu minela sekunda" i caly uzbierany czas
## przepadal razem z jajami i pieniedzmi z nocy.
static func to_dict(state: FarmState, unpaid_seconds: float = 0.0) -> Dictionary:
	var hens := []
	for hen: Chicken in state.chickens:
		hens.append(hen.to_dict())
	var batches := []
	for batch: EggBatch in state.incubating:
		batches.append({"breed": batch.breed_id, "elapsed": batch.elapsed, "count": batch.count})
	var chicks := []
	for chick: Chick in state.chicks:
		chicks.append({"breed": chick.breed_id, "grown": chick.grown, "rooster": chick.rooster})
	var corpses := []
	for corpse: Corpse in state.corpses:
		corpses.append(corpse.to_dict())
	return {
		"version": VERSION,
		"saved_at": Time.get_unix_time_from_system() - maxf(0.0, unpaid_seconds),
		"money": state.money,
		"eggs": state.eggs,
		"eggs_on_ground": state.eggs_on_ground,
		"feed": state.feed,
		"day_fraction": state.day_fraction,
		"days": state.days,
		"unlocked": state.unlocked_breeds,
		"chickens": hens,
		"incubating": batches,
		"chicks": chicks,
		"corpses": corpses,
		"incubator_level": state.incubator_level,
		"coop_level": state.coop_level,
		"storage_level": state.storage_level,
		"guard_level": state.guard_level,
		"dog_level": state.dog_level,
		"dog_age": state.dog_age,
		"dog_life": state.dog_life,
		"construction": state.construction,
		"egg_ages": state.egg_ages,
		"rooster_hints": state.rooster_hints,
		"fox_roll_timer": state.fox_roll_timer,
		"fox_hand_scared": state.fox_hand_scared,
		"disease_timer": state.disease_timer,
		"outbreak_on": state.outbreak_on,
		"outbreak_left": state.outbreak_left,
		"outbreak_timer": state.outbreak_timer,
		"outbreak_dead": state.outbreak_dead,
		"outbreak_breed": state.outbreak_breed,
		"outbreak_survive": state.outbreak_survive,
		"outbreak_saved": state.outbreak_saved,
		"disease_calm": state.disease_calm,
		"fox_visit_left": state.fox_visit_left,
		"fox_pending": state.fox_pending,
		"event_dry": state.event_dry,
		"hunger_seconds": state.hunger_seconds,
		"intro_seen": state.intro_seen,
		"won": state.won,
		"win_reason": state.win_reason,
	}


## Odtwarza stan ze slownika. Zwraca pusty slownik, gdy danych nie da sie uzyc;
## inaczej {"state": FarmState, "elapsed": sekundy od zapisu, "saved_at": czas}.
static func from_dict(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {}
	var version := int(data.get("version", 0))
	if version > VERSION:
		push_warning("SaveGame: zapis pochodzi z nowszej wersji gry (%d) — pomijam go" % version)
		return {}
	data = _migrate(data, version)

	var state := FarmState.new()
	state.money = float(data.get("money", 0))
	state.feed = float(data.get("feed", 0.0))
	state.days = int(data.get("days", 0))
	state.day_fraction = clampf(float(data.get("day_fraction", 0.0)), 0.0, 1.0)
	state.incubator_level = maxi(0, int(data.get("incubator_level", 0)))
	state.coop_level = maxi(0, int(data.get("coop_level", 0)))
	state.storage_level = maxi(0, int(data.get("storage_level", 0)))
	state.guard_level = maxi(0, int(data.get("guard_level", 0)))
	state.dog_level = maxi(0, int(data.get("dog_level", 0)))
	# 13.0: stare zapisy nie znaja wieku psa - pies dostaje nowe zycie od zera.
	state.dog_age = maxf(0.0, float(data.get("dog_age", 0.0)))
	state.dog_life = maxf(0.0, float(data.get("dog_life", 0.0)))
	if state.dog_level > 0 and state.dog_life <= 0.0:
		state.roll_dog_life()
	# Wizyty lisa nie przenosimy przez zapis: gracz, ktory wylaczyl gre
	# w trakcie, nie ma czego przeganiac po powrocie.
	state.fox_visit_left = 0.0
	state.fox_lurk_left = 0.0
	state.fox_pending = 0
	state.fox_kill_left = 0
	state.fox_kill_timer = 0.0
	state.fox_taps_left = 0
	# Licznik do losowania i znacznik recznego przegonienia przenosza sie —
	# dzieki temu kara za przegonienie golymi rekami przezywa wylaczenie gry.
	state.fox_roll_timer = maxf(0.0, float(data.get("fox_roll_timer", 0.0)))
	state.fox_hand_scared = bool(data.get("fox_hand_scared", false))
	state.disease_timer = maxf(0.0, float(data.get("disease_timer", 0.0)))
	# Ognisko choroby (od 12.20). Starsze zapisy go nie znaja — zaczynaja bez
	# ogniska i bez okresu spokoju; chore kury ze starego zapisu i tak dojda
	# do konca choroby.
	state.outbreak_on = bool(data.get("outbreak_on", false))
	state.outbreak_left = maxi(0, int(data.get("outbreak_left", 0)))
	state.outbreak_timer = maxf(0.0, float(data.get("outbreak_timer", 0.0)))
	state.outbreak_dead = maxi(0, int(data.get("outbreak_dead", 0)))
	# 12.22: stare zapisy nie maja rasy ogniska - wtedy zaraza obejmuje rase
	# pierwszej chorej (Simulation._outbreak_breed_of).
	state.outbreak_breed = String(data.get("outbreak_breed", ""))
	state.outbreak_survive = clampf(float(data.get("outbreak_survive", 0.0)), 0.0, 1.0)
	state.outbreak_saved = maxi(0, int(data.get("outbreak_saved", 0)))
	state.disease_calm = maxf(0.0, float(data.get("disease_calm", 0.0)))
	state.fox_massacre = false
	state.rooster_hints = Dictionary(data.get("rooster_hints", {}))
	# Licznik suchych minut przenosi sie przez zapis — na tym polega narastanie
	# szansy przy graniu z doskoku. Stare zapisy zaczynaja od zera.
	state.event_dry = {}
	for key: String in ["fox", "disease"]:
		state.event_dry[key] = maxf(0.0, float(
				(data.get("event_dry", {}) as Dictionary).get(key, 0.0)))
	state.hunger_seconds = maxf(0.0, float(data.get("hunger_seconds", 0.0)))
	# Budowy w toku (od 12.19). Starsze zapisy ich nie znaja.
	state.construction = {}
	var jobs: Variant = data.get("construction", {})
	if jobs is Dictionary:
		for id: String in ["coop", "storage", "incubator"]:
			var job: Variant = (jobs as Dictionary).get(id, [])
			if job is Array and (job as Array).size() >= 2:
				var left := maxf(0.0, float(job[0]))
				var total := maxf(left, float(job[1]))
				state.construction[id] = [left, total]
	state.intro_seen = bool(data.get("intro_seen", false))
	state.won = bool(data.get("won", false))
	state.win_reason = String(data.get("win_reason", ""))
	# Jaja liczone wedlug rasy kury, ktora je zniosla.
	for breed_id: String in Dictionary(data.get("eggs", {})):
		if GameData.breed(breed_id).is_empty():
			continue
		var count := int(Dictionary(data.get("eggs", {}))[breed_id])
		if count > 0:
			state.eggs[breed_id] = count
	# Metryka wieku jaj. Zapisy sprzed wersji 12.4 jej nie maja — wtedy
	# traktujemy caly magazyn jako swiezy, bo karanie gracza za zmiane
	# w kodzie byloby nie w porzadku. Gdy metryka jest, przycinamy ja do
	# faktycznego stanu magazynu, zeby obie liczby nigdy sie nie rozjechaly.
	for breed_id: String in state.eggs:
		var zapisane: Array = (data.get("egg_ages", {}) as Dictionary).get(breed_id, [])
		var buckets: Array = []
		var razem := 0
		for bucket: Variant in zapisane:
			if not (bucket is Array) or (bucket as Array).size() < 2:
				continue
			var count2 := maxi(0, int((bucket as Array)[0]))
			if count2 <= 0:
				continue
			razem += count2
			buckets.append([count2, maxf(0.0, float((bucket as Array)[1]))])
		var maja := int(state.eggs[breed_id])
		if razem > maja:
			# Wiecej w metryce niz w magazynie: scinamy od najstarszych.
			var nadmiar := razem - maja
			while nadmiar > 0 and not buckets.is_empty():
				var w_wiaderku := int(buckets[0][0])
				if w_wiaderku > nadmiar:
					buckets[0][0] = w_wiaderku - nadmiar
					nadmiar = 0
				else:
					nadmiar -= w_wiaderku
					buckets.remove_at(0)
		elif razem < maja:
			buckets.append([maja - razem, 0.0])
		if not buckets.is_empty():
			state.egg_ages[breed_id] = buckets
	for breed_id: String in data.get("eggs_on_ground", []):
		if not GameData.breed(breed_id).is_empty():
			state.eggs_on_ground.append(breed_id)
	for breed_id: String in data.get("unlocked", []):
		if not GameData.breed(breed_id).is_empty() and not state.unlocked_breeds.has(breed_id):
			state.unlocked_breeds.append(breed_id)
	for entry: Dictionary in data.get("chickens", []):
		var breed_id := String(entry.get("breed", ""))
		# Rasa mogla zniknac z breeds.json — taka kura przepada, zamiast psuc zapis.
		if GameData.breed(breed_id).is_empty():
			push_warning("SaveGame: pomijam kure nieznanej rasy '%s'" % breed_id)
			continue
		state.chickens.append(Chicken.from_dict(entry))
	for entry: Dictionary in data.get("incubating", []):
		var breed_id := String(entry.get("breed", ""))
		if GameData.breed(breed_id).is_empty():
			continue
		state.incubating.append(EggBatch.create(breed_id, maxi(1, int(entry.get("count", 1))),
				float(entry.get("elapsed", 0.0))))
	for entry: Dictionary in data.get("chicks", []):
		var breed_id := String(entry.get("breed", ""))
		if GameData.breed(breed_id).is_empty():
			continue
		# Zapisy sprzed 12.18 nie znaly plci piskląt - wtedy kazde bylo kurka.
		state.chicks.append(Chick.create(breed_id, float(entry.get("grown", 0.0)),
				bool(entry.get("rooster", false))))
	for entry: Dictionary in data.get("corpses", []):
		if GameData.breed(String(entry.get("breed", ""))).is_empty():
			continue
		state.corpses.append(Corpse.from_dict(entry))
	state.ensure_starting_unlocks()

	var saved_at := float(data.get("saved_at", 0.0))
	var elapsed := maxf(0.0, Time.get_unix_time_from_system() - saved_at)
	return {"state": state, "elapsed": elapsed, "saved_at": saved_at}


## Zapisuje stan do pliku. Zwraca false, jesli zapis sie nie powiodl.
static func save_state(state: FarmState, path: String = PATH, unpaid_seconds: float = 0.0) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: nie moge zapisac do %s (blad %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(to_dict(state, unpaid_seconds)))
	file.close()
	return true


static func has_save(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)


static func clear(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Wczytuje zapis z pliku; pusty slownik, gdy pliku nie ma albo jest zepsuty.
static func load_state(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_error("SaveGame: zapis %s jest uszkodzony — zaczynam nowa gre" % path)
		return {}
	return from_dict(json.data)


## Przenosi dane ze starszych formatow do biezacego.
static func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version < 1:
		data["version"] = 1
	if from_version < 2:
		# Wersja 2 dodala inkubator, pisklęta, licznik dni i odblokowane rasy.
		data["incubating"] = []
		data["chicks"] = []
		data["days"] = 0
		data["unlocked"] = []
		data["version"] = 2
	if from_version < 3:
		# Wersja 3: jaja liczone wedlug rasy, pieniadze ulamkowe (zlotowki
		# i grosze), choroby, glod, zwloki, lis i rozbudowa inkubatora.
		# Stare jaja bez przypisanej rasy trafiaja na pierwsza posiadana kure.
		var fallback := "leghorn"
		for entry: Dictionary in data.get("chickens", []):
			fallback = String(entry.get("breed", fallback))
			break
		var stored_eggs := int(data.get("eggs", 0))
		data["eggs"] = {fallback: stored_eggs} if stored_eggs > 0 else {}
		var ground := int(data.get("eggs_on_ground", 0))
		var ground_list := []
		for i in maxi(0, ground):
			ground_list.append(fallback)
		data["eggs_on_ground"] = ground_list
		data["corpses"] = []
		data["incubator_level"] = 0
		data["won"] = false
		data["version"] = 3
	if from_version < 4:
		# Wersja 4: poziomy kurnika, magazynu i obrony przed lisem. Stare
		# zapisy zaczynaja od poziomu poczatkowego kazdego budynku.
		data["coop_level"] = 0
		data["storage_level"] = 0
		data["guard_level"] = 0
		data["dog_level"] = 0
		data["version"] = 4
	if from_version < 5:
		# Wersja 5 dzieli stado na kury i koguty, a kura bez koguta swojej rasy
		# nie znosi jaj. W starym zapisie kogutow nie bylo wcale, wiec gra
		# zatrzymalaby sie w miejscu: kazda rasa dostaje jednego koguta
		# w prezencie, zeby wczytana farma dzialala tak jak przed aktualizacja.
		var birds: Array = data.get("chickens", [])
		var vaccinated_breeds := {}
		for entry: Dictionary in birds:
			var breed_id := String(entry.get("breed", ""))
			if breed_id.is_empty():
				continue
			# Kogut przychodzi zaszczepiony, jesli choc jedna kura tej rasy byla —
			# inaczej aktualizacja sama wpuscilaby choroby do zdrowego stada.
			if not vaccinated_breeds.has(breed_id) or bool(entry.get("vax", false)):
				vaccinated_breeds[breed_id] = bool(entry.get("vax", false))
		var gifted: Array = []
		for breed_id: String in vaccinated_breeds:
			var rooster := Chicken.create_rooster(breed_id)
			rooster.vaccinated = bool(vaccinated_breeds[breed_id])
			gifted.append(rooster.to_dict())
		data["chickens"] = birds + gifted
		data["version"] = 5
	if from_version < 6:
		# Wersja 6 rozbija obrone przed lisem na DWIE niezalezne rzeczy.
		# Wczesniej byla jedna drabinka 0-5, w ktorej plot i pies robily to
		# samo: podbijaly szanse, ze lis zawroci przy bramie. Teraz plot
		# decyduje, czy lis wejdzie, a pies — jak szybko wyleci.
		#
		# Przeliczamy hojnie: nikt nie moze stracic tego, za co zaplacil.
		# stary poziom -> [plot, pies]
		var mapa := {0: [0, 0], 1: [1, 0], 2: [1, 1], 3: [2, 1], 4: [2, 2], 5: [3, 2]}
		var stary := clampi(int(data.get("guard_level", 0)), 0, 5)
		var nowe: Array = mapa.get(stary, [0, 0])
		data["guard_level"] = nowe[0]
		data["dog_level"] = nowe[1]
		data["version"] = 6
	return data
