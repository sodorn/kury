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
## Liczba dni gospodarstwa — rosnie z czasem gry, takze offline.
var days: int = 0
## Ulamek biezacego dnia (0.0 - 1.0); trzymany osobno, zeby dni liczyly sie
## tak samo przy grze na zywo i przy nadrabianiu czasu.
var day_fraction: float = 0.0

var chickens: Array[Chicken] = []
var incubating: Array[EggBatch] = []
var chicks: Array[Chick] = []
## Rasy, ktore gracz odblokowal i moze kupowac.
var unlocked_breeds: Array[String] = []


## Tworzy stan nowej gry z sekcji "start" pliku data/balance.json.
static func from_start_config(start: Dictionary) -> FarmState:
	var state := FarmState.new()
	state.money = int(start.get("money", 0))
	state.eggs = int(start.get("eggs", 0))
	state.feed = float(start.get("feed", 0))
	for breed_id: String in start.get("hens", []):
		state.chickens.append(Chicken.create(breed_id))
	state.ensure_starting_unlocks()
	return state


## Rasy bez warunkow odblokowania sa dostepne od poczatku.
func ensure_starting_unlocks() -> void:
	for breed: Dictionary in GameData.breeds():
		var breed_id: String = breed.get("id", "")
		if Dictionary(breed.get("unlock", {})).is_empty() and not unlocked_breeds.has(breed_id):
			unlocked_breeds.append(breed_id)


func hen_count() -> int:
	return chickens.size()


## Ile sztuk kazdej rasy jest w stadzie: {"leghorn": 3, "cemani": 1}.
func hens_by_breed() -> Dictionary:
	var counts := {}
	for hen: Chicken in chickens:
		counts[hen.breed_id] = int(counts.get(hen.breed_id, 0)) + 1
	return counts


func owns_breed(breed_id: String) -> bool:
	for hen: Chicken in chickens:
		if hen.breed_id == breed_id:
			return true
	return false


func is_unlocked(breed_id: String) -> bool:
	return unlocked_breeds.has(breed_id)


## Kwota, jaka sklep placi za kure danej rasy.
static func hen_sell_price(breed_id: String) -> int:
	return int(GameData.breed(breed_id).get("sell_price", 0))


## Laczna wartosc zebranych jaj w monetach.
func eggs_value() -> int:
	if eggs <= 0:
		return 0
	return eggs * average_egg_value()


func average_egg_value() -> int:
	if chickens.is_empty():
		return 1
	var total := 0
	for hen: Chicken in chickens:
		total += int(GameData.breed(hen.breed_id).get("egg_value", 0))
	return maxi(1, int(round(float(total) / chickens.size())))


## Ile paszy zjada cale stado w ciagu minuty (pisklęta jedza polowe tego,
## co dorosla kura tej samej rasy).
func feed_per_minute() -> float:
	var total := 0.0
	for hen: Chicken in chickens:
		total += float(GameData.breed(hen.breed_id).get("feed_per_minute", 0.0))
	for chick: Chick in chicks:
		total += float(GameData.breed(chick.breed_id).get("feed_per_minute", 0.0)) * 0.5
	return total


## Mnoznik predkosci inkubatora. Kury jedwabiste slyna z tego, ze chetnie
## siedza na jajach — w grze przyspieszaja wykluwanie.
func incubation_speed() -> float:
	var bonus := 0.0
	for hen: Chicken in chickens:
		bonus += float(GameData.breed(hen.breed_id).get("incubation_bonus", 0.0))
	return 1.0 + minf(bonus, 1.5)
