# Wersje i cofanie się do nich

Ściągawka na wypadek, gdyby nowa wersja okazała się gorsza od poprzedniej.
Wszystko tutaj działa w PowerShellu na Windowsie, w katalogu `D:\GIT\kury`.

## Ważne punkty

- **12.31 — ostatnia wersja przed 13.0.** Commit `36eb94e`, gałąź
  `v12.31-final-przed-13`. Powrót: `git checkout v12.31-final-przed-13`.

## Jak numerujemy

```
11.6
│  └─ druga cyfra: każde wydanie (poprawki, interfejs, balans)
└──── pierwsza: zmiana formatu zapisu — uwaga na stare farmy
```

Każde wydanie dostaje gałąź `vNUMER-krótki-opis`, na przykład
`v11.6-rozpakowanie-odpowiedzi`. Gałąź jest zamrożona: `main` idzie dalej,
ona zostaje tam, gdzie była.

Numer widać na dole ekranu powitalnego w grze. Jeśli tam jest co innego,
niż się spodziewasz, przeglądarka podsunęła starą wersję z pamięci —
wtedy `Ctrl+Shift+R`.

## Jakie wersje w ogóle są

```
git fetch
git branch -r
```

## Chcę tylko zobaczyć starą wersję u siebie

```
git checkout v11.5-do-testow
```

Powrót do najnowszej:

```
git checkout main
```

Jeśli git narzeka, że nadpisze lokalne zmiany (najczęściej `project.godot`,
bo edytor Godota dopisuje tam swoje), to najpierw:

```
git checkout -- project.godot
```

## Chcę cofnąć GRĘ NA STRONIE do starszej wersji

To jest ten ważny przypadek — gdy na `sodorn.github.io/kury` coś jest
zepsute, a Claude akurat nie odpowiada.

Nie trzeba niczego budować. Gałąź `gh-pages` trzyma **gotową, zbudowaną grę
z każdego wydania osobno**. Wystarczy cofnąć ją na wcześniejszy wpis.

```
git fetch
git checkout gh-pages
git log --oneline -10
```

Zobaczysz listę w stylu:

```
cf2253f Wersja 11.6 na GitHub Pages
4003a82 Wersja 11.5 na GitHub Pages
3f65932 Wersja 11.4 na GitHub Pages (poprawka ponownego wczytania kodu)
```

Wybierz wersję, do której chcesz wrócić, i weź jej skrót z lewej:

```
git reset --hard 4003a82
git push --force origin gh-pages
git checkout main
```

Po minucie (tyle GitHub buduje stronę) `sodorn.github.io/kury` chodzi na
11.5. Zrób `Ctrl+Shift+R` i sprawdź numer na dole ekranu powitalnego.

### Co to psuje, a czego nie

- `--force` przepisuje historię gałęzi `gh-pages`. To jest branch z samym
  zbudowaną grą, nie ze źródłami — nic z Twojej pracy tam nie ginie.
- Kod źródłowy (`main` i gałęzie `v*`) zostaje nietknięty.
- **Farmy graczy zostają nietknięte.** Zapisy leżą w Supabase, nie w grze.
  Cofnięcie strony nie kasuje niczyjej farmy.
- Jedyny wyjątek: gdyby kiedyś zmienił się format zapisu (pierwsza cyfra
  wersji), starsza gra może nie zrozumieć nowszych zapisów. Dlatego ta
  cyfra w ogóle istnieje.

## Jak wrócić do przodu

Nic nie jest stracone — nowsze wydanie nadal siedzi w gałęzi `vNUMER-...`
i w `main`. Powiedz Claude'owi „wróć na 11.6", albo zbuduj ponownie
z `main` i wypchnij na `gh-pages` tą samą metodą co wyżej.
