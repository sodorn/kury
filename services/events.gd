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

## Lis wyszedl z krzakow obok wybiegu i za `seconds` sekund stanie pod
## plotem. Scena pokazuje go w krzakach, a potem idacego do zagrody.
@warning_ignore("unused_signal")
signal fox_lurking(seconds: float)

## Rasy kur, ktore lis wlasnie dopadl (po jednej pozycji na sztuke).
## Scena sypie piora w ich kolorach.
@warning_ignore("unused_signal")
signal fox_victims(breeds: Array)

## Wizyta lisa skonczyla sie sama: lis wybral swoj lup albo minal mu czas.
## Do 12.17 scena o tym nie wiedziala i lis bez licznika biegal dalej.
@warning_ignore("unused_signal")
signal fox_left()

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

## Pies wygryzl lisa z wybiegu — lis zyje, po prostu ucieka.
@warning_ignore("unused_signal")
signal fox_chased()

## 13.0.2: tchorzliwy kundel uciekl z pogoni - scena odprowadza go do budy.
@warning_ignore("unused_signal")
signal dog_fled()

## 13.0.2: pies ugryzl lisa (zabral mu zycie), ale lis jeszcze stoi.
@warning_ignore("unused_signal")
signal fox_bitten()

## Pies ZABIL lisa. Scena ma pokazac rozszarpanie, a nie zwykle odejscie.
@warning_ignore("unused_signal")
signal fox_killed()

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


## Gry nie da sie kontynuowac: brak pary do rozrodu i brak pieniedzy na nia.
## Pokazuje pelnoekranowe GAME OVER.
@warning_ignore("unused_signal")
signal game_over()


## Kronika fermy (12.21): po przerwie dluzszej niz offline.report_hours gra
## pokazuje raport, co sie dzialo pod nieobecnosc gracza.
@warning_ignore("unused_signal")
signal away_report(report: Dictionary)
