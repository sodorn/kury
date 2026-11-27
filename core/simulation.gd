class_name Simulation
extends RefCounted
## Postep gospodarstwa w czasie.
##
## Cala logika uplywu czasu siedzi w jednej funkcji `advance`. Uzywa jej tick
## na zywo i nadrabianie czasu, kiedy gra byla zamknieta. Dzieki temu gra
## off-line liczy sie dokladnie tak samo jak na ekranie.

## Dlugosc kroku calkowania przy grze na zywo.
const STEP := 1.0
## Przy nadrabianiu wielu godzin krok rosnie, zeby nie liczyc po sekundzie
## kilkudziesieciu tysiecy razy. Czasy w grze sa dluzsze od 40 s, wiec blad
## calkowania jest pomijalny.
const MAX_STEP := 10.0


## Przesuwa stan o `delta` sekund. Zwraca podsumowanie tego, co sie wydarzylo.
## `offline` wlacza bezpiecznik, ktory ogranicza straty z glodu.
## `offline` ma dwa skutki: wlacza bezpiecznik strat i kieruje zniesione jaja
## prosto do magazynu zamiast na wybieg. Bez tego nadrabianie czasu nie mialoby
## sensu — wybieg miesci `run.max_eggs_on_ground` jaj, wiec po kilkunastu
## minutach nieobecnosci kury przestawalyby niesc i caly nocny urobek
## przepadalby. Zbieranie jaj palcem zostaje dla gry na zywo.
static func advance(state: FarmState, delta: float, offline: bool = false) -> Dictionary:
	var summary := {
		"eggs_laid": 0,
		"hatched": 0,
		"grown_up": 0,
		"days_passed": 0,
		"out_of_feed": false,
		"died_hunger": 0,
		"died_disease": 0,
		"got_sick": 0,
		"fox_took": 0,
		"fox_arrived": 0,
		"fox_blocked": 0,
		"fox_lurking": 0,
		"fox_left": 0,
		"fox_victims": [],
		"built": [],
		"rotted": 0,
		# Dziennik zdarzen do raportu po powrocie (12.21): lista slownikow
		# {"t": sekundy ZEGARA od poczatku tego advance, "kind": ..., ...}.
		"log": [],
		"_t": 0.0,
	}
	var remaining := maxf(delta, 0.0)
	var step_size := STEP if remaining <= 600.0 else clampf(remaining / 600.0, STEP, MAX_STEP)
	# Przy nadrabianiu czasu stado nie moze wyginac do zera: powrot do gry po
	# dobie nie moze oznaczac pustego wybiegu. Limit obejmuje glod, choroby
	# i lisa razem, bo kazde z nich potrafi samo wyciac cale stado.
	var loss_budget := 1 << 30
	if offline:
		var share := float(GameData.balance().get("hunger", {}).get("offline_max_share", 0.5))
		loss_budget = int(floor(state.hen_count() * clampf(share, 0.0, 1.0)))
	var done := 0.0
	var scale := maxf(0.0001, GameData.time_scale())
	# Nadrabiany odcinek konczy sie TERAZ - stad zegar poczatku (do nocy).
	_clock_start = Time.get_unix_time_from_system() - remaining / scale
	while remaining > 0.0:
		var step := minf(remaining, step_size)
		summary["_t"] = done / scale
		_step(state, step, summary, loss_budget, offline)
		remaining -= step
		done += step
	return summary


## Wpis do dziennika zdarzen. Czas to sekundy ZEGARA od poczatku `advance`;
## Game przelicza je na godzine na zegarku gracza.
## 13.0: pies sie starzeje (czas ZEGARA) i po wylosowanej liczbie dni umiera.
static func _advance_dog(state: FarmState, real: float, out: Dictionary) -> void:
	if state.dog_level <= 0:
		return
	if state.dog_life <= 0.0:
		state.roll_dog_life()
	state.dog_age += real
	if state.dog_age < state.dog_life:
		return
	var level := state.dog_level
	state.dog_level = 0
	state.dog_age = 0.0
	state.dog_life = 0.0
	out["dog_died"] = level
	_log(out, "dog_died", {"level": level})


static func _log(out: Dictionary, kind: String, data: Dictionary = {}) -> void:
	var entry := data.duplicate()
	entry["t"] = float(out.get("_t", 0.0))
	entry["kind"] = kind
	if not out.has("log"):
		out["log"] = []
	(out["log"] as Array).append(entry)


## Ile kur ubylo ze stada od poczatku tego wywolania `advance`.
static func _losses(out: Dictionary) -> int:
	return int(out["died_hunger"]) + int(out["died_disease"]) + int(out["fox_took"])


## Czas UNIX poczatku biezacego `advance` (koniec = teraz) - do nocy.
static var _clock_start := 0.0


