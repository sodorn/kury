class_name EggBatch
extends RefCounted
## Partia jaj w inkubatorze. Czyste dane, bez wezlow.

var breed_id: String = ""
## Ile piskląt wyklu je sie z tej partii.
var count: int = 1
## Sekundy w inkubatorze.
var elapsed: float = 0.0


static func create(breed_id: String, count: int = 1, elapsed: float = 0.0) -> EggBatch:
	var batch := EggBatch.new()
	batch.breed_id = breed_id
	batch.count = maxi(1, count)
	batch.elapsed = elapsed
	return batch


## Ile sekund trwa wyklucie tej rasy.
func total_seconds() -> float:
	return float(GameData.breed(breed_id).get("incubate_seconds", 180.0))


## Postep wykluwania, 0.0 - 1.0.
func progress() -> float:
	var total := total_seconds()
	if total <= 0.0:
		return 1.0
	return clampf(elapsed / total, 0.0, 1.0)
