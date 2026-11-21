extends Node
## Autoload "Cloud": zapis stanu gry po stronie serwera.
##
## Gra dziala tak samo bez serwera — wtedy zapisuje sie tylko lokalnie.
## Po wlaczeniu w data/backend.json serwer staje sie zrodlem prawdy, a zapis
## lokalny zostaje kopia na czas braku sieci.
##
## Gracza rozpoznajemy po kodzie farmy: losowym identyfikatorze zapisanym
## przy pierwszym uruchomieniu. Bez logowania i bez hasla — kto ma kod,
## ten ma farme, dlatego kod pokazujemy graczowi i pozwalamy go przepisac
## na innym urzadzeniu.
##
## Protokol jest zgodny z REST-em Supabase, ale to zwykly HTTP, wiec pod ten
## sam adres mozna podstawic dowolny wlasny serwer (tak tez jest testowany).

## `for_player` mowi, ktorego kodu farmy dotyczy odpowiedz. Bez tego nie da
## sie odroznic spoznionej odpowiedzi na startowe pobranie od tej, na ktora
## gracz czeka po wpisaniu kodu.
signal pulled(payload: Dictionary, ok: bool, for_player: String)
signal pushed(ok: bool)
signal status_changed(online: bool)

const PLAYER_ID_PATH := "user://player_id.txt"
const CONFIG_PATH := "res://data/backend.json"

var player_id: String = ""
var online := false

var _config: Dictionary = {}
var _push_http: HTTPRequest
var _busy_push := false
## Kod farmy, o ktory pytamy w trwajacym zapytaniu.
var _pulling_for := ""
## Numer biezacego pobrania i wezly zapytan czekajace na sprzatniecie.
var _pull_token := 0
var _pull_nodes: Array[HTTPRequest] = []
## Slad po ostatniej rozmowie z serwerem, do diagnostyki w panelu Kurnika.
## Bez tego "brak polaczenia" nie mowilo nic o tym, CO poszlo nie tak:
## inaczej leczy sie brak tabeli, inaczej brak uprawnien, a inaczej siec.
var last_action := ""
var last_http_code := 0
var last_result := -1
var last_rows := -1


func _ready() -> void:
	_config = _load_config()
	player_id = _load_or_create_player_id()
	_push_http = HTTPRequest.new()
	_push_http.timeout = float(_config.get("timeout_seconds", 8))
	_push_http.accept_gzip = false
	add_child(_push_http)
	_push_http.request_completed.connect(_on_push_done)


## Czy zapis na serwerze jest w ogole skonfigurowany.
func is_enabled() -> bool:
	return bool(_config.get("enabled", false)) \
			and String(_config.get("url", "")) != "" \
			and String(_config.get("api_key", "")) != ""


## Kod farmy to szesc cyfr — tyle, zeby dalo sie go zapamietac i przepisac
## z telefonu bez bledow. Zakres zaczyna sie od 100000, bo kod z zerem
## na poczatku ludzie gubia przy przepisywaniu.
const CODE_LENGTH := 6
const CODE_MIN := 100000
const CODE_MAX := 999999

## Kody sprzed wersji 8.1 mialy postac XXXX-XXXX-XXXX z tego alfabetu.
## Nadal je przyjmujemy przy wpisywaniu, zeby nikt nie stracil farmy
## zalozonej na starej wersji gry.
const LEGACY_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const LEGACY_LENGTH := 12


## Sprowadza kod wpisany przez gracza do postaci, pod ktora lezy na serwerze,
## albo zwraca pusty napis, gdy to nie jest poprawny kod. Spacje, myslniki
## i wielkosc liter nie maja znaczenia — przepisywanie z drugiego telefonu
## i tak jest zmudne.
static func normalize_code(raw: String) -> String:
	var upper := raw.to_upper()
	var digits := ""
	var legacy := ""
	var has_letter := false
	for character in upper:
		if character >= "0" and character <= "9":
			digits += character
		elif character >= "A" and character <= "Z":
			has_letter = true
		if LEGACY_ALPHABET.contains(character):
			legacy += character

	if not has_letter:
		return digits if digits.length() == CODE_LENGTH else ""

	# Stary kod literowo-cyfrowy.
	if legacy.length() != LEGACY_LENGTH:
		return ""
	return "%s-%s-%s" % [legacy.substr(0, 4), legacy.substr(4, 4), legacy.substr(8, 4)]


## Czy kod jest w nowym, szesciocyfrowym formacie.
static func is_short_code(code: String) -> bool:
	return code.length() == CODE_LENGTH and code.is_valid_int()


