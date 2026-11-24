extends Node
## Autoload "Updater": dowozi nowe wersje gry do JUZ OTWARTYCH kart.
##
## Po co: wlasciciel trzyma gre otwarta godzinami, takze przez noc. Karta
## nie przeladowuje sie sama, wiec po wdrozeniu nowej wersji dalej chodzila
## stara — zrzut z 24 listopada pokazywal ceny sprzed dwoch wydan, choc
## serwer mial juz nowe. Wlasciciel: "zmiany maja byc wypychane do instancji
## gry przy apdejtach".
##
## Jak to dziala:
##   1. Build publikuje obok gry plik version.json z numerem wersji.
##   2. Co CHECK_SECONDS i przy kazdym powrocie do karty gra pobiera ten plik.
##   3. Gdy numer sie rozni: zapis na serwer, krotkie czekanie na odpowiedz
##      serwera i przeladowanie strony pod adresem z numerem nowej wersji.
##   4. Po przeladowaniu gra wie, ze to aktualizacja, a nie nowe wejscie:
##      nie pyta o kod, tylko gra dalej i mowi, do jakiej wersji przeszla.
##
## Bezpiecznik przed petla: gdyby przegladarka mimo wszystko podala stara
## wersje, druga proba dojscia do tej samej wersji juz nie przeladowuje,
## tylko prosi gracza o reczne odswiezenie.
##
## Dziala tylko w przegladarce. Na komputerze i w testach nic nie robi.

const CHECK_SECONDS := 60.0
## Ile najdluzej czekamy, az serwer potwierdzi zapis przed przeladowaniem.
const PUSH_WAIT_SECONDS := 5.0
## Po takim czasie znacznik aktualizacji uznajemy za stary i ignorujemy.
const FLAG_FRESH_SECONDS := 300.0
## Tyle prob dojscia do tej samej wersji, zanim poprosimy o reczne odswiezenie.
const MAX_ATTEMPTS := 2
## Ile czekamy po ostatnim zapisie, zanim przeladujemy strone. Pliki gry
## (user://) przegladarka odklada do swojej bazy ASYNCHRONICZNIE. Sprawdzone
## w Chrome: zapis zrobiony tuz przed przeladowaniem potrafil przepasc.
const DISK_SYNC_SECONDS := 1.5
## Znacznik aktualizacji. W przegladarce siedzi w localStorage, bo ten
## zapisuje sie od razu; plik zostaje dla testow poza przegladarka.
const FLAG_PATH := "user://update.json"
const FLAG_KEY := "kury_update"

## Ta sesja zaczela sie od automatycznej aktualizacji.
var just_updated := false

var _http: HTTPRequest
var _left := CHECK_SECONDS
var _busy := false
var _reloading := false
var _stuck_reported := ""


func _ready() -> void:
	just_updated = _consume_flag()
	if _is_web():
		# Slad w konsoli przegladarki: przy zgloszeniu "mam stara wersje"
		# od razu widac, co gra o sobie mysli.
		print("KURY: wersja %s%s" % [GameData.VERSION, " (po aktualizacji)" if just_updated else ""])
	if not _is_web():
		set_process(false)
		return
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_checked)
	if just_updated:
		# Komunikat dopiero po starcie sceny, inaczej nie ma kto go pokazac.
		_announce_update.call_deferred()


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_left = CHECK_SECONDS
		check_now()


func _notification(what: int) -> void:
	# Powrot do karty to najwazniejszy moment: rano, po nocy w tle.
	if what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN]:
		if _is_web():
			check_now()


func check_now() -> void:
	if _busy or _reloading or _http == null:
		return
	var base := _page_base()
	if base.is_empty():
		return
	_busy = true
	var url := "%sversion.json?t=%d" % [base, int(Time.get_unix_time_from_system())]
	if _http.request(url, ["Cache-Control: no-cache"]) != OK:
		_busy = false


func _on_checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var remote := parse_version(body.get_string_from_utf8())
	var flag := _read_flag()
	match decide(remote, GameData.VERSION, flag):
		"reload":
			_start_reload(remote, flag)
		"stuck":
			if _stuck_reported != remote:
				print("KURY: przegladarka trzyma stara wersje, prosba o reczne odswiezenie")
				_stuck_reported = remote
				Events.notice.emit(tr("UPDATE_STUCK") % remote)


