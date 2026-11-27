class_name FarmState
extends RefCounted
## Stan gospodarstwa. Czyste dane: bez wezlow, bez UI, bez dostepu do plikow.

## Gotowka w zlotowkach. Ulamkowa, bo jajko moze kosztowac 40 groszy.
var money: float = 0.0
## Jaja zebrane do magazynu, policzone wedlug rasy kury, ktora je zniosla:
## {"leghorn": 12, "cemani": 2}. Rasa decyduje o cenie sprzedazy.
var eggs: Dictionary = {}
## Metryka wieku jaj: rasa -> lista wiaderek [sztuk, wiek w sekundach
## REALNYCH], od najstarszego. Liczba sztuk w `eggs` zawsze zgadza sie
## z suma wiaderek — pilnuja tego `add_egg`, `take_eggs` i `age_eggs`.
var egg_ages: Dictionary = {}
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
## Ile sekund gry minelo bez lisa i bez choroby, osobno dla kazdego zdarzenia.
## Szansa na zdarzenie rosnie razem z tym licznikiem, a licznik idzie do zapisu,
## zeby granie po minucie z doskoku tez sie liczylo. Klucze: "fox", "disease".
var event_dry: Dictionary = {}
## Trwajaca wizyta lisa: ile sekund jeszcze biega po wybiegu. Dopoki trwa,
## kury sa tylko zagrozone — zabiera je dopiero na koniec wizyty. Dzieki temu
## gracz, ktory akurat patrzy na ekran, ma szanse go przegonic.
## Wizyta lisa, liczona w sekundach REALNYCH. Dotad czesc pol liczyla czas
## gry, a czesc zegarek, i na tym sie przewrocilismy — tutaj wszystko, co
## dotyczy lisa i choroby, jest w czasie realnym.
var fox_visit_left: float = 0.0
## Lis czai sie w krzakach i idzie pod plot: ile sekund REALNYCH do chwili,
## w ktorej stanie pod plotem i plot rozstrzygnie, czy wejdzie. 0 = nie ma
## lisa w krzakach. Nie idzie do zapisu, tak samo jak trwajaca wizyta.
var fox_lurk_left: float = 0.0
## Ile kur lis zamierza jeszcze porwac w tej wizycie i ile sekund zostalo do
## nastepnej. Zabija po jednej przez cala wizyte, a nie wszystkie na koniec.
var fox_kill_left: int = 0
var fox_kill_timer: float = 0.0
## Co ile sekund lis siega po kolejna kure w tej wizycie.
var fox_kill_pace: float = 1.0
## Ile jeszcze trafien palcem trzeba, zeby go przegonic.
var fox_taps_left: int = 0
## 13.1.1: ile trafien w lisa czajacego sie w krzakach (0 = jeszcze nikt nie
## kliknal). Nie zapisujemy - czajenie trwa kilkanascie sekund.
var fox_lurk_taps: int = 0
## 13.0.2 (wlasciciel 27.11): ZYCIE LISA. fox_taps_left to teraz jego punkty
## zycia (palec zabiera 1, pies wiecej), fox_hp_max - ile mial na poczatku.
var fox_hp_max: int = 0
## 13.0.2: piec psow. Przy tej wizycie lisa pies nie pomaga: stary gluchy
## kundel go nie uslyszal albo maly tchorzliwy uciekl (bez zapisu).
var dog_off_visit: bool = false
## Ile sekund jeszcze pogoni, zanim tchorzliwy kundel ucieknie; -1 = nie ucieknie.
var dog_quit_left: float = -1.0


## Losowane przy wejsciu lisa: czy pies go uslyszy i czy nie stchorzy.
func roll_dog_visit() -> void:
	dog_off_visit = false
	dog_quit_left = -1.0
	if dog_level <= 0:
		return
	var cfg := current_building_upgrade("dog")
	dog_off_visit = randf() < float(cfg.get("deaf_chance", 0.0))
	if not dog_off_visit and randf() < float(cfg.get("quit_chance", 0.0)):
		dog_quit_left = float(cfg.get("quit_after", 3.0))


