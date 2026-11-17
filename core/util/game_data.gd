class_name GameData
extends RefCounted
## Dane gry wczytane z res://data/*.json.
##
## Dostep statyczny, bez autoloadu: dziala tak samo w grze, w testach
## uruchamianych przez `-s` i w edytorze. Balans zmienia sie w plikach JSON,
## nie w kodzie.

const DATA_DIR := "res://data/"

static var _balance: Dictionary = {}
static var _buildings: Array = []
static var _loaded := false


## Sekcje balansu gry (np. "start").
static func balance() -> Dictionary:
	_ensure_loaded()
	return _balance


## Lista definicji budynkow z data/buildings.json.
static func buildings() -> Array:
	_ensure_loaded()
	return _buildings


## Definicja budynku o podanym id; pusty slownik, jesli nie ma takiego wpisu.
static func building(id: String) -> Dictionary:
	for def: Dictionary in buildings():
		if def.get("id", "") == id:
			return def
	return {}


## Wymusza ponowne wczytanie plikow (uzywane w testach).
static func reload() -> void:
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_balance = _load_json("balance.json", {})
	_buildings = _load_json("buildings.json", [])


static func _load_json(file_name: String, fallback: Variant) -> Variant:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("GameData: brak pliku %s" % path)
		return fallback
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		push_error("GameData: blad w %s (linia %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return fallback
	if typeof(json.data) != typeof(fallback):
		push_error("GameData: nieoczekiwany typ danych w %s" % path)
		return fallback
	return json.data
