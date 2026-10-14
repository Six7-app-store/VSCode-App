# VS Code im Browser

Willkommen! Das hier ist dein eigener Ordner auf der Team-VM.

## Erste Schritte

- **Terminal öffnen:** Menü ☰ → Terminal → New Terminal (oder Strg+`)
- **Programm starten:** Datei öffnen, oben rechts auf ▷ klicken
  oder im Terminal ausführen (siehe unten)

## Beispiele

| Ordner | Starten im Terminal |
|---|---|
| `python/` | `python3 python/hallo.py` |
| `java/` | `cd java && javac Hallo.java && java Hallo` |
| `javascript/` | `node javascript/hallo.js` |
| `c/` | `cd c && gcc -Wall -o hallo hallo.c && ./hallo` |

## Was installiert ist

Python 3 (mit `venv` und `pip`), Java 21 mit Maven, Node.js mit npm,
gcc/g++/make/gdb und Git. Erweiterungen installierst du selbst über das
Erweiterungen-Symbol links (Quelle: Open VSX).

Python-Pakete am besten in einer virtuellen Umgebung:

    python3 -m venv .venv
    . .venv/bin/activate
    pip install requests

## Gut zu wissen

- Deine Dateien liegen unter `/home/<dein-name>/` und bleiben erhalten,
  solange das Deployment läuft. Wichtiges regelmäßig mit Git sichern.
- Kein `sudo`: Pakete systemweit installieren geht nicht, `pip` in einer
  venv und `npm install` im Projekt funktionieren.
- Die anderen im Team arbeiten auf derselben VM, sehen aber deine Dateien
  nicht.
