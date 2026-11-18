extends Node
## Autoload "Game": wlasciciel stanu gry i jedyne miejsce, ktore go zmienia.
## UI czyta Game.state, wywoluje te metody i slucha sygnalow z Events.

## Co ile sekund zapisywac stan w tle. Przegladarka nie zawsze zdazy zglosic
## zamkniecie karty, wiec nie opieramy sie wylacznie na zapisie przy wyjsciu.
const AUTOSAVE_SECONDS := 8.0

var state: FarmState

## Pamietamy, czy brak paszy byl juz zgloszony, zeby nie powtarzac komunikatu.
var _reported_no_feed := false
## Ostatnio pokazana (calkowita) ilosc paszy — zeby licznik w HUD nadazal
## za powolnym ubywaniem, ale bez wysylania sygnalu w kazdej klatce.
var _shown_feed := -1
var _autosave_left := AUTOSAVE_SECONDS


func _ready() -> void:
	load_or_start()


func _notification(what: int) -> void:
	# Telefon usypiajacy aplikacje, zamykana karta, zamykane okno.
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST,
			NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_EXIT_TREE]:
		save()


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

	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_SECONDS
		save()


## Wczytuje zapis i nadrabia czas spedzony poza gra; bez zapisu zaczyna od nowa.
func load_or_start() -> void:
	var loaded := SaveGame.load_state()
	if loaded.is_empty():
		new_game()
		return
	state = loaded["state"]
	_reported_no_feed = false
	_shown_feed = -1
	_catch_up(float(loaded["elapsed"]))
	Events.resources_changed.emit()


func new_game() -> void:
	_reported_no_feed = false
	_shown_feed = -1
	state = FarmState.from_start_config(GameData.balance().get("start", {}))
	Events.resources_changed.emit()


func save() -> void:
	if state != null:
		SaveGame.save_state(state)


## Kasuje zapis i zaczyna od zera.
func reset() -> void:
	SaveGame.clear()
	new_game()
	save()


## Dolicza produkcje z czasu, kiedy gra byla zamknieta.
## Limit godzin siedzi w balance.json, zeby po dlugiej przerwie gracz nie
## zastawal od razu wszystkiego gotowego.
func _catch_up(elapsed: float) -> void:
	var max_hours := float(GameData.balance().get("offline", {}).get("max_hours", 8.0))
	var seconds := clampf(elapsed, 0.0, max_hours * 3600.0)
	if seconds < 1.0:
		return
	var result := Simulation.advance(state, seconds)
	var laid := int(result["eggs_laid"])
	if laid > 0:
		Events.notice.emit(tr("HINT_WELCOME_BACK") % laid)


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


## Sprzedaje jedna kure podanej rasy. Zwraca uzyskana kwote albo 0.
func sell_hen(breed_id: String) -> int:
	var index := -1
	for i in state.chickens.size():
		if state.chickens[i].breed_id == breed_id:
			index = i
			break
	if index < 0:
		return 0
	var price := FarmState.hen_sell_price(breed_id)
	state.chickens.remove_at(index)
	state.money += price
	Events.hen_removed.emit(breed_id)
	Events.resources_changed.emit()
	return price
