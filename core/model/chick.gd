class_name Chick
extends RefCounted
## Pisklę rosnace w dorosla kure. Czyste dane, bez wezlow.

var breed_id: String = ""
## Sekundy wzrostu, ktore juz uplynely.
var grown: float = 0.0


static func create(breed_id: String, grown: float = 0.0) -> Chick:
	var chick := Chick.new()
	chick.breed_id = breed_id
	chick.grown = grown
	return chick


## Ile sekund pisklę rosnie do dorosłosci.
func total_seconds() -> float:
	return float(GameData.breed(breed_id).get("grow_seconds", 240.0))


## Postep wzrostu, 0.0 - 1.0.
func progress() -> float:
	var total := total_seconds()
	if total <= 0.0:
		return 1.0
	return clampf(grown / total, 0.0, 1.0)
