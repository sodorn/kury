extends Node
## Autoload "Game": wlasciciel stanu gry i jedyne miejsce, ktore go zmienia.
## UI czyta Game.state, wywoluje te metody i slucha sygnalow z Events.

## Co ile sekund zapisywac stan. Przegladarka nie zawsze zdazy zglosic
## zamkniecie karty, wiec nie opieramy sie wylacznie na zapisie przy wyjsciu.
const AUTOSAVE_SECONDS := 8.0
## Ile czekamy na odpowiedz serwera przy starcie, zanim ruszymy z lokalnym zapisem.
const CLOUD_WAIT_SECONDS := 6.0
## Najdluzszy odstep miedzy klatkami, ktory jeszcze uznajemy za normalna gre.
## Wiekszy oznacza, ze petla stanela (uspiony laptop, zawieszona karta) —
## wtedy nie ufamy roznicy zegara i bierzemy delte klatki, a reszte nadrobi
## zapis przy nastepnym wczytaniu.
const MAX_LIVE_STEP := 30.0

var state: FarmState

var _reported_no_feed := false
var _shown_feed := -1
var _autosave_left := AUTOSAVE_SECONDS
var _started := false
## Zegar scienny z poprzedniej klatki.
var _last_tick := 0.0
## Czas uzbierany, gdy okno bylo nieaktywne. Rozliczany po powrocie.
var _away_seconds := 0.0


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

	# Symulacje prowadzi zegar scienny, a nie delta klatki. Przegladarka
	# zwalnia petle gry w karcie, ktora jest w tle, wiec delta bywa kilka razy
	# mniejsza niz czas, ktory naprawde uplynal. Zmierzone w Chrome: po stu
	# sekundach w tle gra naliczala sobie 21% tego czasu.
	var now := Time.get_unix_time_from_system()
	var elapsed := now - _last_tick
	_last_tick = now
	# Cofniety zegar systemowy albo pierwsza klatka: bierzemy delte.
	if elapsed <= 0.0 or elapsed > MAX_LIVE_STEP:
		elapsed = maxf(delta, 0.0)

	# Karta w tle to ten sam przypadek co zamknieta gra: jaja ida do magazynu
	# zamiast na wybieg, bo nie ma komu ich zbierac, i obowiazuje bezpiecznik
	# strat. Czas zbieramy do kupy i rozliczamy jednym wywolaniem po powrocie —
	# inaczej odstepy ponizej sekundy przepadalyby, a komunikat powitalny
	# wyskakiwalby raz za razem do pustego ekranu.
	if not DisplayServer.window_is_focused():
		_away_seconds += elapsed
		return
	if _away_seconds > 0.0:
		var away := _away_seconds
		_away_seconds = 0.0
		_apply_elapsed(away)

	var result := Simulation.advance(state, elapsed)
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
	_check_win()

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

	var sick := int(result["got_sick"])
	if sick > 0:
		Events.notice.emit(tr("HINT_SICK") % sick)
	var died_disease := int(result["died_disease"])
	if died_disease > 0:
		Events.notice.emit(tr("HINT_DIED_DISEASE") % died_disease)
		Events.resources_changed.emit()
	var died_hunger := int(result["died_hunger"])
	if died_hunger > 0:
		Events.notice.emit(tr("HINT_DIED_HUNGER") % died_hunger)
		Events.resources_changed.emit()
	var fox := int(result["fox_took"])
	if fox > 0:
		Events.fox_visited.emit(fox)
		Events.notice.emit(tr("HINT_FOX") % fox)
		Events.resources_changed.emit()


func _check_unlocks() -> void:
	for breed_id in Simulation.check_unlocks(state):
		Events.breed_unlocked.emit(breed_id)
		Events.notice.emit(tr("HINT_BREED_UNLOCKED") % tr(GameData.breed(breed_id).get("name", "")))


func _check_win() -> void:
	var reason := Simulation.check_win(state)
	if reason.is_empty():
		return
	Events.game_won.emit(reason)
	save()


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
	_away_seconds = 0.0
	_last_tick = Time.get_unix_time_from_system()
	_apply_elapsed(float(loaded["elapsed"]))
	Events.resources_changed.emit()


