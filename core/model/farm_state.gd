class_name FarmState
extends RefCounted
## Stan gospodarstwa. Czyste dane: bez wezlow, bez UI, bez dostepu do plikow.

var money: int = 0
## Jaja zebrane, lezace w magazynie.
var eggs: int = 0
## Jaja zniesione, ale jeszcze nie zebrane z wybiegu.
var eggs_on_ground: int = 0
## Pasza; ulamkowa, bo zuzywa sie w sposob ciagly. UI pokazuje czesc calkowita.
var feed: float = 0.0
var chickens: Array[Chicken] = []


## Tworzy stan nowej gry z sekcji "start" pliku data/balance.json.
static func from_start_config(start: Dictionary) -> FarmState:
	var state := FarmState.new()
	state.money = int(start.get("money", 0))
	state.eggs = int(start.get("eggs", 0))
	state.feed = float(start.get("feed", 0))
	for breed_id: String in start.get("hens", []):
		state.chickens.append(Chicken.create(breed_id))
	return state


func hen_count() -> int:
	return chickens.size()


## Ile sztuk kazdej rasy jest w stadzie: {"leghorn": 3, "cemani": 1}.
func hens_by_breed() -> Dictionary:
	var counts := {}
	for hen: Chicken in chickens:
		counts[hen.breed_id] = int(counts.get(hen.breed_id, 0)) + 1
	return counts


## Kwota, jaka sklep placi za kure danej rasy.
static func hen_sell_price(breed_id: String) -> int:
	return int(GameData.breed(breed_id).get("sell_price", 0))


## Laczna wartosc zebranych jaj w monetach.
func eggs_value() -> int:
	# Jaja roznych ras trafiaja do wspolnego magazynu, wiec licze po sredniej
	# wartosci stada. Przy jednej rasie to po prostu jej cena.
	if eggs <= 0:
		return 0
	return eggs * average_egg_value()


func average_egg_value() -> int:
	if chickens.is_empty():
		return int(GameData.breeds()[0].get("egg_value", 1)) if not GameData.breeds().is_empty() else 1
	var total := 0
	for hen in chickens:
		total += int(GameData.breed(hen.breed_id).get("egg_value", 0))
	return maxi(1, int(round(float(total) / chickens.size())))


## Ile paszy zjada cale stado w ciagu minuty.
func feed_per_minute() -> float:
	var total := 0.0
	for hen in chickens:
		total += float(GameData.breed(hen.breed_id).get("feed_per_minute", 0.0))
	return total
