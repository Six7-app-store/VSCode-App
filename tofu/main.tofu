# OpenTofu erwartet weiterhin das Schluesselwort "terraform"; die Provider
# werden ueber registry.opentofu.org aufgeloest. .tofu-Dateien ab 1.8.
terraform {
  required_version = ">= 1.8"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

provider "openstack" {
  cloud = "openstack"
}

############################
# APP-DEFAULTS
############################

locals {
  app_name = "vscode"

  # Wie bei den anderen Apps: keine Floating IP. Zwischen VM-Subnetz und
  # externem Netz fehlt der Router; oeffentlich erreichbar ist die VM ueber
  # die feste Adresse der gewaehlten Familie (var.ip_mode).
  enable_floating_ip = false

  # code-server des ersten Nutzers lauscht auf 127.0.0.1:8001, der zweite
  # auf 8002 usw. Von aussen erreichbar ist nur Caddy auf 443.
  first_port = 8001
}

############################
# ADRESSFAMILIEN (var.ip_mode)
############################

locals {
  ethertypes = {
    ipv4 = ["IPv4"]
    ipv6 = ["IPv6"]
    dual = ["IPv4", "IPv6"]
  }[var.ip_mode]

  # Bei dual liegt die Hauptschnittstelle im IPv6-Netz: dessen private IPv4
  # bringt den Weg nach draussen (Paketquellen) ueber NAT mit, die
  # oeffentliche IPv4 kommt als zweite Schnittstelle dazu.
  primary_network_id = var.ip_mode == "ipv4" ? var.network_v4_uuid : var.network_uuid

  dual = var.ip_mode == "dual"
}

############################
# USER MANAGEMENT (CONTRACT)
############################

locals {
  # Der Benutzername ist Linux-Login und Pfad der IDE (https://<ip>/<name>/).
  # Linux-Namen muessen mit einem Buchstaben beginnen - "anna.schulz" wird
  # so zu "annaschulz".
  all_users = flatten([
    for team, members in var.users : [
      for member in members : {
        id    = "${team}-${replace(split("@", member.email)[0], ".", "-")}"
        team  = team
        email = member.email
        username = (
          can(regex("^[a-z]", lower(replace(split("@", member.email)[0], "/[^A-Za-z0-9]/", ""))))
          ? substr(lower(replace(split("@", member.email)[0], "/[^A-Za-z0-9]/", "")), 0, 30)
          : "u${substr(lower(replace(split("@", member.email)[0], "/[^A-Za-z0-9]/", "")), 0, 29)}"
        )
      }
    ]
  ])

  users_map  = { for user in local.all_users : user.id => user }
  teams_list = distinct([for user in local.all_users : user.team])

  # VM-Name: Teamnamen wie "Team #1" sind als Hostname unzulaessig.
  team_slugs = {
    for team in local.teams_list : team => trim(replace(lower(team), "/[^a-z0-9-]+/", "-"), "-")
  }

  # Mitglieder je Team in fester Reihenfolge (Map-Schluessel sind sortiert),
  # damit jeder Nutzer bei jedem Plan denselben Port behaelt.
  team_members = {
    for team in local.teams_list : team => [
      for uid, user in local.users_map : uid if user.team == team
    ]
  }
}

# Ein Passwort pro User, gilt fuer SSH und die IDE. Sonderzeichen bewusst
# eingeschraenkt; das Passwort landet im cloud-init-YAML und in der
# code-server-Konfiguration.
resource "random_password" "user_passwords" {
  for_each         = local.users_map
  length           = 16
  special          = true
  override_special = "!@%^*_-+="
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

# Abbruch vor dem Anlegen, wenn zu viele Teams kommen.
resource "terraform_data" "team_limit" {
  input = length(local.teams_list)

  lifecycle {
    precondition {
      condition     = length(local.teams_list) <= var.max_teams
      error_message = "Dieses Deployment wuerde ${length(local.teams_list)} Team-VMs anlegen, erlaubt sind ${var.max_teams}. Teams zusammenlegen oder max_teams erhoehen."
    }
  }
}

# Normales Ubuntu-Image; die Software installiert cloud-init beim ersten Boot.
data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true
}

# External network nur abfragen, wenn Floating IPs aktiv sind - sonst bricht
# der Plan ab, falls das Netz im Projekt nicht existiert.
data "openstack_networking_network_v2" "external" {
  count = local.enable_floating_ip ? 1 : 0
  name  = var.floating_ip_pool
}

############################
# SECURITY GROUP FUER HTTPS
############################

# Die gemeinsame Default-SG laesst 80/443 nicht durch und gehoert nicht dieser
# App (wie bei Kali fuer RDP). Deshalb eine eigene, zusaetzlich an der VM.
# Regeln je Adressfamilie aus var.ip_mode: eine IPv4-Regel laesst kein
# IPv6-Paket durch und umgekehrt.
# Der Zufallsanhang verhindert doppelte Namen bei mehreren Deployments im
# selben Projekt - die Instanz referenziert Security Groups per Name.
resource "random_string" "secgroup_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "openstack_networking_secgroup_v2" "web" {
  name        = "${local.app_name}-web-${random_string.secgroup_suffix.result}"
  description = "HTTPS-Zugang (80/443) fuer VS Code im Browser"
}

