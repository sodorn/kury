class_name Corpse
extends RefCounted
## Padla kura lezaca na wybiegu. Po `corpse_seconds` rozklada sie i znika.
##
## Pozycja siedzi w stanie, a nie w scenie, zeby po wylaczeniu i wlaczeniu
## gry zwloki lezaly tam, gdzie gracz je zostawil.

var breed_id: String = ""
var elapsed: float = 0.0
## Miejsce na wybiegu, w pikselach swiata.
var x: float = 0.0
var y: float = 0.0
## Z czego kura padla: "hunger" albo "disease". Tylko do komunikatu w UI.
var cause: String = "hunger"


static func create(breed_id: String, position: Vector2, cause: String = "hunger") -> Corpse:
	var corpse := Corpse.new()
	corpse.breed_id = breed_id
	corpse.x = position.x
	corpse.y = position.y
	corpse.cause = cause
	return corpse


func total_seconds() -> float:
	return float(GameData.balance().get("hunger", {}).get("corpse_seconds", 90.0))


## 0.0 swiezo padla, 1.0 rozlozona do konca.
func progress() -> float:
	var total := total_seconds()
	if total <= 0.0:
		return 1.0
	return clampf(elapsed / total, 0.0, 1.0)


func position() -> Vector2:
	return Vector2(x, y)


func to_dict() -> Dictionary:
	return {"breed": breed_id, "elapsed": elapsed, "x": x, "y": y, "cause": cause}


static func from_dict(data: Dictionary) -> Corpse:
	var corpse := Corpse.new()
	corpse.breed_id = String(data.get("breed", ""))
	corpse.elapsed = float(data.get("elapsed", 0.0))
	corpse.x = float(data.get("x", 0.0))
	corpse.y = float(data.get("y", 0.0))
	corpse.cause = String(data.get("cause", "hunger"))
	return corpse
