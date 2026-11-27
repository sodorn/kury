extends CanvasLayer
## HUD: gorny pasek z licznikami zasobow. Tylko czyta Game.state.

const BAR_MARGIN := 20

@onready var _root: Control = $Root
@onready var _top_bar: MarginContainer = $Root/TopBar
@onready var _money: ResourceCounter = $Root/TopBar/Counters/Money
@onready var _eggs: ResourceCounter = $Root/TopBar/Counters/Eggs
@onready var _feed: ResourceCounter = $Root/TopBar/Counters/Feed
@onready var _animals: ResourceCounter = $Root/TopBar/Counters/Animals


func _ready() -> void:
	_root.theme = UiTheme.build()
	Events.resources_changed.connect(_refresh)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_make_admin_bar()
	_refresh()


func _refresh() -> void:
	var state := Game.state
	if state == null:
		return
	if _admin_bar != null:
		_admin_bar.visible = Game.is_admin()
	_money.set_value(state.money)
	_eggs.set_value(state.egg_count())
	_feed.set_value(floor(state.feed))
	_animals.set_value_of(state.coop_occupied(), state.coop_capacity())


## Odsuwa pasek od wyciecia na aparat / paska statusu telefonu.
func _apply_safe_area() -> void:
	_top_bar.add_theme_constant_override("margin_top", BAR_MARGIN + SafeArea.top_inset(get_viewport()))


## 13.0: pasek przyciskow fermy admina (kod 000000) pod licznikami.
var _admin_bar: GridContainer


func _make_admin_bar() -> void:
	_admin_bar = GridContainer.new()
	_admin_bar.name = "AdminBar"
	_admin_bar.columns = 4
	_admin_bar.add_theme_constant_override("h_separation", 8)
	_admin_bar.add_theme_constant_override("v_separation", 8)
	# 13.1.1: na dole ekranu - u gory zaslanial komunikaty.
	_admin_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_admin_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_admin_bar.offset_top = -170
	_admin_bar.offset_bottom = -40
	var actions := {
		"+1000 zł": func() -> void: Game.admin_add_money(1000.0),
		"Przywołaj lisa": func() -> void: Game.admin_call_fox(),
		"Zabij psa": func() -> void: Game.admin_kill_dog(),
		"Wywołaj zarazę": func() -> void: Game.admin_outbreak(),
		"Dzień": func() -> void: Daylight.force = 0,
		"Noc": func() -> void: Daylight.force = 1,
		"Auto": func() -> void: Daylight.force = -1,
	}
	for label: String in actions:
		var b := Button.new()
		b.text = label
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(actions[label])
		_admin_bar.add_child(b)
	_root.add_child(_admin_bar)
	_admin_bar.visible = false
