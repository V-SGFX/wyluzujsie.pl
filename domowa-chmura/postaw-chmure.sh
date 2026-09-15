#!/usr/bin/env bash
#
# Domowa chmura: Immich (zdjęcia) i opcjonalnie Nextcloud AIO (pliki).
# Automatyzuje poradnik z forum:
# https://wyluzujsie.pl/t/domowa-chmura-zamiast-dysku-i-zdjec-google-immich-i-nextcloud-na-wlasnym-serwerze/119
#
# Skrypt NIE otwiera portów na routerze i nie konfiguruje dostępu z zewnątrz —
# to świadoma decyzja, tak samo jak w poradniku. Dostęp spoza domu rób VPN-em.

set -Eeuo pipefail

KATALOG="${HOME}/immich"
DANE=""
NEXTCLOUD=0
PORT_NEXTCLOUD=8080
SYMULACJA=0
BEZ_STARTU=0
PORADNIK="https://wyluzujsie.pl/t/domowa-chmura-zamiast-dysku-i-zdjec-google-immich-i-nextcloud-na-wlasnym-serwerze/119"

log() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
ostrzez() { printf '  \033[33m! %s\033[0m\n' "$*"; }
blad() { printf '\033[31mBŁĄD: %s\033[0m\n' "$*" >&2; exit 1; }

# W trybie symulacji wypisujemy polecenie zamiast je wykonywać. Dzięki temu
# można zobaczyć, co skrypt zrobi, zanim cokolwiek powstanie na dysku.
wykonaj() {
  if [ "$SYMULACJA" -eq 1 ]; then
    printf '  [symulacja] %s\n' "$*"
  else
    "$@"
  fi
}

pomoc() {
  cat <<POMOC
Stawia domową chmurę na Dockerze: Immich, opcjonalnie Nextcloud AIO.

Użycie: $(basename "$0") --dane /sciezka/na/dysku [opcje]

Opcje:
  --dane KATALOG        gdzie fizycznie mają leżeć zdjęcia (duży dysk, nie systemowy).
                        Wymagane przy pierwszym uruchomieniu.
  --katalog KATALOG     gdzie zapisać pliki konfiguracyjne Immicha
                        (domyślnie: ${KATALOG})
  --z-nextcloud         postaw także Nextcloud All-in-One
  --port-nextcloud PORT port panelu Nextcloud AIO (domyślnie: ${PORT_NEXTCLOUD})
  --bez-startu          przygotuj pliki, ale nie uruchamiaj kontenerów
  --symuluj             tylko pokaż, co zostanie zrobione — nic nie zmienia
  -h, --help            ta pomoc

Przykłady:
  $(basename "$0") --dane /mnt/dysk/immich
  $(basename "$0") --dane /mnt/dysk/immich --z-nextcloud
  $(basename "$0") --dane /mnt/dysk/immich --symuluj

Poradnik: ${PORADNIK}
POMOC
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dane) DANE="${2:-}"; shift 2 ;;
    --katalog) KATALOG="${2:-}"; shift 2 ;;
    --z-nextcloud) NEXTCLOUD=1; shift ;;
    --port-nextcloud) PORT_NEXTCLOUD="${2:-}"; shift 2 ;;
    --bez-startu) BEZ_STARTU=1; shift ;;
    --symuluj) SYMULACJA=1; shift ;;
    -h|--help) pomoc; exit 0 ;;
    *) blad "nieznana opcja: $1 (--help pokaże listę)" ;;
  esac
done

# ---------------------------------------------------------------- KONTROLE ---

log "Sprawdzam, czy jest czym stawiać"

command -v docker >/dev/null 2>&1 || blad "nie ma Dockera. Zainstaluj go i uruchom skrypt ponownie."
docker info >/dev/null 2>&1 || blad "Docker nie odpowiada. Uruchom usługę albo dodaj siebie do grupy 'docker'."
command -v curl >/dev/null 2>&1 || blad "nie ma polecenia curl."