static func _step(state: FarmState, step: float, out: Dictionary, loss_budget: int,
		offline: bool = false) -> void:
	out["days_passed"] = int(out["days_passed"]) + _advance_days(state, step)
	# Bez paszy nic sie nie wykluwa i nic nie rosnie. Wczesniej inkubator
	# i odchow chodzily nawet przy pustym magazynie, wiec stado odnawialo sie
	# szybciej, niz gloddzilo — dalo sie grac w ogole nie kupujac paszy.
	if state.feed > 0.0:
		out["hatched"] = int(out["hatched"]) + _advance_incubator(state, step)
		out["grown_up"] = int(out["grown_up"]) + _advance_chicks(state, step)
	out["rotted"] = int(out["rotted"]) + _advance_corpses(state, step)
	_advance_construction(state, step, out)
	_advance_dog(state, step / maxf(0.0001, GameData.time_scale()), out)
	# Jaja starzeja sie niezaleznie od tego, czy stado jeszcze zyje — stad
	# miejsce PRZED wyjsciem dla pustej farmy nizej.
	_advance_egg_spoilage(state, step, out)
	_advance_fox(state, step, out, loss_budget, offline)

	# 13.0: w nocy (Daylight) kury spia zamkniete - nie jedza, a glod stoi.
	var night := Daylight.is_night(_clock_start + float(out.get("_t", 0.0)))
	out["_night"] = night
	if night:
		out["night_seconds"] = float(out.get("night_seconds", 0.0)) + step / GameData.time_scale()
	# Karmienie rozliczamy przed sprawdzeniem, czy stado istnieje: inaczej
	# po stracie ostatniej kury licznik glodu zostalby zamrozony.
	if night:
		pass
	elif state.feed > 0.0:
		state.feed = maxf(0.0, state.feed - state.feed_per_minute() * step / 60.0)
		state.hunger_seconds = 0.0
		state.hunger_next_death = 0.0
	else:
		state.feed = 0.0
		if not state.chickens.is_empty():
			if not bool(out["out_of_feed"]):
				_log(out, "no_feed")
			out["out_of_feed"] = true
		_advance_hunger(state, step, out, loss_budget)

	# Choroba przed wyjsciem dla pustej farmy: ognisko musi wygasnac takze
	# wtedy, gdy wybilo cale stado.
	_advance_disease(state, step, out, loss_budget, offline)
	if state.chickens.is_empty():
		return
	if state.feed <= 0.0:
		# Glodne stado nie znosi jaj; samo czekanie na karme to juz kara.
		return
	_lay_eggs(state, step, out, offline)


## Licznik dni gospodarstwa. Dlugosc dnia siedzi w balance.json.
static func _advance_days(state: FarmState, step: float) -> int:
	var day_seconds := float(GameData.balance().get("day", {}).get("seconds", 600.0))
	if day_seconds <= 0.0:
		return 0
	state.day_fraction += step / day_seconds
	# Przy nadrabianiu godzin ulamek sumuje sie setki razy, wiec 2.0 moze wyjsc
	# jako 1.999999. Bez tej poprawki gra gubilaby caly dzien.
	var passed := int(floor(state.day_fraction + 1e-9))
	if passed <= 0:
		return 0
	state.day_fraction -= passed
	state.days += passed
	return passed


## Budowy ida czasem REALNYM, takze przy grze w tle. Po skonczeniu budynek
## wskakuje na nastepny poziom, a id trafia do out["built"].
static func _advance_construction(state: FarmState, step: float, out: Dictionary) -> void:
	if state.construction.is_empty():
		return
	var real := step / maxf(0.0001, GameData.time_scale())
	for id: String in state.construction.keys():
		var job: Array = state.construction[id]
		job[0] = float(job[0]) - real
		if float(job[0]) > 0.0:
			continue
		state.construction.erase(id)
		state.set_building_level(id, state.building_level(id) + 1)
		var built: Array = out.get("built", [])
		built.append(id)
		out["built"] = built
		_log(out, "built", {"id": id, "level": state.building_level(id)})


## Inkubator: partie jaj dochodza do wyklucia i zamieniaja sie w pisklęta.
static func _advance_incubator(state: FarmState, step: float) -> int:
	# 13.0 (wlasciciel 26.11): w trakcie rozbudowy inkubator stoi - nic sie
	# nie wykluwa. (Rozbudowy i tak nie da sie zaczac przy pelnym inkubatorze,
	# ale stare zapisy moga miec obie rzeczy naraz.)
	if state.incubating.is_empty() or state.is_building("incubator"):
		return 0
	var speed := state.incubation_speed()
	var hatched := 0
	var still_warming: Array[EggBatch] = []
	for batch: EggBatch in state.incubating:
		batch.elapsed += step * speed
		if batch.elapsed < batch.total_seconds():
			still_warming.append(batch)
			continue
		for i in batch.count:
			state.chicks.append(Chick.create(batch.breed_id, 0.0, Chick.roll_rooster()))
			hatched += 1
	state.incubating = still_warming
	return hatched


## Pisklęta rosna i dolaczaja do stada jako dorosle kury. Mlode nie dziedzicza
## szczepienia — trzeba zaszczepic je osobno. Gdy kurnik jest pelny, podrosniete
## pisklę czeka przy inkubatorze, zamiast znikac.
static func _advance_chicks(state: FarmState, step: float) -> int:
	if state.chicks.is_empty():
		return 0
	var grown := 0
	var still_small: Array[Chick] = []
	for chick: Chick in state.chicks:
		chick.grown += step
		if chick.grown < chick.total_seconds():
			still_small.append(chick)
			continue
		if not state.coop_has_room():
			# Brak miejsca: pisklę czeka, a licznik stoi na koncu wzrostu.
			chick.grown = chick.total_seconds()
			still_small.append(chick)
			continue
		state.chickens.append(Chicken.create_rooster(chick.breed_id) if chick.rooster
				else Chicken.create(chick.breed_id))
		grown += 1
	state.chicks = still_small
	return grown


