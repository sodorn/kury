extends Node
## Test dymny z oknem: uruchamia scene glowna i sprawdza, czy rozgrywka
## reaguje — budynki otwieraja panel, kury stoja na wybiegu, jajko da sie
## zebrac dotknieciem, a przyciski w sklepie dzialaja. Zapisuje zrzuty ekranu.
##   godot --path . res://tests/smoke_ui.tscn -- <katalog_na_zrzuty>
## Wymaga wyswietlania (na serwerze: xvfb-run).

var _failed := 0
var _out_dir := "user://"
var _main: Node


func _ready() -> void:
	# Odroczone, bo w trakcie _ready() drzewo sceny jest zajete i add_child()
	# na korzeniu zostalby odrzucony.
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0].trim_suffix("/") + "/"

	# Gra wczytuje zapis przy starcie, wiec przed zbudowaniem sceny kasujemy go
	# i zaczynamy od stanu poczatkowego — inaczej kolejne uruchomienia testu
	# dziedziczylyby stado i jaja z poprzedniego.
	SaveGame.clear()
	Game.new_game()

	_main = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await _frames(20)
	# Symulacja chodzi dalej w tle i przy wolnym renderze (xvfb) potrafi w czasie
	# testu znosić jaja, co psuje liczenia. Na czas testu ja zatrzymujemy
	# i zmieniamy stan recznie.
	Game.set_process(false)
	_shot("farma.png")

	await _test_buildings()
	await _test_hens()
	await _test_egg_pickup()
	await _test_shop()
	await _test_sell_hen()
	await _test_no_feed_notice()

	SaveGame.clear()
	print("TEST DYMNY: %s" % ("OK" if _failed == 0 else "%d BLEDOW" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed += 1
		printerr("  BLAD " + label)


func _test_buildings() -> void:
	var panel: Control = _main.get_node("Hud/Root/BuildingPanel")
	var title: Label = panel.get_node("Sheet/Content/Header/Title")
	for def: Dictionary in GameData.buildings():
		var id: String = def["id"]
		var building: Node2D = _main.get_node("Farm/Objects").get_node(id.capitalize())
		await _tap(_canvas_point(building, Vector2(0, -150)))
		await _frames(30)
		_check(panel.is_open() and title.text == tr(def["name"]), "panel budynku '%s'" % id)
		if id == "shop":
			_shot("panel_sklep.png")
		await _tap(Vector2(540, 260))
		await _frames(30)
		_check(not panel.visible, "panel '%s' zamyka sie dotknieciem tla" % id)


func _test_hens() -> void:
	var hens := _nodes_of_type("FarmChicken")
	_check(hens.size() == Game.state.hen_count(), "liczba kur w scenie zgadza sie ze stanem gry")
	var before: Array[Vector2] = []
	for hen: Node2D in hens:
		before.append(hen.position)
	await _frames(90)
	var moved := 0
	for i in hens.size():
		if (hens[i] as Node2D).position.distance_to(before[i]) > 1.0:
			moved += 1
	_check(moved > 0, "kury chodza po wybiegu (ruszylo sie %d z %d)" % [moved, hens.size()])


func _test_egg_pickup() -> void:
	Game.state.eggs_on_ground += 2
	Events.eggs_laid.emit(2)
	await _frames(20)
	var eggs := _nodes_of_type("GroundEgg")
	_check(eggs.size() == 2, "jajka pojawily sie na wybiegu")
	_shot("jajka.png")
	if eggs.is_empty():
		return
	var stored_before: int = Game.state.eggs
	await _tap(_canvas_point(eggs[0], Vector2(0, -38)))
	await _frames(40)
	_check(Game.state.eggs == stored_before + 1, "dotkniecie jajka zwieksza stan magazynu")
	_check(_nodes_of_type("GroundEgg").size() == 1, "zebrane jajko znika z wybiegu")


func _test_shop() -> void:
	Game.state.eggs = 6
	Game.state.money = 500
	var shop: Node2D = _main.get_node("Farm/Objects/Shop")
	await _tap(_canvas_point(shop, Vector2(0, -150)))
	await _frames(30)
	var actions: VBoxContainer = _main.get_node("Hud/Root/BuildingPanel/Sheet/Content/Scroll/Scrollable/Actions")
	var buttons := actions.get_children()
	_check(buttons.size() == 2 + GameData.breeds().size(), "sklep ma komplet przyciskow")
	if buttons.is_empty():
		return

	var money_before: int = Game.state.money
	(buttons[0] as Button).emit_signal("pressed")
	await _frames(10)
	_check(Game.state.eggs == 0 and Game.state.money > money_before, "sprzedaz jaj dziala")

	var feed_before: float = Game.state.feed
	(buttons[1] as Button).emit_signal("pressed")
	await _frames(10)
	_check(Game.state.feed > feed_before, "zakup paszy dziala")

	var hens_before: int = Game.state.hen_count()
	(buttons[2] as Button).emit_signal("pressed")
	await _frames(20)
	_check(Game.state.hen_count() == hens_before + 1, "zakup kury dziala")
	_check(_nodes_of_type("FarmChicken").size() == Game.state.hen_count(), "kupiona kura pojawila sie na wybiegu")
	_shot("panel_po_zakupach.png")


## Sprzedaz kury w kurniku: stado maleje, pieniedzy przybywa, kura znika z wybiegu.
func _test_sell_hen() -> void:
	var panel: Control = _main.get_node("Hud/Root/BuildingPanel")
	if panel.visible:
		panel.close()
		await _frames(30)
	var coop: Node2D = _main.get_node("Farm/Objects/Coop")
	await _tap(_canvas_point(coop, Vector2(0, -150)))
	await _frames(30)
	_shot("panel_kurnik.png")

	var actions: VBoxContainer = _main.get_node("Hud/Root/BuildingPanel/Sheet/Content/Scroll/Scrollable/Actions")
	var sell_button: Button = null
	for child in actions.get_children():
		if (child as Button).visible:
			sell_button = child
			break
	_check(sell_button != null, "kurnik pokazuje przycisk sprzedazy posiadanej rasy")
	if sell_button == null:
		return
	var hens_before: int = Game.state.hen_count()
	var money_before: int = Game.state.money
	sell_button.emit_signal("pressed")
	await _frames(60)
	_check(Game.state.hen_count() == hens_before - 1, "sprzedaz zmniejsza stado")
	_check(Game.state.money > money_before, "sprzedaz kury daje pieniadze")
	_check(_nodes_of_type("FarmChicken").size() == Game.state.hen_count(), "sprzedana kura znika z wybiegu")


## Gdy skonczy sie pasza, gracz musi dostac komunikat — inaczej nie wie,
## dlaczego kury przestaly znosic.
func _test_no_feed_notice() -> void:
	var panel: Control = _main.get_node("Hud/Root/BuildingPanel")
	if panel.visible:
		panel.close()
		await _frames(30)
	var notice: Control = _main.get_node("Hud/Root/Notice")
	Game.state.feed = 0.0
	Game.set_process(true)
	await _frames(10)
	Game.set_process(false)
	_check(notice.visible, "komunikat o braku paszy sie pokazuje")
	_shot("brak_paszy.png")


# --- narzedzia ----------------------------------------------------------


func _nodes_of_type(class_name_wanted: String) -> Array[Node]:
	var found: Array[Node] = []
	for child in _main.get_node("Farm/Objects").get_children():
		if child.get_script() != null and child.get_script().get_global_name() == class_name_wanted:
			found.append(child)
	return found


func _canvas_point(node: Node2D, offset: Vector2) -> Vector2:
	return node.get_global_transform_with_canvas() * offset


func _tap(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = point * get_tree().root.get_final_transform().get_scale()
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(4)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	get_tree().root.get_texture().get_image().save_png(_out_dir + file_name)
