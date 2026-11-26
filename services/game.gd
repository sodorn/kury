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
## GAME OVER zgloszone dla obecnej fermy (raz, do restartu).
var _game_over_sent := false
## Test dymny wylacza GAME OVER poza wlasnym testem: grzebie w stanie gry
## (np. stado bez koguta i bez grosza) i pelnoekranowa plansza zaslonilaby
## reszte sprawdzen.
var game_over_enabled := true
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
	# Przejscie na inna karte albo inne okno to w przegladarce ostatni pewny
	# moment, w ktorym gra jeszcze dziala. Potem Chrome potrafi zamrozic
	# strone i nie zglosic juz niczego. Zapisujemy wiec od razu, zeby na
	# serwerze zawsze lezal stan z chwili odejscia od gry.
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
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
	_check_game_over()

	# Odliczanie do autozapisu idzie ZEGAREM SCIENNYM, nie delta klatki.
	# W karcie w tle przegladarka zwalnia petle gry kilkukrotnie, wiec przy
	# delcie "co osiem sekund" robilo sie co kilka minut.
	_autosave_left -= elapsed
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
	# Czas gry plynie `offline.scale` razy wolniej od zegara sciennego — tak
	# samo w grze i poza nia. Przeliczenie siedzi tutaj, zeby cala symulacja
	# dostawala juz sekundy gry i nie musiala o tym wiedziec.
	_report(Simulation.advance(state, pending * GameData.time_scale()))
	return false


## Zglasza do UI, co przyniosl ostatni krok symulacji.
func _report(result: Dictionary) -> void:
	# Ostrzezenie o braku paszy pokazujemy raz, przy przejsciu w glod,
	# a nie co klatke.
	var hungry := bool(result["out_of_feed"]) and not state.chickens.is_empty()
	if hungry and not _reported_no_feed:
		# Pusty magazyn zatrzymuje cale gospodarstwo: stado przestaje niesc,
		# inkubator i odchow staja, a po chwili zaczynaja padac kury. Na tyle
		# powazne, zeby przerwac gre okienkiem, a nie znikajacym paskiem.
		Events.alert.emit(tr("ALERT_NO_FEED_TITLE"), tr("ALERT_NO_FEED_BODY"))
	_reported_no_feed = hungry

	var laid := int(result["eggs_laid"])
	if laid > 0:
		Events.eggs_laid.emit(laid)
		Events.resources_changed.emit()
	if int(result["hatched"]) > 0 or int(result["grown_up"]) > 0:
		Events.resources_changed.emit()

	# Choroba (12.20): okienko tylko przy WYBUCHU ogniska. Kolejne zarazenia
	# co minute widac na wybiegu (zielona poswiata), wiec okienko co minute
	# byloby tylko zawalidroga.
	if int(result.get("outbreak", 0)) > 0:
		Events.alert.emit(tr("ALERT_SICK_TITLE"), tr("ALERT_SICK_BODY") % _breed_name(
				String(result.get("outbreak_breed", state.outbreak_breed))))
		Events.resources_changed.emit()
	if int(result.get("dog_died", 0)) > 0:
		Events.alert.emit(tr("ALERT_DOG_DIED_TITLE"), tr("ALERT_DOG_DIED_BODY") % _dog_name(
				int(result["dog_died"])))
	if int(result.get("outbreak_over", 0)) > 0:
		Events.notice.emit(tr("HINT_OUTBREAK_OVER") % [int(result.get("outbreak_dead", 0)),
				int(result.get("outbreak_saved", 0))])
		Events.resources_changed.emit()
	if int(result.get("fox_massacre", 0)) > 0:
		Events.notice.emit(tr("HINT_FOX_MASSACRE"))
	var died_disease := int(result["died_disease"])
	if died_disease > 0:
		Events.notice.emit(tr("HINT_DIED_DISEASE") % died_disease)
		Events.resources_changed.emit()
	var died_hunger := int(result["died_hunger"])
	if died_hunger > 0:
		Events.notice.emit(tr("HINT_DIED_HUNGER") % died_hunger)
		Events.resources_changed.emit()
	for id in result.get("built", []):
		_announce_built(String(id))
		Events.resources_changed.emit()
	if int(result.get("fox_lurking", 0)) > 0:
		Events.notice.emit(tr("HINT_FOX_LURKING"))
		Events.fox_lurking.emit(state.fox_lurk_left)
	# Zawrocony lis tez zasluguje na slowo — inaczej gracz nie widzi,
	# za co zaplacil za plot.
	if int(result["fox_blocked"]) > 0:
		Events.notice.emit(tr("HINT_FOX_BLOCKED"))
		Events.fox_repelled.emit()
	var arrived := int(result["fox_arrived"])
	if arrived > 0:
		Events.fox_arrived.emit(state.fox_kill_left, state.fox_visit_left)
		# Gracz ma wiedziec, ze pies pracuje — inaczej 200 zl wyglada
		# jak wyrzucone w bloto.
		Events.notice.emit(tr("HINT_FOX_HERE_DOG") if state.dog_level > 0 else tr("HINT_FOX_HERE"))
	var fox := int(result["fox_took"])
	if fox > 0:
		Events.fox_visited.emit(fox)
		Events.fox_victims.emit(result.get("fox_victims", []))
		Events.notice.emit(tr("HINT_FOX") % fox)
		Events.resources_changed.emit()
	_report_fox_end(result)


