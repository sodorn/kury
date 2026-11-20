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
## Gracz przepisal kod farmy z innego urzadzenia. Wtedy zapis z serwera
## wygrywa niezaleznie od tego, co lezy lokalnie — inaczej swiezy zapis
## nowego telefonu przykrylby farme, po ktora gracz wlasnie siegnal.
var _force_pull := false
## Na tym urzadzeniu nie bylo jeszcze zadnego zapisu. Ekran powitalny
## sprawdza to przy starcie i pyta: nowa farma czy wczytanie po kodzie.
var is_new_player := false
## Kod, po ktory wlasnie siegnelismy. Odpowiedzi serwera na starsze
## zapytania moga przyjsc pozniej, wiec sprawdzamy, ze dotycza tego kodu.
var _restore_code := ""


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
	# zwalnia petle gry w karcie w tle, a telefon potrafi zamrozic strone
	# calkiem. Zmierzone w Chrome: po stu sekundach w tle gra naliczala sobie
	# 21% tego czasu.
	var now := Time.get_unix_time_from_system()
	var elapsed := now - _last_tick
	_last_tick = now
	# Cofniety zegar systemowy albo pierwsza klatka: bierzemy delte.
	if elapsed <= 0.0:
		elapsed = maxf(delta, 0.0)
	apply_gap(elapsed)

	var feed_now := int(floor(state.feed))
	if feed_now != _shown_feed:
		_shown_feed = feed_now
		Events.resources_changed.emit()

	_check_unlocks()
	_check_win()

	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_SECONDS
		save()


## Rozlicza czas, ktory uplynal od poprzedniej klatki. Wydzielone z `_process`,
## zeby dalo sie to przetestowac bez uruchamiania calej gry.
##
## Trzy przypadki:
##  - okno nieaktywne: czas zbiera sie w `_away_seconds` i czeka na powrot.
##    Rozliczanie go co klatke gubiloby odstepy ponizej sekundy, a komunikat
##    powitalny lecialby w kolko do pustego ekranu;
##  - dziura dluzsza niz `MAX_LIVE_STEP`: petla gry stanela (zminimalizowana
##    przegladarka na telefonie zamraza strone calkiem). Taki czas rozliczamy
##    jak offline. Wczesniej byl po prostu wyrzucany, przez co po powrocie do
##    gry nic sie nie dzialo, a jaja ladowaly na wybiegu zamiast w magazynie;
##  - zwykla klatka: normalny krok symulacji.
##
## `focused` wstrzykuje sie w testach; w grze bierze sie z okna.
## Zwraca true, gdy czas poszedl sciezka offline.
func apply_gap(elapsed: float, focused: bool = DisplayServer.window_is_focused()) -> bool:
	if not focused:
		_away_seconds += elapsed
		return false
	var pending := _away_seconds + elapsed
	_away_seconds = 0.0
	if pending > MAX_LIVE_STEP:
		_apply_elapsed(pending)
		return true
	_report(Simulation.advance(state, pending))
	return false


## Zglasza do UI, co przyniosl ostatni krok symulacji.
func _report(result: Dictionary) -> void:
	# Ostrzezenie o braku paszy pokazujemy raz, przy przejsciu w glod,
	# a nie co klatke.
	var hungry := bool(result["out_of_feed"]) and not state.chickens.is_empty()
	if hungry and not _reported_no_feed:
		Events.notice.emit(tr("HINT_NO_FEED"))
	_reported_no_feed = hungry

	var laid := int(result["eggs_laid"])
	if laid > 0:
		Events.eggs_laid.emit(laid)
		Events.resources_changed.emit()
	if int(result["hatched"]) > 0 or int(result["grown_up"]) > 0:
		Events.resources_changed.emit()

	var sick := int(result["got_sick"])
	if sick > 0:
		Events.alert.emit(tr("ALERT_SICK_TITLE"), tr("ALERT_SICK_BODY") % sick)
	var died_disease := int(result["died_disease"])
	if died_disease > 0:
		Events.notice.emit(tr("HINT_DIED_DISEASE") % died_disease)
		Events.resources_changed.emit()
	var died_hunger := int(result["died_hunger"])
	if died_hunger > 0:
		Events.notice.emit(tr("HINT_DIED_HUNGER") % died_hunger)
		Events.resources_changed.emit()
	var arrived := int(result["fox_arrived"])
	if arrived > 0:
		Events.fox_arrived.emit(state.fox_pending, state.fox_visit_left)
		Events.notice.emit(tr("HINT_FOX_HERE"))
	var fox := int(result["fox_took"])
	if fox > 0:
		Events.fox_visited.emit(fox)
		Events.notice.emit(tr("HINT_FOX") % fox)
		Events.resources_changed.emit()


