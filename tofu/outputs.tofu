############################
# [CONTRACT] User Accounts Output
############################

# Schluessel "<team>-<username>", wie vom AppStore fuer den Mailversand
# verlangt. protocol "web": die Mail zeigt die Team-URL aus team_vms; dort
# fuehrt ein Link zur eigenen IDE, die nach dem Passwort fragt.
# Bewusst ohne "port": aus ip+port baut das Frontend selbst einen Link mit
# http:// (und IPv6 ohne Klammern) statt die Team-URL zu nehmen.
output "user_accounts" {
  description = "[CONTRACT] User accounts mit Login-Informationen"
  sensitive   = true
  value = {
    for uid, user in local.users_map : uid => {
      type     = "password"
      protocol = "web"
      ip       = local.team_ip[user.team]
      username = user.username
      auth     = random_password.user_passwords[uid].result
      email    = user.email
      team     = user.team
    }
  }

  depends_on = [time_sleep.wait_for_ide]
}

############################
# Team-VM Details
############################

# "url" liest der AppStore als Link fuer die Mail.
output "team_vms" {
  description = "Details aller Team-VMs"
  value = {
    for team in local.teams_list : team => {
      instance_id   = openstack_compute_instance_v2.team_vm[team].id
      instance_name = openstack_compute_instance_v2.team_vm[team].name
      ip            = local.team_ip[team]
      url           = local.team_url[team]
      floating_ip   = local.enable_floating_ip ? openstack_networking_floatingip_v2.team_fip[team].address : null
      users = [
        for uid in local.team_members[team] : {
          username    = local.users_map[uid].username
          ide_url     = "${local.team_url[team]}${local.users_map[uid].username}/"
          ssh_command = "ssh ${local.users_map[uid].username}@${local.team_ip[team]}"
        }
      ]
    }
  }

  depends_on = [time_sleep.wait_for_ide]
}

output "teams_summary" {
  description = "Übersicht: Teams und User-Anzahl"
  value = {
    for team in local.teams_list : team => length([for u in local.all_users : u if u.team == team])
  }
}
