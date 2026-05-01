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
template_name_windows = "template-win2k22-ltsc-64bit-datacenter"

# ─── Global VM Defaults ───────────────────────────────────────────────────────
network_interfaces = [{ network_name = "NET01" }]
dns_servers        = ["10.0.0.1", "10.0.0.2"]
dns_suffix_list    = ["corp.example.com"]
domain             = "corp.example.com"
time_zone_windows  = 260 # 260 = E. Australia Standard Time (Brisbane, UTC+10, no DST)
hardware_version   = 21

# ─── Domain Join ──────────────────────────────────────────────────────────────
windows_domain         = "corp.example.com"
windows_domain_netbios = "CORP"
windows_domain_user    = "svc-domainjoin@corp.example.com"
# windows_domain_password = set via TF_VAR_windows_domain_password
windows_domain_ou = "OU=Servers,DC=corp,DC=example,DC=com"

# ─── Windows Credentials ──────────────────────────────────────────────────────
# windows_admin_password = set via TF_VAR_windows_admin_password

# ─── Ansible Post-Provisioning ────────────────────────────────────────────────
iso_datastore = "MYDS01"
iso_folder    = "ISOs/"
iso_filename  = "payload-2024.iso"
vlan          = 100

ansible_windows_user          = "svc-ansible@corp.example.com"
ansible_winrm_transport       = "kerberos"
ansible_winrm_cert_validation = "ignore"


# ══════════════════════════════════════════════════════════════════════════════
#  VM DEFINITIONS — edit this block for each deployment
# ══════════════════════════════════════════════════════════════════════════════

vms = {

  "win-app-01" = {
    is_windows = true
    num_cpus   = 4
    memory     = 8192
    disks = [
      { label = "OS", size = 100 },
      { label = "Data", size = 50 }
    ]
    ip_settings  = [{ ipv4_address = "10.0.1.101", ipv4_netmask = 24 }]
    ipv4_gateway = "10.0.1.1"
  }

}
