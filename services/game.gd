extends Node
## Autoload "Game": wlasciciel stanu gry i jedyne miejsce, ktore go zmienia.
## UI czyta Game.state, wywoluje te metody i slucha sygnalow z Events.

var state: FarmState

## Pamietamy, czy brak paszy byl juz zgloszony, zeby nie powtarzac komunikatu.
var _reported_no_feed := false
## Ostatnio pokazana (calkowita) ilosc paszy — zeby licznik w HUD nadazal
## za powolnym ubywaniem, ale bez wysylania sygnalu w kazdej klatce.
var _shown_feed := -1


func _ready() -> void:
	new_game()


func _process(delta: float) -> void:
	if state == null:
		return
	var result := Simulation.advance(state, delta)
	if int(result["eggs_laid"]) > 0:
		Events.eggs_laid.emit(int(result["eggs_laid"]))
		Events.resources_changed.emit()
	var feed_now := int(floor(state.feed))
	if feed_now != _shown_feed:
		_shown_feed = feed_now
		Events.resources_changed.emit()
	var hungry := bool(result["out_of_feed"]) and not state.chickens.is_empty()
	if hungry and not _reported_no_feed:
		Events.notice.emit(tr("HINT_NO_FEED"))
	_reported_no_feed = hungry


func new_game() -> void:
	_reported_no_feed = false
	_shown_feed = -1
	state = FarmState.from_start_config(GameData.balance().get("start", {}))
	Events.resources_changed.emit()


## Zbiera jedno jajko z wybiegu. Zwraca false, jesli nie bylo czego zbierac.
func collect_egg() -> bool:
	if state.eggs_on_ground <= 0:
		return false
	state.eggs_on_ground -= 1
	state.eggs += 1
	Events.resources_changed.emit()
	return true


## Sprzedaje wszystkie zebrane jaja. Zwraca zarobek.
func sell_eggs() -> int:
	if state.eggs <= 0:
		return 0
	var earned := state.eggs_value()
	state.money += earned
	state.eggs = 0
	Events.resources_changed.emit()
	return earned


## Kupuje jedna paczke paszy. Zwraca false przy braku pieniedzy.
func buy_feed() -> bool:
	var economy: Dictionary = GameData.balance().get("economy", {})
	var price := int(economy.get("feed_pack_price", 0))
	if state.money < price:
		return false
	state.money -= price
	state.feed += float(economy.get("feed_pack_size", 0))
	_reported_no_feed = false
	Events.resources_changed.emit()
	return true


## Kupuje kure podanej rasy. Zwraca false przy braku pieniedzy lub zlej rasie.
func buy_hen(breed_id: String) -> bool:
	var def := GameData.breed(breed_id)
	if def.is_empty():
		return false
	var price := int(def.get("price", 0))
	if state.money < price:
		return false
	state.money -= price
	var hen := Chicken.create(breed_id)
	state.chickens.append(hen)
	Events.hen_added.emit(hen)
	Events.resources_changed.emit()
	return true