func _check_unlocks() -> void:
	pass


func _check_win() -> void:
	var reason := Simulation.check_win(state)
	if reason.is_empty():
		return
	Events.game_won.emit(reason)
	save()


## Bankructwo: brak pary do rozrodu i brak pieniedzy, zeby ja odtworzyc.
## Zgloszone raz; plansza GAME OVER ma tylko przycisk "od nowa".
func _check_game_over() -> void:
	if _game_over_sent or not game_over_enabled or not _started or state == null:
		return
	if not Simulation.check_bankrupt(state):
		return
	_game_over_sent = true
	Events.game_over.emit()


## Nowa ferma po bankructwie POD TYM SAMYM KODEM: wlasciciel zna swoj kod
## na pamiec, wiec zmiana kodu przy przegranej tylko by przeszkadzala.
func restart_after_game_over() -> void:
	SaveGame.clear()
	new_game()
	state.intro_seen = true
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


## Ekran powitalny pokazuje sie przy KAZDYM uruchomieniu gry. Wlasciciel
## poprosil o to wprost: przy testowaniu chce miec kod farmy pod reka bez
## szukania go w Kurniku. Dla gracza z farma pierwszym przyciskiem jest
## "Graj dalej", wiec jedno dotkniecie wraca do gry.
func should_show_intro() -> bool:
	# Wyjatek: strona przeladowala sie SAMA, bo przyszla nowa wersja gry.
	# Stan zostal zapisany sekunde wczesniej, wiec pytanie o kod tylko
	# wyrzucaloby gracza z gry w srodku zabawy.
	return not Updater.just_updated


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
	# 13.0: ferma admina 000000 do testow - gdy jej jeszcze nie ma na
	# serwerze, zakladamy ja pod tym kodem zamiast zglaszac "nie ma farmy".
	if forced and ok and payload.is_empty() and for_player == ADMIN_CODE:
		SaveGame.clear()
		Cloud.set_player_id(ADMIN_CODE)
		_owned_code = ADMIN_CODE
		new_game()
		state.intro_seen = true
		save()
		Events.resources_changed.emit()
		Events.notice.emit(tr("HINT_ADMIN_FARM"))
		return
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
	# Serwer oddal farme — dopiero teraz urzadzenie przyjmuje jej kod.
	if forced:
		Cloud.set_player_id(for_player)
		_owned_code = for_player
	var local_saved_at := 0.0
	var local := SaveGame.load_state()
	if not local.is_empty():
		local_saved_at = float(local["saved_at"])
	if not forced and float(remote["saved_at"]) <= local_saved_at:
		return
	_apply_loaded(remote)
	save()
	Events.notice.emit(tr("HINT_CODE_RESTORED") if forced else tr("HINT_CLOUD_LOADED"))


# --- ferma admina (13.0) -------------------------------------------------

## Kod fermy do testow (wlasciciel 26.11). Ma dodatkowe przyciski: poziom
## budynku w gore/dol za darmo, +1000 zl, lis, smierc psa, zaraza.
const ADMIN_CODE := "000000"


func is_admin() -> bool:
	return Cloud.player_id == ADMIN_CODE


func admin_add_money(amount: float = 1000.0) -> void:
	if not is_admin():
		return
	state.money += amount
	Events.resources_changed.emit()
	save()


## Poziom budynku od razu i za darmo; `delta` +1 albo -1. Przerywa budowe.
func admin_change_level(building_id: String, delta: int) -> bool:
	if not is_admin():
		return false
	var level := state.building_level(building_id)
	var top := level + 1 if not state.next_building_upgrade(building_id).is_empty() else level
	var target := clampi(level + delta, 0, top)
	if target == level:
		return false
	state.construction.erase(building_id)
	state.set_building_level(building_id, target)
	Events.resources_changed.emit()
	save()
	return true


## Lis od razu wychodzi z krzakow (a dalej jak zwykle: plot, pies, palec).
func admin_call_fox() -> void:
	if not is_admin() or state.fox_visit_left > 0.0:
		return
	state.fox_lurk_left = maxf(1.0, state.fox_lurk_seconds())
	Events.resources_changed.emit()


func admin_kill_dog() -> void:
	if not is_admin() or state.dog_level <= 0:
		return
	state.dog_age = state.dog_life
	_report(Simulation.advance(state, 1.0))
	Events.resources_changed.emit()