## Zwloki na wybiegu rozkladaja sie i znikaja.
static func _advance_corpses(state: FarmState, step: float) -> int:
	if state.corpses.is_empty():
		return 0
	var gone := 0
	var still_there: Array[Corpse] = []
	for corpse: Corpse in state.corpses:
		corpse.elapsed += step
		if corpse.elapsed < corpse.total_seconds():
			still_there.append(corpse)
		else:
			gone += 1
	state.corpses = still_there
	return gone


## Glod: po okresie laski kury zaczynaja padac, jedna po drugiej.
static func _advance_hunger(state: FarmState, step: float, out: Dictionary, budget: int) -> void:
	if state.chickens.is_empty():
		return
	var hunger: Dictionary = GameData.balance().get("hunger", {})
	var grace := float(hunger.get("grace_minutes", 3.0)) * 60.0
	state.hunger_seconds += step
	if state.hunger_seconds < grace:
		return
	# Tempo padania rosnie razem ze stadem. Przy stalym odstepie duze stado
	# gloduje godzinami i pasza przestaje byc problemem: wystarczylo hodowac
	# nowe kury szybciej, niz stare padaly. `reference_hens` to wielkosc stada,
	# przy ktorej obowiazuje goly `death_interval_seconds`.
	var reference := maxf(1.0, float(hunger.get("reference_hens", 10.0)))
	var scale := maxf(1.0, float(state.chickens.size()) / reference)
	var interval := maxf(0.5, float(hunger.get("death_interval_seconds", 50.0)) / scale)
	state.hunger_next_death -= step
	while state.hunger_next_death <= 0.0 and not state.chickens.is_empty():
		if _losses(out) >= budget:
			state.hunger_next_death = interval
			return
		state.hunger_next_death += interval
		_kill_hen(state, randi() % state.chickens.size(), "hunger")
		out["died_hunger"] = int(out["died_hunger"]) + 1


## Jaja maja termin przydatnosci liczony ZEGARKIEM. Bez tego gra zostawiona
## na noc witala gracza magazynem pelnym jaj sprzed doby i cala ekonomia
## stawala na glowie.
static func _advance_egg_spoilage(state: FarmState, step: float, out: Dictionary) -> void:
	var hours := float(GameData.balance().get("economy", {}).get("egg_spoil_hours", 0.0))
	if hours <= 0.0:
		return
	var real := step / maxf(0.0001, GameData.time_scale())
	var spoiled := state.age_eggs(real, hours * 3600.0)
	if spoiled > 0:
		out["eggs_spoiled"] = int(out.get("eggs_spoiled", 0)) + spoiled


## Choroba (12.20): ogniska. Kostka co minute z szansa zalezna od wielkosci
## stada; wybuch zaraza 30-100% stada po jednej kurze co minute; chora pada po
## death_minutes minutach REALNYCH; leku nie ma, szczepionka chroni tylko
## zdrowe; po wygasnieciu 3-12 godzin spokoju.
static func _advance_disease(state: FarmState, step: float, out: Dictionary, budget: int,
		_offline: bool) -> void:
	var disease: Dictionary = GameData.balance().get("disease", {})
	var real := step / maxf(0.0001, GameData.time_scale())
	# Od 12.20 choroba idzie w calosci czasem REALNYM (wlasciciel 25.11:
	# "roznosi sie co minute"). Chora kura pada po death_minutes minutach
	# zegarka. Leku nie ma — chora jest stracona, mozna ja tylko sprzedac
	# do McDonalda.
	var death_seconds := float(disease.get("death_minutes", 5.0)) * 60.0

	# 1. Przebieg choroby u tych, ktore juz choruja. Po death_minutes chory
	#    albo pada, albo (z szansa outbreak_survive, 0-30%) zdrowieje i jest
	#    odporny do konca zycia - jak po szczepieniu (wlasciciel 25.11).
	var index := state.chickens.size() - 1
	while index >= 0:
		var hen: Chicken = state.chickens[index]
		if hen.sick:
			hen.sick_seconds += real
			if hen.sick_seconds >= death_seconds:
				if state.outbreak_on and randf() < state.outbreak_survive:
					hen.sick = false
					hen.sick_seconds = 0.0
					hen.vaccinated = true
					state.outbreak_saved += 1
					out["recovered"] = int(out.get("recovered", 0)) + 1
				elif _losses(out) < budget:
					_kill_hen(state, index, "disease")
					out["died_disease"] = int(out["died_disease"]) + 1
					if state.outbreak_on:
						state.outbreak_dead += 1
		index -= 1

	# 2. Ognisko w toku: co spread_seconds zaraza przechodzi na kolejna kure,
	#    az zarazi zaplanowana liczbe albo zabraknie zdrowych bez szczepienia.
	if state.outbreak_on:
		_spread_outbreak(state, out, budget, real)
		if state.outbreak_left <= 0 and state.sick_count() == 0:
			_end_outbreak(state, out)
		return

	# 3. Spokoj po ognisku: 3-12 godzin bez rzucania kostka.
	if state.disease_calm > 0.0:
		state.disease_calm = maxf(0.0, state.disease_calm - real)
		return

	# 4. Karencja na starcie gry (zegarkiem).
	var played_real := state.played_seconds() / maxf(0.0001, GameData.time_scale())
	if played_real < float(disease.get("grace_minutes", 30.0)) * 60.0:
		return

	# 5. Kostka co roll_seconds. Szansa zalezy od wielkosci stada: do 10 sztuk
	#    zero, przy 20 niska, przy 50 czesta, od 100 bardzo czesta — krzywa
	#    rate_per_hour w balance.json. Ta sama w grze aktywnej i w tle.
	var roll := maxf(1.0, float(disease.get("roll_seconds", 60.0)))
	state.disease_timer += real
	while state.disease_timer >= roll:
		state.disease_timer -= roll
		var chance := FarmState.disease_rate_per_hour(state.chickens.size()) * roll / 3600.0
		if chance > 0.0 and randf() < chance:
			_start_outbreak(state, out, budget)
			state.disease_timer = 0.0
			return


