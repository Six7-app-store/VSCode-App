#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# VSCode-App: Software installieren (beim ersten Boot, als root)
# Installiert Compiler/Laufzeiten, Caddy und code-server. Nutzer, Erweiterungen
# und den Reverse Proxy richtet danach vscode-provision.sh ein.
# -----------------------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

echo "Updating package lists..."
apt-get update -y
apt-get install -y curl wget git vim nano htop jq unzip bash-completion ufw ca-certificates

# -----------------------------------------------------------------------------
# [1] Sprachen fuer typische Vorlesungen: C/C++, Python, Java, JavaScript
# -----------------------------------------------------------------------------
echo "Installing toolchains..."
apt-get install -y \
  build-essential gdb \
  python3 python3-pip python3-venv \
  openjdk-21-jdk-headless maven \
  nodejs npm

# -----------------------------------------------------------------------------
# [2] Caddy (Reverse Proxy mit eigenem TLS-Zertifikat) aus Ubuntu universe
# -----------------------------------------------------------------------------
echo "Installing caddy..."
apt-get install -y caddy
caddy version

# -----------------------------------------------------------------------------
# [3] code-server (offizielles Installationsskript, installiert das .deb)
# -----------------------------------------------------------------------------
echo "Installing code-server..."
curl -fsSL https://code-server.dev/install.sh | sh
code-server --version

apt-get clean
echo "Installation finished."