func admin_outbreak() -> void:
	if not is_admin() or state.outbreak_on:
		return
	var out := {"died_disease": 0, "log": []}
	Simulation._start_outbreak(state, out, 1 << 30)
	if int(out.get("outbreak", 0)) > 0:
		Events.alert.emit(tr("ALERT_SICK_TITLE"), tr("ALERT_SICK_BODY") % _breed_name(state.outbreak_breed))
	Events.resources_changed.emit()


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
	# Kod rowny obecnemu NIE jest powodem do odmowy. Po nieudanej probie
	# wczytania gra zostaje juz z tym kodem (ustawiamy go ponizej, zanim
	# serwer odpowie), wiec druga proba trafiala na "nie ma czego
	# wczytywac" i nie robila nic. Gracz nie mial jak sprobowac ponownie
	# po chwilowym braku sieci. Teraz pobieramy zawsze, tylko uprzedzamy,
	# ze to ten sam kod.
	if code == Cloud.player_id:
		Events.notice.emit(tr("HINT_CODE_SAME"))
	_force_pull = true
	_restore_code = code
	# Tozsamosci urzadzenia NIE zmieniamy tutaj. Dopiero gdy serwer odda
	# farme, przejmujemy jej kod — patrz `_on_cloud_pulled`. Wczesniej kod
	# szedl od razu i nieudane pobranie zostawialo urzadzenie z cudzym
	# kodem; najblizszy autozapis wrzucal pod niego lokalna, pusta farme
	# i kasowal prawdziwa. Wlasciciel stracil tak dwie.
	Cloud.pull_for(code)
	Events.resources_changed.emit()
	return true


## Furtka dla testow: wczytuje gotowy slownik tak samo jak zwykle wczytanie
## zapisu, zeby dalo sie sprawdzic zachowanie po roznej dlugosci przerwy.
func apply_loaded_for_test(loaded: Dictionary) -> void:
	is_new_player = false
	_apply_loaded(loaded)


func _apply_loaded(loaded: Dictionary) -> void:
	state = loaded["state"]
	_reported_no_feed = false
	_shown_feed = -1
	_away_seconds = 0.0
	_last_tick = Time.get_unix_time_from_system()
	# Zapis z dysku nalezy do tego urzadzenia, wiec wolno pod ten kod pisac.
	if _owned_code.is_empty():
		_owned_code = Cloud.player_id
	_last_gap = maxf(0.0, float(loaded["elapsed"]))
	_apply_elapsed(_last_gap)
	Events.resources_changed.emit()


## Ile sekund realnych minelo od ostatniego zapisu do wlaczenia gry. Na tej
## podstawie ekran powitalny decyduje, czy wymagac wpisania kodu.
var _last_gap := 0.0
## Kod, do ktorego ta sesja ma prawo pisac. Ustawiamy go w trzech miejscach:
## przy zalozeniu nowej farmy, przy wczytaniu wlasnego zapisu z dysku i po
## UDANYM pobraniu farmy z serwera. Push do innego kodu jest odrzucany.
##
## To jest siatka bezpieczenstwa po bledzie, ktory skasowal wlascicielowi
## dwie farmy: gra przestawiala tozsamosc urzadzenia przed odpowiedzia
## serwera i autozapis wrzucal pusta farme pod cudzy kod.
var _owned_code := ""


## Czy po tej przerwie gracz musi wpisac kod, zamiast klikac "Graj dalej".
## Wlasciciel poprosil o to wprost: chce testowac wczytywanie i przeskakiwac
## miedzy farmami bez czyszczenia ciasteczek. Zero w balansie wylacza wymog.
func must_enter_code() -> bool:
	if is_new_player or not Cloud.is_enabled():
		return false
	var session: Dictionary = GameData.balance().get("session", {})
	if not bool(session.get("require_code", false)):
		return false
	# Zero znaczy ZAWSZE. Liczba wieksza od zera — dopiero po takiej przerwie.
	var minutes := float(session.get("require_code_after_minutes", 0.0))
	return minutes <= 0.0 or _last_gap >= minutes * 60.0


## Ostrzezenie o braku koguta pokazujemy najwyzej ROOSTER_HINTS razy na rase.
## Wlasciciel slusznie zglosil, ze przy kazdym zakupie to juz tylko
## przeszkadza — raz zrozumiana zasada nie wymaga powtarzania w kolko.
const ROOSTER_HINTS := 3


func _warn_no_rooster(breed_id: String, breed_name: String) -> void:
	var shown := int(state.rooster_hints.get(breed_id, 0))
	if shown >= ROOSTER_HINTS:
		return
	state.rooster_hints[breed_id] = shown + 1
	Events.alert.emit(tr("ALERT_NO_ROOSTER_TITLE"),
			tr("ALERT_NO_ROOSTER_BODY") % tr(breed_name))


