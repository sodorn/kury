# Pomysły na pogłębienie rozgrywki

Diagnoza Tomka: „gra jest beznadziejnie prosta, nie klikasz tylko to,
jak zbierasz, i za wiele nie można się wykazać".

Zgadza się. Dzisiaj gra ma jeden tryb działania: poczekaj, naciśnij
oczywisty przycisk. **Nie ma decyzji, w których można się pomylić, więc
nie ma też takich, w których można się wykazać.** Poniżej pomysły
uszeregowane od tych, które dają najwięcej za najmniej roboty.

---

## 1. Lisa da się przegonić, a pod nieobecność broni pies — ZROBIONE (7.0)

**Problem:** lis jest dziś czystą karą. Nie da się go uniknąć, nie da się
przygotować, nie da się zareagować. Losowa strata bez żadnej odpowiedzi
to najgorszy możliwy rodzaj zdarzenia w grze.

**Pomysł:**
- Lis biegnie przez wybieg ~6 sekund. **Jeśli jesteś w grze i trafisz
  w niego trzy razy, ucieka z niczym.** Nagle bycie obecnym przy grze
  coś znaczy, a animacja, która już istnieje, staje się mini-grą.
- Na czas, gdy cię nie ma: **pies w sklepie** (jednorazowy zakup, np.
  4000 zł) zmniejsza częstotliwość wizyt o połowę. Albo mocniejszy płot
  jako ulepszenie budynku.
- Wtedy lis przestaje być podatkiem, a staje się pytaniem: inwestować
  w obronę czy w kolejne kury?

**Koszt:** mały. Lis już ma scenę i animację, trzeba dodać obszar dotyku
i licznik trafień.

---

## 2. Kurnik ma pojemność, którą się rozbudowuje — ZROBIONE (7.0)

**Problem:** dziś stado może rosnąć w nieskończoność. Nie ma żadnego
powodu, żeby cokolwiek budować — a „co rozbudować jako następne" to
kręgosłup wszystkich gier tego typu.

**Pomysł:** kurnik mieści np. 12 kur. Rozbudowa do 25, 50, 100 za
rosnące kwoty. Przepełniony kurnik = kury chorują częściej. Do tego
magazyn paszy (większy zapas = zakup hurtem taniej) i poidło
(zmniejsza ryzyko chorób).

Nagle pieniądze mają kilka konkurencyjnych zastosowań zamiast jednego.

**Koszt:** średni. Budynki już stoją na mapie, trzeba im dodać poziomy.

---

## 3. Zamówienia

**Problem:** gra nie mówi graczowi, po co ma cokolwiek robić. Cel jest
jeden i odległy — milion.

**Pomysł:** co jakiś czas pojawia się zamówienie z terminem:
„Restauracja: 40 jaj araukany w ciągu 2 dni — 2,5-krotna cena",
„Hodowca: 3 dorosłe czubatki w ciągu 3 dni — 1,8-krotna cena".

Przyjmujesz albo odrzucasz. Niewykonane przepada. To daje:
- powód, żeby trzymać konkretną rasę, a nie tylko najdroższą,
- powód, żeby zaglądać do gry o określonej porze,
- decyzję: sprzedać jaja teraz czy odłożyć pod zamówienie?

**Koszt:** średni. Nowa tabelka w `data/`, panel w UI, licznik czasu.

---

## 4. Każda kura jest inna

**Problem:** wszystkie kury danej rasy są identyczne. Inkubator to
przycisk, a nie hodowla.

**Pomysł:** każda kura dostaje niewielkie odchylenia — znosi o 10%
szybciej, żyje dłużej, rzadziej choruje. Widać to w kurniku. **Pisklę
dziedziczy uśrednione cechy rodziców z lekkim losowaniem**, więc
wybierając, z których jaj wykluwać, faktycznie hodujesz.

Dobre sztuki sprzedajesz drożej. Najlepsze zostawiasz na rozpłód.
To jest dokładnie to, na czym polega prawdziwa hodowla ozdobna, i to
jest mechanika, która potrafi wciągnąć na miesiące.

**Koszt:** duży — zmiana modelu danych, formatu zapisu i UI. Ale to
jest ten pomysł, który z „klikania jajek" robi grę o hodowli.

---

## 5. Ceny się wahają

**Pomysł:** cena skupu jaj i kur zmienia się z dnia na dzień o ±30%,
z zapowiedzią na jeden dzień do przodu. Sprzedaż przestaje być
„naciśnij, gdy się uzbiera", a staje się „sprzedaj, gdy się opłaca".

**Koszt:** mały. Jeden mnożnik w stanie gry plus wykres w sklepie.

---

## 6. Wystawy drobiu

**Pomysł:** raz na kilka dni wystawa. Zgłaszasz jedną kurę; ocena zależy
od rasy, rzadkości i (jeśli powstanie pomysł 4) jakości sztuki. Nagroda
pieniężna i puchary na półce w kurniku.

To pasuje do tematu lepiej niż cokolwiek innego — rasy ozdobne istnieją
w prawdziwym świecie właśnie po to, żeby je pokazywać, a nie po to, żeby
na nich zarabiać na jajach.

**Koszt:** średni, ale ma sens dopiero razem z pomysłem 4.

---

## 7. Pory roku

**Pomysł:** zima — kury znoszą rzadziej i jedzą więcej. Lato — upał
zwiększa ryzyko chorób. Wiosna — najlepszy czas na wykluwanie.
Gra dostaje rytm, a plan „co robić teraz" zmienia się w czasie.

**Koszt:** mały, bo licznik dni już jest.

---

## Co dalej

Pomysły 1 i 2 weszły w wersji 7.0, razem z trzecim budynkiem (magazyn
z hurtem na paszę).

Następny w kolejce: **3** (zamówienia), bo daje grze cel na krótką metę.

**4** (genetyka) to osobny, duży etap. Jeśli gra ma mieć jedną rzecz,
która sprawia, że wraca się do niej miesiącami, to właśnie ta — ale nie
ma sensu zaczynać od niej, zanim reszta nie stoi stabilnie.
