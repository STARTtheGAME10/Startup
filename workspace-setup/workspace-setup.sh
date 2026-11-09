#!/usr/bin/env bash
# workspace-setup – Apps prüfen/installieren und (auf dem Laptop) auf Arbeitsflächen verteilen
# https://github.com/<dein-user>/workspace-setup
set -uo pipefail

VERSION="0.1.0"

# ============================================================================
#  KONFIGURATION
# ============================================================================

# Nur auf diesem Rechner werden Apps geöffnet und verteilt
LAYOUT_HOST="it-fasi"

# Wie lange die temporäre Fensterzuordnung aktiv bleibt (Sekunden).
# Muss länger sein als die langsamste App zum Starten braucht (Discord!).
RESTORE_DELAY=60

# Layout: "Arbeitsfläche|Desktop-ID|Startbefehl|Prozessmuster"
#  - Desktop-ID: .desktop-Datei, an der GNOME das Fenster erkennt
#      "@pwa:<Name>"     → Chromium-PWA anhand ihres Namens suchen
#      "@exec:<Befehl>"  → .desktop-Datei anhand des Exec-Befehls suchen
#  - Startbefehl: leer = "gtk-launch <Desktop-ID>"
#  - Prozessmuster: läuft ein Prozess, der darauf passt (pgrep -f), wird die
#    App nicht nochmals geöffnet. Leer = immer öffnen.
LAYOUT=(
  "1|org.gnome.Nautilus.desktop|nautilus --new-window|"
  "2|firefox_firefox.desktop|firefox|/snap/firefox/.*/firefox"
  "3|@pwa:Outlook||"
  "3|@pwa:Teams||"
  "4|@exec:brave-origin|brave-origin|brave-origin"
  "4|discord_discord.desktop|discord|/snap/discord/.*Discord"
)

# ============================================================================

AUTOMOVE_UUID="auto-move-windows@gnome-shell-extensions.gcampax.github.com"
AUTOMOVE_SCHEMA="org.gnome.shell.extensions.auto-move-windows"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/workspace-setup"
STATE_FILE="$STATE_DIR/automove.state"
SELF="$(realpath "${BASH_SOURCE[0]}")"

DRY_RUN=0
INSTALL_ONLY=0
OS_RELEASE="${OS_RELEASE:-/etc/os-release}"   # für Tests überschreibbar

# ---------- Ausgabe ----------
if [[ -t 1 ]]; then
  C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_FAIL=$'\e[31m'; C_B=$'\e[1m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
  C_OK=""; C_WARN=""; C_FAIL=""; C_B=""; C_DIM=""; C_RST=""
fi
ok()    { printf '%s✔%s %s\n'  "$C_OK"   "$C_RST" "$*"; }
info()  { printf '%s⬇%s %s\n'  "$C_B"    "$C_RST" "$*"; }
warn()  { printf '%s!%s %s\n'  "$C_WARN" "$C_RST" "$*"; }
fail()  { printf '%s✘%s %s\n'  "$C_FAIL" "$C_RST" "$*"; }
title() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_RST"; }
die()   { fail "$*" >&2; exit 2; }

# Befehl ausführen oder im Dry-Run nur anzeigen
run() {
  if (( DRY_RUN )); then printf '  %s[dry-run] %s%s\n' "$C_DIM" "$*" "$C_RST"; return 0; fi
  "$@"
}

usage() {
  cat <<EOF
workspace-setup $VERSION

Verwendung: $(basename "$0") [Optionen]

  -n          Dry-Run: nur anzeigen, was passieren würde
  -i          Nur prüfen/installieren, nichts öffnen
  -h          Hilfe anzeigen
  -V          Version anzeigen
  --restore   Fensterzuordnung sofort zurücksetzen (läuft sonst automatisch)
EOF
}

# ============================================================================
#  Teil 1: Apps prüfen und installieren (Ubuntu)
# ============================================================================

SUDO_READY=0
need_sudo() {
  (( SUDO_READY || DRY_RUN )) && return 0
  echo "  Für die Installation werden Admin-Rechte benötigt:"
  sudo -v || die "sudo fehlgeschlagen"
  SUDO_READY=1
}

has_deb() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

ensure_brave_repo() {
  local src=/etc/apt/sources.list.d/brave-browser-release.sources
  [[ -f $src ]] && return 0
  info "Brave-Paketquelle wird eingerichtet"
  need_sudo
  run sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg || return 1
  run sudo curl -fsSLo "$src" \
    https://brave-browser-apt-release.s3.brave.com/brave-browser.sources || return 1
  run sudo apt-get update -qq
}

install_snap() { need_sudo; run sudo snap install "$1"; }
install_apt()  { need_sudo; run sudo apt-get install -y "$1"; }

