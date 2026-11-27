# ZADANIA — plan dalszych wersji

Wszystkie pomysły, zadania i następne kroki do gry. Właściciel dopisuje tu
pomysły „od czapy” (albo prosi o to Claude), a przed kolejną wersją przeglądamy
listę i wdrażamy całe etapy naraz — bez commitów co chwilę z drobiazgami.

Zasady:
- Najpierw planujemy, potem wdrażamy całym etapem.
- Nowe pomysły trafiają do sekcji „SKRZYNKA” na dole; przy przeglądzie
  przenosimy je do właściwego etapu albo odrzucamy (z powodem).
- Zrobione pozycje przenosimy do PROJECT_STATE.md i usuwamy stąd.
- Kolejność etapów: od najmniejszej roboty i największego zysku.

Stan na 27.11.2026: wersja 13.2 (magazyny skokami: 200 / 1 000 / 3 000 /
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

## ETAP B — ustawienia i samouczek (1–2 sesje)

B1. Zębatka z opcjami (prawy górny róg).
B2. W opcjach: dla każdego typu przycisku osobno „suwak / zwykły klik”
    (kupno ptaka, rozbudowy, pasza, szczepienie, sprzedaż...). Zapis
    w ustawieniach urządzenia, nie w farmie.
B3. Samouczek przy nowej fermie: kilka okienek po kolei (jaja → sklep →
    pasza → kogut → inkubator → lis → zaraza → noc) + przycisk „?” do
    ponownego przejrzenia. Właściciel chce go od początku projektu.

## ETAP C — pomysły kolegów 1 i 2 (1–2 sesje)

C1. Klikalne krzaki: lis czai się w krzakach 10–30 s przed podejściem;
    dotknięcie właściwego krzaka wypłasza go, zanim dojdzie do płotu.
C2. Zamówienia od klientów: np. „40 jaj araukany w 2 dni za podwójną
    cenę”. Cel na krótką metę + powód trzymania wielu ras (pasuje do
    zarazy jednej rasy).

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