# Immich zaleca wtyczkę "docker compose" (wersja 2). Starsze docker-compose 1.x
# zwykle uruchomi te pliki, ale przy aktualizacjach potrafi się wyłożyć — stąd
# ostrzeżenie zamiast cichego działania.
COMPOSE=()
if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
  ostrzez "Masz stare docker-compose $(docker-compose --version | awk '{print $3}' | tr -d ,). Immich zaleca wtyczkę 'docker compose' (wersja 2)."
else
  blad "nie ma ani wtyczki 'docker compose', ani polecenia docker-compose."
fi
info "Docker (${COMPOSE[*]}) działa."

if [ -r /proc/meminfo ]; then
  PAMIEC_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
  if [ "${PAMIEC_MB:-0}" -lt 6000 ]; then
    ostrzez "Masz ${PAMIEC_MB} MB RAM. Immich z modułem uczenia maszynowego lubi 6–8 GB — może być ciasno."
  else
    info "Pamięć: ${PAMIEC_MB} MB."
  fi
fi

# Katalog na dane jest wymagany tylko wtedy, gdy nie ma jeszcze gotowego .env.
if [ -z "$DANE" ] && [ ! -f "${KATALOG}/.env" ]; then
  blad "podaj --dane /sciezka/na/dysku — tam wylądują zdjęcia. Wskaż duży dysk, nie systemowy."
fi

# ------------------------------------------------------------------ IMMICH ---

log "Pobieram aktualne pliki Immicha z jego wydań"

# Poradnik mówi wprost: bierzemy pliki z najnowszego wydania projektu, a nie
# z przypadkowego poradnika, bo kolejne wersje zmieniają układ bazy danych.
# grep -o zamiast cięcia linii po cudzysłowach: GitHub potrafi zwrócić cały
# JSON w jednej linii i wtedy "czwarte pole" to przypadkowy adres, nie wersja.
ODPOWIEDZ=$(curl -fsSL https://api.github.com/repos/immich-app/immich/releases/latest || true)
WYDANIE=$(printf '%s' "$ODPOWIEDZ" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d '"' -f 4)
[ -n "$WYDANIE" ] || blad "nie udało się odczytać numeru najnowszego wydania Immicha (brak internetu albo limit GitHuba)."
info "Najnowsze wydanie: ${WYDANIE}"

wykonaj mkdir -p "$KATALOG"

pobierz() {
  local plik="$1" cel="$2"
  local adres="https://github.com/immich-app/immich/releases/download/${WYDANIE}/${plik}"
  if [ "$SYMULACJA" -eq 1 ]; then
    printf '  [symulacja] curl -fsSL %s -o %s\n' "$adres" "$cel"
  else
    curl -fsSL "$adres" -o "$cel" || blad "nie udało się pobrać ${plik} z wydania ${WYDANIE}."
  fi
}

# docker-compose.yml nadpisujemy zawsze — to on niesie nową wersję.
# Kopia poprzedniego zostaje obok, gdyby aktualizacja wymagała cofnięcia.
if [ -f "${KATALOG}/docker-compose.yml" ]; then
  wykonaj cp "${KATALOG}/docker-compose.yml" "${KATALOG}/docker-compose.yml.poprzedni"
  info "Poprzedni docker-compose.yml zapisany jako docker-compose.yml.poprzedni"
fi
pobierz "docker-compose.yml" "${KATALOG}/docker-compose.yml"

# .env zostawiamy w spokoju, jeśli już istnieje — są w nim hasła do bazy.
if [ -f "${KATALOG}/.env" ]; then
  info "Plik .env już istnieje — zostawiam go bez zmian (są w nim hasła)."
else
  pobierz "example.env" "${KATALOG}/.env"

  # Hasło bazy: tylko litery i cyfry. Znaki specjalne potrafią rozjechać
  # połączenie z bazą, o czym poradnik ostrzega osobno.
  HASLO=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)
  [ -n "$HASLO" ] || blad "nie udało się wylosować hasła do bazy."

  ustaw_klucz() {
    local klucz="$1" wartosc="$2" plik="${KATALOG}/.env"
    if [ "$SYMULACJA" -eq 1 ]; then
      printf '  [symulacja] ustaw %s w %s\n' "$klucz" "$plik"
      return
    fi
    if grep -q "^${klucz}=" "$plik"; then
      # Podmiana przez plik pomocniczy: wartość może zawierać ukośniki,
      # a te rozwaliłyby wyrażenie sed.
      awk -v k="$klucz" -v w="$wartosc" 'BEGIN{FS=OFS="="} $1==k {print k "=" w; next} {print}' \
        "$plik" >"${plik}.nowy" && mv "${plik}.nowy" "$plik"
    else
      printf '%s=%s\n' "$klucz" "$wartosc" >>"$plik"
    fi
  }

  ustaw_klucz "UPLOAD_LOCATION" "$DANE"
  ustaw_klucz "DB_PASSWORD" "$HASLO"
  wykonaj chmod 600 "${KATALOG}/.env"
  info "Utworzyłem .env: zdjęcia trafią do ${DANE}, hasło bazy wylosowane."
