extends Node
## Autoload "Events": globalne sygnaly laczace logike, scene farmy i UI.

## Zmienily sie zasoby w Game.state (pieniadze, jaja, pasza, zwierzeta).
@warning_ignore("unused_signal")
signal resources_changed

## Gracz dotknal budynku na mapie; `picture` to grafika tego budynku.
@warning_ignore("unused_signal")
signal building_tapped(building_id: String, picture: Texture2D)

## Stado znioslo `count` jaj — wybieg ma je pokazac.
@warning_ignore("unused_signal")
signal eggs_laid(count: int)

## Do stada dolaczyla kura — wybieg ma ja postawic.
@warning_ignore("unused_signal")
signal hen_added(hen: Chicken)

## Krotki komunikat dla gracza (np. koniec paszy).
@warning_ignore("unused_signal")
signal notice(text: String)
