# workspace-setup

Ein Befehl, und die Arbeitsumgebung ist startklar: Das Skript prüft, ob meine Standard-Apps installiert sind, installiert fehlende aus offiziellen Quellen und verteilt sie auf meinem Laptop automatisch auf vier GNOME-Arbeitsflächen – **ohne** dauerhafte Fensterregeln.

```
== Apps prüfen ==
✔ Firefox
✔ Proton Pass
⬇ Brave fehlt – wird installiert
✔ Brave installiert
✔ Discord
✔ Brave Origin
✔ Chromium (für Outlook/Teams-PWA)

== Arbeitsflächen einrichten ==
⬇ Fläche 1  org.gnome.Nautilus.desktop
⬇ Fläche 2  firefox_firefox.desktop
⬇ Fläche 3  chrome-faoln…-Default.desktop
⬇ Fläche 3  chrome-ompif…-Default.desktop
⬇ Fläche 4  brave-origin.desktop
✔ Fläche 4  discord_discord.desktop          läuft bereits
✔ Zuordnung wird in 60s automatisch zurückgesetzt
```

## Was passiert wo?

| System | Apps prüfen & installieren | Apps öffnen & verteilen |
|---|---|---|
| Ubuntu-Laptop (`it-fasi`) | Firefox, Proton Pass, Brave, Discord, **Brave Origin** | ✔ |
| Anderes Ubuntu | Firefox, Proton Pass, Brave, Discord | – |
| Windows 11 (`setup.ps1`) | Firefox, Proton Pass, Brave, Discord | – |

### Layout auf dem Laptop

| Fläche | Apps |
|---|---|
| 1 | Dateimanager (Nautilus) – das Terminal, aus dem das Skript läuft, ist ja schon da |
| 2 | Firefox |
| 3 | Outlook-PWA, Teams-PWA (Chromium) |
| 4 | Brave Origin, Discord |

Apps, die schon laufen, werden nicht doppelt geöffnet.

## Wie das Verteilen unter Wayland funktioniert

Unter Wayland dürfen Programme fremde Fenster nicht verschieben. Das Skript nutzt deshalb die offizielle GNOME-Extension **Auto Move Windows** – aber nur **vorübergehend**:

1. Die aktuelle Konfiguration der Extension wird gesichert.
2. Die Zuordnung «App → Arbeitsfläche» wird gesetzt und die Extension (falls nötig) aktiviert.
3. Die Apps werden gestartet; GNOME schiebt jedes neue Fenster auf seine Fläche.
4. Nach 60 Sekunden setzt ein `systemd-run`-Timer alles wieder auf den vorherigen Zustand zurück.

Danach gelten keine festen Regeln mehr – neue Arbeitsflächen und Fenster verhalten sich ganz normal, und die dynamischen Arbeitsflächen bleiben erhalten.

## Installation

### Ubuntu

```bash
git clone https://github.com/<dein-user>/workspace-setup.git
cd workspace-setup
install -Dm755 workspace-setup.sh ~/.local/bin/workspace-setup
workspace-setup -n     # Testlauf
workspace-setup        # richtig ausführen
```

Voraussetzungen: Ubuntu mit GNOME, Paket `gnome-shell-extensions` (bei Ubuntu vorinstalliert), `curl`, `python3`.

### Windows 11

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1 -DryRun   # Testlauf
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

Nutzt `winget`, das bei Windows 11 dabei ist.

## Optionen (Linux)

| Option | Wirkung |
|---|---|
| `-n` | Dry-Run: nur anzeigen, nichts verändern |
| `-i` | Nur prüfen und installieren, nichts öffnen |
| `--restore` | Fensterzuordnung sofort zurücksetzen |
| `-h` / `-V` | Hilfe / Version |

## Installationsquellen

| App | Ubuntu | Windows (winget-ID) |
|---|---|---|
| Firefox | Snap | `Mozilla.Firefox` |
| Proton Pass | offizielles .deb von proton.me, SHA-512 geprüft | `Proton.ProtonPass` |
| Brave / Brave Origin | offizielles Brave-APT-Repo (`brave-browser` / `brave-origin`) | `Brave.Brave` |
| Discord | Snap | `Discord.Discord` |

`sudo` wird nur abgefragt, wenn tatsächlich etwas installiert werden muss.

## Anpassen

Alles Wichtige steht im Konfigurationsblock oben in `workspace-setup.sh`:

```bash
LAYOUT_HOST="it-fasi"   # nur hier wird geöffnet
RESTORE_DELAY=60        # Sekunden bis zum Zurücksetzen

LAYOUT=(
  # Fläche | Desktop-ID | Startbefehl | Prozessmuster
  "2|firefox_firefox.desktop|firefox|/snap/firefox/.*/firefox"
  "3|@pwa:Outlook||"                     # PWA per Name suchen
  "4|@exec:brave-origin|brave-origin|brave-origin"
)
```

Die Desktop-ID einer App findest du mit `ls /usr/share/applications /var/lib/snapd/desktop/applications`.

## Fehlersuche

- **Ein Fenster landet auf der falschen Fläche:** Die App hat länger als `RESTORE_DELAY` gebraucht → Wert erhöhen.
- **Zuordnung hängt:** `workspace-setup --restore`
- **PWA wird nicht gefunden:** Der Name im Layout muss im `Name=`-Eintrag der `chrome-*-Default.desktop`-Datei vorkommen.

## Lizenz

MIT
