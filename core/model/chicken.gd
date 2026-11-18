class_name Chicken
extends RefCounted
## Pojedyncza kura. Czyste dane, bez wezlow.

var breed_id: String = ""
## Sekundy, ktore uplynely od ostatnio zniesionego jaja.
var since_last_egg: float = 0.0
## Czy kura jest chora. Chora nie znosi jaj i po kilku minutach pada.
var sick: bool = false
## Sekundy od zachorowania. Liczone tylko gdy `sick`.
var sick_seconds: float = 0.0
## Szczepienie chroni do konca zycia, ale tylko kury zyjace w chwili
## szczepienia — mlode wyklute pozniej trzeba zaszczepic osobno.
var vaccinated: bool = false


static func create(breed_id: String, since_last_egg: float = 0.0) -> Chicken:
	var hen := Chicken.new()
	hen.breed_id = breed_id
	hen.since_last_egg = since_last_egg
	return hen


## Postep do nastepnego jaja, 0.0 - 1.0 (do paska w UI).
func progress() -> float:
	if sick:
		return 0.0
	var seconds := float(GameData.breed(breed_id).get("egg_seconds", 0))
	if seconds <= 0.0:
		return 0.0
	return clampf(since_last_egg / seconds, 0.0, 1.0)


## Ile sekund zostalo choremu zwierzeciu do padniecia.
func seconds_to_death() -> float:
	if not sick:
		return 0.0
	var minutes := float(GameData.balance().get("disease", {}).get("death_minutes", 7.0))
	return maxf(0.0, minutes * 60.0 - sick_seconds)


func to_dict() -> Dictionary:
	return {
		"breed": breed_id,
		"egg": since_last_egg,
		"sick": sick,
		"sick_s": sick_seconds,
		"vax": vaccinated,
	}


static func from_dict(data: Dictionary) -> Chicken:
	var hen := Chicken.create(String(data.get("breed", "")), float(data.get("egg", 0.0)))
	hen.sick = bool(data.get("sick", false))
	hen.sick_seconds = float(data.get("sick_s", 0.0))
	hen.vaccinated = bool(data.get("vax", false))
	return hen
