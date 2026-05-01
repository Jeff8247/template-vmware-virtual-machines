# ══════════════════════════════════════════════════════════════════════════════
#  ENVIRONMENT CONFIG — set once per environment, commit and leave alone
# ══════════════════════════════════════════════════════════════════════════════

# ─── vCenter Connection ───────────────────────────────────────────────────────
vsphere_server = "vcenter.corp.example.com"
vsphere_user   = "administrator@vsphere.local"
# vsphere_password = set via TF_VAR_vsphere_password

# ─── Infrastructure Placement ─────────────────────────────────────────────────
datacenter = "MYDC01"
cluster    = "MYCLU01"
datastore  = "MYDS01"
vm_folder  = "VMs/Servers"

# ─── Templates ────────────────────────────────────────────────────────────────
template_name_linux = "template-rhel-9-lts"

# ─── Global VM Defaults ───────────────────────────────────────────────────────
network_interfaces = [{ network_name = "NET01" }]
dns_servers        = ["10.0.0.1", "10.0.0.2"]
dns_suffix_list    = ["corp.example.com"]
domain             = "corp.example.com"
time_zone_linux    = "Australia/Brisbane"
hardware_version   = 21

# ─── Domain Join ──────────────────────────────────────────────────────────────
# Linux domain join is handled by Ansible post-boot using realm join.
# windows_domain and windows_domain_netbios are still required — realm uses them.
windows_domain         = "corp.example.com"
windows_domain_netbios = "CORP"
windows_domain_user    = "svc-domainjoin@corp.example.com"
# windows_domain_password = set via TF_VAR_windows_domain_password
windows_domain_ou      = "OU=Servers,DC=corp,DC=example,DC=com"

# ─── Ansible Post-Provisioning ────────────────────────────────────────────────
ansible_linux_user = "ansible"


# ══════════════════════════════════════════════════════════════════════════════
#  VM DEFINITIONS — edit this block for each deployment
# ══════════════════════════════════════════════════════════════════════════════

vms = {

  "lnx-app-01" = {
    is_windows   = false
    num_cpus     = 2
    memory       = 4096
    disks        = [{ label = "OS", size = 80 }]
    ip_settings  = [{ ipv4_address = "10.0.2.101", ipv4_netmask = 24 }]
    ipv4_gateway = "10.0.2.1"
  }

}
