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
		_step(state, step, summary, loss_budget)
		remaining -= step
	return summary


## Ile kur ubylo ze stada od poczatku tego wywolania `advance`.
static func _losses(out: Dictionary) -> int:
	return int(out["died_hunger"]) + int(out["died_disease"]) + int(out["fox_took"])


static func _step(state: FarmState, step: float, out: Dictionary, loss_budget: int) -> void:
	out["days_passed"] = int(out["days_passed"]) + _advance_days(state, step)
	out["hatched"] = int(out["hatched"]) + _advance_incubator(state, step)
	out["grown_up"] = int(out["grown_up"]) + _advance_chicks(state, step)
	out["rotted"] = int(out["rotted"]) + _advance_corpses(state, step)
	_advance_fox(state, step, out, loss_budget)

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
	_lay_eggs(state, step, out)


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
## szczepienia — trzeba zaszczepic je osobno.
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
	var interval := maxf(1.0, float(hunger.get("death_interval_seconds", 50.0)))
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
	var per_hen_second := float(disease.get("chance_per_hen_hour", 0.05)) / 3600.0

	var index := state.chickens.size() - 1
	while index >= 0:
		var hen: Chicken = state.chickens[index]
		if hen.sick:
			hen.sick_seconds += step
			if hen.sick_seconds >= death_seconds and _losses(out) < budget:
				_kill_hen(state, index, "disease")
				out["died_disease"] = int(out["died_disease"]) + 1
		elif not hen.vaccinated and randf() < per_hen_second * step:
			hen.sick = true
			hen.sick_seconds = 0.0
			out["got_sick"] = int(out["got_sick"]) + 1
		index -= 1


## Lis: przychodzi raz na kilka godzin i porywa czesc stada.
static func _advance_fox(state: FarmState, step: float, out: Dictionary, budget: int) -> void:
	var fox: Dictionary = GameData.balance().get("fox", {})
	if state.fox_timer < 0.0:
		state.reset_fox_timer()
		return
	state.fox_timer -= step
	if state.fox_timer > 0.0:
		return
	state.reset_fox_timer()
	if state.chickens.size() < int(fox.get("min_hens", 5)):
		return
	var share := randf_range(float(fox.get("min_share", 0.2)), float(fox.get("max_share", 0.9)))
	var taken := clampi(int(round(state.chickens.size() * share)), 1, state.chickens.size() - 1)
	taken = mini(taken, maxi(0, budget - _losses(out)))
	if taken <= 0:
		return
	for i in taken:
		# Lis zabiera kury ze soba — zwlok nie ma.
		state.chickens.remove_at(randi() % state.chickens.size())
	out["fox_took"] = int(out["fox_took"]) + taken


## Znoszenie jaj. Chore kury nie znosza, a pelny wybieg wstrzymuje reszte.
static func _lay_eggs(state: FarmState, step: float, out: Dictionary) -> void:
	var capacity := int(GameData.balance().get("run", {}).get("max_eggs_on_ground", 30))
	for hen: Chicken in state.chickens:
		if hen.sick:
			continue
		var seconds := float(GameData.breed(hen.breed_id).get("egg_seconds", 0.0))
		if seconds <= 0.0:
			continue
		hen.since_last_egg += step
		if hen.since_last_egg < seconds:
			continue
		if state.eggs_on_ground.size() >= capacity:
			# Wybieg pelny: kura czeka ze zniesieniem, postep stoi na maksimum.
			hen.since_last_egg = seconds
			continue
		hen.since_last_egg -= seconds
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


## Rasy, ktore wlasnie spelnily warunki odblokowania. Dopisuje je do stanu
## i zwraca ich identyfikatory, zeby gra mogla pokazac komunikat.
static func check_unlocks(state: FarmState) -> Array[String]:
	var fresh: Array[String] = []
	for breed: Dictionary in GameData.breeds():
		var breed_id: String = breed.get("id", "")
		if state.is_unlocked(breed_id):
			continue
		if not meets_unlock(state, breed):
			continue
		state.unlocked_breeds.append(breed_id)
		fresh.append(breed_id)
	return fresh


## Czy gospodarstwo spelnia warunki odblokowania danej rasy.
static func meets_unlock(state: FarmState, breed: Dictionary) -> bool:
	var need: Dictionary = breed.get("unlock", {})
	if need.is_empty():
		return true
	if state.money < float(need.get("money", 0)):
		return false
	if state.days < int(need.get("days", 0)):
		return false
	if state.hen_count() < int(need.get("hens", 0)):
		return false
	if state.feed < float(need.get("feed", 0)):
		return false
	for required_id: String in need.get("breeds", []):
		if not state.owns_breed(required_id):
			return false
	return true


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
