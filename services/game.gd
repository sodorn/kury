extends Node
## Autoload "Game": wlasciciel stanu gry i jedyne miejsce, ktore go zmienia.
## UI czyta Game.state, wywoluje te metody i slucha sygnalow z Events.

## Co ile sekund zapisywac stan. Przegladarka nie zawsze zdazy zglosic
## zamkniecie karty, wiec nie opieramy sie wylacznie na zapisie przy wyjsciu.
const AUTOSAVE_SECONDS := 8.0
## Ile czekamy na odpowiedz serwera przy starcie, zanim ruszymy z lokalnym zapisem.
const CLOUD_WAIT_SECONDS := 6.0

var state: FarmState

var _reported_no_feed := false
var _shown_feed := -1
var _autosave_left := AUTOSAVE_SECONDS
var _started := false


func _ready() -> void:
	Cloud.pulled.connect(_on_cloud_pulled)
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
	_report(result)

	var feed_now := int(floor(state.feed))
	if feed_now != _shown_feed:
		_shown_feed = feed_now
		Events.resources_changed.emit()

	var hungry := bool(result["out_of_feed"]) and not state.chickens.is_empty()
	if hungry and not _reported_no_feed:
		Events.notice.emit(tr("HINT_NO_FEED"))
	_reported_no_feed = hungry

	_check_unlocks()

	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_SECONDS
		save()


## Zglasza do UI, co przyniosl ostatni krok symulacji.
func _report(result: Dictionary) -> void:
	var laid := int(result["eggs_laid"])
	if laid > 0:
		Events.eggs_laid.emit(laid)
		Events.resources_changed.emit()
	if int(result["hatched"]) > 0 or int(result["grown_up"]) > 0:
		Events.resources_changed.emit()


func _check_unlocks() -> void:
	for breed_id in Simulation.check_unlocks(state):
		Events.breed_unlocked.emit(breed_id)
		Events.notice.emit(tr("HINT_BREED_UNLOCKED") % tr(GameData.breed(breed_id).get("name", "")))


## Wczytuje stan: najpierw lokalnie, potem (jesli wlaczony) z serwera.
func load_or_start() -> void:
	var loaded := SaveGame.load_state()
	if loaded.is_empty():
		new_game()
	else:
		_apply_loaded(loaded)
	_started = true
	if Cloud.is_enabled():
		Cloud.pull()


## Serwer odpowiedzial. Jesli ma nowszy zapis niz lokalny, bierzemy jego.
func _on_cloud_pulled(payload: Dictionary, ok: bool) -> void:
	if not ok or payload.is_empty():
		return
	var remote := SaveGame.from_dict(payload)
	if remote.is_empty():
		return
	var local_saved_at := 0.0
	var local := SaveGame.load_state()
	if not local.is_empty():
		local_saved_at = float(local["saved_at"])
	if float(remote["saved_at"]) <= local_saved_at:
		return
	_apply_loaded(remote)
	Events.notice.emit(tr("HINT_CLOUD_LOADED"))


func _apply_loaded(loaded: Dictionary) -> void:
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
	if state == null:
		return
	SaveGame.save_state(state)
	if Cloud.is_enabled():
		Cloud.push(SaveGame.to_dict(state))


## Kasuje zapis i zaczyna od zera.
func reset() -> void:
	SaveGame.clear()
	new_game()
	save()


## Dolicza produkcje z czasu, kiedy gra byla zamknieta.
func _catch_up(elapsed: float) -> void:
	var max_hours := float(GameData.balance().get("offline", {}).get("max_hours", 8.0))
	var seconds := clampf(elapsed, 0.0, max_hours * 3600.0)
	if seconds < 1.0:
		return
	var result := Simulation.advance(state, seconds)
	_check_unlocks()
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


## Kupuje kure podanej rasy. Rasa musi byc odblokowana.
func buy_hen(breed_id: String) -> bool:
	var def := GameData.breed(breed_id)
	if def.is_empty() or not state.is_unlocked(breed_id):
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


# --- inkubator ----------------------------------------------------------


func incubator_slots() -> int:
	return int(GameData.balance().get("incubator", {}).get("slots", 3))


func eggs_per_chick() -> int:
	return int(GameData.balance().get("incubator", {}).get("eggs_per_chick", 6))


## Czy da sie wstawic jaja danej rasy do inkubatora.
func can_incubate(breed_id: String) -> bool:
	return state.owns_breed(breed_id) \
			and state.incubating.size() < incubator_slots() \
			and state.eggs >= eggs_per_chick()


## Wstawia jaja do inkubatora. Rase bierzemy z posiadanego stada —
## z jaj wlasnych kur wyklu je sie pisklę tej samej rasy.
func incubate(breed_id: String) -> bool:
	if not can_incubate(breed_id):
		return false
	state.eggs -= eggs_per_chick()
	state.incubating.append(EggBatch.create(breed_id, 1))
	Events.resources_changed.emit()
	return true
