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
		"rotted": 0,
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
	while remaining > 0.0:
		var step := minf(remaining, step_size)
		_step(state, step, summary, loss_budget, offline)
		remaining -= step
	return summary


## Ile kur ubylo ze stada od poczatku tego wywolania `advance`.
static func _losses(out: Dictionary) -> int:
	return int(out["died_hunger"]) + int(out["died_disease"]) + int(out["fox_took"])


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
	# Jaja starzeja sie niezaleznie od tego, czy stado jeszcze zyje — stad
	# miejsce PRZED wyjsciem dla pustej farmy nizej.
	_advance_egg_spoilage(state, step, out)
	_advance_fox(state, step, out, loss_budget, offline)

	# Karmienie rozliczamy przed sprawdzeniem, czy stado istnieje: inaczej
	# po stracie ostatniej kury licznik glodu zostalby zamrozony.
	if state.feed > 0.0:
		state.feed = maxf(0.0, state.feed - state.feed_per_minute() * step / 60.0)
		state.hunger_seconds = 0.0
		state.hunger_next_death = 0.0
	else:
		state.feed = 0.0
		if not state.chickens.is_empty():
			out["out_of_feed"] = true
		_advance_hunger(state, step, out, loss_budget)

	if state.chickens.is_empty():
		return

	_advance_disease(state, step, out, loss_budget, offline)
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


## Inkubator: partie jaj dochodza do wyklucia i zamieniaja sie w pisklęta.
static func _advance_incubator(state: FarmState, step: float) -> int:
	if state.incubating.is_empty():
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


## Choroby: zdrowa kura moze zachorowac, chora przestaje znosic i po
## `death_minutes` pada. Szczepienie chroni do konca zycia.
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