## Przestawia gre na inna farme (kod przepisany z drugiego urzadzenia).
func set_player_id(new_id: String) -> void:
	var trimmed := new_id.strip_edges()
	if trimmed.is_empty():
		return
	player_id = trimmed
	_store_player_id(player_id)


## Wysyla stan na serwer. Wynik przychodzi sygnalem `pushed`.
func push(payload: Dictionary) -> void:
	if not is_enabled() or _busy_push:
		return
	_busy_push = true
	var body := [{
		"player_id": player_id,
		"payload": payload,
		"updated_at": int(Time.get_unix_time_from_system()),
	}]
	var url := "%s/rest/v1/%s?on_conflict=player_id" % [_base_url(), _table()]
	var err := _push_http.request(url, _headers(["Prefer: resolution=merge-duplicates,return=minimal"]),
			HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_busy_push = false
		_set_online(false)
		pushed.emit(false)


## Pobiera stan z serwera. Wynik przychodzi sygnalem `pulled`.
func pull() -> void:
	if not is_enabled():
		pulled.emit({}, false, player_id)
		return
	_pulling_for = player_id
	var url := "%s/rest/v1/%s?player_id=eq.%s&select=payload,updated_at" % [
			_base_url(), _table(), player_id.uri_encode()]
	# Kazde pobranie dostaje WLASNY wezel zapytania. Wczesniej byl jeden wezel
	# wielokrotnego uzytku, a drugie wolanie zaczynalo sie od `cancel_request()`.
	# W eksporcie na przegladarke to sie mscilo: przerwanie trwajacego XHR
	# potrafilo wrocic jako niepowodzenie JUZ ROZPOCZETEGO nowego zapytania,
	# czyli gra pokazywala "serwer nie odpowiada", mimo ze ten sam adres
	# otwarty recznie w tej samej przegladarce zwracal dane. Zapis dzialal, bo
	# szedl innym wezlem — stad mylacy obraz "czasem dziala, czasem nie".
	_pull_token += 1
	var token := _pull_token
	for old_node in _pull_nodes:
		if is_instance_valid(old_node):
			old_node.queue_free()
	_pull_nodes.clear()
	var http := HTTPRequest.new()
	http.timeout = float(_config.get("timeout_seconds", 8))
	# Rozpakowywanie gzipa zostawiamy przegladarce. Godot robil to sam i
	# przewracal sie z RESULT_BODY_DECOMPRESS_FAILED (kod 8) — odpowiedz
	# serwera przychodzila cala, a gra i tak mowila "serwer nie odpowiada".
	# Z tym wylaczonym dostajemy cialo takie, jakie przyslal serwer,
	# a gdyby mimo wszystko bylo spakowane, radzi sobie `_body_text()`.
	http.accept_gzip = false
	add_child(http)
	_pull_nodes.append(http)
	# Odpowiedz spoznionego zapytania nie moze podmienic wyniku biezacego.
	http.request_completed.connect(
			func(result: int, code: int, head: PackedStringArray, body: PackedByteArray) -> void:
				if token != _pull_token:
					return
				_on_pull_done(result, code, head, body)
				http.queue_free())
	var err := http.request(url, _headers(), HTTPClient.METHOD_GET)
	if err != OK:
		last_action = "odczyt"
		last_result = -1
		last_http_code = 0
		last_rows = -1
		_set_online(false)
		pulled.emit({}, false, _pulling_for)


func _on_push_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_busy_push = false
	last_action = "zapis"
	last_http_code = code
	last_result = result
	last_rows = -1
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	_set_online(ok)
	pushed.emit(ok)


func _on_pull_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	last_action = "odczyt"
	last_http_code = code
	last_result = result
	last_rows = -1
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_set_online(false)
		pulled.emit({}, false, _pulling_for)
		return
	_set_online(true)
	var json := JSON.new()
	if json.parse(_body_text(body)) != OK or typeof(json.data) != TYPE_ARRAY:
		pulled.emit({}, false, _pulling_for)
		return
	var rows: Array = json.data
	last_rows = rows.size()
	if rows.is_empty():
		# Serwer odpowiedzial, ale tej farmy jeszcze na nim nie ma.
		pulled.emit({}, true, _pulling_for)
		return
	var row: Dictionary = rows[0]
	var payload: Variant = row.get("payload", {})
	pulled.emit(payload if typeof(payload) == TYPE_DICTIONARY else {}, true, _pulling_for)


## Tekst odpowiedzi serwera. Zwykle to czysty JSON, bo przegladarka sama
## rozpakowuje to, co przyszlo spakowane. Jesli jednak trafi do nas gzip
## (pierwsze dwa bajty 0x1f 0x8b), rozpakowujemy go tutaj — lepiej, zeby
## gra poradzila sobie sama, niz zeby znowu klamala o braku polaczenia.
func _body_text(body: PackedByteArray) -> String:
	if body.size() >= 2 and body[0] == 0x1f and body[1] == 0x8b:
		var raw := body.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
		if not raw.is_empty():
			return raw.get_string_from_utf8()
	return body.get_string_from_utf8()


func _set_online(value: bool) -> void:
	if value != online:
		online = value
		status_changed.emit(online)


func _base_url() -> String:
	return String(_config.get("url", "")).rstrip("/")


func _table() -> String:
	return String(_config.get("table", "saves"))


func _headers(extra: Array = []) -> PackedStringArray:
	var key := String(_config.get("api_key", ""))
	var list := [
		"apikey: " + key,
		"Authorization: Bearer " + key,
		"Content-Type: application/json",
	]
	list.append_array(extra)
	return PackedStringArray(list)


func _load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CONFIG_PATH)) != OK:
		push_error("Cloud: nieczytelny plik %s" % CONFIG_PATH)
		return {}
	return json.data if typeof(json.data) == TYPE_DICTIONARY else {}


