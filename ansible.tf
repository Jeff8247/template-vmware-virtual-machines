# ─── Ansible Inventory Generation ─────────────────────────────────────────────
# Writes under inventory/ on terraform apply:
#   inventory/hosts.yml                  — group structure
#   inventory/group_vars/all.yml         — vCenter connection vars + ISO datastore path
#   inventory/group_vars/linux.yml       — shared SSH connection vars
#   inventory/group_vars/windows.yml     — shared WinRM connection vars
#   inventory/host_vars/<vm>.yml         — per-VM: IP, hostname, domain facts
#
# Pass the directory to Ansible: ansible-playbook -i inventory/ playbook.yml
# IPs come from VMware Tools (module.vm[k].default_ip_address).

locals {
  # ── Group membership ────────────────────────────────────────────────────────
  ansible_linux_hosts   = { for k, v in var.vms : k => {} if !v.is_windows }
  ansible_windows_hosts = { for k, v in var.vms : k => {} if v.is_windows }
  ansible_domain_hosts = {
    for k, v in var.vms : k => {}
    if try(coalesce(v.windows_domain, var.windows_domain), null) != null
  }

  # Flatten VM+tag pairs to build tag-based groups
  ansible_vm_tag_entries = flatten([
    for k, v in var.vms : [
      for cat, tag in coalesce(v.tags, var.tags, {}) : {
        vm  = k
        grp = "tag_${lower(replace(cat, " ", "_"))}_${lower(replace(tag, " ", "_"))}"
      }
    ]
  ])

  ansible_tag_group_names = distinct([
    for e in local.ansible_vm_tag_entries : e.grp
  ])

  ansible_tag_groups = {
    for grp in local.ansible_tag_group_names : grp => {
      hosts = { for e in local.ansible_vm_tag_entries : e.vm => {} if e.grp == grp }
    }
  }

  ansible_inventory = {
    all = {
      children = merge(
        { linux = { hosts = local.ansible_linux_hosts } },
        { windows = { hosts = local.ansible_windows_hosts } },
        length(local.ansible_domain_hosts) > 0 ? { domain_joined = { hosts = local.ansible_domain_hosts } } : {},
        local.ansible_tag_groups
      )
    }
  }
}

# ── inventory/group_vars/all.yml ─────────────────────────────────────────────
# Sourced directly from terraform.tfvars — no manual editing needed.
# The vCenter password is never written to disk; pass VMWARE_PASSWORD as an
# environment variable at playbook runtime.
resource "local_file" "ansible_group_vars_all" {
  filename = "${path.root}/inventory/group_vars/all.yml"
  content = yamlencode({
    vcenter_fqdn           = var.vsphere_server
    vcenter_username       = var.vsphere_user
    vm_datacenter          = var.datacenter
    vm_cluster             = var.cluster
    iso_datastore_path     = "[${coalesce(var.iso_datastore, var.datastore)}] ${var.iso_folder}"
    iso_filename           = var.iso_filename
    vlan                   = var.vlan
    windows_domain         = var.windows_domain
    windows_domain_netbios = var.windows_domain_netbios
    sccm_management_point  = var.sccm_management_point
    sccm_site_code         = var.sccm_site_code
  })
  file_permission = "0644"
}

# ── inventory/hosts.yml ───────────────────────────────────────────────────────
resource "local_file" "ansible_hosts" {
  filename        = "${path.root}/inventory/hosts.yml"
  content         = yamlencode(local.ansible_inventory)
  file_permission = "0644"
}

# ── inventory/group_vars/linux.yml ────────────────────────────────────────────
resource "local_file" "ansible_group_vars_linux" {
  filename = "${path.root}/inventory/group_vars/linux.yml"
  content = yamlencode({
    ansible_connection    = "ssh"
    ansible_port          = 22
    ansible_user          = var.ansible_linux_user
    ansible_become        = true
    ansible_become_method = "sudo"
  })
  file_permission = "0644"
}

# ── inventory/group_vars/windows.yml ─────────────────────────────────────────
resource "local_file" "ansible_group_vars_windows" {
  filename = "${path.root}/inventory/group_vars/windows.yml"
  content = yamlencode({
    ansible_connection                   = "winrm"
    ansible_port                         = 5985
    ansible_user                         = var.ansible_windows_user
    ansible_winrm_transport              = var.ansible_winrm_transport
    ansible_winrm_server_cert_validation = var.ansible_winrm_cert_validation
  })
  file_permission = "0644"
}

# ── inventory/host_vars/<vm>.yml ──────────────────────────────────────────────
resource "local_file" "ansible_host_vars" {
  for_each = var.vms

  filename = "${path.root}/inventory/host_vars/${each.key}.yml"
  content = yamlencode(merge(
    # Per-host identity — always present
    {
      ansible_host  = module.vm[each.key].default_ip_address
      computer_name = local.vms_resolved[each.key].computer_name
      vm_uuid       = module.vm[each.key].uuid
    },
    # DNS domain — when set at VM or global level
    try(coalesce(each.value.domain, var.domain), null) != null ? {
      domain = coalesce(each.value.domain, var.domain)
    } : {},
    # AD domain — when set at VM or global level
    try(coalesce(each.value.windows_domain, var.windows_domain), null) != null ? {
      windows_domain = coalesce(each.value.windows_domain, var.windows_domain)
    } : {},
    # AD OU — only when both domain and OU are set
    try(coalesce(each.value.windows_domain, var.windows_domain), null) != null &&
    try(coalesce(each.value.windows_domain_ou, var.windows_domain_ou), null) != null ? {
      windows_domain_ou = coalesce(each.value.windows_domain_ou, var.windows_domain_ou)
    } : {}
  ))
  file_permission = "0640"
}