## Losuje zycie lisa: Gauss (hp_mean, hp_sd) przyciety do hp_min..hp_max -
## zwykle przecietny, bardzo slaby albo bardzo mocny rzadko.
func roll_fox_hp() -> void:
	var fox: Dictionary = GameData.balance().get("fox", {})
	var low := int(fox.get("hp_min", 5))
	var high := maxi(low, int(fox.get("hp_max", 50)))
	fox_hp_max = clampi(int(round(randfn(float(fox.get("hp_mean", 20)), float(fox.get("hp_sd", 8))))), low, high)
	fox_taps_left = fox_hp_max


## Ile punktow zycia lisa zabiera jedno udane ugryzienie obecnego psa.
func dog_damage() -> int:
	if dog_level <= 0:
		return 0
	var cfg := current_building_upgrade("dog")
	var low := int(cfg.get("damage_min", 5))
	return randi_range(low, maxi(low, int(cfg.get("damage_max", low))))
## Sekundy uzbierane do nastepnego losowania i znacznik, ze ostatnim razem
## gracz przegonil lisa recznie — wtedy wraca szybciej.
var fox_roll_timer: float = 0.0
var fox_hand_scared: bool = false
## Mnoznik odstepu do nastepnego lisa. Rosnie, gdy pies zagryzie lisa —
## zagryziony nie wraca, a nastepny dlugo sie nie pokazuje.
var fox_next_multiplier: float = 1.0
## Sekundy do nastepnej proby psa.
var dog_timer: float = 0.0
## Ile razy pokazalismy juz ostrzezenie "ta rasa potrzebuje koguta",
## osobno dla kazdej rasy. Po kilku razach gracz wie i okienko tylko
## przeszkadza.
var rooster_hints: Dictionary = {}
## Sekundy REALNE uzbierane do nastepnego rzutu kostka na nowa chorobe
## (rzut co `disease.roll_seconds`).
var disease_timer: float = 0.0
## Ognisko choroby (12.20, wlasciciel 25.11). `outbreak_left` = ile kur
## choroba jeszcze zarazi w tym ognisku; `outbreak_timer` = sekundy REALNE do
## nastepnego zarazenia; `outbreak_dead` = ile kur padlo w tym ognisku
## (do komunikatu na koniec); `outbreak_on` = ognisko trwa (sa chore albo
## zostali kandydaci do zarazenia). `disease_calm` = sekundy REALNE spokoju po
## wygasnieciu ogniska — wtedy kostka nie rzuca.
var outbreak_on: bool = false
var outbreak_left: int = 0
var outbreak_timer: float = 0.0
var outbreak_dead: int = 0
## 12.22: ognisko atakuje JEDNA rase (`outbreak_breed`); inne sa odporne.
## `outbreak_survive` = szansa, ze chory ptak wyzdrowieje (0-30%, losowana
## przy wybuchu); `outbreak_saved` = ilu wyzdrowialo w tym ognisku.
var outbreak_breed: String = ""
var outbreak_survive: float = 0.0
var outbreak_saved: int = 0
var disease_calm: float = 0.0
## Rzez: lis, ktory wszedl na wybieg bez psa, zabija cale stado (12.20).
var fox_massacre: bool = false
## Ile kur lis zabierze, jesli nikt go nie przegoni.
var fox_pending: int = 0
## Poziomy rozbudowy budynkow: kurnik, magazyn i obrona przed lisem.
var coop_level: int = 0
var storage_level: int = 0
var guard_level: int = 0
## Budowy w toku (wlasciciel, 25.11: rozbudowa trwa jak wylęganie, 5 min do
## godziny). Klucz: id budynku ("coop", "storage", "incubator"), wartosc:
## [sekundy REALNE do konca, sekundy realne calej budowy]. W trakcie budowy
## budynek dziala na starym poziomie; nowy wchodzi po skonczeniu.
var construction: Dictionary = {}
## Pies podworzowy. Osobna sciezka od plotu: plot decyduje, czy lis wejdzie,
## pies — jak szybko wyleci i ile zdazy zabrac. Kupiony raz, zostaje.
var dog_level: int = 0
## 13.0 (wlasciciel 26.11): pies zyje ograniczony czas. Wiek i dlugosc zycia
## w sekundach ZEGARA; dlugosc losowana przy zakupie (Gauss w przedziale
## zyje_dni_min..max z data/rozbudowy.json).
var dog_age: float = 0.0
var dog_life: float = 0.0
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
##
## 12.31: kazda rasa, ktora gracz ma w stadzie, w inkubatorze albo wsrod
## piskląt, liczy sie jako zdobyta. Startowe leghorny nigdy nie trafialy na
## liste (nie byly kupione), wiec karta leghorna byla ciemna, choc gracz od
## poczatku je hodowal. Wolane przy nowej grze i przy kazdym odczycie zapisu.
func ensure_starting_unlocks() -> void:
	for hen: Chicken in chickens:
		mark_owned(hen.breed_id)
	for batch: EggBatch in incubating:
		mark_owned(batch.breed_id)
	for chick: Chick in chicks:
		mark_owned(chick.breed_id)


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


