# VSCode-App

VS Code im Browser für Hochschulkurse. Jedes Team bekommt eine **eigene VM**,
jedes Teammitglied darauf einen **eigenen code-server** mit eigenem Passwort.
Programmieren, Terminal und Git laufen komplett im Browser – lokal muss
nichts installiert werden.

## Zugang

Die E-Mail des AppStores enthält die Team-Adresse, den Benutzernamen und das
Passwort.

1. `https://[<IPv6-Adresse>]/` öffnen – eine Startseite listet alle
   Teammitglieder.
2. Den eigenen Namen anklicken (`https://[<IPv6>]/<benutzername>/`) und mit
   dem Passwort anmelden.

Das Zertifikat stellt Caddy aus einer eigenen CA der VM aus (ohne Domain gibt
es kein Let's Encrypt). Der Browser warnt deshalb beim ersten Aufruf.
Firefox läuft nach dem Wegklicken der Warnung uneingeschränkt. Chrome
blockiert bei nicht vertrauenswürdigem Zertifikat Service Worker, dann
bleiben Markdown-Vorschau und manche Erweiterungsansichten leer. Abhilfe:
`ca.crt` von der Startseite als vertrauenswürdige Stelle importieren oder
einen SSH-Tunnel nutzen:

    ssh -L 8080:127.0.0.1:<port> <benutzername>@<IPv6>
    # dann http://localhost:8080 im Browser

Der Port steht in der Ausgabe `team_vms` nicht, er ist 8001 für das erste
Teammitglied (alphabetisch nach E-Mail), 8002 für das zweite usw.;
auf der VM zeigt ihn `cat ~/.config/code-server/config.yaml`.

## Vorinstallierte Software

- code-server (aktuelle Version) mit Erweiterungen Python (`ms-python.python`)
  und Java (`redhat.java`) aus Open VSX
- Python 3 mit `pip` und `venv`
- Java 21 (OpenJDK) und Maven
- Node.js und npm
- gcc, g++, make, gdb
- Git, curl, jq, vim, nano, htop

Unter `~/projekte/` liegen eine `LIES_MICH.md` und Hallo-Welt-Beispiele für
Python, Java, JavaScript und C.

## User-Management

- **Ein Account pro Nutzer**, abgeleitet aus der E-Mail-Adresse
  (z. B. `anna.schulz@dhbw.de` → Benutzername `annaschulz`)
- Ein zufälliges Passwort pro Nutzer, gilt für die IDE und für SSH
- Jeder code-server läuft unter dem Linux-Konto seines Nutzers und lauscht
  nur auf `127.0.0.1`; von außen erreichbar ist nur Caddy
- Kein `sudo`. Home-Verzeichnisse sind für andere Teammitglieder nicht lesbar

## VM-Deployment

| | |
|---|---|
| VMs | **eine VM pro Team** |
| Flavor | im Wizard wählbar, Standard `gp1.medium` |
| Betriebssystem | Ubuntu 24.04, Software wird beim ersten Boot per cloud-init installiert |
| Erreichbarkeit | IPv6-Adresse der VM, HTTPS auf 443, SSH auf 22 |
| Offene Ports | 22 (SSH), 80 (Weiterleitung auf HTTPS), 443 (IDE) |
| Bereit nach | ca. 6–7 Minuten nach dem Start der VM |
| Obergrenze | `max_teams`, Standard 15 Team-VMs pro Deployment |

Jeder code-server braucht mit geöffnetem Java- oder Python-Projekt einige
hundert MB RAM. `gp1.medium` reicht für kleine Teams, ab etwa fünf Personen
`gp1.large` wählen.

## Konfigurierbare Variablen

| Variable | Wizard-Feld | Standard |
|---|---|---|
| `image_name` | Image-Auswahl | `Ubuntu 24.04` |
| `network_uuid` | Netzwerk-Auswahl | DHBWV6-Netz |
| `shared_secgroup_id` | Security-Group-Auswahl | gemeinsame App-Store-SG |
| `flavor_name` | Flavor-Auswahl | `gp1.medium` |
| `floating_ip_pool` | External-Network-Auswahl (derzeit ungenutzt) | `DHBW` |
| `max_teams` | Obergrenze | `15` |

`users` setzt der AppStore selbst.

## Aufbau

Reine OpenTofu-App nach ADR 0010: ein Ordner `tofu/`, kein Packer, kein
Image-Bau.

    VSCode-App/
    └── tofu/
        ├── main.tofu
        ├── variables.tofu
        ├── outputs.tofu
        ├── cloud-init.yml.tpl          ← legt Nutzer und Dateien an, startet die Skripte
        └── files/
            ├── install.sh              ← Toolchains, Caddy, code-server
            ├── vscode-provision.sh     ← code-server je Nutzer, Caddy, Startseite
            └── projekte/               ← Beispielprojekte (→ /etc/skel)

Beim ersten Boot läuft zuerst `install.sh`, danach `vscode-provision.sh`.
Die Skripte gehen gzip-komprimiert in die `user_data` (Limit 64 KB).

## Fehlersuche

Auf der VM (als Admin über die OpenStack-Konsole):

    cat /var/log/vscode-provision.log
    systemctl status caddy 'code-server@*'
    journalctl -u code-server@<benutzername>
    cat /etc/caddy/Caddyfile

## Lokale Checks

    cd tofu && tofu fmt -check && tofu init -backend=false && tofu validate
    shellcheck tofu/files/*.sh

## Release

Der AppStore deployt nur Git-Tags im Format `v<Major>.<Minor>.<Patch>`.

### v1.0.0

Erste Version: eine VM pro Team, code-server pro Nutzer hinter Caddy,
Python, Java, Node.js und C vorinstalliert.
