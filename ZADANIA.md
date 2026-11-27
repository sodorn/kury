# ZADANIA — plan dalszych wersji

Wszystkie pomysły, zadania i następne kroki do gry. Właściciel dopisuje tu
pomysły „od czapy” (albo prosi o to Claude), a przed kolejną wersją przeglądamy
listę i wdrażamy całe etapy naraz — bez commitów co chwilę z drobiazgami.

Zasady:
- WSZYSTKO, co nie jest jeszcze zrobione (pomysly, uwagi, bledy, decyzje do
  podjecia), trafia do tego pliku od razu - zeby nic nie zginelo.
- Najpierw planujemy, potem wdrażamy całym etapem.
- Nowe pomysły trafiają do sekcji „SKRZYNKA” na dole; przy przeglądzie
  przenosimy je do właściwego etapu albo odrzucamy (z powodem).
- Zrobione pozycje przenosimy do PROJECT_STATE.md i usuwamy stąd.
- Kolejność etapów: od najmniejszej roboty i największego zysku.

Stan na 27.11.2026: wersja 13.0.1 (poprawki po 13.2; numer na prosbe
wlasciciela). Wczesniej 13.2 (magazyny skokami: 200 / 1 000 / 3 000 /
10 000 / 25 000 / 60 000 / 150 000 / 350 000 / 800 000 / 2 000 000 jaj). Kopia linii 12: gałąź
`v12.31-final-przed-13` (12.31, commit 36eb94e).

---------------------------------------------------------------------------

## ETAP A — małe rzeczy, decyzje już zapadły (ok. 1 sesja)

A2. Ochrona przed bankructwem nieaktywnych: „dopłata z ARiMR” — gdy na
    fermie nie ma ani jednej kury, a pieniędzy nie starcza na 2 kury
    i koguta najtańszej rasy, raz na dobę darmowy zestaw startowy
    (2 leghorny + kogut + worek paszy). Bez zarabiania na tym.
A3. Pasza: na razie BEZ zmian zużycia (na jajo w grze kura je już ~3,5 raza
    mniej niż w realu, ok. 43 g vs ok. 150 g). Noc (13.1) tnie zużycie
    o kilka godzin na dobę. Wrócić po tygodniu gry z nocą: jeśli dalej za
    drogo — zmniejszyć 1,5–2 razy (feed_per_hen_minute w balance.json).
A4. Lis w nocy (decyzja 27.11: lis w nocy WCHODZI do kurnika i zabija -
    lisy atakuja najczesciej w nocy). Mechanika juz tak dziala; do zrobienia
    tylko wyglad: w nocy lis idzie do drzwi kurnika, a nie na pusty wybieg.
A5. Noc w interfejsie: ikonka księżyca / napis „Kury śpią do 7:12”
    (godzina wschodu z Daylight), żeby gracz wiedział, czemu wybieg pusty.

A6. Martwe kury leza do doby; ikonka lopaty (brazowa, lewy dolny rog,
    w krzakach) = pochowaj wszystkie. Ofiary zarazy w calosci, bez krwi,
    zgnilozielone; ofiary lisa jak teraz.
A7. Nazwy smieszniejsze i dopasowane do poziomow (stary camper, szopa
    kryta papa, stary namiot wojskowy, zardzewialy zuk, rozpadajaca sie
    chata z bali...) - przejrzec kurnik i magazyn w rozbudowy.json.

## ETAP B — ustawienia i samouczek (1–2 sesje)

B1. Zębatka z opcjami (prawy górny róg).
B2. W opcjach: dla każdego typu przycisku osobno „suwak / zwykły klik”
    (kupno ptaka, rozbudowy, pasza, szczepienie, sprzedaż...). Zapis
    w ustawieniach urządzenia, nie w farmie.
B2a. Kod fermy i "wczytaj ferme z kodu" przeniesc z kurnika do opcji.
B2b. Nocny motyw interfejsu: ciemny, stonowany fiolet - okienka nie
    razia w nocy.
B3. Samouczek przy nowej fermie: kilka okienek po kolei (jaja → sklep →
    pasza → kogut → inkubator → lis → zaraza → noc) + przycisk „?” do
    ponownego przejrzenia. Właściciel chce go od początku projektu.

## ETAP C — pomysły kolegów 1 i 2 (1–2 sesje)

C1. Klikalne krzaki: lis czai się w krzakach 10–30 s przed podejściem;
    dotknięcie właściwego krzaka wypłasza go, zanim dojdzie do płotu.
C2. Zamówienia od klientów: np. „40 jaj araukany w 2 dni za podwójną
    cenę”. Cel na krótką metę + powód trzymania wielu ras (pasuje do
    zarazy jednej rasy).

## ETAP C2 — kronika i dziennik (1 sesja)

C3. Dziennik wszystkich zdarzen gry: zlota ikonka dwoch "chevronow" (jak
    belki sierzanta) w prawym dolnym rogu; rozwija liste: tytul wiekszymi
    literami ("Uwaga, zaraza"), pod spodem opis i godzina. Okienka
    (kronika, zaraza, pies...) zamykasz OK, a tresc zostaje w dzienniku.
    Do tego przycisk w kurniku. Wpisy: rozbudowy, uklady gwiazd, nowe
    rasy, zarazy, lisy - wszystko istotne. (Kronika od 13.0.1 pokazuje
    sie po kazdym powrocie, od 6 minut nieobecnosci.)