## Wybuch choroby (12.22, wlasciciel 25.11). Losuje JEDNA rase - drozsza
## chetniej - i zaraza po kolei wszystkie jej niezaszczepione ptaki; inne rasy
## sa odporne (premia za zroznicowane stado). Losuje tez, jaka czesc chorych
## przezyje: survive_share_min..max co survive_share_step (0%, 10%, 20%, 30%).
## Pierwszy ptak choruje od razu.
static func _start_outbreak(state: FarmState, out: Dictionary, budget: int) -> void:
	var first := _pick_for_infection(state, "")
	if first == null:
		return
	var disease: Dictionary = GameData.balance().get("disease", {})
	var low := clampf(float(disease.get("survive_share_min", 0.0)), 0.0, 1.0)
	var high := clampf(float(disease.get("survive_share_max", 0.3)), low, 1.0)
	var step := maxf(0.01, float(disease.get("survive_share_step", 0.1)))
	var steps := int(round((high - low) / step))
	state.outbreak_survive = minf(high, low + step * randi_range(0, steps))
	state.outbreak_breed = first.breed_id
	var target := 0
	for hen: Chicken in state.chickens:
		if hen.breed_id == first.breed_id and not hen.sick and not hen.vaccinated:
			target += 1
	state.outbreak_on = true
	state.outbreak_left = target
	state.outbreak_timer = 0.0
	state.outbreak_dead = 0
	state.outbreak_saved = 0
	out["outbreak"] = target
	out["outbreak_breed"] = first.breed_id
	out["outbreaks"] = int(out.get("outbreaks", 0)) + 1
	_log(out, "outbreak", {"target": target, "breed": first.breed_id})
	_spread_outbreak(state, out, budget, 0.0)


## Kolejne zarazenia w trwajacym ognisku. Przy grze w tle zaraza staje, gdy
## straty plus chore dobija do bezpiecznika strat (polowa stada) — po powrocie
## gracza ognisko rusza dalej i mozna jeszcze zaszczepic reszte.
static func _spread_outbreak(state: FarmState, out: Dictionary, budget: int, real: float) -> void:
	if state.outbreak_left <= 0:
		return
	var gap := maxf(1.0, float(GameData.balance().get("disease", {}).get("spread_seconds", 60.0)))
	state.outbreak_timer -= real
	while state.outbreak_timer <= 0.0 and state.outbreak_left > 0:
		if _losses(out) + state.sick_count() >= budget:
			state.outbreak_timer = 0.0
			return
		var hen: Chicken = _pick_for_infection(state, _outbreak_breed_of(state))
		if hen == null:
			# Nie ma juz kogo zarazic: reszta zaszczepiona albo wybita.
			state.outbreak_left = 0
			return
		hen.sick = true
		hen.sick_seconds = 0.0
		state.outbreak_left -= 1
		state.outbreak_timer += gap
		out["got_sick"] = int(out["got_sick"]) + 1


## Koniec ogniska: wszystkie zarazone padly albo poszly do McDonalda i nie ma
## kogo wiecej zarazic. Potem 3-12 godzin spokoju.
static func _end_outbreak(state: FarmState, out: Dictionary) -> void:
	var disease: Dictionary = GameData.balance().get("disease", {})
	var low := maxf(0.0, float(disease.get("calm_hours_min", 3.0)))
	var high := maxf(low, float(disease.get("calm_hours_max", 12.0)))
	state.disease_calm = randf_range(low, high) * 3600.0
	out["outbreak_over"] = int(out.get("outbreak_over", 0)) + 1
	out["outbreak_dead"] = state.outbreak_dead
	out["outbreak_saved"] = state.outbreak_saved
	_log(out, "outbreak_over", {"dead": state.outbreak_dead, "saved": state.outbreak_saved})
	state.outbreak_on = false
	state.outbreak_left = 0
	state.outbreak_timer = 0.0
	state.outbreak_dead = 0
	state.outbreak_saved = 0
	state.outbreak_breed = ""
	state.outbreak_survive = 0.0
	state.disease_timer = 0.0


## Rasa trwajacego ogniska. Zapis sprzed 12.22 jej nie ma - wtedy bierzemy
## rase pierwszego chorego ptaka (a bez chorych: ognisko i tak wygasa).
static func _outbreak_breed_of(state: FarmState) -> String:
	if state.outbreak_breed.is_empty():
		for hen: Chicken in state.chickens:
			if hen.sick:
				state.outbreak_breed = hen.breed_id
				break
	return state.outbreak_breed