static func _advance_disease(state: FarmState, step: float, out: Dictionary, budget: int,
		offline: bool) -> void:
	var disease: Dictionary = GameData.balance().get("disease", {})
	var death_seconds := float(disease.get("death_minutes", 7.0)) * 60.0

	# Najpierw przebieg choroby u tych, ktore juz choruja.
	var index := state.chickens.size() - 1
	while index >= 0:
		var hen: Chicken = state.chickens[index]
		if hen.sick:
			hen.sick_seconds += step
			if hen.sick_seconds >= death_seconds and _losses(out) < budget:
				_kill_hen(state, index, "disease")
				out["died_disease"] = int(out["died_disease"]) + 1
		index -= 1

	# Potem losowanie nowego zachorowania — jedno na cale gospodarstwo, nie na
	# kura. Wczesniejsza stawka od sztuki sprawiala, ze duze stado chorowalo
	# bez przerwy, a male prawie wcale.
	# Nowe zachorowanie: w grze AKTYWNEJ co active_minutes minut realnych,
	# w NIEaktywnej co offline_hours godzin. Prosty zegar zamiast dawnej
	# krzywej narastania — wlasciciel podal tempo wprost.
	var real := step / maxf(0.0001, GameData.time_scale())
	var played_real := state.played_seconds() / maxf(0.0001, GameData.time_scale())
	if played_real < float(disease.get("grace_minutes", 30.0)) * 60.0:
		return
	if state.chickens.size() < int(disease.get("min_hens", 5)):
		return
	# Ta sama kostka co u lisa, tylko dwa razy czesciej: lis losuje co
	# godzine i co dobe, choroba co pol godziny i co dwanascie godzin.
	state.disease_timer += real
	var interval := float(disease.get("offline_roll_hours", 12.0)) * 3600.0 if offline \
			else float(disease.get("active_roll_minutes", 30.0)) * 60.0
	if state.disease_timer < interval:
		return
	state.disease_timer = 0.0
	var chance := float(disease.get("offline_chance", 0.1667)) if offline \
			else float(disease.get("active_chance", 0.3333))
	if randf() >= chance:
		return
	# Droga rasa choruje czesciej. Waga to pierwiastek z ceny, a nie sama cena:
	# przy cenach od 40 do 8000 zl sama cena dawalaby cemani dwiescie razy
	# wieksza szanse niz leghornowi, czyli w praktyce tylko cemani by chorowaly.
	var healthy: Array[Chicken] = []
	var weights: Array[float] = []
	var total := 0.0
	for hen: Chicken in state.chickens:
		if hen.sick or hen.vaccinated:
			continue
		var weight := sqrt(maxf(1.0, float(GameData.breed(hen.breed_id).get("price", 1))))
		healthy.append(hen)
		weights.append(weight)
		total += weight
	if healthy.is_empty():
		return
	var roll := randf() * total
	var chosen: Chicken = healthy[healthy.size() - 1]
	for i in healthy.size():
		roll -= weights[i]
		if roll <= 0.0:
			chosen = healthy[i]
			break
	chosen.sick = true
	chosen.sick_seconds = 0.0
	out["got_sick"] = int(out["got_sick"]) + 1


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
			state.fox_kill_timer += randf_range(
					float(fox.get("kill_interval_min", 3.0)),
					float(fox.get("kill_interval_max", 10.0)))
		# Pies probuje do skutku: co `interval` sekund rzuca kostka.
		if state.dog_level > 0:
			state.dog_timer -= real
			while state.dog_timer <= 0.0:
				state.dog_timer += state.dog_interval()
				if randf() >= state.dog_chance():
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

	# 3. Kostka. W grze aktywnej raz na active_roll_minutes, w nieaktywnej
	#    raz na offline_roll_hours — dokladnie tak, jak chcial wlasciciel.
	state.fox_roll_timer += real
	var interval := float(fox.get("offline_roll_hours", 24.0)) * 3600.0 if offline \
			else float(fox.get("active_roll_minutes", 60.0)) * 60.0
	# Przegoniony golymi rekami lis wraca szybciej. Pies albo plot zdejmuja
	# te kare — gospodarstwo wyglada na pilnowane.
	if state.fox_hand_scared and state.dog_level <= 0 and state.guard_level <= 0:
		interval *= clampf(float(fox.get("hand_return_factor", 0.1)), 0.01, 1.0)
	interval *= maxf(1.0, state.fox_next_multiplier)
	if state.fox_roll_timer < interval:
		return
	state.fox_roll_timer = 0.0
	state.fox_next_multiplier = 1.0

	var chance := float(fox.get("offline_chance", 0.1667)) if offline \
			else float(fox.get("active_chance", 0.3333))
	if randf() >= chance:
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

	state.fox_kill_left = quota
	state.fox_kill_pace = randf_range(float(fox.get("kill_interval_min", 3.0)),
			float(fox.get("kill_interval_max", 10.0)))
	state.fox_taps_left = maxi(1, int(fox.get("scare_taps", 20)))
	state.fox_hand_scared = false
	state.dog_timer = state.dog_interval()

	# Gdy gracza nie ma przy grze, nie ma kogo straszyc ani komu pokazywac
	# wizyty: cala wizyte rozgrywamy od razu, na tej samej osi czasu co
	# w grze aktywnej. Wczesniej lis zabieral wtedy CALY lup naraz, a pies
	# w ogole nie dostawal szansy — czyli pilnowal tylko, gdy gracz patrzyl.
	if offline:
		_fox_visit_offline(state, out, budget, full)
		return

	# Pies rusza za lisem. Jesli da rade, skraca wizyte do swojego czasu —
	# lis przez te sekundy dalej zabija, uciekajac.
	state.fox_visit_left = full
	if state.dog_level > 0:
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
		visit_seconds: float) -> void:
	var fox: Dictionary = GameData.balance().get("fox", {})
	var next_kill := 0.0
	var next_dog := state.dog_interval() if state.dog_level > 0 else INF
	while state.fox_kill_left > 0:
		if next_dog < next_kill:
			if next_dog > visit_seconds:
				break
			next_dog += state.dog_interval()
			if randf() >= state.dog_chance():
				continue
			if randf() < state.dog_kill_chance():
				state.fox_next_multiplier = maxf(1.0,
						float(fox.get("killed_return_multiplier", 5.0)))
				out["fox_killed"] = int(out.get("fox_killed", 0)) + 1
			else:
				out["fox_chased"] = int(out.get("fox_chased", 0)) + 1
			break
		if next_kill > visit_seconds:
			break
		if not _fox_grabs_one(state, out, budget):
			break
		next_kill += randf_range(float(fox.get("kill_interval_min", 3.0)),
				float(fox.get("kill_interval_max", 10.0)))
	_fox_leaves(state)


static func _fox_leaves(state: FarmState) -> void:
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
			if offline or state.eggs_on_ground.size() >= capacity:
				# Pod nieobecnosc gracza i przy zapelnionym wybiegu jajko idzie
				# prosto do magazynu. Gdy magazyn jest pelny, jajko przepada —
				# to jest wlasnie hamulec, dzieki ktoremu gra nie przechodzi
				# sie sama przez noc.
				if state.add_egg(hen.breed_id) <= 0:
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
