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


## Kwota z waluta: "12,40 zł", "1 250 zł". Ceny w grze sa ulamkowe (jajko moze
## kosztowac 40 groszy), wiec wszystkie kwoty przechodza przez te funkcje —
## inaczej na ekranie wyladowalyby liczby w rodzaju 1234.5600000001.
static func money(amount: float) -> String:
	return "%s zł" % amount_only(amount)


## Kwota bez waluty. Grosze pokazujemy tylko wtedy, gdy sa niezerowe.
static func amount_only(amount: float) -> String:
	var rounded := roundf(absf(amount) * 100.0) / 100.0
	var whole := int(floor(rounded))
	var cents := int(round((rounded - whole) * 100.0))
	if cents >= 100:
		whole += 1
		cents = 0
	var out := grouped(whole)
	if cents > 0:
		out += ",%02d" % cents
	return ("-" + out) if amount < 0.0 else out
