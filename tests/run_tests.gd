extends SceneTree
## Testy logiki i danych (bez okna):
##   godot --headless --path . -s tests/run_tests.gd
## Kod wyjscia 0 = wszystko OK, 1 = sa bledy.

var _failed := 0
var _passed := 0


func _initialize() -> void:
	_test_number_format()
	_test_farm_state()
	_test_data_files()
	print("TESTY: %d OK, %d BLEDOW" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


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


func _test_data_files() -> void:
	var config: Node = load("res://services/config.gd").new()
	_check(config.balance.has("start"), "balance.json ma sekcje start")
	_check(config.buildings.size() == 4, "buildings.json ma 4 budynki")
	var translation := load("res://data/strings.pl.translation") as Translation
	_check(translation != null, "tlumaczenie pl wczytane")
	var ids := {}
	for def: Dictionary in config.buildings:
		var id: String = def.get("id", "")
		_check(id != "" and not ids.has(id), "unikalne id budynku: '%s'" % id)
		ids[id] = true
		_check(ResourceLoader.exists(def.get("sprite", "")), "grafika budynku '%s'" % id)
		for key in ["name", "desc"]:
			var text_key: String = def.get(key, "")
			_check(translation != null and translation.get_message(text_key) != &"", "tekst %s" % text_key)
	config.free()
