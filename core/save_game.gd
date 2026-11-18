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
const VERSION := 2


## Zamienia stan gry na slownik gotowy do zapisu.
static func to_dict(state: FarmState) -> Dictionary:
	var hens := []
	for hen: Chicken in state.chickens:
		hens.append({"breed": hen.breed_id, "since_last_egg": hen.since_last_egg})
	var batches := []
	for batch: EggBatch in state.incubating:
		batches.append({"breed": batch.breed_id, "elapsed": batch.elapsed, "count": batch.count})
	var chicks := []
	for chick: Chick in state.chicks:
		chicks.append({"breed": chick.breed_id, "grown": chick.grown})
	return {
		"version": VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"money": state.money,
		"eggs": state.eggs,
		"eggs_on_ground": state.eggs_on_ground,
		"feed": state.feed,
		"days": state.days,
		"unlocked": state.unlocked_breeds,
		"chickens": hens,
		"incubating": batches,
		"chicks": chicks,
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
	state.money = int(data.get("money", 0))
	state.eggs = int(data.get("eggs", 0))
	state.eggs_on_ground = int(data.get("eggs_on_ground", 0))
	state.feed = float(data.get("feed", 0.0))
	state.days = int(data.get("days", 0))
	for breed_id: String in data.get("unlocked", []):
		if not GameData.breed(breed_id).is_empty() and not state.unlocked_breeds.has(breed_id):
			state.unlocked_breeds.append(breed_id)
	for entry: Dictionary in data.get("chickens", []):
		var breed_id := String(entry.get("breed", ""))
		# Rasa mogla zniknac z breeds.json — taka kura przepada, zamiast psuc zapis.
		if GameData.breed(breed_id).is_empty():
			push_warning("SaveGame: pomijam kure nieznanej rasy '%s'" % breed_id)
			continue
		state.chickens.append(Chicken.create(breed_id, float(entry.get("since_last_egg", 0.0))))
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
		state.chicks.append(Chick.create(breed_id, float(entry.get("grown", 0.0))))
	state.ensure_starting_unlocks()

	var saved_at := float(data.get("saved_at", 0.0))
	var elapsed := maxf(0.0, Time.get_unix_time_from_system() - saved_at)
	return {"state": state, "elapsed": elapsed, "saved_at": saved_at}


## Zapisuje stan do pliku. Zwraca false, jesli zapis sie nie powiodl.
static func save_state(state: FarmState, path: String = PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: nie moge zapisac do %s (blad %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(to_dict(state)))
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
	return data