## Losuje zdrowego, niezaszczepionego ptaka do zarazenia; przy `breed_id`
## tylko z tej rasy. Droga rasa choruje czesciej - waga to pierwiastek z ceny
## (sama cena dawalaby cemani sto razy wieksza szanse niz leghornowi). null,
## gdy nie ma kogo zarazic.
static func _pick_for_infection(state: FarmState, breed_id: String) -> Chicken:
	# 13.0.1 (wlasciciel 27.11): rasa ogniska losowana ROWNO - wczesniej waga
	# sqrt(ceny) sprawiala, ze zaraza prawie zawsze brala najdrozsza rase.
	var by_breed := {}
	for hen: Chicken in state.chickens:
		if hen.sick or hen.vaccinated:
			continue
		if not breed_id.is_empty() and hen.breed_id != breed_id:
			continue
		if not by_breed.has(hen.breed_id):
			by_breed[hen.breed_id] = []
		(by_breed[hen.breed_id] as Array).append(hen)
	if by_breed.is_empty():
		return null
	var keys: Array = by_breed.keys()
	var pool: Array = by_breed[keys[randi() % keys.size()]]
	return pool[randi() % pool.size()]


static func _advance_fox(state: FarmState, step: float, out: Dictionary, budget: int,
		offline: bool) -> void:
	var fox: Dictionary = GameData.balance().get("fox", {})
	var real := step / maxf(0.0001, GameData.time_scale())

	# 1. Wizyta w toku. Lis zabiera po jednej kurze przez caly swoj pobyt,
	#    a nie wszystkie naraz na koniec. Dzieki temu kazda sekunda, o ktora
	#    skrocisz mu wizyte — palcem albo psem — to uratowana kura.
	if state.fox_visit_left > 0.0:
		state.fox_visit_left -= real
		state.fox_kill_timer -= real
		while state.fox_kill_timer <= 0.0 and state.fox_kill_left > 0:
			if not _fox_grabs_one(state, out, budget):
				break
			# Kazda kura ma wlasne, losowane od nowa odliczanie.
			state.fox_kill_timer += _fox_kill_gap(state)
		# Tchorzliwy kundel po kilku sekundach pogoni sam ucieka.
		if state.dog_level > 0 and not state.dog_off_visit and state.dog_quit_left >= 0.0:
			state.dog_quit_left -= real
			if state.dog_quit_left <= 0.0:
				state.dog_off_visit = true
				out["dog_fled"] = int(out.get("dog_fled", 0)) + 1
		# Pies probuje do skutku: co `interval` sekund rzuca kostka.
		if state.dog_level > 0 and not state.dog_off_visit:
			state.dog_timer -= real
			while state.dog_timer <= 0.0:
				state.dog_timer += state.dog_interval()
				if randf() >= state.dog_chance():
					continue
				# 13.0.2: ugryzienie zabiera lisowi punkty zycia; dopiero przy
				# zerze lis ucieka albo (pies z zagryza_proc) ginie.
				out["fox_bitten"] = int(out.get("fox_bitten", 0)) + 1
				state.fox_taps_left -= state.dog_damage()
				if state.fox_taps_left > 0:
					continue
				if randf() < state.dog_kill_chance():
					# Zagryziony lis nie wraca. Nastepny dlugo sie nie pokaze.
					state.fox_next_multiplier = maxf(1.0,
							float(fox.get("killed_return_multiplier", 5.0)))
					out["fox_killed"] = int(out.get("fox_killed", 0)) + 1
				else:
					out["fox_chased"] = int(out.get("fox_chased", 0)) + 1
				_fox_leaves(state)
				return
		# Lis odchodzi, gdy wybierze swoja pule albo gdy skonczy mu sie czas.
		if state.fox_kill_left <= 0 or state.fox_visit_left <= 0.0 \
				or state.chickens.is_empty():
			_fox_leaves(state)
			out["fox_left"] = int(out.get("fox_left", 0)) + 1
		return

	# 1b. Lis czai sie w krzakach i podchodzi pod plot. Dopiero gdy dojdzie,
	#     plot decyduje, czy wejdzie. Wczesniej losowanie plotu szlo w tej
	#     samej chwili co losowanie przyjscia i gracz nie widzial, ze plot
	#     cokolwiek robi (wlasciciel, 24.11).
	if state.fox_lurk_left > 0.0:
		state.fox_lurk_left -= real
		if state.fox_lurk_left > 0.0:
			return
		state.fox_lurk_left = 0.0
		_fox_at_fence(state, out, budget, offline)
		return

	# 2. Warunki wstepne: karencja na starcie gry i minimalne stado.
	# Karencja liczona ZEGARKIEM: wlasciciel mowi o pol godzinie grania,
	# a `played_seconds()` zwraca sekundy gry, ktore plyna trzy razy wolniej.
	var played_real := state.played_seconds() / maxf(0.0001, GameData.time_scale())
	if played_real < float(fox.get("grace_minutes", 30.0)) * 60.0:
		return
	if state.chickens.size() < int(fox.get("min_hens", 5)):
		return

	# 3. Kostka: co roll_minutes minut ZEGARA z szansa chance - tak samo
	#    w grze i w tle (wlasciciel 25.11: "w kazdej godzinie jakas szansa").
	#    Wczesniej w tle kostka leciala raz na dobe, a licznik uzbierany przez
	#    noc odpalal kostke w pierwszej sekundzie po powrocie - stad lis
	#    witajacy gracza prawie po kazdej dluzszej przerwie.
	state.fox_roll_timer += real
	var interval := float(fox.get("roll_minutes", 60.0)) * 60.0
	# Przegoniony golymi rekami lis wraca szybciej. Pies albo plot zdejmuja
	# te kare — gospodarstwo wyglada na pilnowane.
	if state.fox_hand_scared and state.dog_level <= 0 and state.guard_level <= 0:
		interval *= clampf(float(fox.get("hand_return_factor", 0.1)), 0.01, 1.0)
	interval *= maxf(1.0, state.fox_next_multiplier)
	if state.fox_roll_timer < interval:
		return
	state.fox_roll_timer = 0.0
	state.fox_next_multiplier = 1.0

	if randf() >= float(fox.get("chance", 0.3333)):
		return

	# 4. W grze aktywnej lis najpierw czai sie w krzakach, potem podchodzi
	#    pod plot. Przy grze w tle nie ma komu tego pokazywac.
	var lurk := 0.0 if offline else state.fox_lurk_seconds()
	if lurk > 0.0:
		state.fox_lurk_left = lurk
		out["fox_lurking"] = int(out.get("fox_lurking", 0)) + 1
		return
	_fox_at_fence(state, out, budget, offline)


