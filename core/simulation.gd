class_name Simulation
extends RefCounted
## Postep gospodarstwa w czasie.
##
## Cala logika uplywu czasu siedzi w jednej funkcji `advance`. Uzywa jej tick
## na zywo, a od ETAPU 4 tez nadrabianie czasu, kiedy aplikacja byla zamknieta.
## Dzieki temu gra off-line liczy sie dokladnie tak samo jak na ekranie.

## Dlugosc kroku calkowania. Male kroki trzymaja wynik stabilny takze wtedy,
## gdy nadrabiamy wiele godzin naraz.
const STEP := 1.0


## Przesuwa stan o `delta` sekund. Zwraca podsumowanie: ile jaj zniesiono
## i czy zabraklo paszy.
static func advance(state: FarmState, delta: float) -> Dictionary:
	var laid := 0
	var ran_out := false
	var remaining := maxf(delta, 0.0)
	while remaining > 0.0:
		var step := minf(remaining, STEP)
		var result := _step(state, step)
		laid += int(result["laid"])
		ran_out = ran_out or bool(result["ran_out"])
		remaining -= step
	return {"eggs_laid": laid, "out_of_feed": ran_out}


static func _step(state: FarmState, step: float) -> Dictionary:
	if state.chickens.is_empty():
		return {"laid": 0, "ran_out": false}

	# Bez paszy kury nie znosza i nic nie jedza — stado czeka na karmienie.
	if state.feed <= 0.0:
		state.feed = 0.0
		return {"laid": 0, "ran_out": true}

	state.feed = maxf(0.0, state.feed - state.feed_per_minute() * step / 60.0)

	var capacity := int(GameData.balance().get("run", {}).get("max_eggs_on_ground", 24))
	var laid := 0
	for hen in state.chickens:
		var seconds := float(GameData.breed(hen.breed_id).get("egg_seconds", 0.0))
		if seconds <= 0.0:
			continue
		hen.since_last_egg += step
		if hen.since_last_egg < seconds:
			continue
		if state.eggs_on_ground >= capacity:
			# Wybieg pelny: kura czeka z zniesieniem, postep stoi na maksimum.
			hen.since_last_egg = seconds
			continue
		hen.since_last_egg -= seconds
		state.eggs_on_ground += 1
		laid += 1
	return {"laid": laid, "ran_out": false}