resource "openstack_networking_secgroup_rule_v2" "web" {
  for_each = {
    for pair in setproduct(local.ethertypes, [80, 443]) : "${pair[0]}-${pair[1]}" => {
      ethertype = pair[0]
      port      = pair[1]
    }
  }

  direction         = "ingress"
  ethertype         = each.value.ethertype
  protocol          = "tcp"
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = each.value.ethertype == "IPv4" ? var.web_source_cidr_v4 : var.web_source_cidr
  security_group_id = openstack_networking_secgroup_v2.web.id
}

# Zweite Schnittstelle fuer dual, vorab als Port angelegt: so sind MAC und
# Adresse schon bekannt, wenn cloud-init sein user-data bekommt.
resource "openstack_networking_port_v2" "team_v4" {
  for_each   = local.dual ? toset(local.teams_list) : toset([])
  name       = "${local.app_name}-${local.team_slugs[each.key]}-v4"
  network_id = var.network_v4_uuid

  security_group_ids = [
    var.shared_secgroup_id,
    openstack_networking_secgroup_v2.web.id,
  ]
}

locals {
  secondary = {
    for team, port in openstack_networking_port_v2.team_v4 : team => {
      mac  = port.mac_address
      ipv4 = one([for ip in port.all_fixed_ips : ip if !strcontains(ip, ":")])
    }
  }
  secondary_gateway = local.dual ? data.openstack_networking_subnet_v2.v4[0].gateway_ip : ""
}

# Gateway des IPv4-Netzes fuer die eigene Routing-Tabelle der zweiten
# Schnittstelle (dual), siehe cloud-init.yml.tpl.
data "openstack_networking_subnet_v2" "v4" {
  count      = local.dual ? 1 : 0
  network_id = var.network_v4_uuid
  ip_version = 4

  lifecycle {
    postcondition {
      condition     = self.gateway_ip != ""
      error_message = "Das IPv4-Netz in network_v4_uuid hat kein Gateway; dual braucht eins fuer die Antworten der zweiten Schnittstelle."
    }
  }
}

############################
# EINE VM PRO TEAM
############################

resource "openstack_compute_instance_v2" "team_vm" {
  for_each = toset(local.teams_list)

  name        = "${local.app_name}-${local.team_slugs[each.key]}"
  image_id    = data.openstack_images_image_v2.image.id
  flavor_name = var.flavor_name
  key_pair    = null

  # Security Groups per NAME; die geteilte kommt als UUID/Name aus der Variable.
  security_groups = [var.shared_secgroup_id, openstack_networking_secgroup_v2.web.name]

  timeouts {
    create = "15m"
    delete = "15m"
  }

  # Nur die Hauptschnittstelle. Die zweite bei dual haengt interface_attach
  # unten an: als zweiter network-Block wuerde cloud-init sie beim ersten
  # Boot mit einer eigenen Default-Route einrichten.
  network {
    uuid = local.primary_network_id
  }

  # Skripte gzip+base64: so stoeren ${...} der Shell das Template nicht, und
  # user_data bleibt weit unter dem Nova-Limit von 64 KB.
  user_data = templatefile("${path.module}/cloud-init.yml.tpl", {
    install_gz   = base64gzip(file("${path.module}/files/install.sh"))
    provision_gz = base64gzip(file("${path.module}/files/vscode-provision.sh"))
    projekt_files = {
      for f in fileset("${path.module}/files/projekte", "**") :
      f => base64gzip(file("${path.module}/files/projekte/${f}"))
    }
    team_name = each.key
    team_users = [
      for i, uid in local.team_members[each.key] : {
        username = local.users_map[uid].username
        password = random_password.user_passwords[uid].result
        port     = local.first_port + i
      }
    ]
    secondary_mac     = local.dual ? local.secondary[each.key].mac : ""
    secondary_ipv4    = local.dual ? local.secondary[each.key].ipv4 : ""
    secondary_gateway = local.secondary_gateway
  })

  metadata = {
    team = each.key
    app  = local.app_name
  }

  depends_on = [terraform_data.team_limit, openstack_networking_secgroup_rule_v2.web]

  lifecycle {
    precondition {
      condition     = var.ip_mode == "ipv6" || var.network_v4_uuid != ""
      error_message = "ip_mode \"${var.ip_mode}\" braucht ein IPv4-Netz in network_v4_uuid."
    }
    precondition {
      condition     = var.ip_mode == "ipv4" || var.network_uuid != ""
      error_message = "ip_mode \"${var.ip_mode}\" braucht ein IPv6-Netz in network_uuid."
    }
  }
}

