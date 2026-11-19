# Uwagi do wersji 6.0 — do zrobienia

Lista zebrana 19.11.2026. **Nic z tego nie jest jeszcze wdrożone.**
Przy każdej uwadze dopisałem, co zmiana pociąga za sobą, żeby było
wiadomo, co jest kliknięciem, a co przebudową balansu.

---

## 1. Jedna opcja sprzedaży, cena 30% niżej od zakupu — DECYZJA

**Uwaga Tomka:** „Jaki sens 2 opcji sprzedaży z czego jedna taniej?
Głupie." Po doprecyzowaniu: „zrób po prostu opcję sprzedaj, zwykłe kury
tanie, drogie droższe. Ale nie 2 razy taniej tylko jak sprzedaję to 30%
taniej niż kupiłem. I masz rację jajka droższych powinny być droższe,
ale nieznacznie. Za to kura w sprzedaży droga jest cenna."

**Jak jest teraz:** trzy przyciski na karcie rasy (Kup / Sprzedaj
hodowlaną za 50% / Oddaj na mięso). Sprzedaż hodowlana nie przyjmuje
chorych kur, mięso przyjmuje.

**Do zrobienia:**

1. Jeden przycisk „Sprzedaj za X zł". Przycisk „na mięso" znika.
2. **Cena sprzedaży = 70% ceny zakupu** (czyli 30% taniej), zamiast
   dzisiejszych 50%.
3. Chora kura sprzedaje się taniej — kwota na przycisku zmienia się
   sama, z dopiskiem „(chora)". Dzięki temu znika wybór, a zostaje
   możliwość odzyskania czegoś z kury, która i tak padnie.
4. **Ceny jaj ścieśnić.** Dziś rozstrzał 0,40–3,00 zł. Nowy zamysł:
   wartość siedzi w kurze, nie w jajku, więc jajka droższych ras mają
   być droższe tylko nieznacznie. Wstępnie 0,40–1,00 zł, do potwierdzenia
   modelem.

**Konsekwencja dla balansu — trzeba przeliczyć, nie da się tego minąć.**
Sprzedaż za 70% zamiast 50% to 1,4 raza większy zysk z każdej odchowanej
kury, a to jest główne źródło pieniędzy w grze. Samo to skraca drogę do
miliona z ~21,7 h do mniej więcej 15 h. Ścieśnienie cen jaj działa
w drugą stronę, ale słabiej, bo na jajach i tak się nie zarabia.
Po zmianie: `tools/balance_model.py`, a potem najpewniej korekta cen
rozbudowy inkubatora albo czasów wykluwania, żeby wrócić w okolice 20 h.

Uwaga: przy 70% kupno i natychmiastowa odsprzedaż to nadal strata 30%,
więc nie powstaje żaden sposób na dorabianie w kółko.

Do poprawienia także **test** `run_tests.gd`, który dziś pilnuje, że
sprzedaż to dokładnie połowa zakupu, oraz ten pilnujący widełek 0,40–3,00
na jajkach.

---

## 2. Szczepionka za droga, choroby za rzadkie

**Uwaga Tomka:** „Szczepionka jest chyba za droga a choroby za rzadko."

**Jak jest teraz (`data/balance.json`):**

```
disease.chance_per_hen_hour    0.05     ~1 zachorowanie na 2 h przy 10 kurach
disease.death_minutes          7        tyle chora kura żyje
disease.medicine_price         140      leczy jedną kurę
disease.vaccine_price          1200     opłata stała
disease.vaccine_price_per_hen  45       plus tyle od każdej niezaszczepionej
```

Przy 10 kurach szczepienie kosztuje 1200 + 450 = **1650 zł**, a gra
zaczyna się od 150 zł. Czyli przez pierwsze godziny szczepionka jest
poza zasięgiem i choroby są wyłącznie stratą, bez możliwości reakcji.
Zgadza się z tym, co napisał.

**Propozycja:** opłata stała w dół do 0–200 zł, stawka od kury do ~60 zł
(10 kur = 600 zł zamiast 1650), `chance_per_hen_hour` w górę do ~0.15
(przy 10 kurach ok. 1,5 zachorowania na godzinę), lek w dół do ~80 zł.
Po zmianie **trzeba przepuścić `tools/balance_model.py`** — choroby
wycinają kury, więc częstsze choroby spowalniają dojście do miliona.

---

## 3. Sześć jaj na jedno pisklę

**Pytanie Tomka:** „6 jaj na jedno pisklę do wyklucia?"

To nie jest realizm, tylko hamulec. Odpowiedź w rozmowie, tutaj tylko
do zapamiętania: jeśli zejdziemy do 1 jajka = 1 pisklę bez innych zmian,
inkubator chodzi bez przerwy i milion wychodzi w jakieś 4 h zamiast 21 h.

**Propozycja:** zejść do 3 jaj i wydłużyć wykluwanie, albo zostawić 6.
Do przeliczenia modelem, nie na oko.

---

## 4. Czas przy otwartej, ale nieaktywnej karcie — do sprawdzenia

Nie wynika z uwag Tomka, zauważyłem przy odpowiadaniu na jego pytanie
o upływ czasu.

`Game._catch_up` wywołuje się **tylko przy wczytywaniu gry**. Czyli:

- zamknięta karta → po powrocie czas jest doliczony (do 12 h), działa;
- karta otwarta, ale w tle → przeglądarka wstrzymuje pętlę gry, a że
  nie ma wczytywania, nic tego nie nadrabia. Czas prawdopodobnie
  **przepada**.

To odwrotnie, niż gracz się spodziewa. **Najpierw trzeba to sprawdzić
w prawdziwej przeglądarce**, a jeśli się potwierdzi — doliczać czas
także przy powrocie do karty (zdarzenie `visibilitychange`), nie tylko
przy starcie.

---

## Nadal otwarte z wcześniejszych etapów

- Samouczek na start i przycisk „?".
- Okienko do przepisania kodu farmy na drugie urządzenie (razem
  z wymuszeniem pobrania z serwera, inaczej nowszy zapis lokalny
  nadpisze cudzą farmę).
- Zdjęcia ras do sklepu — lista nazw plików w `assets/photos/CZYTAJ_TO.md`.
- Serwer na zapisy — instrukcja w `INSTRUKCJA_SERWER.md`.
- Eksport APK — zablokowany, moje środowisko nie ma dostępu do Android SDK.
