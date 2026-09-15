# Domowa chmura — Immich i Nextcloud

Skrypty do poradnika [Domowa chmura zamiast Dysku i Zdjęć Google](https://wyluzujsie.pl/t/domowa-chmura-zamiast-dysku-i-zdjec-google-immich-i-nextcloud-na-wlasnym-serwerze/119)
z forum [WYLUZUJSIE.pl](https://wyluzujsie.pl).

Robią to samo, co poradnik opisuje krok po kroku, tylko bez przepisywania poleceń ręcznie:
stawiają **Immicha** na zdjęcia z telefonów, opcjonalnie **Nextcloud All-in-One** na pliki
i pilnują **kopii zapasowej**, o której najłatwiej zapomnieć.

## Czego potrzebujesz

- komputer albo NAS pracujący 24/7 (Linux),
- Docker z wtyczką `docker compose` w wersji 2,
- minimum 6–8 GB RAM, jeśli chcesz Immicha z wyszukiwaniem po treści zdjęć,
- `curl` do pobrania plików wydania,
- osobny dysk na dane — nie systemowy.

## Jak postawić

```bash
git clone https://github.com/V-SGFX/wyluzujsie.pl.git
cd wyluzujsie.pl/domowa-chmura

# Najpierw zobacz, co się wydarzy — nic nie zostanie zmienione:
./postaw-chmure.sh --dane /mnt/dysk/immich --symuluj

# Potem na serio:
./postaw-chmure.sh --dane /mnt/dysk/immich

# Z Nextcloudem na pliki i dokumenty:
./postaw-chmure.sh --dane /mnt/dysk/immich --z-nextcloud

# Przygotuj pliki, ale nie uruchamiaj kontenerów — obejrzysz .env przed startem:
./postaw-chmure.sh --dane /mnt/dysk/immich --bez-startu
```

Co robi skrypt:

1. sprawdza Dockera, `docker compose` i ilość pamięci,
2. pobiera `docker-compose.yml` i `example.env` **z najnowszego wydania Immicha**
   (poradnik ostrzega, żeby nie kopiować konfiguracji z przypadkowych źródeł),
3. tworzy `.env`: ustawia `UPLOAD_LOCATION` na Twój dysk i losuje `DB_PASSWORD`
   złożone z samych liter i cyfr,
4. uruchamia kontenery i wypisuje adresy oraz następne kroki.

Przy kolejnym uruchomieniu skrypt **nie nadpisuje `.env`** (są w nim hasła), a stary
`docker-compose.yml` zachowuje jako `docker-compose.yml.poprzedni` — dzięki temu nadaje się
też do aktualizacji Immicha.

## Kopia zapasowa

Domowa chmura nie jest kopią zapasową. Jeśli padnie dysk, zdjęcia przepadają.

```bash
./kopia-zapasowa.sh --cel /mnt/kopie/immich

# Codziennie o 3:30:
30 3 * * * /sciezka/do/kopia-zapasowa.sh --cel /mnt/kopie/immich >> /var/log/kopia-immich.log 2>&1
```

Baza danych Immicha leży w katalogu konfiguracji (`DB_DATA_LOCATION`, domyślnie `./postgres`),
a nie na dysku ze zdjęciami — kopiowanie samego `UPLOAD_LOCATION` jej nie obejmie.
Skrypt zapisuje **zrzut bazy danych razem z plikami** — same zdjęcia bez bazy tracą albumy,
twarze i opisy. Stare zrzuty starsze niż 14 dni kasuje (`--trzymaj DNI` zmienia ten okres).

Pamiętaj o zasadzie **3-2-1**: trzy kopie, dwa różne nośniki, jedna poza domem. RAID kopią
zapasową nie jest — nie chroni przed skasowaniem plików ani przed ransomware.

## Czego skrypty celowo nie robią

- **Nie otwierają portów na routerze.** Dostęp spoza domu rób VPN-em (Tailscale, WireGuard).
- **Nie konfigurują tunelu Cloudflare.** Na darmowym planie odrzuca on żądania powyżej 100 MB,
  więc filmy z telefonu nie wyślą się do Immicha. Do Nextclouda tunel działa, bo ten dzieli
  duże pliki na kawałki.
- **Nie aktualizują Immicha bez Twojej wiedzy.** Wydania potrafią zmieniać układ bazy danych —
  przed aktualizacją przeczytaj notatki do wydania.

## Rozwiązywanie problemów

| Objaw | Zwykle chodzi o |
|---|---|
| Aplikacja na telefonie nie łączy się poza domem | adres `192.168…` działa tylko w domu — włącz VPN albo dodaj drugi adres w aplikacji |
| Duże filmy nie wysyłają się, zdjęcia tak | limit 100 MB darmowego tunelu Cloudflare |
| Immich nie startuje po aktualizacji | nowy `docker-compose.yml` z wydania i notatki do wydania |
| Serwer długo „mieli” dyskiem po pierwszej wysyłce | moduł uczenia maszynowego indeksuje zdjęcia — przy dużej kolekcji trwa godzinami |

Pytania i własne rozwiązania wrzucaj do [wątku na forum](https://wyluzujsie.pl/t/domowa-chmura-zamiast-dysku-i-zdjec-google-immich-i-nextcloud-na-wlasnym-serwerze/119).