## Kod farmy: szesc cyfr, latwe do zapamietania i przepisania.
##
## Urzadzenie, ktore ma jeszcze stary kod literowo-cyfrowy, dostaje nowy.
## Nic przez to nie traci: lokalny zapis zostaje nietkniety i przy najblizszym
## zapisie trafia na serwer juz pod nowym kodem. Stary kod nadal mozna wpisac
## recznie, gdyby cos pod nim zostalo.
func _load_or_create_player_id() -> String:
	if FileAccess.file_exists(PLAYER_ID_PATH):
		var saved := FileAccess.get_file_as_string(PLAYER_ID_PATH).strip_edges()
		if is_short_code(saved):
			return saved
	var generated := str(randi_range(CODE_MIN, CODE_MAX))
	_store_player_id(generated)
	return generated


## Losuje nowy kod farmy. Uzywane, gdy gracz zaklada gospodarstwo od zera.
func new_player_id() -> String:
	player_id = str(randi_range(CODE_MIN, CODE_MAX))
	_store_player_id(player_id)
	return player_id


func _store_player_id(code: String) -> void:
	var file := FileAccess.open(PLAYER_ID_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(code)
		file.close()


## Jednozdaniowa diagnoza ostatniej rozmowy z serwerem. Kody HTTP tlumaczymy
## na to, co trzeba z nimi zrobic — sam numer nikomu nic nie mowi.
func describe_last() -> String:
	if last_action.is_empty():
		return tr("DIAG_NONE")
	if last_result != HTTPRequest.RESULT_SUCCESS:
		return tr("DIAG_NO_ANSWER") % [last_action, _result_name(last_result), last_result]
	match last_http_code:
		401, 403:
			return tr("DIAG_FORBIDDEN") % [last_action, last_http_code]
		404:
			return tr("DIAG_NO_TABLE") % last_http_code
		409:
			return tr("DIAG_CONFLICT")
	if last_http_code < 200 or last_http_code >= 300:
		return tr("DIAG_HTTP") % [last_action, last_http_code]
	if last_action == "zapis":
		return tr("DIAG_SAVE_OK")
	if last_rows == 0:
		return tr("DIAG_EMPTY")
	return tr("DIAG_READ_OK") % maxi(last_rows, 0)


## Nazwa powodu, dla ktorego zapytanie w ogole nie doszlo do skutku. Sam numer
## nic nie mowi, a roznica miedzy "nie rozwiazalem nazwy", "nie polaczylem sie"
## i "minal czas" decyduje o tym, gdzie szukac bledu.
func _result_name(code: int) -> String:
	match code:
		HTTPRequest.RESULT_CANT_CONNECT:
			return tr("DIAG_R_CONNECT")
		HTTPRequest.RESULT_CANT_RESOLVE:
			return tr("DIAG_R_RESOLVE")
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return tr("DIAG_R_CONNECTION")
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return tr("DIAG_R_TLS")
		HTTPRequest.RESULT_NO_RESPONSE:
			return tr("DIAG_R_SILENCE")
		HTTPRequest.RESULT_TIMEOUT:
			return tr("DIAG_R_TIMEOUT")
		HTTPRequest.RESULT_REQUEST_FAILED:
			return tr("DIAG_R_REFUSED")
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return tr("DIAG_R_UNPACK")
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return tr("DIAG_R_TRUNCATED")
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return tr("DIAG_R_TOO_BIG")
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return tr("DIAG_R_REDIRECTS")
	return tr("DIAG_R_OTHER")
