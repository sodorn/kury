class_name Chick
extends RefCounted
## Pisklę rosnace w dorosla kure. Czyste dane, bez wezlow.

var breed_id: String = ""
## Sekundy wzrostu, ktore juz uplynely.
var grown: float = 0.0
## Plec ustalana przy wykluciu. Jak w naturze: z jaj wykluwa sie mniej
## wiecej tyle samo kogutkow co kurek (incubator.rooster_share, 0.5).
## Do 12.17 z inkubatora wychodzily same kury.
var rooster: bool = false


static func create(breed_id: String, grown: float = 0.0, rooster: bool = false) -> Chick:
	var chick := Chick.new()
	chick.breed_id = breed_id
	chick.grown = grown
	chick.rooster = rooster
	return chick


## Losuje plec pisklecia z incubator.rooster_share.
static func roll_rooster() -> bool:
	var share := float(GameData.balance().get("incubator", {}).get("rooster_share", 0.5))
	return randf() < clampf(share, 0.0, 1.0)


## Ile sekund pisklę rosnie do dorosłosci.
func total_seconds() -> float:
	return float(GameData.breed(breed_id).get("grow_seconds", 240.0))


## Postep wzrostu, 0.0 - 1.0.
func progress() -> float:
	var total := total_seconds()
	if total <= 0.0:
		return 1.0
	return clampf(grown / total, 0.0, 1.0)
