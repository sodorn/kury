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

signal pulled(payload: Dictionary, ok: bool)
signal pushed(ok: bool)
signal status_changed(online: bool)

const PLAYER_ID_PATH := "user://player_id.txt"
const CONFIG_PATH := "res://data/backend.json"

var player_id: String = ""
var online := false

var _config: Dictionary = {}
var _push_http: HTTPRequest
var _pull_http: HTTPRequest
var _busy_push := false


func _ready() -> void:
	_config = _load_config()
	player_id = _load_or_create_player_id()
	_push_http = HTTPRequest.new()
	_pull_http = HTTPRequest.new()
	for http in [_push_http, _pull_http]:
		http.timeout = float(_config.get("timeout_seconds", 8))
		add_child(http)
	_push_http.request_completed.connect(_on_push_done)
	_pull_http.request_completed.connect(_on_pull_done)


## Czy zapis na serwerze jest w ogole skonfigurowany.
func is_enabled() -> bool:
	return bool(_config.get("enabled", false)) \
			and String(_config.get("url", "")) != "" \
			and String(_config.get("api_key", "")) != ""


## Znaki, z ktorych skladaja sie kody farm. Bez liter i cyfr, ktore latwo
## pomylic przy przepisywaniu (0/O, 1/I).
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
## Dlugosc kodu bez myslnikow.
const CODE_LENGTH := 12


## Sprowadza kod wpisany przez gracza do postaci XXXX-XXXX-XXXX albo zwraca
## pusty napis, gdy to nie jest poprawny kod. Wielkosc liter, myslniki
## i spacje nie maja znaczenia — przepisywanie z drugiego telefonu i tak
## jest zmudne.
static func normalize_code(raw: String) -> String:
	var letters := ""
	for character in raw.to_upper():
		if ALPHABET.contains(character):
			letters += character
	if letters.length() != CODE_LENGTH:
		return ""
	return "%s-%s-%s" % [letters.substr(0, 4), letters.substr(4, 4), letters.substr(8, 4)]


## Przestawia gre na inna farme (kod przepisany z drugiego urzadzenia).
func set_player_id(new_id: String) -> void:
	var trimmed := new_id.strip_edges()
	if trimmed.is_empty():
		return
	player_id = trimmed
	var file := FileAccess.open(PLAYER_ID_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(player_id)
		file.close()


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
		pulled.emit({}, false)
		return
	var url := "%s/rest/v1/%s?player_id=eq.%s&select=payload,updated_at" % [
			_base_url(), _table(), player_id.uri_encode()]
	var err := _pull_http.request(url, _headers(), HTTPClient.METHOD_GET)
	if err != OK:
		_set_online(false)
		pulled.emit({}, false)


func _on_push_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_busy_push = false
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	_set_online(ok)
	pushed.emit(ok)


func _on_pull_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_set_online(false)
		pulled.emit({}, false)
		return
	_set_online(true)
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_ARRAY:
		pulled.emit({}, false)
		return
	var rows: Array = json.data
	if rows.is_empty():
		# Serwer odpowiedzial, ale tej farmy jeszcze na nim nie ma.
		pulled.emit({}, true)
		return
	var row: Dictionary = rows[0]
	var payload: Variant = row.get("payload", {})
	pulled.emit(payload if typeof(payload) == TYPE_DICTIONARY else {}, true)


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


## Kod farmy: czytelny, latwy do przepisania z ekranu na inne urzadzenie.
func _load_or_create_player_id() -> String:
	if FileAccess.file_exists(PLAYER_ID_PATH):
		var saved := FileAccess.get_file_as_string(PLAYER_ID_PATH).strip_edges()
		if not saved.is_empty():
			return saved
	const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var generated := ""
	for i in 12:
		if i > 0 and i % 4 == 0:
			generated += "-"
		generated += ALPHABET[randi() % ALPHABET.length()]
	var file := FileAccess.open(PLAYER_ID_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(generated)
		file.close()
	return generated
