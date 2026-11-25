extends Control
## KRONIKA FERMY (12.21, wlasciciel 25.11): po przerwie dluzszej niz
## offline.report_hours gracz dostaje raport - ile jaj, ile wizyt lisa, ile
## chorob, co sie zbudowalo - i dziennik z godzinami zegarka. Okno czeka,
## az zniknie ekran startowy, zeby sie z nim nie gryzc.

const MAX_LOG := 40

var _report: Dictionary = {}
var _waiting := false
var _away: Label
var _summary: Label
var _log_title: Label
var _log: Label
var _button: Button


func _ready() -> void:
	name = "AwayReportPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()
	Events.away_report.connect(_on_report)
	# Raport mogl przyjsc, zanim HUD powstal (wczytanie przy starcie).
	if not Game.last_away_report.is_empty():
		_on_report(Game.last_away_report)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.19, 0.12, 0.07, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.set_anchors_preset(Control.PRESET_CENTER)
	sheet.offset_left = -480
	sheet.offset_right = 480
	sheet.offset_top = -760
	sheet.offset_bottom = 760
	add_child(sheet)

	var box := VBoxContainer.new()
	box.name = "Content"
	box.add_theme_constant_override("separation", 16)
	sheet.add_child(box)

	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = tr("REPORT_TITLE")
	box.add_child(title)

	_away = Label.new()
	_away.name = "Away"
	_away.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_away.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_away)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 12)
	scroll.add_child(text)

	var sum_title := Label.new()
	sum_title.theme_type_variation = &"GroupLabel"
	sum_title.text = tr("REPORT_SUMMARY")
	text.add_child(sum_title)
	_summary = Label.new()
	_summary.name = "Summary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_summary)
	_log_title = Label.new()
	_log_title.theme_type_variation = &"GroupLabel"
	_log_title.text = tr("REPORT_LOG")
	text.add_child(_log_title)
	_log = Label.new()
	_log.name = "Log"
	_log.theme_type_variation = &"NoteLabel"
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_log)

	_button = Button.new()
	_button.name = "Close"
	_button.theme_type_variation = &"PrimaryButton"
	_button.text = tr("REPORT_CLOSE")
	_button.custom_minimum_size = Vector2(0, 110)
	_button.pressed.connect(_on_close)
	box.add_child(_button)


func _on_report(report: Dictionary) -> void:
	_report = report
	_fill()
	_waiting = true
	set_process(true)


func _process(_delta: float) -> void:
	if not _waiting:
		set_process(false)
		return
	var start := get_parent().get_node_or_null("StartPanel") as Control
	if start != null and start.visible:
		return
	_waiting = false
	get_parent().move_child(self, -1)
	# GAME OVER zostaje na samym wierzchu.
	var over := get_parent().get_node_or_null("GameOverPanel") as Control
	if over != null:
		get_parent().move_child(over, -1)
	show()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)


func _fill() -> void:
	var r := _report
	_away.text = tr("REPORT_AWAY") % NumberFormat.duration(float(r.get("away", 0.0)))
	var lines: PackedStringArray = []
	if int(r.get("eggs_laid", 0)) > 0:
		lines.append(tr("REPORT_EGGS") % NumberFormat.grouped(int(r["eggs_laid"])))
	if int(r.get("eggs_lost", 0)) > 0:
		lines.append(tr("REPORT_EGGS_LOST") % NumberFormat.grouped(int(r["eggs_lost"])))
	if int(r.get("eggs_spoiled", 0)) > 0:
		lines.append(tr("REPORT_EGGS_SPOILED") % NumberFormat.grouped(int(r["eggs_spoiled"])))
	if int(r.get("hatched", 0)) > 0 or int(r.get("grown_up", 0)) > 0:
		lines.append(tr("REPORT_HATCHED") % [int(r["hatched"]), int(r["grown_up"])])
	var visits := int(r.get("fox_blocked", 0)) + int(r.get("fox_in", 0))
	if visits > 0:
		lines.append(tr("REPORT_FOX_VISITS") % [visits, int(r["fox_blocked"]), int(r["fox_in"])])
	if int(r.get("fox_took", 0)) > 0:
		lines.append(tr("REPORT_FOX_TOOK") % int(r["fox_took"]))
	if int(r.get("fox_chased", 0)) > 0 or int(r.get("fox_killed", 0)) > 0:
		lines.append(tr("REPORT_FOX_DOG") % [int(r["fox_chased"]), int(r["fox_killed"])])
	if bool(r.get("fox_massacre", false)):
		lines.append(tr("REPORT_FOX_MASSACRE"))
	if int(r.get("outbreaks", 0)) > 0 or int(r.get("died_disease", 0)) > 0:
		lines.append(tr("REPORT_OUTBREAKS") % [int(r.get("outbreaks", 0)), int(r.get("got_sick", 0)),
				int(r.get("died_disease", 0))])
	if bool(r.get("out_of_feed", false)):
		lines.append(tr("REPORT_NO_FEED"))
	if int(r.get("died_hunger", 0)) > 0:
		lines.append(tr("REPORT_HUNGER") % int(r["died_hunger"]))
	for id: Variant in r.get("built", []):
		lines.append(tr("REPORT_BUILT") % Game.building_title(String(id)))
	if lines.is_empty():
		lines.append(tr("REPORT_QUIET"))
	lines.append(tr("REPORT_FLOCK") % [int(r.get("hens", 0)), int(r.get("roosters", 0))])
	_summary.text = "\n".join(_bullets(lines))

	var log: Array = r.get("log", [])
	var rows: PackedStringArray = []
	for i in mini(log.size(), MAX_LOG):
		rows.append("%s   %s" % [log[i][1], log[i][2]])
	if log.size() > MAX_LOG:
		rows.append(tr("LOG_MORE") % (log.size() - MAX_LOG))
	_log.text = "\n".join(rows)
	_log.visible = not rows.is_empty()
	_log_title.visible = _log.visible


func _bullets(lines: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for line in lines:
		out.append("•  " + line)
	return out


func _on_close() -> void:
	Game.last_away_report = {}
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(hide)


## Dla testow: tresc podsumowania i dziennika.
func summary_text() -> String:
	return _summary.text


func log_text() -> String:
	return _log.text