func new_game() -> void:
	_game_over_sent = false
	_last_gap = 0.0
	_reported_no_feed = false
	_shown_feed = -1
	_away_seconds = 0.0
	_last_tick = Time.get_unix_time_from_system()
	state = FarmState.from_start_config(GameData.balance().get("start", {}))
	_owned_code = Cloud.player_id
	Events.resources_changed.emit()


func save() -> void:
	if state == null:
		return
	# `_away_seconds` to czas uzbierany przy nieaktywnym oknie, jeszcze
	# nierozliczony. Musi pojechac razem z zapisem, inaczej kolejny
	# autozapis skasuje go na zawsze — tak przepadla wlascicielowi cala noc.
	SaveGame.save_state(state, SaveGame.PATH, _away_seconds)
	if Cloud.is_enabled() and may_push_to_cloud():
		Cloud.push(SaveGame.to_dict(state, _away_seconds))


## Czy wolno wyslac biezacy stan na serwer. Trzy bezpieczniki, kazdy po
## przejsciach:
##
## 1. Czekamy na farme spod przepisanego kodu — nic nie wysylamy, bo
##    wysylka trafilaby w miejsce farmy, po ktora gracz wlasnie siegnal.
## 2. Kod, pod ktorym jestesmy, nie nalezy do tej sesji. Tak wlasnie
##    ginely farmy wlasciciela: tozsamosc urzadzenia zmieniala sie przed
##    odpowiedzia serwera i autozapis nadpisywal cudzy zapis.
## 3. Stan jest pusty. Pusta farma nie jest warta wyslania NIGDY — a gdyby
##    cos znowu przestawilo kod, to wlasnie pustka skasowalaby komus stado.
##    Lepiej nie zapisac nic, niz zapisac nic NA CZYMS.
## 4. Gracz nie potwierdzil jeszcze, ze chce TE farme. Po wyczyszczeniu
##    ciasteczek gra zaklada swieza farme, zanim pokaze ekran powitalny.
##    Taka farma nie moze trafic na serwer, dopoki gracz nie wybierze
##    "Nowa farma" albo nie przepisze kodu — inaczej samo otwarcie gry
##    po czyszczeniu ciasteczek zasmieca baze startowymi farmami
##    (w tabeli lezy ich kilka: 131090, 187265, 367990 — wszystkie
##    4 kury i 150 zl, nikt nimi nigdy nie gral).
func may_push_to_cloud() -> bool:
	if _force_pull:
		return false
	if _owned_code.is_empty() or _owned_code != Cloud.player_id:
		return false
	if state != null and not state.intro_seen:
		return false
	return not is_farm_empty()


## Farma bez jednej kury, bez jaj i bez niczego w inkubatorze. Taki stan
## powstaje tylko po wczytaniu pustki albo po calkowitej klesce.
func is_farm_empty() -> bool:
	return state != null \
			and state.chickens.is_empty() \
			and state.corpses.is_empty() \
			and state.incubating.is_empty() \
			and state.chicks.is_empty() \
			and state.egg_count() == 0


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
	# Czas poza gra liczy sie dokladnie tak samo jak w grze. Dawny dzielnik 60
	# zniknal: wlasciciel chcial jednej skali na wszystko.
	var seconds := real_seconds * GameData.time_scale()
	if seconds < 1.0:
		return
	var flock_before := state.hen_count()
	var result := Simulation.advance(state, seconds, true)
	_check_unlocks()
	_check_win()
	_check_game_over()
	for id in result.get("built", []):
		_announce_built(String(id))
	# Dluga przerwa (np. noc): zamiast dymkow KRONIKA FERMY z godzinami.
	var report_hours := float(offline.get("report_hours", 3.0))
	if real_seconds >= report_hours * 3600.0:
		last_away_report = build_away_report(result, real_seconds, flock_before)
		Events.away_report.emit(last_away_report)
	else:
		var laid := int(result["eggs_laid"])
		if laid > 0:
			Events.notice.emit(tr("HINT_WELCOME_BACK") % laid)
		var lost := int(result["died_hunger"]) + int(result["died_disease"]) + int(result["fox_took"])
		if lost > 0:
			Events.notice.emit(tr("HINT_LOST_WHILE_AWAY") % lost)
	# Lis w tle rozgrywa sie od razu i znika (12.21) - nie czeka na gracza.
	# Zostaje tylko sprzatanie sceny, gdy w trakcie przerwy skonczyla sie
	# wizyta rozpoczeta jeszcze przy graczu.
	_report_fox_end(result)


## Ostatnia kronika fermy (dla panelu, ktory czeka, az zniknie ekran startowy).
var last_away_report: Dictionary = {}


