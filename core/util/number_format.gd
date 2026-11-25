class_name NumberFormat
extends RefCounted
## Formatowanie liczb i kwot do wyswietlania.


## 1234567 -> "1 234 567" (spacja nierozdzielajaca jako separator tysiecy).
static func grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "\u00a0" + out
		out = digits[i] + out
		count += 1
	return ("-" + out) if value < 0 else out


## Kwota z waluta: "1 250 zl". Kwoty pokazujemy w pelnych zlotowkach, bez
## groszy — przecinek w liczniku na gornym pasku nie miescil sie w polu,
## a sam w sobie niczego nie wnosil.
static func money(amount: float) -> String:
	return "%s zł" % amount_only(amount)


## Kwota bez waluty, w pelnych zlotowkach. Zaokraglenie w dol, zeby licznik
## nigdy nie pokazal wiecej, niz gracz naprawde ma.
static func amount_only(amount: float) -> String:
	var whole := int(floor(absf(amount)))
	var out := grouped(whole)
	return ("-" + out) if amount < 0.0 else out


## Drobna kwota, np. wartosc jednego jajka. Ponizej zlotowki podajemy ja
## w groszach ("40 gr"), zeby nie trzeba bylo pisac "0,40 zl" — inaczej
## wyszloby z tego "0 zl" i rasy wygladalyby na bezwartosciowe.
static func small_money(amount: float) -> String:
	var grosze := int(round(absf(amount) * 100.0))
	if grosze < 100:
		return "%d gr" % grosze
	if grosze % 100 == 0:
		return money(amount)
	return "%d,%02d zł" % [grosze / 100, grosze % 100]


## Liczba jaj z poprawna polska koncowka: 1 jajo, 2-4 jaja, 5 jaj, 22 jaja,
## 12 jaj, 100 jaj.
static func eggs(count: int) -> String:
	var n := absi(count)
	var word := "jaj"
	if n == 1:
		word = "jajo"
	elif n % 10 >= 2 and n % 10 <= 4 and not (n % 100 >= 12 and n % 100 <= 14):
		word = "jaja"
	return "%s %s" % [grouped(count), word]


## Czas ZIEMSKI (sekundy zegara) po polsku: "45 s", "12 min", "3 godz. 5 min",
## "2 dni 4 godz.". Wlasciciel (25.11): czas w grze podajemy wszedzie
## w czasie zegarowym, nigdy w "dniach gospodarstwa".
static func duration(real_seconds: float) -> String:
	var s := maxf(0.0, real_seconds)
	if s < 90.0:
		return "%d s" % maxi(1, int(ceil(s)))
	if s < 3600.0:
		return "%d min" % int(ceil(s / 60.0))
	if s < 86400.0:
		var h := int(s / 3600.0)
		var m := int(fmod(s, 3600.0) / 60.0)
		return "%d godz." % h if m == 0 else "%d godz. %d min" % [h, m]
	var d := int(s / 86400.0)
	var hours := int(fmod(s, 86400.0) / 3600.0)
	var word := "dzień" if d == 1 else "dni"
	return "%d %s" % [d, word] if hours == 0 else "%d %s %d godz." % [d, word, hours]


## Odliczanie jak na zegarku: "4:07", "1:02:30".
static func clock(real_seconds: float) -> String:
	var s := int(ceil(maxf(0.0, real_seconds)))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


## Waga paszy: "25 kg", "500 kg", "2 t", "1,5 t", "48 t".
static func weight(kg: float) -> String:
	if kg < 1000.0:
		return "%s kg" % grouped(int(round(kg)))
	var tenths := int(round(kg / 100.0))
	if tenths % 10 == 0:
		return "%s t" % grouped(tenths / 10)
	return "%s,%d t" % [grouped(tenths / 10), tenths % 10]


## Jednostka paszy z pliku rozbudow razem z waga: "worek 25 kg",
## "dostawa luzem 2 t". `pack` to wynik FarmState.feed_pack().
static func feed_unit(pack: Dictionary) -> String:
	return "%s %s" % [String(pack.get("unit", "worek")), weight(float(pack.get("size", 25)))]


## Liczba z polska koncowka: count(22, "miejsce", "miejsca", "miejsc")
## -> "22 miejsca", count(55, ...) -> "55 miejsc", count(1, ...) -> "1 miejsce".
static func count(n: int, one: String, few: String, many: String) -> String:
	var a := absi(n)
	var word := many
	if a == 1:
		word = one
	elif a % 10 >= 2 and a % 10 <= 4 and not (a % 100 >= 12 and a % 100 <= 14):
		word = few
	return "%s %s" % [grouped(n), word]
