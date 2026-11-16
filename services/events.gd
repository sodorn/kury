extends Node
## Autoload "Events": globalne sygnaly laczace logike, scene farmy i UI.

## Zmienily sie zasoby w Game.state (pieniadze, jaja, pasza, zwierzeta).
@warning_ignore("unused_signal")
signal resources_changed

## Gracz dotknal budynku na mapie.
@warning_ignore("unused_signal")
signal building_tapped(building_id: String)