## Sklada kronike fermy z podsumowania nadrabiania. `real_seconds` to dlugosc
## przerwy, `flock_before` - stado przed nia. Wpisy dziennika dostaja godzine
## zegarka ("02:14").
func build_away_report(result: Dictionary, real_seconds: float, flock_before: int) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var start := now - real_seconds
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var log_lines: Array = []
	for entry: Dictionary in result.get("log", []):
		var clock := Time.get_datetime_dict_from_unix_time(int(start + float(entry["t"])) + bias)
		log_lines.append([float(entry["t"]), "%02d:%02d" % [clock["hour"], clock["minute"]],
				_log_text(entry)])
	var fox_in := 0
	var massacre := false
	for entry: Dictionary in result.get("log", []):
		if entry["kind"] == "fox":
			fox_in += 1
			massacre = massacre or bool(entry.get("massacre", false))
	var cocks := 0
	for bird: Chicken in state.chickens:
		if bird.is_rooster:
			cocks += 1
	return {
		"away": real_seconds,
		"eggs_laid": int(result["eggs_laid"]),
		"eggs_lost": int(result.get("eggs_lost", 0)),
		"eggs_spoiled": int(result.get("eggs_spoiled", 0)),
		"hatched": int(result["hatched"]),
		"grown_up": int(result["grown_up"]),
		"fox_blocked": int(result["fox_blocked"]),
		"fox_in": fox_in,
		"fox_took": int(result["fox_took"]),
		"fox_chased": int(result.get("fox_chased", 0)),
		"fox_killed": int(result.get("fox_killed", 0)),
		"fox_massacre": massacre,
		"outbreaks": int(result.get("outbreaks", 0)),
		"got_sick": int(result["got_sick"]),
		"died_disease": int(result["died_disease"]),
		"died_hunger": int(result["died_hunger"]),
		"out_of_feed": bool(result["out_of_feed"]),
		"built": result.get("built", []).duplicate(),
		"flock_before": flock_before,
		"hens": state.chickens.size() - cocks,
		"roosters": cocks,
		"log": log_lines,
	}


func _log_text(entry: Dictionary) -> String:
	match String(entry["kind"]):
		"fox_blocked":
			return tr("LOG_FOX_BLOCKED")
		"fox":
			var text := tr("LOG_FOX_MASSACRE" if bool(entry.get("massacre", false)) else "LOG_FOX") \
					% int(entry.get("taken", 0))
			match String(entry.get("dog", "")):
				"chased":
					text += tr("LOG_FOX_DOG_CHASED")
				"killed":
					text += tr("LOG_FOX_DOG_KILLED")
			return text
		"outbreak":
			return tr("LOG_OUTBREAK") % [_breed_name(String(entry.get("breed", ""))),
					int(entry.get("target", 0))]
		"outbreak_over":
			return tr("LOG_OUTBREAK_OVER") % [int(entry.get("dead", 0)), int(entry.get("saved", 0))]
		"storage_full":
			return tr("LOG_STORAGE_FULL")
		"no_feed":
			return tr("LOG_NO_FEED")
		"built":
			return tr("LOG_BUILT") % building_title(String(entry.get("id", "")))
		"dog_died":
			return tr("LOG_DOG_DIED") % _dog_name(int(entry.get("level", 1)))
	return String(entry["kind"])


## "Magazyn: mała szopka" - nazwa budynku z nazwa jego poziomu.
func building_title(building_id: String) -> String:
	var cfg: Dictionary = GameData.balance().get("incubator", {}) if building_id == "incubator" \
			else GameData.balance().get("buildings", {}).get(building_id, {})
	var level := state.building_level(building_id)
	var level_name := String(cfg.get("name", ""))
	var ups: Array = cfg.get("upgrades", [])
	if level > 0 and not ups.is_empty():
		level_name = String((ups[mini(level, ups.size()) - 1] as Dictionary).get("name", ""))
	return "%s: %s" % [tr("BUILDING_%s_NAME" % building_id.to_upper()), tr(level_name)]


## Koniec wizyty lisa. WAZNE: scena lisa sama pilnuje tylko wlasnego zegara,
## wiec gdy symulacja skroci wizyte (pies!), trzeba jej o tym powiedziec —
## inaczej zabity albo wygoniony lis dalej siedzi na wybiegu. Na tym samym
## bledzie gra juz raz sie wylozyla przy trzech niesmiertelnych lisach.
func _report_fox_end(result: Dictionary) -> void:
	if int(result.get("fox_killed", 0)) > 0:
		Events.notice.emit(tr("HINT_FOX_KILLED"))
		Events.fox_killed.emit()
	elif int(result.get("fox_chased", 0)) > 0:
		Events.notice.emit(tr("HINT_FOX_CHASED"))
		Events.fox_chased.emit()
	elif int(result.get("fox_left", 0)) > 0:
		Events.fox_left.emit()


# --- jaja ---------------------------------------------------------------


