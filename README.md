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
| Erreichbarkeit | wählbar über IPv6 (Standard), IPv4 oder beides, HTTPS auf 443, SSH auf 22 |
| Offene Ports | 22 (SSH), 80 (Weiterleitung auf HTTPS), 443 (IDE) |
| Security Group | eigene Gruppe `vscode-web-<zufall>` für 80/443 je gewählter Adressfamilie, zusätzlich zur gemeinsamen |
| Bereit nach | ca. 6–7 Minuten nach dem Start der VM |
| Obergrenze | `max_teams`, Standard 15 Team-VMs pro Deployment |

Jeder code-server braucht mit geöffnetem Java- oder Python-Projekt einige
hundert MB RAM. `gp1.medium` reicht für kleine Teams, ab etwa fünf Personen
`gp1.large` wählen.

## Konfigurierbare Variablen

| Variable | Wizard-Feld | Standard |
|---|---|---|
| `image_name` | Image-Auswahl | `Ubuntu 24.04` |
| `ip_mode` | Adressfamilie: `ipv4`, `ipv6` oder `dual` | `ipv6` |
| `network_uuid` | Netz mit öffentlicher IPv6, für `ipv6` und `dual` | DHBWV6-Netz |
| `network_v4_uuid` | Netz mit öffentlich gerouteter IPv4, für `ipv4` und `dual` | leer |
| `shared_secgroup_id` | Security-Group-Auswahl | gemeinsame App-Store-SG |
| `flavor_name` | Flavor-Auswahl | `gp1.medium` |
| `floating_ip_pool` | External-Network-Auswahl (derzeit ungenutzt) | `DHBW` |
| `max_teams` | Obergrenze | `15` |
| `web_source_cidr` | IPv6-Präfix für 80/443 | `::/0` (überall) |
| `web_source_cidr_v4` | IPv4-Präfix für 80/443, nur bei `ipv4` und `dual` | `0.0.0.0/0` (überall) |

`users` setzt der AppStore selbst.

## Adressfamilie (`ip_mode`)

| `ip_mode` | Schnittstellen | Team-URL nennt |
|---|---|---|
| `ipv6` (Standard) | eine, im Netz `network_uuid` | die IPv6 |
| `ipv4` | eine, im Netz `network_v4_uuid` | die IPv4 |
| `dual` | Hauptschnittstelle in `network_uuid`, zweite in `network_v4_uuid` | die IPv4 |

Wie bei der Ubuntu-App: Bei `dual` hängt OpenTofu die IPv4-Schnittstelle
erst an die laufende VM, cloud-init wartet auf sie und richtet sie mit
eigener Routing-Tabelle ein, bevor Caddy startet. Caddy stellt das
Zertifikat für alle Adressen der VM aus. Die IPv4 im Netz `DHBWV6` ist eine
private NAT-Adresse; öffentliches IPv4 gibt es nur über ein eigenes
IPv4-Netz, deshalb brauchen `ipv4` und `dual` die Variable `network_v4_uuid`.

Auf newstack erprobt ist bisher nur `ipv6`.

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

    cd tofu && tofu fmt -check && tofu init -backend=false && tofu validate && tofu test
    shellcheck tofu/files/*.sh

`tofu test` mockt alle Provider und braucht keinen OpenStack-Zugang.

## Release

Der AppStore deployt nur Git-Tags im Format `v<Major>.<Minor>.<Patch>`.

### v1.1.0

Adressfamilie wählbar: `ip_mode` mit `ipv4`, `ipv6` oder `dual`, neue
Variablen `network_v4_uuid` und `web_source_cidr_v4`. Caddy nimmt alle
Adressen der VM ins Zertifikat statt nur der ersten. Tests mit gemockten
Providern unter `tofu/tests/`.

### v1.0.3

Die Team-URL enthielt die IPv6 in doppelten Klammern.

### v1.0.2

Einrichtung lief nicht durch: cloud-init startet die Skripte ohne `HOME`,
das code-server-Installationsskript brach daran ab. Der AppStore zeigt
jetzt die HTTPS-Team-URL statt `http://<ip>:443`.

### v1.0.1

Eigene Security Group für 80/443 über IPv6: die gemeinsame Default-SG
lässt HTTPS nicht durch, die Startseite war daher nicht erreichbar. Neue
Variable `web_source_cidr`.

### v1.0.0

Erste Version: eine VM pro Team, code-server pro Nutzer hinter Caddy,
Python, Java, Node.js und C vorinstalliert.