func _check_unlocks() -> void:
	pass


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
		# Nikt jeszcze nie gral na tym urzadzeniu. Ekran powitalny zapyta,
		# czy zakladamy nowa farme, czy wracamy do istniejacej po kodzie.
		is_new_player = true
		new_game()
	else:
		_apply_loaded(loaded)
	_started = true
	if Cloud.is_enabled() and not is_new_player:
		Cloud.pull()


## Czy pokazac ekran powitalny. Nowy gracz widzi go zawsze, a ten, kto
## zalozyl farme przed jego dodaniem — raz, z przyciskiem "Graj dalej".
func should_show_intro() -> bool:
	return is_new_player or (state != null and not state.intro_seen)


## Zamyka sprawe ekranu powitalnego, zeby wiecej nie wyskakiwal.
func mark_intro_seen() -> void:
	is_new_player = false
	if state != null and not state.intro_seen:
		state.intro_seen = true
		save()


## Wstrzymuje gospodarstwo na czas ekranu powitalnego — inaczej kury
## zaczynaly by jesc i znosic, zanim gracz w ogole zobaczy wybieg.
func pause_simulation(paused: bool) -> void:
	set_process(not paused)
	if not paused:
		# Zegar scienny stal w miejscu, wiec zaczynamy liczyc od teraz.
		_last_tick = Time.get_unix_time_from_system()
		_away_seconds = 0.0


## Serwer odpowiedzial. Jesli ma nowszy zapis niz lokalny, bierzemy jego.
func _on_cloud_pulled(payload: Dictionary, ok: bool, for_player: String) -> void:
	# Odpowiedz na startowe pobranie moze przyjsc juz po tym, jak gracz
	# wpisal kod. Taka spozniona odpowiedz nie moze ani skasowac oczekiwania
	# na wlasciwa farme, ani podmienic stanu gry.
	if _force_pull and for_player != _restore_code:
		return
	var forced := _force_pull
	_force_pull = false
	_restore_code = ""
	if not ok or payload.is_empty():
		if forced:
			# Rozrozniamy dwa zupelnie rozne klopoty: serwer nie odpowiada
			# (brak sieci, brak tabeli, zly klucz) kontra serwer odpowiedzial,
			# ale farmy o takim kodzie u niego nie ma.
			Events.notice.emit(tr("HINT_CODE_NOT_FOUND") if ok else tr("HINT_SERVER_DOWN"))
		return
	var remote := SaveGame.from_dict(payload)
	if remote.is_empty():
		if forced:
			Events.notice.emit(tr("HINT_SAVE_BROKEN"))
		return
	var local_saved_at := 0.0
	var local := SaveGame.load_state()
	if not local.is_empty():
		local_saved_at = float(local["saved_at"])
	if not forced and float(remote["saved_at"]) <= local_saved_at:
		return
	_apply_loaded(remote)
	save()
	Events.notice.emit(tr("HINT_CODE_RESTORED") if forced else tr("HINT_CLOUD_LOADED"))


## Zaklada nowa farme: swiezy kod i stan poczatkowy. Wywolywane z ekranu
## powitalnego po wybraniu "Nowa farma".
func start_new_farm() -> void:
	is_new_player = false
	SaveGame.clear()
	Cloud.new_player_id()
	new_game()
	state.intro_seen = true
	save()


