extends Node
## Test dymny z oknem: uruchamia scene glowna, symuluje dotkniecie kazdego
## budynku i sprawdza, czy otwiera sie panel z wlasciwym tytulem.
## Zapisuje zrzuty ekranu.
##   godot --path . res://tests/smoke_ui.tscn -- <katalog_na_zrzuty>
## Wymaga wyswietlania (na serwerze: xvfb-run).

var _failed := 0


func _ready() -> void:
	# Odroczone, bo w trakcie _ready() drzewo sceny jest zajete i add_child()
	# na korzeniu zostalby odrzucony.
	_run.call_deferred()


func _run() -> void:
	var out_dir := "user://"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0].trim_suffix("/") + "/"

	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(20)
	_shot(out_dir + "farm.png")

	var panel: Control = main.get_node("Hud/Root/BuildingPanel")
	var title: Label = panel.get_node("Sheet/Content/Header/Title")
	for def: Dictionary in GameData.buildings():
		var id: String = def["id"]
		var building: Node2D = main.get_node("Farm/Objects").get_node(id.capitalize())
		var point: Vector2 = building.get_global_transform_with_canvas() * Vector2(0, -150)
		await _tap(point)
		await _frames(30)
		var ok: bool = panel.is_open() and title.text == tr(def["name"])
		print("%s: panel %s (tytul '%s')" % [id, "OK" if ok else "BLAD", title.text])
		if not ok:
			_failed += 1
		if id == "coop":
			_shot(out_dir + "panel.png")
		# Zamkniecie przez dotkniecie przyciemnionego tla u gory ekranu.
		await _tap(Vector2(540, 300))
		await _frames(30)
		if panel.visible:
			print("%s: panel sie nie zamknal" % id)
			_failed += 1
	get_tree().quit(1 if _failed > 0 else 0)


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


func _shot(path: String) -> void:
	get_tree().root.get_texture().get_image().save_png(path)
	print("zrzut: " + path)