## Lis stoi pod plotem. Plot losuje, czy go zawroci; jesli nie, lis wchodzi.
static func _fox_at_fence(state: FarmState, out: Dictionary, budget: int,
		offline: bool) -> void:
	if randf() < state.fox_block_chance():
		out["fox_blocked"] = int(out["fox_blocked"]) + 1
		_log(out, "fox_blocked")
		return
	_fox_arrives(state, out, budget, offline)


## Lis wchodzi na wybieg. Lup to stala liczba kur z przedzialu
## kills_min..kills_max, zabierana po jednej co kill_interval_min..max
## sekund. Pierwsza kura ginie od razu — lis ZAWSZE cos zabiera.
static func _fox_arrives(state: FarmState, out: Dictionary, budget: int,
		offline: bool) -> void:
	var fox: Dictionary = GameData.balance().get("fox", {})
	# Lis bierze z gory ustalona liczbe kur, nie procent stada: wlasciciel
	# chcial, zeby przychodzil, zabil pare sztuk i poszedl.
	var quota := randi_range(int(fox.get("kills_min", 3)), int(fox.get("kills_max", 10)))
	quota = clampi(quota, 1, maxi(1, state.chickens.size()))
	var full := state.fox_visit_seconds()
	# Rzez (wlasciciel 25.11): okolo 5% wejsc konczy sie wybiciem CALEGO stada,
	# ale tylko na gospodarstwie bez psa. Lis zabija wtedy szybciej i zostaje,
	# az skonczy — chyba ze gracz przegoni go palcem.
	state.fox_massacre = state.dog_level <= 0 \
			and randf() < float(fox.get("massacre_chance", 0.0))
	if state.fox_massacre:
		quota = state.chickens.size()
		out["fox_massacre"] = int(out.get("fox_massacre", 0)) + 1
		full = maxf(full, quota * float(fox.get("kill_interval_max", 10.0))
				* _fox_pace_factor(state) + 10.0)

	state.fox_kill_left = quota
	state.fox_kill_pace = _fox_kill_gap(state)
	# Lis, ktoremu gracz juz dokuczal w krzakach, zachowuje obrazenia.
	if state.fox_lurk_taps <= 0 or state.fox_taps_left <= 0:
		state.roll_fox_hp()
	state.fox_hand_scared = false
	state.dog_timer = state.dog_interval()
	state.roll_dog_visit()
	if state.dog_off_visit:
		out["dog_deaf"] = int(out.get("dog_deaf", 0)) + 1

	# Gdy gracza nie ma przy grze, nie ma kogo straszyc ani komu pokazywac
	# wizyty: cala wizyte rozgrywamy od razu, na tej samej osi czasu co
	# w grze aktywnej. Wczesniej lis zabieral wtedy CALY lup naraz, a pies
	# w ogole nie dostawal szansy — czyli pilnowal tylko, gdy gracz patrzyl.
	# W tle lis NIE ma bezpiecznika strat (wlasciciel 25.11: "niech zezre,
	# ile chce") - budzet strat dotyczy tylko glodu i choroby.
	if offline:
		var before := int(out["fox_took"])
		var massacre := state.fox_massacre
		var dog := _fox_visit_offline(state, out, 1 << 30, full)
		_log(out, "fox", {"taken": int(out["fox_took"]) - before, "massacre": massacre, "dog": dog})
		return

	# Pies rusza za lisem. Jesli da rade, skraca wizyte do swojego czasu —
	# lis przez te sekundy dalej zabija, uciekajac.
	state.fox_visit_left = full
	if state.dog_level > 0 and not state.dog_off_visit:
		out["fox_dog"] = int(out.get("fox_dog", 0)) + 1
	out["fox_arrived"] = int(out["fox_arrived"]) + 1
	# Pierwsza ofiara zaraz po wejsciu — lis ZAWSZE cos zabiera.
	if _fox_grabs_one(state, out, budget):
		state.fox_kill_timer = state.fox_kill_pace


## Jedna kura z lupu lisa. Czesc zostaje na wybiegu jako zwloki, reszte lis
## wynosi. Zwraca false, gdy nie ma juz czego brac.
static func _fox_grabs_one(state: FarmState, out: Dictionary, budget: int) -> bool:
	if state.fox_kill_left <= 0 or state.chickens.is_empty():
		return false
	if _losses(out) >= budget:
		return false
	var share := clampf(float(GameData.balance().get("fox", {}).get("carcass_share", 0.5)), 0.0, 1.0)
	var index := randi() % state.chickens.size()
	# Rasa ofiary idzie do sceny: piora sypia sie w jej kolorze.
	var victims: Array = out.get("fox_victims", [])
	victims.append(state.chickens[index].breed_id)
	out["fox_victims"] = victims
	if randf() < share:
		_kill_hen(state, index, "fox")
	else:
		state.chickens.remove_at(index)
	state.fox_kill_left -= 1
	out["fox_took"] = int(out["fox_took"]) + 1
	return true


