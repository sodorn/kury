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

## Kura danej rasy opuscila stado — wybieg ma zabrac jedna z nich.
@warning_ignore("unused_signal")
signal hen_removed(breed_id: String)

## Gracz odblokowal nowa rase.
@warning_ignore("unused_signal")
signal breed_unlocked(breed_id: String)

## Krotki komunikat dla gracza (np. koniec paszy).
@warning_ignore("unused_signal")
signal notice(text: String)

## Lis odwiedzil wybieg i porwal `count` kur — scena ma to pokazac.
@warning_ignore("unused_signal")
signal fox_visited(count: int)

## Gra zostala wygrana; `reason` to "money" albo "collection".
@warning_ignore("unused_signal")
signal game_won(reason: String)
