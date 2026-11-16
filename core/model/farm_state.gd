class_name FarmState
extends RefCounted
## Stan gospodarstwa. Czyste dane: bez wezlow, bez UI, bez dostepu do plikow.

var money: int = 0
var eggs: int = 0
var feed: int = 0
var hens: int = 0
var chicks: int = 0


## Tworzy stan nowej gry z sekcji "start" pliku data/balance.json.
static func from_start_config(start: Dictionary) -> FarmState:
	var state := FarmState.new()
	state.money = int(start.get("money", 0))
	state.eggs = int(start.get("eggs", 0))
	state.feed = int(start.get("feed", 0))
	state.hens = int(start.get("hens", 0))
	state.chicks = int(start.get("chicks", 0))
	return state


func animal_count() -> int:
	return hens + chicks
