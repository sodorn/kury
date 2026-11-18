class_name Simulation
extends RefCounted
## Postep gospodarstwa w czasie.
##
## Cala logika uplywu czasu siedzi w jednej funkcji `advance`. Uzywa jej tick
## na zywo i nadrabianie czasu, kiedy gra byla zamknieta. Dzieki temu gra
## off-line liczy sie dokladnie tak samo jak na ekranie.

## Dlugosc kroku calkowania. Male kroki trzymaja wynik stabilny takze wtedy,
## gdy nadrabiamy wiele godzin naraz.
const STEP := 1.0


## Przesuwa stan o `delta` sekund. Zwraca podsumowanie tego, co sie wydarzylo.
static func advance(state: FarmState, delta: float) -> Dictionary:
	var laid := 0
	var hatched := 0
	var grown := 0
	var days_passed := 0
	var ran_out := false
	var remaining := maxf(delta, 0.0)
	while remaining > 0.0:
		var step := minf(remaining, STEP)
		var result := _step(state, step)
		laid += int(result["laid"])
		hatched += int(result["hatched"])
		grown += int(result["grown"])
		days_passed += int(result["days"])
		ran_out = ran_out or bool(result["ran_out"])
		remaining -= step
	return {
		"eggs_laid": laid,
		"hatched": hatched,
		"grown_up": grown,
		"days_passed": days_passed,
		"out_of_feed": ran_out,
	}


static func _step(state: FarmState, step: float) -> Dictionary:
	var days := _advance_days(state, step)
	var hatched := _advance_incubator(state, step)
	var grown := _advance_chicks(state, step)

	if state.chickens.is_empty():
		return {"laid": 0, "hatched": hatched, "grown": grown, "days": days, "ran_out": false}

	# Bez paszy kury nie znosza i nic nie jedza — stado czeka na karmienie.
	if state.feed <= 0.0:
		state.feed = 0.0
		return {"laid": 0, "hatched": hatched, "grown": grown, "days": days, "ran_out": true}

	state.feed = maxf(0.0, state.feed - state.feed_per_minute() * step / 60.0)

	var capacity := int(GameData.balance().get("run", {}).get("max_eggs_on_ground", 24))
	var laid := 0
	for hen: Chicken in state.chickens:
		var seconds := float(GameData.breed(hen.breed_id).get("egg_seconds", 0.0))
		if seconds <= 0.0:
			continue
		hen.since_last_egg += step
		if hen.since_last_egg < seconds:
			continue
		if state.eggs_on_ground >= capacity:
			# Wybieg pelny: kura czeka ze zniesieniem, postep stoi na maksimum.
			hen.since_last_egg = seconds
			continue
		hen.since_last_egg -= seconds
		state.eggs_on_ground += 1
		laid += 1
	return {"laid": laid, "hatched": hatched, "grown": grown, "days": days, "ran_out": false}


## Licznik dni gospodarstwa. Dlugosc dnia siedzi w balance.json.
static func _advance_days(state: FarmState, step: float) -> int:
	var day_seconds := float(GameData.balance().get("day", {}).get("seconds", 600.0))
	if day_seconds <= 0.0:
		return 0
	state.day_fraction += step / day_seconds
	var passed := int(floor(state.day_fraction))
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


## Pisklęta rosna i dolaczaja do stada jako dorosle kury.
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
	if state.money < int(need.get("money", 0)):
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