## Zbiera z wybiegu jedno jajko danej rasy. Zwraca false, jesli go tam nie ma.
func collect_egg_of_breed(breed_id: String) -> bool:
	var index := state.eggs_on_ground.find(breed_id)
	if index < 0:
		return false
	if state.egg_room() <= 0:
		Events.notice.emit(tr("PANEL_EGGS_FULL") % NumberFormat.grouped(state.egg_capacity()))
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
## Sprzedaje jaja. `count` > 0 = tylko tyle sztuk, najstarsze najpierw
## (przycisk w sklepie sprzedaje partiami - economy.egg_sale_lot). Bez
## argumentu - wszystkie. Zwraca zarobek.
func sell_eggs(count: int = 0) -> float:
	if count <= 0:
		var earned_all := state.eggs_value()
		if earned_all <= 0.0:
			return 0.0
		state.money += earned_all
		state.eggs.clear()
		state.egg_ages.clear()
		Events.resources_changed.emit()
		return earned_all
	var lot := state.oldest_eggs(count)
	var earned := 0.0
	for breed_id: String in lot:
		var taken := state.take_eggs(breed_id, int(lot[breed_id]))
		earned += taken * FarmState.egg_value(breed_id)
	if earned <= 0.0:
		return 0.0
	state.money += earned
	Events.resources_changed.emit()
	return earned



## Ile jaj idzie w jednej partii sprzedazy.
func egg_sale_lot() -> int:
	return maxi(1, int(GameData.balance().get("economy", {}).get("egg_sale_lot", 100)))


# --- pasza --------------------------------------------------------------


## Kupuje `packs` workow paszy naraz (wszystkie albo zaden). Zwraca false
## przy braku pieniedzy. Od 12.18 kura je tyle, co prawdziwa nioska na
## jajo, wiec przy wiekszym stadzie jeden worek znika w dwie minuty -
## stad przycisk "kup 10 workow".
## `option` = ktory przycisk paszy (0 worek, 1 big-bag), `packs` = ile sztuk.
func buy_feed(option: int = 0, packs: int = 1) -> bool:
	var pack := state.feed_pack(option)
	packs = maxi(1, packs)
	var price := float(pack["price"]) * packs
	if state.money < price:
		return false
	state.money -= price
	state.feed += float(pack["size"]) * packs
	_reported_no_feed = false
	Events.resources_changed.emit()
	return true


# --- handel kurami ------------------------------------------------------


## Kupuje kure podanej rasy. Rasa musi byc odblokowana.
## Kupuje jednego ptaka danej rasy. `rooster` decyduje o plci; cena jest ta sama,
## bo kogut je tyle samo i zajmuje tyle samo miejsca co kura.
## Czy kurnik jest juz dosc duzy na te rase.
func breed_allowed(breed_id: String) -> bool:
	return state.coop_level >= int(GameData.breed(breed_id).get("coop_level", 0))


## Poziom kurnika (liczony od 1, jak w panelu), od ktorego rasa jest dostepna.
func breed_required_level(breed_id: String) -> int:
	return int(GameData.breed(breed_id).get("coop_level", 0)) + 1


func buy_hen(breed_id: String, rooster: bool = false) -> bool:
	var def := GameData.breed(breed_id)
	if def.is_empty() or not state.is_unlocked(breed_id):
		return false
	# Drozsza rasa wymaga wiekszego kurnika: cemani nie wstawisz do szopy
	# na dwadziescia sztuk. Daje to drabince rozbudowy drugi sens poza
	# samym miejscem.
	if not breed_allowed(breed_id):
		Events.notice.emit(tr("HINT_BREED_NEEDS_COOP") % [
				tr(String(def.get("name", ""))), int(def.get("coop_level", 0)) + 1])
		return false
	var price := FarmState.hen_buy_price(breed_id, rooster)
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
		_warn_no_rooster(breed_id, String(def.get("name", "")))
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
## Sprzedaje jednego ZDROWEGO ptaka. Chorej sztuki skup nie przyjmuje —
## chora idzie tylko do McDonalda (`cull_hen`).
func sell_hen(breed_id: String, rooster: bool = false) -> float:
	var index := _find_hen(breed_id, false, rooster)
	if index < 0:
		return 0.0
	var price := FarmState.hen_sell_price(breed_id, false, rooster)
	state.chickens.remove_at(index)
	state.money += price
	Events.hen_removed.emit(breed_id)
	Events.resources_changed.emit()
	# Sprzedany kogut moze byc ostatnim kogutem swojej rasy — wtedy cala
	# reszta tej rasy przestaje niesc i gracz musi o tym wiedziec.
	if rooster and state.hens_of_breed(breed_id) > 0 and not state.has_rooster(breed_id):
		_warn_no_rooster(breed_id, String(GameData.breed(breed_id).get("name", "")))
	return price