## Co zrobic po odczytaniu wersji z serwera. Czysta funkcja — do testow.
##   "none"   - nic, mamy te sama wersje albo serwer nie odpowiedzial sensownie
##   "reload" - zapisac i przeladowac
##   "stuck"  - juz probowalismy, przegladarka uparcie trzyma stara wersje
static func decide(remote: String, local: String, flag: Dictionary) -> String:
	if remote.is_empty() or remote == local:
		return "none"
	if String(flag.get("to", "")) == remote and int(flag.get("attempts", 0)) >= MAX_ATTEMPTS:
		return "stuck"
	return "reload"


## Wyciaga numer wersji z version.json. Pusty napis, gdy plik jest zly.
static func parse_version(text: String) -> String:
	# JSON.new().parse zamiast JSON.parse_string: ta druga przy zlym tekscie
	# (np. strona bledu 404) sypie bledem do konsoli przegladarki.
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return ""
	return String((json.data as Dictionary).get("version", "")).strip_edges()


func _start_reload(target: String, flag: Dictionary) -> void:
	# Nie przerywamy wpisywania kodu ani wczytywania farmy. Sprobujemy
	# przy kolejnym sprawdzeniu.
	if not Game.is_processing() or Game._force_pull:
		return
	_reloading = true
	print("KURY: nowa wersja %s, przeladowanie z %s" % [target, GameData.VERSION])
	var attempts := int(flag.get("attempts", 0)) + 1 if String(flag.get("to", "")) == target else 1
	_write_flag({"to": target, "attempts": attempts, "at": Time.get_unix_time_from_system()})
	Events.notice.emit(tr("UPDATE_COMING") % target)
	# Najpierw stan na serwer. Przeladowanie bez tego gubiloby ostatnie sekundy.
	var waiting := Game.may_push_to_cloud() and Cloud.is_enabled()
	Game.save()
	if waiting:
		var timer := get_tree().create_timer(PUSH_WAIT_SECONDS)
		await _first_of(Cloud.pushed, timer.timeout)
	await get_tree().create_timer(DISK_SYNC_SECONDS).timeout
	JavaScriptBridge.eval("location.replace(location.pathname + '?v=' + %s)"
			% JSON.stringify(target))


## Czeka na pierwszy z dwoch sygnalow.
func _first_of(a: Signal, b: Signal) -> void:
	var done := [false]
	var finish := func(_x = null) -> void: done[0] = true
	a.connect(finish, CONNECT_ONE_SHOT)
	b.connect(finish, CONNECT_ONE_SHOT)
	while not done[0]:
		await get_tree().process_frame
	if a.is_connected(finish):
		a.disconnect(finish)
	if b.is_connected(finish):
		b.disconnect(finish)


func _announce_update() -> void:
	await get_tree().create_timer(1.5).timeout
	Events.notice.emit(tr("UPDATE_DONE") % GameData.VERSION)


## Czyta znacznik po przeladowaniu. Zwraca true tylko wtedy, gdy wlasnie
## doszlismy do wersji, o ktora chodzilo. Udana aktualizacja kasuje znacznik;
## nieudana zostawia go, zeby licznik prob dzialal.
func _consume_flag() -> bool:
	var flag := _read_flag()
	if flag.is_empty():
		return false
	var fresh := Time.get_unix_time_from_system() - float(flag.get("at", 0.0)) < FLAG_FRESH_SECONDS
	if String(flag.get("to", "")) == GameData.VERSION:
		_clear_flag()
		return fresh
	if not fresh:
		_clear_flag()
	return false


static func _read_flag() -> Dictionary:
	var text := ""
	if _is_web():
		var stored: Variant = JavaScriptBridge.eval(
				"localStorage.getItem(%s) || ''" % JSON.stringify(FLAG_KEY))
		text = String(stored) if stored != null else ""
	elif FileAccess.file_exists(FLAG_PATH):
		text = FileAccess.get_file_as_string(FLAG_PATH)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


static func _write_flag(flag: Dictionary) -> void:
	if _is_web():
		JavaScriptBridge.eval("localStorage.setItem(%s, %s)"
				% [JSON.stringify(FLAG_KEY), JSON.stringify(JSON.stringify(flag))])
		return
	var file := FileAccess.open(FLAG_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(flag))


static func _clear_flag() -> void:
	if _is_web():
		JavaScriptBridge.eval("localStorage.removeItem(%s)" % JSON.stringify(FLAG_KEY))
		return
	if FileAccess.file_exists(FLAG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FLAG_PATH))


static func _is_web() -> bool:
	return OS.has_feature("web")


## Adres katalogu, z ktorego zaladowano gre, z koncowym ukosnikiem.
static func _page_base() -> String:
	if not _is_web():
		return ""
	var base: Variant = JavaScriptBridge.eval(
			"location.origin + location.pathname.replace(/[^/]*$/, '')")
	return String(base) if base != null else ""
