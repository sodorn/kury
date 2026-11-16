extends Node
## Autoload "Config": wczytuje dane gry z res://data/*.json.
## Balans i definicje zmienia sie w tych plikach, nie w kodzie.

const DATA_DIR := "res://data/"

var balance: Dictionary = {}
var buildings: Array = []


func _init() -> void:
	balance = _load_json("balance.json", {})
	buildings = _load_json("buildings.json", [])


func building(id: String) -> Dictionary:
	for def: Dictionary in buildings:
		if def.get("id", "") == id:
			return def
	push_error("Config: nieznany budynek '%s'" % id)
	return {}


func _load_json(file_name: String, fallback: Variant) -> Variant:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("Config: brak pliku %s" % path)
		return fallback
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		push_error("Config: blad w %s (linia %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return fallback
	if typeof(json.data) != typeof(fallback):
		push_error("Config: nieoczekiwany typ danych w %s" % path)
		return fallback
	return json.data
