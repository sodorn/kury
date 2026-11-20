class_name FarmState
extends RefCounted
## Stan gospodarstwa. Czyste dane: bez wezlow, bez UI, bez dostepu do plikow.

## Gotowka w zlotowkach. Ulamkowa, bo jajko moze kosztowac 40 groszy.
var money: float = 0.0
## Jaja zebrane do magazynu, policzone wedlug rasy kury, ktora je zniosla:
## {"leghorn": 12, "cemani": 2}. Rasa decyduje o cenie sprzedazy.
var eggs: Dictionary = {}
## Jaja lezace na wybiegu, w kolejnosci zniesienia. Kazdy wpis to id rasy.
var eggs_on_ground: Array[String] = []
## Pasza w kilogramach; ulamkowa, bo zuzywa sie w sposob ciagly.
var feed: float = 0.0
## Liczba dni gospodarstwa — rosnie z czasem gry, takze offline.
var days: int = 0
## Ulamek biezacego dnia (0.0 - 1.0); trzymany osobno, zeby dni liczyly sie
## tak samo przy grze na zywo i przy nadrabianiu czasu.
var day_fraction: float = 0.0

## Cale stado: kury i koguty razem. `Chicken.is_rooster` rozstrzyga, kto jest kim.
var chickens: Array[Chicken] = []
var incubating: Array[EggBatch] = []
var chicks: Array[Chick] = []
## Zwloki lezace na wybiegu, az sie rozloza.
var corpses: Array[Corpse] = []
## Rasy, ktore gracz odblokowal i moze kupowac.
var unlocked_breeds: Array[String] = []

## Sekundy bez paszy. Po przekroczeniu `hunger.grace_minutes` kury zaczynaja padac.
var hunger_seconds: float = 0.0
## Odliczanie do nastepnej smierci z glodu, zeby stado nie padalo naraz.
var hunger_next_death: float = 0.0
## Poziom rozbudowy inkubatora: 0 to stan poczatkowy, dalej wpisy z
## `incubator.upgrades` w balance.json.
var incubator_level: int = 0
## Trwajaca wizyta lisa: ile sekund jeszcze biega po wybiegu. Dopoki trwa,
## kury sa tylko zagrozone — zabiera je dopiero na koniec wizyty. Dzieki temu
## gracz, ktory akurat patrzy na ekran, ma szanse go przegonic.
var fox_visit_left: float = 0.0
## Ile kur lis zabierze, jesli nikt go nie przegoni.
var fox_pending: int = 0
## Poziomy rozbudowy budynkow: kurnik, magazyn i obrona przed lisem.
var coop_level: int = 0
var storage_level: int = 0
var guard_level: int = 0
## Czy gracz widzial juz ekran powitalny. Dzieki temu pokazuje sie raz,
## takze komus, kto zalozyl farme przed jego dodaniem.
var intro_seen: bool = false
## Czy gra jest wygrana i z jakiego powodu ("money" albo "collection").
var won: bool = false
var win_reason: String = ""


## Tworzy stan nowej gry z sekcji "start" pliku data/balance.json.
static func from_start_config(start: Dictionary) -> FarmState:
	var state := FarmState.new()
	state.money = float(start.get("money", 0))
	state.feed = float(start.get("feed", 0))
	for breed_id: String in start.get("hens", []):
		state.chickens.append(Chicken.create(breed_id))
	# Bez koguta stado nie zniesie ani jednego jajka, wiec nowa farma dostaje go
	# razem z kurami. Inaczej gra wygladalaby na zepsuta od pierwszej minuty.
	for breed_id: String in start.get("roosters", []):
		state.chickens.append(Chicken.create_rooster(breed_id))
	var starting_eggs := int(start.get("eggs", 0))
	if starting_eggs > 0 and not state.chickens.is_empty():
		state.eggs[state.chickens[0].breed_id] = starting_eggs
	state.ensure_starting_unlocks()
	return state


## W sklepie stoja wszystkie rasy od pierwszej minuty. Bariera jest cena,
## a nie sztuczny prog — mozesz kupic Ayam Cemani na starcie, jesli tylko
## uzbierasz 8 tysiecy.
##
## Lista `unlocked_breeds` sluzy teraz do czego innego: pamieta, ktore rasy
## gracz juz mial. Dzieki temu okienko z historia rasy pokazuje sie raz,
## przy pierwszym zakupie, i nie wyskakuje przy kazdej kolejnej sztuce.
func ensure_starting_unlocks() -> void:
	pass


## Czy gracz mial juz kiedys kure tej rasy.
func has_ever_owned(breed_id: String) -> bool:
	return unlocked_breeds.has(breed_id)


func mark_owned(breed_id: String) -> void:
	if not unlocked_breeds.has(breed_id):
		unlocked_breeds.append(breed_id)


## Cale stado razem z kogutami. Tyle ptakow je pasze, tyle zajmuje miejsc
## w kurniku i tyle lis ma do wyboru.
func hen_count() -> int:
	return chickens.size()