func vaccinated_count() -> int:
	var count := 0
	for hen: Chicken in chickens:
		if hen.vaccinated:
			count += 1
	return count


## Ile ZDROWYCH ptakow nie ma szczepienia. Chorych nie liczymy: szczepionka
## nie leczy (wlasciciel 25.11), wiec szczepienie chorej to wyrzucone pieniadze.
func unvaccinated_count() -> int:
	var count := 0
	for hen: Chicken in chickens:
		if not hen.vaccinated and not hen.sick:
			count += 1
	return count


## Szansa na wybuch choroby na GODZINE realna przy danym stadzie. Krzywa
## z `disease.rate_per_hour` — pary [liczba ptakow, szansa na godzine],
## miedzy punktami liniowo, ponizej pierwszego i powyzej ostatniego plasko.
static func disease_rate_per_hour(flock: int) -> float:
	var points: Array = GameData.balance().get("disease", {}).get("rate_per_hour", [])
	if points.is_empty():
		return 0.0
	var first: Array = points[0]
	if float(flock) <= float(first[0]):
		return float(first[1])
	for i in range(1, points.size()):
		var a: Array = points[i - 1]
		var b: Array = points[i]
		if float(flock) <= float(b[0]):
			var span := maxf(0.0001, float(b[0]) - float(a[0]))
			var t := (float(flock) - float(a[0])) / span
			return lerpf(float(a[1]), float(b[1]), t)
	var last: Array = points[points.size() - 1]
	return float(last[1])


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
## Ile dostaje sie za zdrowa dorosla sztuke. Kogut idzie za sell_price razy
## ten sam mnoznik co w kupnie (economy.rooster_price_multiplier) - wlasciciel,
## 24.11: "tak jak w kupnie, dla kazdej rasy adekwatnie". Dzieki temu kogut,
## tak samo jak kura, schodzi za 70% swojej ceny kupna.
static func hen_sell_price(breed_id: String, sick: bool = false, rooster: bool = false) -> float:
	if sick:
		return 0.0
	var price := float(GameData.breed(breed_id).get("sell_price", 0))
	if not rooster:
		return price
	return price * rooster_multiplier()


static func rooster_multiplier() -> float:
	return float(GameData.balance().get("economy", {}).get("rooster_price_multiplier", 2.5))


## Ile kosztuje zakup jednej sztuki. Kogut jest DROZSZY od kury tej samej
## rasy (mnoznik w balance.economy.rooster_price_multiplier): jeden kogut
## obsluguje cale stado swojej rasy, wiec przy cenie kury byl najtanszym
## obowiazkowym zakupem w calej grze.
static func hen_buy_price(breed_id: String, rooster: bool = false) -> float:
	var price := float(GameData.breed(breed_id).get("price", 0))
	if not rooster:
		return price
	return price * rooster_multiplier()


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


## Do ilu sekund realnych jaja z jednego "wiaderka" sa traktowane razem.
## Godzina wystarcza: przy szesciogodzinnym terminie przydatnosci daje to
## najwyzej siedem wiaderek na rase, a nie tysiac wpisow po jednym jaju.
const EGG_BUCKET_SECONDS := 3600.0