func new_game() -> void:
	_reported_no_feed = false
	_shown_feed = -1
	_away_seconds = 0.0
	_last_tick = Time.get_unix_time_from_system()
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


## Dolicza produkcje z czasu, ktorego petla gry nie policzyla: gra byla
## zamknieta albo karta wisiala w tle.
func _apply_elapsed(elapsed: float) -> void:
	var max_hours := float(GameData.balance().get("offline", {}).get("max_hours", 12.0))
	var seconds := clampf(elapsed, 0.0, max_hours * 3600.0)
	if seconds < 1.0:
		return
	var result := Simulation.advance(state, seconds, true)
	_check_unlocks()
	_check_win()
	var laid := int(result["eggs_laid"])
	if laid > 0:
		Events.notice.emit(tr("HINT_WELCOME_BACK") % laid)
	var lost := int(result["died_hunger"]) + int(result["died_disease"]) + int(result["fox_took"])
	if lost > 0:
		Events.notice.emit(tr("HINT_LOST_WHILE_AWAY") % lost)


# --- jaja ---------------------------------------------------------------


## Zbiera z wybiegu jedno jajko danej rasy. Zwraca false, jesli go tam nie ma.
func collect_egg_of_breed(breed_id: String) -> bool:
	var index := state.eggs_on_ground.find(breed_id)
	if index < 0:
		return false
	state.eggs_on_ground.remove_at(index)
	state.add_egg(breed_id)
	Events.resources_changed.emit()
	return true


## Ile jaj kazdej rasy lezy na wybiegu: {"leghorn": 3}.
func ground_eggs_by_breed() -> Dictionary:
	var counts := {}
	for breed_id: String in state.eggs_on_ground:
		counts[breed_id] = int(counts.get(breed_id, 0)) + 1
	return counts


## Sprzedaje wszystkie zebrane jaja. Zwraca zarobek w zlotowkach.
func sell_eggs() -> float:
	var earned := state.eggs_value()
	if earned <= 0.0:
		return 0.0
	state.money += earned
	state.eggs.clear()
	Events.resources_changed.emit()
	return earned


# --- pasza --------------------------------------------------------------


## Kupuje jedna paczke paszy. Zwraca false przy braku pieniedzy.
func buy_feed() -> bool:
	var economy: Dictionary = GameData.balance().get("economy", {})
	var price := float(economy.get("feed_pack_price", 0))
	if state.money < price:
		return false
	state.money -= price
	state.feed += float(economy.get("feed_pack_size", 0))
	_reported_no_feed = false
	Events.resources_changed.emit()
	return true


# --- handel kurami ------------------------------------------------------


## Kupuje kure podanej rasy. Rasa musi byc odblokowana.
func buy_hen(breed_id: String) -> bool:
	var def := GameData.breed(breed_id)
	if def.is_empty() or not state.is_unlocked(breed_id):
		return false
	var price := float(def.get("price", 0))
	if state.money < price:
		return false
	state.money -= price
	var hen := Chicken.create(breed_id)
	state.chickens.append(hen)
	Events.hen_added.emit(hen)
	Events.resources_changed.emit()
	return true


## Sprzedaje jedna kure danej rasy. Najpierw idzie zdrowa, bo za nia skup
## placi pelna stawke; chora dopiero wtedy, gdy zdrowej juz nie ma. Dzieki
## temu kwota na przycisku zawsze zgadza sie z tym, co gracz dostanie.
## Zwraca uzyskana kwote albo 0, gdy nie ma czego sprzedac.
func sell_hen(breed_id: String) -> float:
	var sick := false
	var index := _find_hen(breed_id, false)
	if index < 0:
		index = _find_hen(breed_id, true)
		sick = true
	if index < 0:
		return 0.0
	var price := FarmState.hen_sell_price(breed_id, sick)
	state.chickens.remove_at(index)
	state.money += price
	Events.hen_removed.emit(breed_id)
	Events.resources_changed.emit()
	return price