## Ile w stadzie jest kur, a ile kogutow.
func laying_hen_count() -> int:
	var count := 0
	for bird: Chicken in chickens:
		if not bird.is_rooster:
			count += 1
	return count


func rooster_count() -> int:
	return chickens.size() - laying_hen_count()


## Czy na farmie jest kogut tej rasy. Bez niego kury tej rasy nie znosza jaj.
## Chory kogut dalej sie liczy — choruje, ale zyje.
func has_rooster(breed_id: String) -> bool:
	for bird: Chicken in chickens:
		if bird.is_rooster and bird.breed_id == breed_id:
			return true
	return false


## Rasy, ktore maja kury, ale nie maja koguta — czyli stoja bezproduktywnie.
func breeds_without_rooster() -> Array[String]:
	var missing: Array[String] = []
	for bird: Chicken in chickens:
		if bird.is_rooster or missing.has(bird.breed_id):
			continue
		if not has_rooster(bird.breed_id):
			missing.append(bird.breed_id)
	return missing


## Ile sztuk kazdej rasy jest w stadzie, bez kogutow: {"leghorn": 3, "cemani": 1}.
func hens_by_breed() -> Dictionary:
	var counts := {}
	for bird: Chicken in chickens:
		if bird.is_rooster:
			continue
		counts[bird.breed_id] = int(counts.get(bird.breed_id, 0)) + 1
	return counts


## Ile sztuk danej rasy i danej plci; `only_healthy` pomija chore.
func hens_of_breed(breed_id: String, only_healthy: bool = false,
		roosters: bool = false) -> int:
	var count := 0
	for bird: Chicken in chickens:
		if bird.breed_id != breed_id or bird.is_rooster != roosters:
			continue
		if only_healthy and bird.sick:
			continue
		count += 1
	return count


func sick_count() -> int:
	var count := 0
	for hen: Chicken in chickens:
		if hen.sick:
			count += 1
	return count


func unvaccinated_count() -> int:
	var count := 0
	for hen: Chicken in chickens:
		if not hen.vaccinated:
			count += 1
	return count


func owns_breed(breed_id: String) -> bool:
	for hen: Chicken in chickens:
		if hen.breed_id == breed_id:
			return true
	return false


## Zostawione dla UI: w sklepie nic juz nie jest zablokowane.
func is_unlocked(_breed_id: String) -> bool:
	return true


## Ile czasu gry uplynelo od zalozenia farmy, w sekundach. Liczone z licznika
## dni, wiec nie wymaga osobnego pola w zapisie. Lis i choroba daja farmie
## spokoj przez pierwsze pol godziny i wlasnie to tu sprawdzaja.
func played_seconds() -> float:
	var day_seconds := float(GameData.balance().get("day", {}).get("seconds", 600.0))
	return (float(days) + day_fraction) * day_seconds


## Czy gracz ma po jednej kurze kazdej rasy w grze.
func has_full_collection() -> bool:
	for breed: Dictionary in GameData.breeds():
		if not owns_breed(String(breed.get("id", ""))):
			return false
	return true


## Kwota, jaka skup placi za kure. Cena z breeds.json to 70% ceny zakupu,
## wiec odsprzedanie kupionej kury zawsze jest strata — zarabia sie na
## odchowanych mlodych, nie na obracaniu tym samym ptakiem.
## Chorej kury skup nie przyjmuje w ogole — trzeba ja wyleczyc albo ubic.
## Parametr `sick` zostaje, zeby stare wywolania nadal sie kompilowaly, ale
## zwraca teraz zero zamiast ulamka ceny.
static func hen_sell_price(breed_id: String, sick: bool = false) -> float:
	if sick:
		return 0.0
	return float(GameData.breed(breed_id).get("sell_price", 0))


static func egg_value(breed_id: String) -> float:
	return float(GameData.breed(breed_id).get("egg_value", 0.0))


## Ile zebranych jaj lezy w magazynie, razem.
func egg_count() -> int:
	var total := 0
	for count: int in eggs.values():
		total += count
	return total


## Laczna wartosc zebranych jaj w zlotowkach.
func eggs_value() -> float:
	var total := 0.0
	for breed_id: String in eggs:
		total += int(eggs[breed_id]) * egg_value(breed_id)
	return total


func add_egg(breed_id: String, count: int = 1) -> void:
	eggs[breed_id] = int(eggs.get(breed_id, 0)) + count


## Zabiera `count` jaj danej rasy z magazynu. Zwraca, ile udalo sie zabrac.
func take_eggs(breed_id: String, count: int) -> int:
	var have := int(eggs.get(breed_id, 0))
	var taken := mini(have, count)
	if taken <= 0:
		return 0
	if have - taken <= 0:
		eggs.erase(breed_id)
	else:
		eggs[breed_id] = have - taken
	return taken


## Ile paszy zjada cale stado w ciagu minuty. Kazda kura je tyle samo,
## niezaleznie od rasy; pisklęta jedza polowe porcji doroslej kury.
func feed_per_minute() -> float:
	var economy: Dictionary = GameData.balance().get("economy", {})
	var per_hen := float(economy.get("feed_per_hen_minute", 0.085))
	var chick_share := float(economy.get("chick_feed_multiplier", 0.5))
	return chickens.size() * per_hen + chicks.size() * per_hen * chick_share


