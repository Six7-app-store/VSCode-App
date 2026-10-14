#cloud-config

# SSH mit Passwort-Auth aktivieren (fuer Terminal und SSH-Tunnel).
ssh_pwauth: true

# Benutzer anlegen - ohne sudo. code-server laeuft je Nutzer unter dessen
# eigenem Konto, richtet vscode-provision.sh ein.
# jsonencode() quotet jeden Wert, damit YAML nichts davon umdeutet.
users:
%{ for user in team_users ~}
  - name: ${jsonencode(user.username)}
    shell: /bin/bash
    lock_passwd: false
%{ endfor ~}

# Passwoerter zwingend ueber jsonencode(): eines, das mit ! @ % oder *
# beginnt, waere als unquotierter Skalar ein YAML-Syntaxfehler.
chpasswd:
  expire: false
  users:
%{ for user in team_users ~}
    - name: ${jsonencode(user.username)}
      password: ${jsonencode(user.password)}
      type: text
%{ endfor ~}

write_files:
  - path: /etc/ssh/sshd_config.d/99-vscode-app.conf
    permissions: '0644'
    content: |
      PasswordAuthentication yes
      PubkeyAuthentication yes
      PermitRootLogin no
      UsePAM yes

  # Eine Zeile pro Nutzer: "<benutzername> <port> <passwort>". Nur root darf
  # lesen; vscode-provision.sh schreibt daraus die code-server-Konfiguration.
  - path: /etc/vscode-app/users
    permissions: '0600'
    owner: 'root:root'
    content: |
%{ for user in team_users ~}
      ${user.username} ${user.port} ${user.password}
%{ endfor ~}

  - path: /etc/vscode-app/team
    permissions: '0644'
    content: ${jsonencode(team_name)}

  # Skripte und Beispielprojekte (aus tofu/files/, gzip+base64).
  - path: /usr/local/sbin/vscode-install.sh
    permissions: '0755'
    encoding: gz+b64
    content: ${install_gz}

  - path: /usr/local/sbin/vscode-provision.sh
    permissions: '0755'
    encoding: gz+b64
    content: ${provision_gz}

%{ for name, data in projekt_files ~}
  - path: ${jsonencode("/etc/skel/projekte/${name}")}
    permissions: '0644'
    encoding: gz+b64
    content: ${data}

%{ endfor ~}
# Erst Software installieren, dann code-server und Caddy einrichten.
runcmd:
  - systemctl restart ssh
  - bash -c "/usr/local/sbin/vscode-install.sh && /usr/local/sbin/vscode-provision.sh" > /var/log/vscode-provision.log 2>&1

final_message: "VS-Code-Team-VM bereit - Log unter /var/log/vscode-provision.log"