C4a. Cena Zbyszka i Grazynki musi pasowac do tempa znoszenia (przy 300 jajach
    na godzine na kure jaj jest bardzo duzo) - policzyc przed wdrozeniem.
C4. Zbieranie jaj po staremu, ale szybko (pomysl kolegi): jeden klik =
    jedno jajo, bez czekania na animacje, klik gdziekolwiek za plotem.
    Do zatrudnienia Zbyszek i Grazynka - mnoznik 2, 4, 8 jaj na klik.

## ETAP C3 — nowe mechaniki (do przemyslenia przed wdrozeniem)

C5. Astrologia: uklady gwiazd dobre/zle dla jednej rasy z danego poziomu
    rzadkosci. Dobre: x3 jaj, inkubacja 3 razy krotsza, odpornosc na
    zaraze. Zle: 3 razy wolniej, 10 razy wieksza szansa zarazy. Ikonka:
    bialy heptagram z niebieska poswiata, pod nia opis obecnego ukladu.
C6. Hormony w sklepie, zuzywane jak pasza: +50% ceny w skupie (tylko na
    mieso), kurczaki dorastaja o 30% szybciej. Kurnik: hormony od poziomu
    7, moc rosnie z poziomem.
C7. Cztery najwyzsze poziomy kazdego budynku daja duze premie. Inkubator
    poziomy 7-10: wylegi szybsze o 10/20/30/50%. Kurnik: hormony (C6).
    Magazyn: do wymyslenia (propozycja: wolniejsze psucie jaj).

## ETAP D — konta i kopie zapasowe (1–2 sesje, ważne dla bezpieczeństwa)

D1. Logowanie użytkownik + hasło (Supabase Auth; login bez e-maila
    zamieniony wewnętrznie na sztuczny adres). Zakładanie konta przy nowej
    fermie, zmiana hasła pod zębatką. Reguły w bazie (RLS): każdy zapisuje
    tylko swoją farmę — DZIŚ każdy, kto zna kod, może nadpisać cudzą.
    Jednorazowe przypisanie istniejących farm do kont: zaloguj + podaj kod.
D2. Historia zapisów w bazie: trigger (funkcja, którą baza sama odpala przy
    każdej zmianie wiersza) kopiuje poprzednią wersję farmy do tabeli
    historii; trzymamy 30 dni.
D3. Codzienny zrzut do PRYWATNEGO miejsca (dziś katalog kopie/ jest
    w publicznym repo — wszystkie zapisy są publiczne).
D4. GitHub Action „Przywróć farmę” (pola: kod, data).

## ETAP E — grafiki (kilka sesji, właściciel zatwierdza wygląd)

E1. Budynki: początkowe małe, proste, brzydkie, dziadowskie i śmiesznie
    groteskowe (budka z palet to naprawdę budka z palet); każdy poziom
    większy i ładniejszy, na górze pałacyki. Dalej pastelowo. Wygląd ma
    odpowiadać nazwie z data/rozbudowy.json.
E1a. Obrazek sklepu: handlarz trzymajacy kure za nogi do gory nogami
    (obecny wyglada zle).
E1b. Pies jak lis: przy zmianie kierunku odwraca sie jak karta. Kundel -
    tylko ruch; owczarek - ruch + nowy wyglad: czarny podpalany, ostre
    uszy, wyzszy, mniej wydluzony, ostrzejsze ksztalty (wilczur).
E1c. Lis w nocy idzie do drzwi kurnika (zamiast na pusty wybieg).
E2. Kura szabo od nowa według prawdziwych zdjęć: duża, bardzo pierzasta,
    bez sterczących „dzyndzli” (portret w osiągnięciach i sprite na
    wybiegu).

## ETAP F — większe pomysły na później

F1. Genetyka (cechy dziedziczone po rodzicach), potem wystawy drobiu.
F2. Wahania cen kur ±30% (tylko kury, nie pasza).
F3. Pogoda dnia zamiast pór roku (doba w grze = 24 h realne).
F4. Obrońca droższy od owczarka: alpaka albo gęsi (nie głuszec —
    gatunek chroniony, nie broni kur).
F5. Jednorazowa pomoc „sąsiad myśliwy” jako nagroda, nie za gotówkę.
F6. Dwie mapy, minigra z głuszcem — dopiero po wszystkim powyżej.
F7. APK na Androida — brak Android SDK w środowisku Claude.
F8. Zdjęcia ras w sklepie — brak plików.

## ODRZUCONE

- Kara za niecelne kliknięcie w lisa (telefon nie złapie dotyku,
  gracz uzna to za błąd gry).
- Zmniejszenie zużycia paszy 3+ razy bez nocy (pasza przestałaby być
  kosztem) — patrz A3.

---------------------------------------------------------------------------

## SKRZYNKA (nowe pomysły — dopisuj tutaj)

- 
