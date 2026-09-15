# Skrypty do poradników z forum WYLUZUJSIE.pl

Gotowe, opisane skrypty do poradników publikowanych na **[WYLUZUJSIE.pl](https://wyluzujsie.pl)** —
forum o technologii, gamingu, majsterkowaniu i motoryzacji.

Każdy katalog w tym repozytorium odpowiada jednemu wątkowi na forum: poradnik tłumaczy **dlaczego**
coś robimy właśnie tak, a skrypt **robi to za Ciebie**, bez przepisywania poleceń z ekranu.
Wszystko po polsku — komunikaty, komentarze w kodzie i opisy błędów.

## Co tu znajdziesz

| Katalog | Co automatyzuje | Poradnik na forum |
|---|---|---|
| [`domowa-chmura/`](domowa-chmura/) | Immich i Nextcloud w Dockerze: własna chmura na zdjęcia z telefonu i pliki, z kopią zapasową bazy danych | [Domowa chmura zamiast Dysku i Zdjęć Google](https://wyluzujsie.pl/t/domowa-chmura-zamiast-dysku-i-zdjec-google-immich-i-nextcloud-na-wlasnym-serwerze/119) |

Repozytorium rośnie razem z forum — kolejne poradniki dostają tu swój katalog.

## Domowa chmura na własnym serwerze — Immich i Nextcloud

Jeśli szukasz, **jak postawić własny serwer zdjęć zamiast Google Photos**, jak **zsynchronizować pliki
bez Dropboxa** albo jak **zrobić kopię zapasową Immicha razem z bazą danych** — to jest w
[`domowa-chmura/`](domowa-chmura/):

- `postaw-chmure.sh` — pobiera pliki z najnowszego wydania Immicha, ustawia katalog na zdjęcia,
  losuje hasło bazy i uruchamia kontenery. Opcjonalnie stawia Nextcloud All-in-One.
- `kopia-zapasowa.sh` — zrzut bazy PostgreSQL razem z plikami, z czyszczeniem starych kopii
  i gotowym wpisem do crona.

Skrypty mają tryb `--symuluj` (pokazuje, co się wydarzy, nic nie zmienia) i `--bez-startu`
(przygotowuje pliki, kontenery uruchamiasz sam).

## Jak używać

```bash
git clone https://github.com/V-SGFX/wyluzujsie.pl.git
cd wyluzujsie.pl/domowa-chmura
./postaw-chmure.sh --help
```

Każdy katalog ma własny README z wymaganiami, opisem opcji i tabelą typowych problemów.

## Zasady, którymi kierujemy się w tych skryptach

- **Nic nie dzieje się po cichu.** Skrypt wypisuje, co robi, a tryb symulacji pozwala to sprawdzić
  przed uruchomieniem.
- **Nie otwieramy portów na routerze** i nie konfigurujemy dostępu z internetu za użytkownika.
  Dostęp spoza domu to VPN — tak radzimy w poradnikach.
- **Kopia zapasowa jest częścią instrukcji**, a nie dodatkiem na koniec. Domowy serwer bez kopii
  to jedna awaria dysku od utraty zdjęć.
- **Pliki bierzemy ze źródła projektu**, nie z przypadkowych poradników — wersje potrafią zmieniać
  układ bazy danych.

## Pytania i błędy

Najlepsze miejsce to wątek przy danym poradniku na [WYLUZUJSIE.pl](https://wyluzujsie.pl) — tam
odpowiadamy i tam zbierają się rozwiązania od innych. Błąd w samym skrypcie możesz też zgłosić
jako Issue.

Licencja: [MIT](LICENSE). Korzystasz na własną odpowiedzialność — przed uruchomieniem na serwerze
z danymi przeczytaj, co skrypt robi.
