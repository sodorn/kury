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
