extends Node
## Testy logiki, danych i sceny farmy (bez okna):
##   godot --headless --path . res://tests/tests.tscn
## Kod wyjscia 0 = wszystko OK, 1 = sa bledy.
##
## Testy uruchamiamy jako scene, a nie przez `-s`, bo skrypt podany w `-s`
## kompiluje sie zanim zarejestruja sie autoloady (Events, Game) i wtedy
## skrypty scen nie daja sie zaladowac.

var _failed := 0
var _passed := 0


func _ready() -> void:
	_test_number_format()
	_test_farm_state()
	_test_data_files()
	_test_farm_scene()
	print("TESTY: %d OK, %d BLEDOW" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("BLAD: " + label)


func _test_number_format() -> void:
	_check(NumberFormat.grouped(0) == "0", "grouped(0)")
	_check(NumberFormat.grouped(999) == "999", "grouped(999)")
	_check(NumberFormat.grouped(1000) == "1 000", "grouped(1000)")
	_check(NumberFormat.grouped(1234567) == "1 234 567", "grouped(1234567)")
	_check(NumberFormat.grouped(-12345) == "-12 345", "grouped(-12345)")


func _test_farm_state() -> void:
	var state := FarmState.from_start_config({"money": 100.0, "feed": 20, "hens": 3, "chicks": 2})
	_check(state.money == 100, "money z configu")
	_check(state.eggs == 0, "brakujace pole = 0")
	_check(state.animal_count() == 5, "animal_count")
	_check(Game.state != null and Game.state.money == int(GameData.balance()["start"]["money"]),
			"Game.state wystartowal z balance.json")


func _test_data_files() -> void:
	_check(GameData.balance().has("start"), "balance.json ma sekcje start")
	_check(GameData.buildings().size() == 4, "buildings.json ma 4 budynki")
	var translation := load("res://data/strings.pl.translation") as Translation
	_check(translation != null, "tlumaczenie pl wczytane")
	var ids := {}
	for def: Dictionary in GameData.buildings():
		var id: String = def.get("id", "")
		_check(id != "" and not ids.has(id), "unikalne id budynku: '%s'" % id)
		ids[id] = true
		for key in ["name", "desc"]:
			var text_key: String = def.get(key, "")
			_check(translation != null and translation.get_message(text_key) != &"", "tekst %s" % text_key)


## Scena farmy musi zawierac budynki (zeby bylo je widac w edytorze),
## a kazdy z nich grafike i id istniejace w data/buildings.json.
func _test_farm_scene() -> void:
	var farm: Node2D = load("res://scenes/farm/farm.tscn").instantiate()
	var found := {}
	for child in farm.get_node("Objects").get_children():
		var building := child as Building
		if building == null:
			continue
		found[building.building_id] = true
		_check(not GameData.building(building.building_id).is_empty(),
				"budynek '%s' ma wpis w buildings.json" % building.building_id)
		var sprite := building.get_node("Sprite") as Sprite2D
		_check(sprite != null and sprite.texture != null, "budynek '%s' ma grafike" % building.building_id)
	for def: Dictionary in GameData.buildings():
		_check(found.has(def.get("id", "")), "budynek '%s' jest w scenie farmy" % def.get("id", ""))
	farm.free()
