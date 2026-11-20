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

	_advance_disease(state, step, out, loss_budget)
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
			state.chicks.append(Chick.create(batch.breed_id))
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
		state.chickens.append(Chicken.create(chick.breed_id))
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
static func _advance_disease(state: FarmState, step: float, out: Dictionary, budget: int) -> void:
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
	if not _event_fires(state, step, "disease", disease):
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


## Wspolna zasada dla lisa i choroby: przez pierwsze `grace_minutes` gry nic
## zlego sie nie dzieje i male stado jest nietykalne. Potem co minute leci
## kostka, ale **szansa rosnie z kazda minuta bez zdarzenia**.
##
## Stala szansa nie dziala przy graniu z doskoku. Wlasciciel gra po minucie,
## odklada telefon i wraca — przy stalym losowaniu z taka sama szansa za
## kazdym razem potrafil nie zobaczyc lisa przez caly wieczor. Teraz licznik
## suchych minut (`event_dry`) przechodzi przez zapis, wiec pressja narasta
## miedzy sesjami.
##
## Krzywa: p na minute = (t / G)^4, gdzie t to minuty bez zdarzenia,
## a G = `mean_minutes` * `RAMP_SPAN`. Wykladnik 4 trzyma poczatek spokojny,
## a koniec stromy. Przy `mean_minutes` 45 daje to srednia 45 minut i
## **pewnosc najpozniej po 84 minutach**; przy 15 — srednia 19 minut
## i pewnosc po 30. Liczby wyliczone, nie zgadniete.
const RAMP_SPAN := 1.95
const RAMP_POWER := 4.0

static func _event_fires(state: FarmState, step: float, key: String,
		config: Dictionary) -> bool:
	# Dopoki furtka jest zamknieta, licznik stoi: inaczej gracz dostalby lisa
	# w tej samej sekundzie, w ktorej stado urosło do piatej sztuki.
	if state.chickens.size() < int(config.get("min_hens", 5)):
		return false
	if state.played_seconds() < float(config.get("grace_minutes", 30.0)) * 60.0:
		return false
	var dry := float(state.event_dry.get(key, 0.0)) + step
	state.event_dry[key] = dry
	# Progi w balansie podane sa w minutach RZECZYWISTYCH, bo tak mysli o nich
	# gracz ("pol godziny grania"). Licznik `dry` chodzi w sekundach gry, wiec
	# przeliczamy progi przez te sama skale, ktora spowalnia cala symulacje.
	var scale := GameData.time_scale()
	var dry_real_minutes := dry / 60.0 / scale
	# Twardy sufit: po tylu minutach grania bez zdarzenia wypada ono na pewno,
	# bez zadnego losowania. Wlasciciel poprosil o to wprost po tym, jak przez
	# dwa dni nie zobaczyl lisa ani razu.
	var hard := float(config.get("hard_minutes", 0.0))
	if hard > 0.0 and dry_real_minutes >= hard:
		state.event_dry[key] = 0.0
		return true
	var span := maxf(1.0, float(config.get("mean_minutes", 45.0)) * RAMP_SPAN)
	var chance_per_minute := pow(minf(dry_real_minutes / span, 1.0), RAMP_POWER)
	# Przeliczenie szansy "na minute" na szanse w kroku o dlugosci `step`.
	# Mnozenie przez step/60 byloby przyblizeniem, ktore przy szansie rownej
	# jedynce dawaloby 1/60 zamiast pewnosci.
	var step_real_minutes := step / 60.0 / scale
	if randf() >= 1.0 - pow(1.0 - chance_per_minute, step_real_minutes):
		return false
	state.event_dry[key] = 0.0
	return true


## Lis: przychodzi raz na kilka godzin i porywa czesc stada.
##
## Wizyta ma dwa etapy. Najpierw lis przez `visit_seconds` biega po wybiegu
## i nikogo jeszcze nie zabiera — wtedy gracz moze go przegonic. Dopiero gdy
## czas minie, zabiera to, co sobie upatrzyl. Pod nieobecnosc gracza nie ma
## kogo czekac, wiec strata liczy sie od razu.
static func _advance_fox(state: FarmState, step: float, out: Dictionary, budget: int,
		offline: bool) -> void:
	var fox: Dictionary = GameData.balance().get("fox", {})

	if state.fox_visit_left > 0.0:
		state.fox_visit_left -= step
		if state.fox_visit_left > 0.0:
			return
		state.fox_visit_left = 0.0
		_fox_takes(state, out, budget)
		return

	if not _event_fires(state, step, "fox", fox):
		return

	# Plot, pies i nocne swiatla nie odwlekaja wizyty — po prostu zawracaja
	# lisa od zagrody. Losujemy przy KAZDYM podejsciu, wiec nawet najlepsza
	# obrona kiedys przepusci. Wczesniej obrona rozciagala przerwe miedzy
	# wizytami, co przy cenie 600 zl bylo za malo odczuwalne.
	if randf() < state.fox_block_chance():
		out["fox_blocked"] = int(out["fox_blocked"]) + 1
		return

	var share := randf_range(float(fox.get("min_share", 0.2)), float(fox.get("max_share", 0.9)))
	state.fox_pending = clampi(int(round(state.chickens.size() * share)), 1, state.chickens.size() - 1)
	# Lis, ktory podchodzi pod nieobecnosc gracza, NIE zabiera po cichu.
	# Zostaje na wybiegu i czeka — gracz zastanie go po powrocie i bedzie mial
	# te same kilka sekund na reakcje co zwykle. Wczesniej strata liczyla sie
	# od razu i wlasciciel przez cztery wersje nie zobaczyl lisa ani razu.
	state.fox_visit_left = maxf(1.0, float(fox.get("visit_seconds", 7.0)))
	out["fox_arrived"] = int(out["fox_arrived"]) + 1


## Koniec wizyty: lis zabiera upatrzone kury, o ile nikt go nie przegonil.
static func _fox_takes(state: FarmState, out: Dictionary, budget: int) -> void:
	var taken := mini(state.fox_pending, maxi(0, budget - _losses(out)))
	taken = mini(taken, maxi(0, state.chickens.size() - 1))
	state.fox_pending = 0
	if taken <= 0:
		return
	# Czesc lupu lis wynosi, ale reszte zagryza na miejscu. Zwloki i krew maja
	# zostac na wybiegu na dlugo — bez tego po napasci nie ma po niej sladu
	# i gracz, ktory akurat nie patrzyl, nie wie, co sie stalo.
	var share := clampf(float(GameData.balance().get("fox", {}).get("carcass_share", 0.5)), 0.0, 1.0)
	var left_behind := clampi(int(round(taken * share)), 1, taken)
	for i in taken:
		var index := randi() % state.chickens.size()
		if i < left_behind:
			_kill_hen(state, index, "fox")
		else:
			state.chickens.remove_at(index)
	out["fox_took"] = int(out["fox_took"]) + taken


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
				# prosto do magazynu, zamiast przepadac albo blokowac kure.
				state.add_egg(hen.breed_id)
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