# Zweite Schnittstelle (dual) an die laufende Instanz. Eingerichtet wird sie
# von cloud-init, das auf ihre MAC wartet - siehe runcmd in cloud-init.yml.tpl.
resource "openstack_compute_interface_attach_v2" "team_v4" {
  for_each    = openstack_networking_port_v2.team_v4
  instance_id = openstack_compute_instance_v2.team_vm[each.key].id
  port_id     = each.value.id
}

############################
# FLOATING IPs (optional)
############################

resource "openstack_networking_floatingip_v2" "team_fip" {
  for_each = local.enable_floating_ip ? toset(local.teams_list) : toset([])
  pool     = data.openstack_networking_network_v2.external[0].name
}

data "openstack_networking_port_v2" "vm_port" {
  for_each  = local.enable_floating_ip ? toset(local.teams_list) : toset([])
  device_id = openstack_compute_instance_v2.team_vm[each.key].id
}

resource "openstack_networking_floatingip_associate_v2" "team_fip_assoc" {
  for_each    = local.enable_floating_ip ? toset(local.teams_list) : toset([])
  floating_ip = openstack_networking_floatingip_v2.team_fip[each.key].address
  port_id     = data.openstack_networking_port_v2.vm_port[each.key].id
}

# Paketinstallation, code-server, Erweiterungen und Caddy dauern nach ACTIVE
# noch einige Minuten. Ohne Warten gingen die Zugangsdaten zu frueh raus.
resource "time_sleep" "wait_for_ide" {
  depends_on      = [openstack_compute_instance_v2.team_vm, openstack_compute_interface_attach_v2.team_v4]
  create_duration = "420s"
}

############################
# ADRESSEN
############################

# Verbindungsziel je Team. Bei ipv6 die IPv6-Adresse (die IPv4 im IPv6-Netz
# ist eine projektinterne NAT-Adresse), bei ipv4 die feste IPv4, bei dual die
# oeffentliche IPv4 der zweiten Schnittstelle, weil sie mehr Heimnetze
# erreicht. team_ip ohne Klammern (fuer ssh), team_url mit Klammern, wie es
# ein Browser fuer IPv6 verlangt. access_ip_v6 liefert der Provider schon mit
# Klammern; trim() nimmt sie ab, sonst entstuende https://[[...]]/.
locals {
  team_ip = {
    for team in local.teams_list : team => (
      local.enable_floating_ip ? openstack_networking_floatingip_v2.team_fip[team].address
      : var.ip_mode == "ipv4" ? openstack_compute_instance_v2.team_vm[team].network[0].fixed_ip_v4
      : local.dual ? local.secondary[team].ipv4
      : (
        openstack_compute_instance_v2.team_vm[team].access_ip_v6 != ""
        ? trim(openstack_compute_instance_v2.team_vm[team].access_ip_v6, "[]")
        : openstack_compute_instance_v2.team_vm[team].network[0].fixed_ip_v4
      )
    )
  }

  team_url = {
    for team, ip in local.team_ip : team => (
      strcontains(ip, ":") ? "https://[${ip}]/" : "https://${ip}/"
    )
  }
}
