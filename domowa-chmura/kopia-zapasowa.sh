#!/usr/bin/env bash
#
# Kopia zapasowa domowej chmury: zrzut bazy Immicha + pliki z UPLOAD_LOCATION.
# Poradnik: https://wyluzujsie.pl/t/domowa-chmura-zamiast-dysku-i-zdjec-google-immich-i-nextcloud-na-wlasnym-serwerze/119
#
# Same zdjęcia bez bazy tracą albumy, twarze i opisy — dlatego jedno i drugie
# trafia do kopii w tym samym przebiegu.

set -Eeuo pipefail

KATALOG="${HOME}/immich"
CEL=""
TRZYMAJ_DNI=14
SYMULACJA=0

log() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
ostrzez() { printf '  \033[33m! %s\033[0m\n' "$*"; }
blad() { printf '\033[31mBŁĄD: %s\033[0m\n' "$*" >&2; exit 1; }

pomoc() {
  cat <<POMOC
Robi kopię zapasową Immicha: zrzut bazy danych i pliki ze zdjęciami.

Użycie: $(basename "$0") --cel /sciezka/na/kopie [opcje]

Opcje:
  --cel KATALOG       gdzie zapisać kopię (najlepiej inny dysk niż dane)
  --katalog KATALOG   katalog z konfiguracją Immicha (domyślnie: ${KATALOG})
  --trzymaj DNI       ile dni trzymać stare zrzuty bazy (domyślnie: ${TRZYMAJ_DNI})
  --symuluj           tylko pokaż, co zostanie zrobione
  -h, --help          ta pomoc

Przykład w cronie (codziennie o 3:30):
  30 3 * * * /sciezka/do/kopia-zapasowa.sh --cel /mnt/kopie/immich >> /var/log/kopia-immich.log 2>&1
POMOC
}

while [ $# -gt 0 ]; do
  case "$1" in
    --cel) CEL="${2:-}"; shift 2 ;;
    --katalog) KATALOG="${2:-}"; shift 2 ;;
    --trzymaj) TRZYMAJ_DNI="${2:-}"; shift 2 ;;
    --symuluj) SYMULACJA=1; shift ;;
    -h|--help) pomoc; exit 0 ;;
    *) blad "nieznana opcja: $1 (--help pokaże listę)" ;;
  esac
done

wykonaj() {
  if [ "$SYMULACJA" -eq 1 ]; then
    printf '  [symulacja] %s\n' "$*"
  else
    "$@"
  fi
}

[ -n "$CEL" ] || blad "podaj --cel /sciezka/na/kopie"
[ -f "${KATALOG}/.env" ] || blad "nie znalazłem ${KATALOG}/.env — wskaż --katalog z konfiguracją Immicha."
command -v docker >/dev/null 2>&1 || blad "nie ma Dockera."

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


# Czytamy tylko te klucze, których potrzebujemy — bez wciągania całego .env
# do powłoki, bo hasła potrafią zawierać znaki, które powłoka zinterpretuje.
odczytaj() {
  grep -m1 "^$1=" "${KATALOG}/.env" | cut -d= -f2- || true
}

ZDJECIA=$(odczytaj UPLOAD_LOCATION)
UZYTKOWNIK_BAZY=$(odczytaj DB_USERNAME)
UZYTKOWNIK_BAZY="${UZYTKOWNIK_BAZY:-postgres}"
[ -n "$ZDJECIA" ] || blad "w .env nie ma UPLOAD_LOCATION."

DATA=$(date +%Y-%m-%d_%H%M)
wykonaj mkdir -p "${CEL}/baza" "${CEL}/pliki"

log "Zrzut bazy danych Immicha"
ZRZUT="${CEL}/baza/immich-${DATA}.sql.gz"
if [ "$SYMULACJA" -eq 1 ]; then
  printf '  [symulacja] %s --project-directory %s exec -T database pg_dumpall --clean --if-exists --username %s | gzip > %s\n' \
    "${COMPOSE[*]}" "$KATALOG" "$UZYTKOWNIK_BAZY" "$ZRZUT"
else
  # pg_dumpall zamiast pg_dump: bierze też role i uprawnienia, więc odtworzenie
  # na czystej instancji nie wymaga ręcznego zakładania użytkownika.
  if ! "${COMPOSE[@]}" --project-directory "$KATALOG" exec -T database \
      pg_dumpall --clean --if-exists --username "$UZYTKOWNIK_BAZY" | gzip >"$ZRZUT"; then
    rm -f "$ZRZUT"
    blad "zrzut bazy się nie powiódł. Czy kontenery Immicha działają? (${COMPOSE[*]} ps)"
  fi
  info "Zapisano $(du -h "$ZRZUT" | cut -f1) → ${ZRZUT}"
fi

log "Kopia plików ze zdjęciami"
info "Źródło: ${ZDJECIA}"
if command -v rsync >/dev/null 2>&1; then
  # --delete: kopia ma odzwierciedlać stan, a nie puchnąć o skasowane zdjęcia.
  wykonaj rsync -a --delete --info=stats2 "${ZDJECIA}/" "${CEL}/pliki/"
else
  ostrzez "Brak rsync — kopiuję przez cp (wolniej, bez wykrywania zmian)."
  wykonaj cp -a "${ZDJECIA}/." "${CEL}/pliki/"
fi

log "Sprzątanie starych zrzutów bazy"
if [ "$SYMULACJA" -eq 1 ]; then
  printf '  [symulacja] find %s/baza -name "immich-*.sql.gz" -mtime +%s -delete\n' "$CEL" "$TRZYMAJ_DNI"
else
  find "${CEL}/baza" -name 'immich-*.sql.gz' -mtime "+${TRZYMAJ_DNI}" -delete
  info "Zostawiam zrzuty z ostatnich ${TRZYMAJ_DNI} dni."
fi

log "Gotowe"
ostrzez "To jedna kopia. Zasada 3-2-1: trzy kopie, dwa nośniki, jedna poza domem."
ostrzez "Raz na jakiś czas sprawdź, czy zrzut naprawdę się odtwarza — niesprawdzona kopia to brak kopii."
