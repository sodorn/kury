class_name Chicken
extends RefCounted
## Pojedyncza kura. Czyste dane, bez wezlow.

var breed_id: String = ""
## Sekundy, ktore uplynely od ostatnio zniesionego jaja.
var since_last_egg: float = 0.0


static func create(breed_id: String, since_last_egg: float = 0.0) -> Chicken:
	var hen := Chicken.new()
	hen.breed_id = breed_id
	hen.since_last_egg = since_last_egg
	return hen


## Postep do nastepnego jaja, 0.0 - 1.0 (do paska w UI).
func progress() -> float:
	var seconds := float(GameData.breed(breed_id).get("egg_seconds", 0))
	if seconds <= 0.0:
		return 0.0
	return clampf(since_last_egg / seconds, 0.0, 1.0)