fi

if [ -n "$DANE" ]; then
  wykonaj mkdir -p "$DANE"
fi

if [ "$BEZ_STARTU" -eq 1 ]; then
  log "Pliki gotowe, kontenerów nie uruchamiam (--bez-startu)"
  info "Przejrzyj ${KATALOG}/.env, a potem uruchom:"
  info "  ${COMPOSE[*]} --project-directory ${KATALOG} up -d"
  exit 0
fi

log "Uruchamiam Immicha"
if [ "$SYMULACJA" -eq 1 ]; then
  printf '  [symulacja] %s --project-directory %s up -d\n' "${COMPOSE[*]}" "$KATALOG"
else
  "${COMPOSE[@]}" --project-directory "$KATALOG" up -d
fi

# --------------------------------------------------------------- NEXTCLOUD ---

if [ "$NEXTCLOUD" -eq 1 ]; then
  log "Uruchamiam Nextcloud All-in-One"

  if [ "$SYMULACJA" -eq 0 ] && docker ps -a --format '{{.Names}}' | grep -qx "nextcloud-aio-mastercontainer"; then
    info "Kontener nextcloud-aio-mastercontainer już istnieje — pomijam."
  else
    wykonaj docker run -d \
      --name nextcloud-aio-mastercontainer \
      --restart always \
      -p "${PORT_NEXTCLOUD}:8080" \
      -v nextcloud_aio_mastercontainer:/mnt/docker-aio-config \
      -v /var/run/docker.sock:/var/run/docker.sock:ro \
      nextcloud/nextcloud-aio-mastercontainer:latest
  fi
fi

# ------------------------------------------------------------ CO DALEJ ------

ADRES=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
ADRES="${ADRES:-ADRES-SERWERA}"

log "Gotowe. Co dalej"
info "1. Immich: http://${ADRES}:2283 — załóż konto administratora, potem konta domownikom."
info "2. Na telefonie zainstaluj aplikację Immich, wskaż ten adres, wybierz albumy i włącz kopię w tle."
if [ "$NEXTCLOUD" -eq 1 ]; then
  info "3. Nextcloud: https://${ADRES}:${PORT_NEXTCLOUD} — przeglądarka ostrzeże o certyfikacie, to normalne."
  info "   Zapisz hasło startowe z pierwszego ekranu, bez niego nie wejdziesz do panelu AIO."
fi

log "Zanim uznasz, że skończone"
ostrzez "Dostęp spoza domu rób VPN-em (Tailscale, WireGuard). Nie otwieraj portów na routerze."
ostrzez "Tunel Cloudflare na darmowym planie odrzuca żądania powyżej 100 MB — filmy z Immicha nie przejdą."
ostrzez "To NIE jest kopia zapasowa. Ustaw kopie: ./kopia-zapasowa.sh --cel /gdzie/kopie"
info "Poradnik z wyjaśnieniami: ${PORADNIK}"