## Limit jaj w magazynie. Bez niego gra przechodzila sie sama: wystarczylo
## wrocic po dobie i zastac gore jaj. Teraz trzeba zajrzec i sprzedac.
func egg_capacity() -> int:
	var storage: Dictionary = GameData.balance().get("buildings", {}).get("storage", {})
	if storage_level <= 0:
		return maxi(1, int(storage.get("egg_capacity", 200)))
	return maxi(1, int(current_building_upgrade("storage").get(
			"egg_capacity", storage.get("egg_capacity", 200))))


## Ile jaj jeszcze sie zmiesci.
func egg_room() -> int:
	return maxi(0, egg_capacity() - egg_count())


## Dodaje jaja do magazynu i zwraca, ile sie faktycznie zmiescilo.
## Nadmiar przepada — i o to chodzi.
func add_egg(breed_id: String, count: int = 1) -> int:
	count = mini(count, egg_room())
	if count <= 0:
		return 0
	eggs[breed_id] = int(eggs.get(breed_id, 0)) + count
	# Rownolegle prowadzimy metryke wieku, zeby wiedziec, ktore jaja sie
	# zestarzaly. Najmlodsze wiaderko dobieramy, dopoki nie ma godziny.
	var buckets: Array = egg_ages.get(breed_id, [])
	if buckets.is_empty() or float(buckets[buckets.size() - 1][1]) >= EGG_BUCKET_SECONDS:
		buckets.append([count, 0.0])
	else:
		buckets[buckets.size() - 1][0] = int(buckets[buckets.size() - 1][0]) + count
	egg_ages[breed_id] = buckets
	return count


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
	# Sprzedajemy NAJSTARSZE jaja najpierw — i tak robi sie w prawdziwym
	# gospodarstwie, a przy okazji gracz nie traci swiezych przez to, ze
	# w magazynie lezy stara partia.
	var left := taken
	var buckets: Array = egg_ages.get(breed_id, [])
	while left > 0 and not buckets.is_empty():
		var in_bucket := int(buckets[0][0])
		if in_bucket > left:
			buckets[0][0] = in_bucket - left
			left = 0
		else:
			left -= in_bucket
			buckets.remove_at(0)
	if buckets.is_empty():
		egg_ages.erase(breed_id)
	else:
		egg_ages[breed_id] = buckets
	return taken


## Postarza jaja o `real` sekund i usuwa te, ktore przelezaly termin.
## Zwraca, ile sztuk sie zmarnowalo. Dzieki temu zostawiona na noc gra nie
## wita gracza magazynem pelnym jaj sprzed doby.
func age_eggs(real: float, spoil_seconds: float) -> int:
	var spoiled := 0
	for breed_id: String in egg_ages.keys():
		var buckets: Array = egg_ages[breed_id]
		var kept: Array = []
		for bucket: Array in buckets:
			var age := float(bucket[1]) + real
			if age >= spoil_seconds:
				spoiled += int(bucket[0])
				eggs[breed_id] = maxi(0, int(eggs.get(breed_id, 0)) - int(bucket[0]))
				if int(eggs.get(breed_id, 0)) <= 0:
					eggs.erase(breed_id)
			else:
				kept.append([int(bucket[0]), age])
		if kept.is_empty():
			egg_ages.erase(breed_id)
		else:
			egg_ages[breed_id] = kept
	return spoiled


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


## Nastepny poziom budynku albo inkubatora - jeden odczyt dla wszystkich.
func upgrade_entry(building_id: String) -> Dictionary:
	if building_id == "incubator":
		return next_incubator_upgrade()
	return next_building_upgrade(building_id)


## Ile sekund REALNYCH trwa budowa nastepnego poziomu (0 = od razu).
func build_seconds(building_id: String) -> float:
	return maxf(0.0, float(upgrade_entry(building_id).get("build_minutes", 0.0)) * 60.0)


func is_building(building_id: String) -> bool:
	return construction.has(building_id)


## Sekundy realne do konca budowy (0, gdy nic sie nie buduje).
func construction_left(building_id: String) -> float:
	var job: Array = construction.get(building_id, [])
	return float(job[0]) if job.size() >= 2 else 0.0


