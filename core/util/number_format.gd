class_name NumberFormat
extends RefCounted
## Formatowanie liczb do wyswietlania.


## 1234567 -> "1 234 567" (spacja nierozdzielajaca jako separator tysiecy).
static func grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = " " + out
		out = digits[i] + out
		count += 1
	return ("-" + out) if value < 0 else out