## Czy kolejna sprzedaz tej rasy dotyczy chorej sztuki (bo zdrowych juz nie ma).
## UI pyta o to, zeby pokazac wlasciwa kwote.
func next_sale_is_sick(breed_id: String) -> bool:
	return _find_hen(breed_id, false) < 0 and _find_hen(breed_id, true) >= 0


## Indeks pierwszej kury danej rasy w zadanym stanie zdrowia; -1, gdy nie ma.
func _find_hen(breed_id: String, sick: bool) -> int:
	for i in state.chickens.size():
		var hen: Chicken = state.chickens[i]
		if hen.breed_id == breed_id and hen.sick == sick:
			return i
	return -1


# --- weterynaria --------------------------------------------------------


func medicine_price() -> float:
	return float(GameData.balance().get("disease", {}).get("medicine_price", 140))


## Cena zaszczepienia calego stada: oplata stala plus stawka od kury,
## ktora szczepienia jeszcze nie ma.
func vaccine_price() -> float:
	var disease: Dictionary = GameData.balance().get("disease", {})
	var base := float(disease.get("vaccine_price", 1200))
	var per_hen := float(disease.get("vaccine_price_per_hen", 45))
	return base + per_hen * state.unvaccinated_count()


## Leczy jedna chora kure — najdrozsza, bo ja warto ratowac najbardziej.
func buy_medicine() -> bool:
	var price := medicine_price()
	if state.money < price or state.sick_count() == 0:
		return false
	var best := -1
	var best_value := -1.0
	for i in state.chickens.size():
		var hen: Chicken = state.chickens[i]
		if not hen.sick:
			continue
		var value := float(GameData.breed(hen.breed_id).get("price", 0))
		if value > best_value:
			best_value = value
			best = i
	if best < 0:
		return false
	state.money -= price
	var cured: Chicken = state.chickens[best]
	cured.sick = false
	cured.sick_seconds = 0.0
	Events.resources_changed.emit()
	Events.notice.emit(tr("HINT_CURED") % tr(GameData.breed(cured.breed_id).get("name", "")))
	return true


## Szczepi cale stado. Chroni do konca zycia, ale tylko kury, ktore zyja
## teraz — mlode wyklute pozniej trzeba zaszczepic osobno.
func buy_vaccine() -> bool:
	if state.unvaccinated_count() == 0:
		return false
	var price := vaccine_price()
	if state.money < price:
		return false
	state.money -= price
	var count := 0
	for hen: Chicken in state.chickens:
		if hen.vaccinated:
			continue
		hen.vaccinated = true
		hen.sick = false
		hen.sick_seconds = 0.0
		count += 1
	Events.resources_changed.emit()
	Events.notice.emit(tr("HINT_VACCINATED") % count)
	return true


# --- inkubator ----------------------------------------------------------


func incubator_slots() -> int:
	return state.incubator_slots()


func eggs_per_chick() -> int:
	return int(GameData.balance().get("incubator", {}).get("eggs_per_chick", 6))


## Czy da sie wstawic jaja danej rasy do inkubatora. Potrzebne sa jaja
## wlasnie tej rasy — z jaj leghorna nie wyklu je sie cemani.
func can_incubate(breed_id: String) -> bool:
	return state.owns_breed(breed_id) \
			and state.incubating.size() < incubator_slots() \
			and int(state.eggs.get(breed_id, 0)) >= eggs_per_chick()


func incubate(breed_id: String) -> bool:
	if not can_incubate(breed_id):
		return false
	state.take_eggs(breed_id, eggs_per_chick())
	state.incubating.append(EggBatch.create(breed_id, 1))
	Events.resources_changed.emit()
	return true


## Rozbudowuje inkubator o kolejny poziom z balance.json.
func upgrade_incubator() -> bool:
	var upgrade := state.next_incubator_upgrade()
	if upgrade.is_empty():
		return false
	var price := float(upgrade.get("price", 0))
	if state.money < price:
		return false
	state.money -= price
	state.incubator_level += 1
	Events.resources_changed.emit()
	Events.notice.emit(tr("HINT_INCUBATOR_UPGRADED") % state.incubator_slots())
	return true