## Postep budowy 0..1.
func construction_progress(building_id: String) -> float:
	var job: Array = construction.get(building_id, [])
	if job.size() < 2 or float(job[1]) <= 0.0:
		return 0.0
	return clampf(1.0 - float(job[0]) / float(job[1]), 0.0, 1.0)


## Wspolny odczyt poziomu budynku: 0 to stan poczatkowy.
func building_level(building_id: String) -> int:
	match building_id:
		"coop":
			return coop_level
		"storage":
			return storage_level
		"incubator":
			# Inkubator ma wlasne pole, bo rozbudowe trzyma w balance.incubator,
			# a nie w balance.buildings. Czyta sie go jednak tak samo jak reszte —
			# bez tego scena nie wiedziala, jaki wyglad budynku pokazac.
			return incubator_level
		"guard":
			return guard_level
		"dog":
			return dog_level
	return 0


func set_building_level(building_id: String, level: int) -> void:
	match building_id:
		"coop":
			coop_level = level
		"storage":
			storage_level = level
		"incubator":
			incubator_level = level
		"guard":
			guard_level = level
		"dog":
			var bought := level > dog_level
			dog_level = level
			if bought:
				roll_dog_life()


## Losuje dlugosc zycia obecnego psa: rozklad Gaussa ze srodkiem w polowie
## przedzialu i odchyleniem 1/4 jego szerokosci, przyciety do przedzialu.
func roll_dog_life() -> void:
	dog_age = 0.0
	dog_life = 0.0
	if dog_level <= 0:
		return
	var ups: Array = GameData.balance().get("buildings", {}).get("dog", {}).get("upgrades", [])
	if ups.is_empty():
		return
	var cfg: Dictionary = ups[mini(dog_level, ups.size()) - 1]
	var low := float(cfg.get("life_days_min", 10.0))
	var high := maxf(low, float(cfg.get("life_days_max", 10.0)))
	var days := clampf(randfn((low + high) / 2.0, maxf(0.01, (high - low) / 4.0)), low, high)
	dog_life = days * 86400.0


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


## Pasza do kupienia: `option` to numer przycisku z data/rozbudowy.json
## ("pasza_do_kupienia": worek 20 kg, big-bag 500 kg). Cena za kilogram zalezy
## od WIELKOSCI opakowania (znizka_proc), nie od magazynu (wlasciciel 25.11).
func feed_pack(option: int = 0) -> Dictionary:
	var economy: Dictionary = GameData.balance().get("economy", {})
	var options: Array = economy.get("feed_options", [])
	var size := maxf(1.0, float(economy.get("feed_pack_size", 20)))
	var per_kg := float(economy.get("feed_price_kg", 2.0))
	var unit := "worek"
	var discount := 0.0
	if not options.is_empty():
		var opt: Dictionary = options[clampi(option, 0, options.size() - 1)]
		size = maxf(1.0, float(opt.get("size", size)))
		unit = String(opt.get("unit", unit))
		per_kg = float(opt.get("per_kg", per_kg))
		discount = float(opt.get("discount", 0.0))
	return {
		"size": size,
		# Do pelnych groszy, zeby cena na przycisku i pobrana kwota sie zgadzaly.
		"price": round(size * per_kg * 100.0) / 100.0,
		"per_kg": per_kg,
		"discount": discount,
		"unit": unit,
	}


## Ile jest przyciskow paszy (rodzajow opakowan).
static func feed_option_count() -> int:
	return maxi(1, (GameData.balance().get("economy", {}).get("feed_options", []) as Array).size())