install_proton_pass() {
  # Offizielle Quelle laut proton.me, inkl. SHA-512-Prüfung aus version.json
  local base="https://proton.me/download/PassDesktop/linux/x64"
  local tmp url sum
  tmp=$(mktemp -d) || return 1
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  read -r url sum < <(curl -fsSL "$base/version.json" | python3 -c '
import json, sys
for r in json.load(sys.stdin)["Releases"]:
    if r.get("CategoryName") != "Stable":
        continue
    for f in r["File"]:
        if f["Url"].endswith(".deb"):
            print(f["Url"], f["Sha512CheckSum"]); sys.exit()
') || true
  [[ -n ${url:-} && -n ${sum:-} ]] || { fail "Proton Pass: Download-Infos nicht gefunden"; return 1; }

  if (( DRY_RUN )); then
    printf '  %s[dry-run] download %s + sha512 prüfen + apt install%s\n' "$C_DIM" "$url" "$C_RST"
    return 0
  fi
  curl -fsSL -o "$tmp/ProtonPass.deb" "$url" || return 1
  echo "$sum  $tmp/ProtonPass.deb" | sha512sum --check --quiet - \
    || { fail "Proton Pass: Prüfsumme stimmt nicht – Installation abgebrochen"; return 1; }
  need_sudo
  sudo apt-get install -y "$tmp/ProtonPass.deb"
}

# Name | Prüfung | Installation
check_app() {
  local name=$1 check=$2 install=$3
  if eval "$check"; then
    ok "$name"
  else
    info "$name fehlt – wird installiert"
    if eval "$install"; then ok "$name installiert"; else fail "$name: Installation fehlgeschlagen"; fi
  fi
}

ensure_apps() {
  title "Apps prüfen"
  check_app "Firefox"     "command -v firefox >/dev/null"  "install_snap firefox"
  check_app "Proton Pass" "has_deb proton-pass"            "install_proton_pass"
  check_app "Brave"       "has_deb brave-browser"          "ensure_brave_repo && install_apt brave-browser"
  check_app "Discord"     "command -v discord >/dev/null"  "install_snap discord"

  if (( IS_LAYOUT_HOST )); then
    check_app "Brave Origin" "has_deb brave-origin" "ensure_brave_repo && install_apt brave-origin"
    if command -v chromium >/dev/null; then
      ok "Chromium (für Outlook/Teams-PWA)"
    else
      warn "Chromium fehlt – Outlook/Teams-PWAs können nicht starten"
    fi
  fi
}

# ============================================================================
#  Teil 2: Apps öffnen und verteilen (nur Laptop)
# ============================================================================

APP_DIRS=(
  "$HOME/.local/share/applications"
  "$HOME/snap/chromium/current/.local/share/applications"
  /usr/share/applications
  /var/lib/snapd/desktop/applications
  /var/lib/flatpak/exports/share/applications
)

# .desktop-Datei finden, deren Zeile auf das Muster passt
find_desktop() { # $1 = grep-Muster (ERE, case-insensitiv), $2 = Dateimuster, $3 = "all" für alle Treffer
  local dir f found=1
  for dir in "${APP_DIRS[@]}"; do
    for f in "$dir"/$2; do
      if [[ ! -f $f ]] || ! grep -qiE "$1" "$f"; then continue; fi
      basename "$f"; found=0
      [[ ${3:-} == all ]] || return 0
    done
  done
  return $found
}

desktop_exists() {
  local dir
  for dir in "${APP_DIRS[@]}"; do [[ -f "$dir/$1" ]] && return 0; done
  return 1
}

automove_enabled() { gnome-extensions list --enabled 2>/dev/null | grep -qx "$AUTOMOVE_UUID"; }

# Bisherige Einstellungen sichern (nur wenn nicht schon eine Sicherung aussteht)
save_automove() {
  mkdir -p "$STATE_DIR"
  if [[ -f $STATE_FILE ]]; then
    warn "Vorherige Zuordnung noch aktiv – Sicherung bleibt bestehen"
    return 0
  fi
  local list enabled=0
  list=$(gsettings get "$AUTOMOVE_SCHEMA" application-list)
  automove_enabled && enabled=1
  (( DRY_RUN )) || printf '%s\n%s\n' "$enabled" "$list" > "$STATE_FILE"
}

restore_automove() {
  [[ -f $STATE_FILE ]] || { echo "Nichts zurückzusetzen."; return 0; }
  local enabled list
  { read -r enabled; read -r list; } < "$STATE_FILE"
  gsettings set "$AUTOMOVE_SCHEMA" application-list "$list"
  (( enabled )) || gnome-extensions disable "$AUTOMOVE_UUID" 2>/dev/null
  rm -f "$STATE_FILE"
  echo "Fensterzuordnung zurückgesetzt."
}

schedule_restore() {
  if (( DRY_RUN )); then
    printf '  %s[dry-run] Zuordnung wird nach %ss zurückgesetzt%s\n' "$C_DIM" "$RESTORE_DELAY" "$C_RST"
    return 0
  fi
  # systemd-run: läuft weiter, auch wenn das Terminal geschlossen wird
  if systemd-run --user --quiet --collect --on-active="${RESTORE_DELAY}s" \
       --unit="workspace-setup-restore-$(date +%s)" "$SELF" --restore 2>/dev/null; then
    ok "Zuordnung wird in ${RESTORE_DELAY}s automatisch zurückgesetzt"
  else
    warn "systemd-run nicht verfügbar – setze nach ${RESTORE_DELAY}s im Hintergrund zurück"
    nohup bash -c "sleep $RESTORE_DELAY; '$SELF' --restore" >/dev/null 2>&1 &
  fi
}

open_layout() {
  title "Arbeitsflächen einrichten"

  if ! command -v gnome-extensions >/dev/null || ! gsettings list-keys "$AUTOMOVE_SCHEMA" &>/dev/null; then
    fail "Extension «Auto Move Windows» fehlt (Paket gnome-shell-extensions)"
    return 1
  fi

  # Einträge auflösen: Desktop-ID, Startbefehl, ob schon läuft
  local entry ws id cmd pattern appid
  local -a mapping=() to_launch=()
  for entry in "${LAYOUT[@]}"; do
    IFS='|' read -r ws id cmd pattern <<< "$entry"

    case $id in
      @pwa:*)
        local pwa=${id#@pwa:}
        id=$(find_desktop "^Name=.*${pwa}" 'chrome-*-Default.desktop') \
          || { warn "PWA «$pwa» nicht gefunden – übersprungen"; continue; }
        appid=${id#chrome-}; appid=${appid%-Default.desktop}
        pattern="--app-id=$appid"
        ;;
      @exec:*)
        # Prefix-Match, damit z.B. auch "brave-origin-stable" passt. Gibt es mehrere
        # Starter (brave-origin.desktop + com.brave.Origin.desktop), werden alle
        # derselben Fläche zugeordnet – GNOME nimmt nicht immer denselben.
        local exe=${id#@exec:} extra
        local -a ids=()
        mapfile -t ids < <(find_desktop "^Exec=([^ ]*/)?${exe}" '*.desktop' all)
        (( ${#ids[@]} )) || { warn "Keine .desktop-Datei für «$exe» gefunden – übersprungen"; continue; }
        id=${ids[0]}
        for extra in "${ids[@]:1}"; do mapping+=("'$extra:$ws'"); done
        ;;
      *)
        desktop_exists "$id" || { warn "$id nicht gefunden – übersprungen"; continue; }
        ;;
    esac
    [[ -z $cmd ]] && cmd="gtk-launch ${id%.desktop}"

    if [[ -n $pattern ]] && pgrep -f -- "$pattern" >/dev/null; then
      ok "$(printf 'Fläche %s  %-32s läuft bereits' "$ws" "$id")"
      continue
    fi
    mapping+=("'$id:$ws'")
    to_launch+=("$ws|$id|$cmd")
  done

  (( ${#to_launch[@]} )) || { ok "Alles läuft bereits"; return 0; }

  # Temporäre Zuordnung setzen
  local list
  list="[$(IFS=,; echo "${mapping[*]}")]"
  save_automove
  run gsettings set "$AUTOMOVE_SCHEMA" application-list "$list"
  automove_enabled || run gnome-extensions enable "$AUTOMOVE_UUID"
  (( DRY_RUN )) || sleep 1   # Extension Zeit geben, die neue Liste zu laden

  # Apps starten
  local item
  for item in "${to_launch[@]}"; do
    IFS='|' read -r ws id cmd <<< "$item"
    info "$(printf 'Fläche %s  %s' "$ws" "$id")"
    # shellcheck disable=SC2086  # cmd soll in Wörter aufgeteilt werden
    if (( DRY_RUN )); then
      printf '  %s[dry-run] %s%s\n' "$C_DIM" "$cmd" "$C_RST"
    else
      setsid -f $cmd >/dev/null 2>&1
    fi
    (( DRY_RUN )) || sleep 0.5
  done

  schedule_restore
}

# ============================================================================
#  Hauptprogramm
# ============================================================================

case ${1:-} in
  --restore) restore_automove; exit $? ;;
esac

while getopts ":nihV" opt; do
  case $opt in
    n) DRY_RUN=1 ;;
    i) INSTALL_ONLY=1 ;;
    h) usage; exit 0 ;;
    V) echo "$VERSION"; exit 0 ;;
    *) die "Unbekannte Option -$OPTARG (siehe -h)" ;;
  esac
done

[[ -r $OS_RELEASE ]] || die "$OS_RELEASE nicht lesbar"
# shellcheck source=/dev/null
OS_ID=$(. "$OS_RELEASE"; echo "${ID:-}")
[[ $OS_ID == ubuntu ]] || die "Nur Ubuntu wird unterstützt (gefunden: ${OS_ID:-unbekannt}). Für Windows: setup.ps1"

IS_LAYOUT_HOST=0
[[ $(hostname) == "$LAYOUT_HOST" ]] && IS_LAYOUT_HOST=1

(( DRY_RUN )) && warn "Dry-Run – es wird nichts verändert"
ensure_apps

if (( IS_LAYOUT_HOST && ! INSTALL_ONLY )); then
  [[ ${XDG_SESSION_TYPE:-} == wayland || ${XDG_SESSION_TYPE:-} == x11 ]] \
    || die "Keine grafische Sitzung gefunden – Layout übersprungen"
  open_layout
elif (( ! IS_LAYOUT_HOST )); then
  echo; echo "Anderer Rechner ($(hostname)) – Apps werden nicht geöffnet."
fi