## Przejmuje farme spod kodu przepisanego z innego urzadzenia.
## Zwraca false, gdy kod jest niepoprawny albo serwer jest wylaczony.
func restore_from_code(raw_code: String) -> bool:
	if not Cloud.is_enabled():
		Events.notice.emit(tr("HINT_CLOUD_OFF"))
		return false
	var code := Cloud.normalize_code(raw_code)
	if code.is_empty():
		Events.notice.emit(tr("HINT_CODE_BAD"))
		return false
	if code == Cloud.player_id:
		Events.notice.emit(tr("HINT_CODE_SAME"))
		return false
	_force_pull = true
	_restore_code = code
	Cloud.set_player_id(code)
	Cloud.pull()
	Events.resources_changed.emit()
	return true


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
	# Dopoki czekamy na farme spod przepisanego kodu, nie wolno nic wyslac:
	# kod farmy jest juz przestawiony, wiec autozapis wrzucilby nasz lokalny
	# stan na cudze miejsce i skasowal farme, po ktora gracz wlasnie siegnal.
	if Cloud.is_enabled() and not _force_pull:
		Cloud.push(SaveGame.to_dict(state))


## Kasuje zapis i zaczyna od zera.
func reset() -> void:
	SaveGame.clear()
	new_game()
	save()


## Dolicza produkcje z czasu, ktorego petla gry nie policzyla: gra byla
## zamknieta albo karta wisiala w tle.
func _apply_elapsed(elapsed: float) -> void:
	var offline: Dictionary = GameData.balance().get("offline", {})
	var max_hours := float(offline.get("max_hours", 72.0))
	var real_seconds := clampf(elapsed, 0.0, max_hours * 3600.0)
	# Poza gra czas plynie wolniej, zeby noc nie zmieniala gospodarstwa nie do
	# poznania: stado nie pada z glodu, lis nie wynosi polowy kurnika, ale tez
	# nie ma co liczyc na kokosy z samego czekania.
	var divider := maxf(1.0, float(offline.get("speed_divider", 1.0)))
	var seconds := real_seconds / divider
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
	var pack := state.feed_pack()
	var price := float(pack["price"])
	if state.money < price:
		return false
	state.money -= price
	state.feed += float(pack["size"])
	_reported_no_feed = false
	Events.resources_changed.emit()
	return true


# --- handel kurami ------------------------------------------------------


## Kupuje kure podanej rasy. Rasa musi byc odblokowana.
## Kupuje jednego ptaka danej rasy. `rooster` decyduje o plci; cena jest ta sama,
## bo kogut je tyle samo i zajmuje tyle samo miejsca co kura.
func buy_hen(breed_id: String, rooster: bool = false) -> bool:
	var def := GameData.breed(breed_id)
	if def.is_empty() or not state.is_unlocked(breed_id):
		return false
	var price := float(def.get("price", 0))
	if state.money < price:
		return false
	if not state.coop_has_room():
		Events.notice.emit(tr("HINT_COOP_FULL") % state.coop_capacity())
		return false
	state.money -= price
	var hen := Chicken.create_rooster(breed_id) if rooster else Chicken.create(breed_id)
	state.chickens.append(hen)
	Events.hen_added.emit(hen)
	# Kura bez koguta swojej rasy nie zniesie ani jednego jajka. Lepiej
	# powiedziec to od razu, niz pozwolic graczowi myslec, ze gra jest zepsuta.
	if not rooster and not state.has_rooster(breed_id):
		Events.alert.emit(tr("ALERT_NO_ROOSTER_TITLE"),
				tr("ALERT_NO_ROOSTER_BODY") % tr(String(def.get("name", ""))))
	# Pierwsza sztuka danej rasy to wydarzenie: pokazujemy jej historie.
	if not state.has_ever_owned(breed_id):
		state.mark_owned(breed_id)
		Events.breed_unlocked.emit(breed_id)
	Events.resources_changed.emit()
	return true