## Ktore jaja pojda w nastepnej partii sprzedazy: NAJSTARSZE, niezaleznie od
## rasy - wlasnie one najszybciej zgnija. Zwraca {rasa: sztuk}. Nic nie zmienia.
func oldest_eggs(count: int) -> Dictionary:
	var out := {}
	# Kursor po wiaderkach kazdej rasy: [indeks wiaderka, zabrane z niego].
	var cursor := {}
	var spare := {}
	for breed_id: String in eggs:
		cursor[breed_id] = [0, 0]
		# Jaja bez metryki wieku (stare zapisy) traktujemy jak najswiezsze.
		var in_buckets := 0
		for bucket: Array in egg_ages.get(breed_id, []):
			in_buckets += int(bucket[0])
		spare[breed_id] = maxi(0, int(eggs[breed_id]) - in_buckets)
	var left := count
	while left > 0:
		var best := ""
		var best_age := -1.0
		for breed_id: String in cursor:
			var buckets: Array = egg_ages.get(breed_id, [])
			var at: Array = cursor[breed_id]
			if int(at[0]) < buckets.size():
				var age := float(buckets[int(at[0])][1])
				if age > best_age:
					best_age = age
					best = breed_id
			elif int(spare[breed_id]) > 0 and best_age < 0.0:
				best = breed_id
				best_age = 0.0
		if best.is_empty():
			break
		var buckets: Array = egg_ages.get(best, [])
		var at: Array = cursor[best]
		var take := 0
		if int(at[0]) < buckets.size():
			var room := int(buckets[int(at[0])][0]) - int(at[1])
			take = mini(room, left)
			at[1] = int(at[1]) + take
			if int(at[1]) >= int(buckets[int(at[0])][0]):
				at[0] = int(at[0]) + 1
				at[1] = 0
		else:
			take = mini(int(spare[best]), left)
			spare[best] = int(spare[best]) - take
		out[best] = int(out.get(best, 0)) + take
		left -= take
	return out


## Wartosc zestawu jaj {rasa: sztuk}.
static func eggs_worth(lot: Dictionary) -> float:
	var total := 0.0
	for breed_id: String in lot:
		total += float(lot[breed_id]) * egg_value(breed_id)
	return total


## Ile razy rzadziej przychodzi lis dzieki plotowi albo psu.
## Szansa, ze obrona zawroci lisa od zagrody, zanim ten w ogole wejdzie.
## Losowana przy kazdym podejsciu, wiec nawet pelna obrona kiedys przepusci.
## Bezpiecznik: lis nie zostanie na wybiegu dluzej, nawet gdyby cos poszlo
## nie tak z licznikiem zabitych kur.
## Ile sekund realnych lis spedzi w krzakach i w drodze pod plot:
## losowo lurk_min..lurk_max plus approach_seconds. 0 wylacza te faze.
func fox_lurk_seconds() -> float:
	var fox: Dictionary = GameData.balance().get("fox", {})
	var low := maxf(0.0, float(fox.get("lurk_min_seconds", 10.0)))
	var high := maxf(low, float(fox.get("lurk_max_seconds", 30.0)))
	var walk := maxf(0.0, float(fox.get("approach_seconds", 4.0)))
	if high + walk <= 0.0:
		return 0.0
	return randf_range(low, high) + walk


func fox_visit_seconds() -> float:
	return maxf(30.0, float(GameData.balance().get("fox", {}).get("visit_max_minutes", 10.0)) * 60.0)


## Co ile sekund pies rzuca kostka, probujac wygonic lisa.
func dog_interval() -> float:
	if dog_level <= 0:
		return 0.0
	return maxf(1.0, float(current_building_upgrade("dog").get("interval", 10.0)))


## Szansa pojedynczej proby psa. Probuje do skutku, wiec realna skutecznosc
## rosnie z kazdym podejsciem.
func dog_chance() -> float:
	if dog_level <= 0:
		return 0.0
	return clampf(float(current_building_upgrade("dog").get("chance", 0.0)), 0.0, 1.0)


## Szansa, ze udana proba konczy sie ZAGRYZIENIEM lisa, a nie przegonieniem.
func dog_kill_chance() -> float:
	if dog_level <= 0:
		return 0.0
	return clampf(float(current_building_upgrade("dog").get("kill_chance", 0.0)), 0.0, 1.0)


func fox_block_chance() -> float:
	var upgrade := current_building_upgrade("guard")
	# Gorny poziom daje pelne 100%, czyli wylacza lisa calkowicie — tak zyczyl
	# sobie wlasciciel. Wczesniej sufit wynosil 0,99.
	return clampf(float(upgrade.get("block_chance", 0.0)), 0.0, 1.0)
