################################################
# PFLICHT-Variablen
################################################

variable "users" {
  description = "Per-team roster — vom Worker injiziert."
  type = map(list(object({
    email = string
  })))
  default = {}
}

################################################
# Konfigurierbare Variablen
################################################

variable "image_name" {
  description = "Basis-Image (Ubuntu 24.04 empfohlen) @openstack:image:name"
  type        = string
  default     = "Ubuntu 24.04"
}

#   ipv4  eine Schnittstelle im IPv4-Netz (network_v4_uuid)
#   ipv6  eine Schnittstelle im IPv6-Netz (network_uuid) - Standard
#   dual  IPv6-Netz als Hauptschnittstelle, dazu eine zweite im IPv4-Netz
variable "ip_mode" {
  description = "Adressfamilie: ipv4, ipv6 oder dual (beide)"
  type        = string
  default     = "ipv6"

  validation {
    condition     = contains(["ipv4", "ipv6", "dual"], var.ip_mode)
    error_message = "ip_mode muss \"ipv4\", \"ipv6\" oder \"dual\" sein."
  }
}

# Der Name bleibt network_uuid, damit bestehende Deployments beim Redeploy
# ihre gespeicherte Netzwahl weiter treffen.
variable "network_uuid" {
  description = "Netz mit öffentlicher IPv6, z. B. DHBWV6 - für ipv6 und dual @openstack:network:id"
  type        = string
  default     = "9b579624-d844-4df3-b38d-89978b31d37d"
}

variable "network_v4_uuid" {
  description = "Netz mit öffentlich gerouteter IPv4, z. B. DHBWv4 - für ipv4 und dual @openstack:network:id"
  type        = string
  default     = ""
}

variable "floating_ip_pool" {
  description = "Name des External Networks für Floating IPs @openstack:floating_ip_pool:name"
  type        = string
  default     = "DHBW"
}

variable "shared_secgroup_id" {
  description = "ID der gemeinsamen Security Group für alle VMs @openstack:security_group:id"
  type        = string
  default     = "7ca4f889-e11e-4a16-83a8-73a77ebdbbe6"
}

# Die IDE ist passwortgeschuetzt; trotzdem besser auf das Campusnetz
# eingrenzen, wenn niemand von zuhause arbeiten muss.
variable "web_source_cidr" {
  description = "IPv6-Präfix, das auf Port 80/443 (IDE) zugreifen darf"
  type        = string
  default     = "::/0"
}

variable "web_source_cidr_v4" {
  description = "IPv4-Präfix, das auf Port 80/443 (IDE) zugreifen darf - nur bei ip_mode ipv4 und dual"
  type        = string
  default     = "0.0.0.0/0"
}

# Jeder Nutzer hat einen eigenen code-server; die Java- und Python-
# Sprachserver brauchen je Person einige hundert MB RAM. gp1.small reicht
# nur fuer ein bis zwei Personen, fuer grosse Teams gp1.large waehlen.
variable "flavor_name" {
  description = "VM-Größe der Team-VM @openstack:flavor:name"
  type        = string
  default     = "gp1.medium"
}

# Jedes Team bekommt eine eigene VM. Die Obergrenze schuetzt das
# Projektkontingent: lieber eine klare Meldung vor dem Apply als ein
# Quota-Fehler mit halbfertigen Instanzen.
variable "max_teams" {
  description = "Obergrenze gleichzeitiger Team-VMs"
  type        = number
  default     = 15

  validation {
    condition     = var.max_teams >= 1 && var.max_teams <= 30
    error_message = "max_teams muss zwischen 1 und 30 liegen."
  }
}