## Koniec wizyty, z kazdego powodu. Jedno miejsce, ktore sprzata stan lisa —
## wczesniej bylo ich kilka i jedna sciezka potrafila zostawic lisa na zawsze.
## Publiczna furtka dla Game.poke_fox — ta sama sciezka sprzatania.
static func fox_leaves(state: FarmState) -> void:
	_fox_leaves(state)


## Wizyta lisa przy grze w tle, rozegrana od razu w calosci. Te same zasady
## co w grze aktywnej: pierwsza kura ginie przy wejsciu, kolejne co
## kill_interval_min..max sekund, a pies co dog_interval() sekund rzuca
## kostka. Wygrywa to, co zdarzy sie wczesniej. Klikania palcem tu nie ma,
## bo gracza nie ma przy grze.
static func _fox_visit_offline(state: FarmState, out: Dictionary, budget: int,
		visit_seconds: float) -> String:
	var dog_result := ""
	var fox: Dictionary = GameData.balance().get("fox", {})
	var next_kill := 0.0
	var next_dog := state.dog_interval() if state.dog_level > 0 and not state.dog_off_visit else INF
	# Tchorzliwy kundel goni tylko do swojej chwili, potem ucieka.
	var dog_end := state.dog_quit_left if state.dog_quit_left >= 0.0 else INF
	while state.fox_kill_left > 0:
		if next_dog > dog_end:
			next_dog = INF
		if next_dog < next_kill:
			if next_dog > visit_seconds:
				break
			next_dog += state.dog_interval()
			if randf() >= state.dog_chance():
				continue
			state.fox_taps_left -= state.dog_damage()
			if state.fox_taps_left > 0:
				continue
			if randf() < state.dog_kill_chance():
				state.fox_next_multiplier = maxf(1.0,
						float(fox.get("killed_return_multiplier", 5.0)))
				out["fox_killed"] = int(out.get("fox_killed", 0)) + 1
				dog_result = "killed"
			else:
				out["fox_chased"] = int(out.get("fox_chased", 0)) + 1
				dog_result = "chased"
			break
		if next_kill > visit_seconds:
			break
		if not _fox_grabs_one(state, out, budget):
			break
		next_kill += _fox_kill_gap(state)
	_fox_leaves(state)
	return dog_result


## Odstep miedzy kolejnymi ofiarami lisa, w sekundach REALNYCH. W rzezi
## krotszy o massacre_pace_factor.
static func _fox_kill_gap(state: FarmState) -> float:
	var fox: Dictionary = GameData.balance().get("fox", {})
	return randf_range(float(fox.get("kill_interval_min", 3.0)),
			float(fox.get("kill_interval_max", 10.0))) * _fox_pace_factor(state)


static func _fox_pace_factor(state: FarmState) -> float:
	if not state.fox_massacre:
		return 1.0
	return clampf(float(GameData.balance().get("fox", {}).get("massacre_pace_factor", 0.25)),
			0.05, 1.0)


static func _fox_leaves(state: FarmState) -> void:
	state.fox_lurk_taps = 0
	state.fox_hp_max = 0
	state.dog_off_visit = false
	state.dog_quit_left = -1.0
	state.fox_massacre = false
	state.fox_lurk_left = 0.0
	state.fox_visit_left = 0.0
	state.fox_kill_left = 0
	state.fox_kill_timer = 0.0
	state.fox_taps_left = 0
	state.fox_pending = 0
	state.dog_timer = 0.0



## Znoszenie jaj. Nie znosza: koguty, chore kury i kury rasy, ktora nie ma
## na farmie koguta.
##
## Pelny wybieg **nie wstrzymuje juz znoszenia**. `max_eggs_on_ground` ogranicza
## tylko to, ile jaj lezy na wybiegu do zebrania palcem; nadmiar idzie prosto do
## magazynu. Wczesniej kura z gotowym jajkiem czekala na wolne miejsce, przez co
## cala produkcja byla ograniczona tempem stukania gracza — po dziesieciokrotnym
## przyspieszeniu znoszenia nie zostaloby z tego nic. Przy okazji znika problem
## kolejnosci: kiedys wolne miejsce bralo zawsze zwierze z poczatku tablicy
## i rasy kupione pozniej nie znosily w ogole (pomiar: 20 leghornow 292 jaja,
## cemani 0).
static func _lay_eggs(state: FarmState, step: float, out: Dictionary, offline: bool) -> void:
	var capacity := int(GameData.balance().get("run", {}).get("max_eggs_on_ground", 30))
	if state.chickens.is_empty():
		return
	# Rasy z kogutem zbieramy raz na krok. Pytanie `has_rooster` osobno dla
	# kazdej kury dawaloby koszt kwadratowy — przy 260 ptakach to odczuwalne.
	var with_rooster := {}
	for bird: Chicken in state.chickens:
		if bird.is_rooster:
			with_rooster[bird.breed_id] = true
	if with_rooster.is_empty():
		return
	for hen: Chicken in state.chickens:
		if hen.is_rooster or hen.sick or not with_rooster.has(hen.breed_id):
			continue
		var seconds := float(GameData.breed(hen.breed_id).get("egg_seconds", 0.0))
		if seconds <= 0.0:
			continue
		hen.since_last_egg += step
		# Jedna kura moze w dlugim kroku zniesc wiecej niz jedno jajko —
		# przy odstepie 4 s i kroku 10 s zdarza sie to stale.
		while hen.since_last_egg >= seconds:
			hen.since_last_egg -= seconds
			# 13.0: w nocy kury siedza w kurniku - jajko trafia od razu do magazynu.
			if offline or bool(out.get("_night", false)) or state.eggs_on_ground.size() >= capacity:
				# Pod nieobecnosc gracza i przy zapelnionym wybiegu jajko idzie
				# prosto do magazynu. Gdy magazyn jest pelny, jajko przepada —
				# to jest wlasnie hamulec, dzieki ktoremu gra nie przechodzi
				# sie sama przez noc.
				if state.add_egg(hen.breed_id) <= 0:
					if int(out.get("eggs_lost", 0)) == 0:
						_log(out, "storage_full")
					out["eggs_lost"] = int(out.get("eggs_lost", 0)) + 1
					continue
			else:
				state.eggs_on_ground.append(hen.breed_id)
			out["eggs_laid"] = int(out["eggs_laid"]) + 1


