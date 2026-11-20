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
	_refresh()


func _refresh() -> void:
	var state := Game.state
	if state == null:
		return
	_money.set_value(state.money)
	_eggs.set_value(state.egg_count())
	_feed.set_value(floor(state.feed))
	_animals.set_value_of(state.coop_occupied(), state.coop_capacity())


## Odsuwa pasek od wyciecia na aparat / paska statusu telefonu.
func _apply_safe_area() -> void:
	_top_bar.add_theme_constant_override("margin_top", BAR_MARGIN + SafeArea.top_inset(get_viewport()))