## Ubija jednego chorego ptaka danej rasy. Za darmo i bez zaplaty — to wyjscie
## awaryjne dla kogos, kogo nie stac na lek, a chora kura blokuje miejsce
## w kurniku i i tak za chwile padnie.
## Chora sztuka idzie do skupu — tanio, bo chora, ale lepiej to niz nic.
## Wczesniej byl darmowy ubic; wlasciciel wolal, zeby cos z tego bylo.
func mcdonalds_price() -> float:
	return float(GameData.balance().get("disease", {}).get("mcdonalds_price", 5))


func cull_hen(breed_id: String, rooster: bool = false) -> bool:
	var index := _find_hen(breed_id, true, rooster)
	if index < 0:
		return false
	state.chickens.remove_at(index)
	state.money += mcdonalds_price()
	# Do bilansu ogniska: chora poszla do McDonalda zamiast pasc, ale dla
	# gracza to ta sama strata.
	if state.outbreak_on:
		state.outbreak_dead += 1
	Events.hen_removed.emit(breed_id)
	Events.resources_changed.emit()
	if rooster and state.hens_of_breed(breed_id) > 0 and not state.has_rooster(breed_id):
		_warn_no_rooster(breed_id, String(GameData.breed(breed_id).get("name", "")))
	save()
	return true


## Czy w stadzie jest chora sztuka danej rasy i plci. UI pyta o to, zeby
## pokazac przycisk uboju zamiast sprzedazy.
func has_sick(breed_id: String, rooster: bool = false) -> bool:
	return _find_hen(breed_id, true, rooster) >= 0


## Indeks pierwszego ptaka danej rasy, plci i stanu zdrowia; -1, gdy nie ma.
func _find_hen(breed_id: String, sick: bool, rooster: bool = false) -> int:
	for i in state.chickens.size():
		var hen: Chicken = state.chickens[i]
		if hen.breed_id == breed_id and hen.sick == sick and hen.is_rooster == rooster:
			return i
	return -1


# --- weterynaria --------------------------------------------------------


## Cena zaszczepienia calego stada: stala `vaccine_price` (teraz 0) plus
## `vaccine_price_per_hen` za kazdego niezaszczepionego ptaka (wlasciciel:
## "5 zl za sztuke"). Zaszczepionych nie liczymy drugi raz.
func vaccine_price() -> float:
	var disease: Dictionary = GameData.balance().get("disease", {})
	var base := float(disease.get("vaccine_price", 100))
	var per_hen := float(disease.get("vaccine_price_per_hen", 0))
	return base + per_hen * state.unvaccinated_count()


## Szczepi cale ZDROWE stado. Chroni do konca zycia, ale tylko kury, ktore
## zyja teraz — mlode wyklute pozniej trzeba zaszczepic osobno. Od 12.20
## szczepionka nie leczy (wlasciciel 25.11): chore zostaja chore i sie za nie
## nie placi. Leku nie ma wcale.
func buy_vaccine() -> bool:
	if state.unvaccinated_count() == 0:
		return false
	var price := vaccine_price()
	if state.money < price:
		return false
	state.money -= price
	var count := 0
	for hen: Chicken in state.chickens:
		if hen.vaccinated or hen.sick:
			continue
		hen.vaccinated = true
		count += 1
	Events.resources_changed.emit()
	Events.notice.emit(tr("HINT_VACCINATED") % count)
	return true


## Przegania lisa, ktory wlasnie jest na wybiegu. Zwraca false, gdy nie ma
## kogo przeganiac — wtedy scena nie ma po co reagowac na dotkniecie.
## Jedno trafienie palcem w lisa. Zwraca true dopiero wtedy, gdy to trafienie
## go przegonilo — wczesniej lis tylko odskakuje w inne miejsce.
func poke_fox() -> bool:
	if state.fox_visit_left <= 0.0:
		return false
	state.fox_taps_left -= 1
	if state.fox_taps_left > 0:
		return false
	# Przegoniony golymi rekami wraca szybciej, chyba ze gospodarstwo ma psa
	# albo plot.
	state.fox_hand_scared = true
	Simulation.fox_leaves(state)
	Events.fox_scared.emit()
	Events.notice.emit(tr("HINT_FOX_SCARED"))
	return true


## Ile jeszcze trafien dzieli gracza od przegonienia lisa.
func fox_taps_left() -> int:
	return maxi(0, state.fox_taps_left)


# --- budynki ------------------------------------------------------------


