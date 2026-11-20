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

## Lis wszedl na wybieg i upatrzyl sobie `count` kur. Scena ma go pokazac;
## gracz ma `seconds` na przegonienie go.
@warning_ignore("unused_signal")
signal fox_arrived(count: int, seconds: float)

## Lis odszedl z lupem — `count` kur zniknelo ze stada.
@warning_ignore("unused_signal")
signal fox_visited(count: int)

## Gracz przegonil lisa, zanim ten cokolwiek zabral.
@warning_ignore("unused_signal")
signal fox_scared()

## Plot albo pies zawrocily lisa od zagrody. Nic nie zginelo, ale scena ma go
## pokazac, jak przebiega i odchodzi — inaczej gracz nie widzi, za co zaplacil
## za obrone, a sam lis bywa rzadkim gosciem.
@warning_ignore("unused_signal")
signal fox_repelled()

## Gra zostala wygrana; `reason` to "money" albo "collection".
@warning_ignore("unused_signal")
signal game_won(reason: String)

## Ostrzezenie wymagajace reakcji gracza — pokazuje sie jako okienko,
## nie jako znikajacy pasek.
@warning_ignore("unused_signal")
signal alert(title: String, message: String)