## Sprzedaje jedna kure danej rasy. **Najpierw idzie chora** — i tak by padla,
## wiec pozbycie sie jej jest pierwszym, co gracz chce zrobic; skup placi za
## nia mniej. Zdrowe sztuki ida dopiero, gdy chorych nie ma.
## Zwraca uzyskana kwote albo 0, gdy nie ma czego sprzedac.
func sell_hen(breed_id: String, rooster: bool = false) -> float:
	var sick := true
	var index := _find_hen(breed_id, true, rooster)
	if index < 0:
		index = _find_hen(breed_id, false, rooster)
		sick = false
	if index < 0:
		return 0.0
	var price := FarmState.hen_sell_price(breed_id, sick)
	state.chickens.remove_at(index)
	state.money += price
	Events.hen_removed.emit(breed_id)
	Events.resources_changed.emit()
	# Sprzedany kogut moze byc ostatnim kogutem swojej rasy — wtedy cala
	# reszta tej rasy przestaje niesc i gracz musi o tym wiedziec.
	if rooster and state.hens_of_breed(breed_id) > 0 and not state.has_rooster(breed_id):
		Events.alert.emit(tr("ALERT_NO_ROOSTER_TITLE"),
				tr("ALERT_NO_ROOSTER_BODY") % tr(String(GameData.breed(breed_id).get("name", ""))))
	return price


## Czy kolejna sprzedaz tej rasy dotyczy chorej sztuki. UI pyta o to, zeby
## kwota na przycisku zgadzala sie z tym, co gracz faktycznie dostanie.
func next_sale_is_sick(breed_id: String, rooster: bool = false) -> bool:
	return _find_hen(breed_id, true, rooster) >= 0


## Indeks pierwszego ptaka danej rasy, plci i stanu zdrowia; -1, gdy nie ma.
func _find_hen(breed_id: String, sick: bool, rooster: bool = false) -> int:
	for i in state.chickens.size():
		var hen: Chicken = state.chickens[i]
		if hen.breed_id == breed_id and hen.sick == sick and hen.is_rooster == rooster:
			return i
	return -1


# --- weterynaria --------------------------------------------------------


func medicine_price() -> float:
	return float(GameData.balance().get("disease", {}).get("medicine_price", 140))


## Cena zaszczepienia calego stada. Jedna kwota za cale stado, niezaleznie od
## jego wielkosci: stawka od kury rosla razem ze stadem i w praktyce nikt tego
## nie kupowal. Stawka `vaccine_price_per_hen` zostaje w pliku balansu na wypadek
## powrotu do rozliczania od sztuki — teraz wynosi zero.
func vaccine_price() -> float:
	var disease: Dictionary = GameData.balance().get("disease", {})
	var base := float(disease.get("vaccine_price", 100))
	var per_hen := float(disease.get("vaccine_price_per_hen", 0))
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


## Przegania lisa, ktory wlasnie jest na wybiegu. Zwraca false, gdy nie ma
## kogo przeganiac — wtedy scena nie ma po co reagowac na dotkniecie.
func scare_fox() -> bool:
	if state.fox_visit_left <= 0.0:
		return false
	state.fox_visit_left = 0.0
	state.fox_pending = 0
	Events.fox_scared.emit()
	Events.notice.emit(tr("HINT_FOX_SCARED"))
	return true


# --- budynki ------------------------------------------------------------


## Kupuje kolejny poziom budynku ("coop", "storage", "guard").
func upgrade_building(building_id: String) -> bool:
	var upgrade := state.next_building_upgrade(building_id)
	if upgrade.is_empty():
		return false
	var price := float(upgrade.get("price", 0))
	if state.money < price:
		return false
	state.money -= price
	state.set_building_level(building_id, state.building_level(building_id) + 1)
	if building_id == "guard":
		# Nowy plot albo pies dziala od zaraz, a nie dopiero po nastepnej wizycie.
		state.reset_fox_timer()
	Events.resources_changed.emit()
	Events.notice.emit(tr("HINT_BUILDING_UPGRADED_%s" % building_id.to_upper()))
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
	if not state.coop_has_room():
		# Wstawic jaja mozna, ale warto uprzedzic, ze nie ma gdzie wypuscic.
		Events.notice.emit(tr("HINT_COOP_FULL") % state.coop_capacity())
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