## Kupuje kolejny poziom budynku ("coop", "storage", "incubator", "guard",
## "dog"). Kurnik, magazyn i inkubator sie BUDUJA (build_minutes w
## balance.json, czas realny) - placisz od razu, nowy poziom wchodzi po
## skonczeniu budowy. Plot i pies sa od razu. W trakcie budowy nie da sie
## zamowic kolejnego poziomu tego samego budynku.
func upgrade_building(building_id: String) -> bool:
	if state.is_building(building_id):
		return false
	if not upgrade_block_reason(building_id).is_empty():
		return false
	var upgrade := state.upgrade_entry(building_id)
	if upgrade.is_empty():
		return false
	var price := float(upgrade.get("price", 0))
	if state.money < price:
		return false
	state.money -= price
	var seconds := state.build_seconds(building_id)
	if seconds > 0.0:
		state.construction[building_id] = [seconds, seconds]
		Events.resources_changed.emit()
		Events.notice.emit(tr("HINT_BUILD_STARTED") % [tr(String(upgrade.get("name", ""))),
				NumberFormat.duration(seconds)])
		save()
		return true
	state.set_building_level(building_id, state.building_level(building_id) + 1)
	Events.resources_changed.emit()
	_announce_built(building_id)
	return true


## Dlaczego rozbudowy nie wolno zaczac (pusty tekst = wolno). 13.0
## (wlasciciel 26.11): inkubatora nie rozbudowuje sie, gdy cos sie w nim
## wykluwa - najpierw trzeba poczekac na pisklęta.
func upgrade_block_reason(building_id: String) -> String:
	if building_id == "incubator" and not state.incubating.is_empty():
		return tr("PANEL_INCUBATOR_BUSY")
	return ""


## Komunikat po skonczonej rozbudowie.
func _announce_built(building_id: String) -> void:
	if building_id == "incubator":
		Events.notice.emit(tr("HINT_INCUBATOR_UPGRADED") % state.incubator_slots())
	else:
		Events.notice.emit(tr("HINT_BUILDING_UPGRADED_%s" % building_id.to_upper()))


# --- inkubator ----------------------------------------------------------


func incubator_slots() -> int:
	return state.incubator_slots()


func eggs_per_chick() -> int:
	return int(GameData.balance().get("incubator", {}).get("eggs_per_chick", 6))


## Czy da sie wstawic jaja danej rasy do inkubatora. Potrzebne sa jaja
## wlasnie tej rasy — z jaj leghorna nie wyklu je sie cemani.
## Wylegu nie wolno zaczynac, gdy pisklę nie bedzie mialo gdzie wyjsc.
## Liczymy razem doroslego ptaka, jajo w inkubatorze i pisklę na odchowie —
## inaczej dalo sie nabic kolejke, ktora stoi i czeka bez slowa wyjasnienia.
## Posiadanie dorosłej sztuki tej rasy NIE jest wymagane: jaja, ktore juz
## leza w magazynie, nalezą do gracza i wolno je wylec nawet po sprzedaniu
## calego stada tej rasy. Wczesniej taka sprzedaz wyszarzala przycisk bez
## zadnego wyjasnienia (zglosili to koledzy Tomka).
func can_incubate(breed_id: String) -> bool:
	# 13.0: w trakcie rozbudowy inkubatora nie wklada sie jaj.
	return not state.is_building("incubator") \
			and state.incubating.size() < incubator_slots() \
			and state.coop_free() > 0 \
			and int(state.eggs.get(breed_id, 0)) >= eggs_per_chick()


## Czy wyleg blokuje wylacznie brak miejsca w kurniku. UI pyta o to, zeby
## napisac na wyszarzonym przycisku, czego naprawde brakuje.
func incubation_blocked_by_coop(breed_id: String) -> bool:
	return state.coop_free() <= 0 \
			and state.incubating.size() < incubator_slots() \
			and int(state.eggs.get(breed_id, 0)) >= eggs_per_chick()


func incubate(breed_id: String) -> bool:
	if not can_incubate(breed_id):
		if incubation_blocked_by_coop(breed_id):
			Events.alert.emit(tr("ALERT_COOP_FULL_TITLE"),
					tr("ALERT_COOP_FULL_BODY") % [state.coop_capacity(),
							state.coop_occupied(), state.coop_reserved()])
		return false
	state.take_eggs(breed_id, eggs_per_chick())
	state.incubating.append(EggBatch.create(breed_id, 1))
	Events.resources_changed.emit()
	return true


## Rozbudowuje inkubator o kolejny poziom z balance.json (z czasem budowy).
func upgrade_incubator() -> bool:
	return upgrade_building("incubator")


## Nazwa psa danego poziomu z data/rozbudowy.json.
func _dog_name(level: int) -> String:
	var ups: Array = GameData.balance().get("buildings", {}).get("dog", {}).get("upgrades", [])
	if ups.is_empty() or level <= 0:
		return ""
	return String((ups[mini(level, ups.size()) - 1] as Dictionary).get("name", ""))


## Nazwa rasy po polsku do komunikatow ("Leghorn"); pusty id -> "?".
func _breed_name(breed_id: String) -> String:
	var def := GameData.breed(breed_id)
	return tr(String(def.get("name", ""))) if not def.is_empty() else "?"
