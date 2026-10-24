#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# VSCode-App: Erststart der Team-VM (von cloud-init aufgerufen)
# Gibt jedem Nutzer einen eigenen code-server (127.0.0.1:<port>, eigenes
# Passwort) und stellt alle hinter Caddy unter https://<ip>/<name>/ bereit.
# Idempotent.
# -----------------------------------------------------------------------------

# cloud-init startet runcmd ohne HOME; caddy braucht es.
export HOME=/root

USERS_FILE=/etc/vscode-app/users
WEB_ROOT=/var/www/vscode-app
CADDY_CA=/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt

# Aus Open VSX; schlaegt eine fehl, laeuft die IDE trotzdem.
EXTENSIONS=(ms-python.python redhat.java)

log() { echo "[$(date -Is)] $*"; }

# Nutzerliste vorab lesen: runuser/code-server in einer "while read"-Schleife
# wuerden sonst die restlichen Zeilen von stdin verschlucken.
users=()
ports=()
passwords=()
while read -r user port password; do
  [ -n "$user" ] || continue
  if ! id "$user" >/dev/null 2>&1; then
    log "WARN: Linux-Nutzer $user fehlt, uebersprungen"
    continue
  fi
  users+=("$user")
  ports+=("$port")
  passwords+=("$password")
done <"$USERS_FILE"

# -----------------------------------------------------------------------------
# [1] Pro Nutzer: Beispielprojekte, code-server-Konfiguration, Erweiterungen
# -----------------------------------------------------------------------------
for i in "${!users[@]}"; do
  user=${users[$i]}
  home=$(getent passwd "$user" | cut -d: -f6)
  group=$(id -gn "$user")
  log "Setting up $user (port ${ports[$i]})..."

  # Beispielprojekte nachreichen, falls der Nutzer vor /etc/skel/projekte
  # entstand.
  if [ -d /etc/skel/projekte ] && [ ! -e "$home/projekte" ]; then
    cp -r /etc/skel/projekte "$home/projekte"
    chown -R "$user:$group" "$home/projekte"
  fi

  runuser -u "$user" -- mkdir -p \
    "$home/.config/code-server" \
    "$home/.local/share/code-server/User" </dev/null

  # Passwort in Anfuehrungszeichen: es darf mit ! @ % oder * beginnen.
  (
    umask 077
    cat >"$home/.config/code-server/config.yaml" <<EOF
bind-addr: 127.0.0.1:${ports[$i]}
auth: password
password: "${passwords[$i]}"
cert: false
disable-telemetry: true
disable-update-check: true
EOF
  )
  chown "$user:$group" "$home/.config/code-server/config.yaml"

  settings="$home/.local/share/code-server/User/settings.json"
  if [ ! -e "$settings" ]; then
    cat >"$settings" <<'EOF'
{
  "security.workspace.trust.enabled": false,
  "workbench.startupEditor": "none",
  "telemetry.telemetryLevel": "off",
  "terminal.integrated.defaultProfile.linux": "bash"
}
EOF
    chown "$user:$group" "$settings"
  fi

  # Erweiterungen aller Nutzer parallel laden, das spart Minuten.
  (
    for ext in "${EXTENSIONS[@]}"; do
      runuser -u "$user" -- env HOME="$home" \
        code-server --install-extension "$ext" </dev/null >/dev/null 2>&1 ||
        log "WARN: Erweiterung $ext fuer $user nicht installiert"
    done
  ) &
done

log "Waiting for extension installs..."
wait

for user in "${users[@]}"; do
  systemctl enable "code-server@$user"
  systemctl restart "code-server@$user"
done

# -----------------------------------------------------------------------------
# [2] Firewall
# -----------------------------------------------------------------------------
# Erst SSH freigeben, dann einschalten. code-server selbst bleibt auf
# 127.0.0.1 und ist nur ueber Caddy erreichbar.
log "Configuring ufw..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# -----------------------------------------------------------------------------
# [3] Startseite und Caddy
# -----------------------------------------------------------------------------
# Ohne Domain kein Let's-Encrypt-Zertifikat: Caddy stellt eines aus seiner
# eigenen CA fuer die IP-Adressen aus. Die CA liegt zum Herunterladen auf
# der Startseite, damit man ihr im Browser vertrauen kann.
#
# Alle globalen Adressen, nicht nur die erste: bei ip_mode dual hat die VM
# zwei IPv4 (die private im IPv6-Netz und die oeffentliche der zweiten
# Schnittstelle), und Caddy beantwortet nur Adressen, die im Caddyfile
# stehen.
sites=()
while read -r addr; do
  sites+=("https://[$addr]")
done < <(ip -6 -o addr show scope global | awk '{print $4}' | cut -d/ -f1)
while read -r addr; do
  sites+=("https://$addr")
done < <(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1)
if [ "${#sites[@]}" -eq 0 ]; then
  log "ERROR: keine IP-Adresse gefunden"
  exit 1
fi

# Teamnamen kommen aus dem AppStore; fuer HTML maskieren.
team=$(tr -d '"' </etc/vscode-app/team | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
install -d -m 0755 "$WEB_ROOT"
{
  cat <<EOF
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>VS Code – ${team}</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 40rem; margin: 3rem auto; padding: 0 1rem; color: #1f2328; background: #fff; }
  a { color: #0969da; }
  li { margin: .4rem 0; font-size: 1.15rem; }
  .hint { color: #59636e; font-size: .95rem; }
</style>
</head>
<body>
<h1>VS Code im Browser</h1>
<p>Team <strong>${team}</strong>. Wähle deinen Benutzernamen und melde dich
mit dem Passwort aus der E-Mail an.</p>
<ul>
EOF
  for user in "${users[@]}"; do
    home=$(getent passwd "$user" | cut -d: -f6)
    echo "  <li><a href=\"/$user/?folder=$home/projekte\">$user</a></li>"
  done
  cat <<'EOF'
</ul>
<p class="hint">Das Zertifikat stammt von einer eigenen Zertifizierungsstelle
der VM, der Browser warnt deshalb beim ersten Aufruf. Wer die Warnung nicht
wegklicken möchte oder in Chrome Probleme mit Vorschauen hat, importiert
<a href="/ca.crt">ca.crt</a> als vertrauenswürdige Stelle.</p>
</body>
</html>
EOF
} >"$WEB_ROOT/index.html"

log "Writing Caddyfile for ${sites[*]}..."
{
  echo '{'
  echo '	skip_install_trust'
  echo '}'
  echo
  # Caddy trennt mehrere Adressen per Leerzeichen.
  echo "${sites[*]} {"
  echo '	tls internal'
  for i in "${!users[@]}"; do
    user=${users[$i]}
    echo "	redir /$user /$user/"
    echo "	handle /$user/* {"
    echo "		uri strip_prefix /$user"
    echo "		reverse_proxy 127.0.0.1:${ports[$i]}"
    echo '	}'
  done
  echo '	handle {'
  echo "		root * $WEB_ROOT"
  echo '		file_server'
  echo '	}'
  echo '}'
} >/etc/caddy/Caddyfile

caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl enable caddy
systemctl restart caddy

# Caddy legt seine CA beim ersten Zertifikat an.
for _ in $(seq 1 30); do
  [ -s "$CADDY_CA" ] && break
  sleep 2
done
if [ -s "$CADDY_CA" ]; then
  install -m 0644 "$CADDY_CA" "$WEB_ROOT/ca.crt"
else
  log "WARN: Caddy-CA nicht gefunden, ca.crt fehlt auf der Startseite"
fi

log "VSCode-App bereit."