## Usuwa kure ze stada i kladzie zwloki na wybiegu.
static func _kill_hen(state: FarmState, index: int, cause: String) -> void:
	if index < 0 or index >= state.chickens.size():
		return
	var hen: Chicken = state.chickens[index]
	state.chickens.remove_at(index)
	state.corpses.append(Corpse.create(hen.breed_id, random_run_position(), cause))


## Losowy punkt na wybiegu. Jedno zrodlo prawdy dla symulacji i dla sceny.
static func random_run_position() -> Vector2:
	var area := run_area()
	return Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))


static func run_area() -> Rect2:
	var area: Dictionary = GameData.balance().get("run", {}).get("area", {})
	return Rect2(float(area.get("x", 110)), float(area.get("y", 1105)),
			float(area.get("w", 860)), float(area.get("h", 420)))


## Dawniej rasy odblokowywaly sie po przekroczeniu progu pieniedzy albo
## liczby kur. Gracz czytal te progi jak ceny i slusznie uznal za sztuczne:
## wszystko stoi teraz w sklepie od poczatku, a jedyna bariera jest cena.
## Funkcja zostaje pusta, zeby nie przepisywac wszystkich jej wywolan.
static func check_unlocks(_state: FarmState) -> Array[String]:
	return [] as Array[String]


## Sprawdza warunki wygranej. Zwraca powod ("money" albo "collection"),
## jesli gra wlasnie zostala wygrana, albo pusty napis.
## GAME OVER (wlasciciel 25.11): gry nie da sie kontynuowac. Warunek jest
## celowo ostrozny — falszywe bankructwo kasuje graczowi ferme:
##  - nie ma zdrowej pary kura + kogut tej samej rasy (nikt nie zniesie jaj),
##  - nie ma pisklat ani jaj w inkubatorze,
##  - w magazynie nie ma jaj zadnej rasy na wyleg (eggs_per_chick),
##  - i za cala gotowke (pieniadze + jaja + zdrowe ptaki innych ras + chore
##    dla McDonalda) nie da sie dokupic brakujacej kury albo koguta do zadnej
##    rasy, na ktora pozwala kurnik.
## Pasze pomijamy: glodne stado i tak padnie, a wtedy warunek zadziala.
static func check_bankrupt(state: FarmState) -> bool:
	if not state.chicks.is_empty() or not state.incubating.is_empty():
		return false
	var per_chick := int(GameData.balance().get("incubator", {}).get("eggs_per_chick", 6))
	for breed_id: String in state.eggs:
		if int(state.eggs[breed_id]) >= per_chick:
			return false
	var hens := {}
	var cocks := {}
	var bird_value := {}
	var sick_value := 0.0
	var cull := float(GameData.balance().get("disease", {}).get("mcdonalds_price", 5))
	for bird: Chicken in state.chickens:
		if bird.sick:
			sick_value += cull
			continue
		if bird.is_rooster:
			cocks[bird.breed_id] = true
		else:
			hens[bird.breed_id] = true
		bird_value[bird.breed_id] = float(bird_value.get(bird.breed_id, 0.0)) \
				+ FarmState.hen_sell_price(bird.breed_id, false, bird.is_rooster)
	for breed_id: String in hens:
		if cocks.has(breed_id):
			return false
	var all_birds := 0.0
	for value: float in bird_value.values():
		all_birds += value
	var cash := state.money + state.eggs_value() + sick_value
	for breed: Dictionary in GameData.breeds():
		var breed_id: String = breed.get("id", "")
		if state.coop_level < int(breed.get("coop_level", 0)):
			continue
		var cost := 0.0
		if not hens.has(breed_id):
			cost += FarmState.hen_buy_price(breed_id)
		if not cocks.has(breed_id):
			cost += FarmState.hen_buy_price(breed_id, true)
		# Ptaki tej rasy zostaja w parze, wiec na zakupy idzie reszta.
		var spare := all_birds - float(bird_value.get(breed_id, 0.0))
		if cash + spare >= cost:
			return false
	return true


static func check_win(state: FarmState) -> String:
	if state.won:
		return ""
	var win: Dictionary = GameData.balance().get("win", {})
	var goal := float(win.get("money", 0))
	if goal > 0.0 and state.money >= goal:
		state.won = true
		state.win_reason = "money"
		return "money"
	if bool(win.get("collection", false)) and state.has_full_collection():
		state.won = true
		state.win_reason = "collection"
		return "collection"
	return ""