## Mnoznik predkosci inkubatora. Kury jedwabiste slyna z tego, ze chetnie
## siedza na jajach — w grze przyspieszaja wykluwanie.
func incubation_speed() -> float:
	var bonus := 0.0
	for hen: Chicken in chickens:
		bonus += float(GameData.breed(hen.breed_id).get("incubation_bonus", 0.0))
	return 1.0 + minf(bonus, 1.5)


## Ile miejsc ma inkubator przy obecnym poziomie rozbudowy.
func incubator_slots() -> int:
	var incubator: Dictionary = GameData.balance().get("incubator", {})
	var upgrades: Array = incubator.get("upgrades", [])
	if incubator_level <= 0 or upgrades.is_empty():
		return int(incubator.get("slots", 3))
	var index := mini(incubator_level, upgrades.size()) - 1
	return int(Dictionary(upgrades[index]).get("slots", incubator.get("slots", 3)))


## Opis nastepnej rozbudowy inkubatora albo pusty slownik, gdy to juz maksimum.
func next_incubator_upgrade() -> Dictionary:
	var upgrades: Array = GameData.balance().get("incubator", {}).get("upgrades", [])
	if incubator_level >= upgrades.size():
		return {}
	return upgrades[incubator_level]


# --- budynki ------------------------------------------------------------


## Wspolny odczyt poziomu budynku: 0 to stan poczatkowy.
func building_level(building_id: String) -> int:
	match building_id:
		"coop":
			return coop_level
		"storage":
			return storage_level
		"guard":
			return guard_level
	return 0


func set_building_level(building_id: String, level: int) -> void:
	match building_id:
		"coop":
			coop_level = level
		"storage":
			storage_level = level
		"guard":
			guard_level = level


## Opis nastepnego ulepszenia budynku albo pusty slownik, gdy to juz maksimum.
func next_building_upgrade(building_id: String) -> Dictionary:
	var upgrades: Array = GameData.balance().get("buildings", {}) \
			.get(building_id, {}).get("upgrades", [])
	var level := building_level(building_id)
	if level >= upgrades.size():
		return {}
	return upgrades[level]


## Wpis opisujacy obecny poziom budynku; pusty przy poziomie poczatkowym.
func current_building_upgrade(building_id: String) -> Dictionary:
	var upgrades: Array = GameData.balance().get("buildings", {}) \
			.get(building_id, {}).get("upgrades", [])
	var level := building_level(building_id)
	if level <= 0 or upgrades.is_empty():
		return {}
	return upgrades[mini(level, upgrades.size()) - 1]


## Ile kur miesci kurnik. Liczy sie stado razem z tym, co dopiero dorasta.
func coop_capacity() -> int:
	var coop: Dictionary = GameData.balance().get("buildings", {}).get("coop", {})
	var upgrade := current_building_upgrade("coop")
	if upgrade.is_empty():
		return int(coop.get("capacity", 15))
	return int(upgrade.get("capacity", coop.get("capacity", 15)))


## Ile miejsc w kurniku jest zajete. Licza sie wylacznie dorosle kury —
## pisklęta siedza jeszcze przy inkubatorze. Gdy zabraknie miejsca, podrosniete
## pisklę po prostu czeka, az gracz zwolni kojec.
func coop_occupied() -> int:
	return chickens.size()


func coop_has_room(extra: int = 1) -> bool:
	return coop_occupied() + extra <= coop_capacity()


## Ptaki, ktore sa juz w drodze: jaja w inkubatorze i pisklęta na odchowie.
## Kazde z nich bedzie chcialo miejsca w kurniku.
func coop_reserved() -> int:
	return chicks.size() + incubating.size()


## Ile jeszcze ptakow zmiesci sie w kurniku, liczac to, co juz w drodze.
## Moze wyjsc zero albo mniej, gdy gracz zdazyl dokupic kury.
func coop_free() -> int:
	return coop_capacity() - coop_occupied() - coop_reserved()


## Worek paszy: rozmiar i cena przy obecnym poziomie magazynu.
func feed_pack() -> Dictionary:
	var economy: Dictionary = GameData.balance().get("economy", {})
	var upgrade := current_building_upgrade("storage")
	return {
		"size": float(upgrade.get("pack_size", economy.get("feed_pack_size", 25))),
		"price": float(upgrade.get("pack_price", economy.get("feed_pack_price", 60))),
	}


## Ile razy rzadziej przychodzi lis dzieki plotowi albo psu.
## Szansa, ze obrona zawroci lisa od zagrody, zanim ten w ogole wejdzie.
## Losowana przy kazdym podejsciu, wiec nawet pelna obrona kiedys przepusci.
func fox_block_chance() -> float:
	var upgrade := current_building_upgrade("guard")
	return clampf(float(upgrade.get("block_chance", 0.0)), 0.0, 0.99)
