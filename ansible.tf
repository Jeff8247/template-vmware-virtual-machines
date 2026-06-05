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

  # Per-VM list of data disks that have a mount_point, with unit_number resolved
  ansible_vm_data_disks = {
    for k, v in var.vms : k => [
      for idx, d in coalesce(v.disks, var.disks) :
      merge(d, { unit_number = coalesce(d.unit_number, idx) })
      if try(d.mount_point, null) != null
    ]
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
# The vCenter password is never written to disk; pass TF_VAR_vsphere_password
# as an environment variable at playbook runtime.
resource "local_file" "ansible_group_vars_all" {
  filename = "${path.root}/inventory/group_vars/all.yml"
  content = yamlencode(merge(
    {
      vcenter_fqdn           = var.vsphere_server
      vcenter_username       = var.vsphere_user
      vm_datacenter          = var.datacenter
      vm_cluster             = var.cluster
      iso_datastore_path     = "[${coalesce(var.iso_datastore, var.datastore)}] ${var.iso_folder}"
      iso_filename           = var.iso_filename
      vlan                   = var.vlan
      windows_domain         = var.windows_domain
      windows_domain_netbios = var.windows_domain_netbios
    },
    var.deployment_environment != null ? { deployment_environment = var.deployment_environment } : {}
  ))
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
  content = yamlencode(merge(
    {
      ansible_connection    = "ssh"
      ansible_port          = 22
      ansible_user          = var.ansible_linux_user
      ansible_become        = true
      ansible_become_method = "sudo"
      realm_join_user       = var.windows_domain_user
    },
    var.domain_site != null ? { domain_site = var.domain_site } : {}
  ))
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
      ansible_host = each.value.is_windows && try(coalesce(each.value.windows_domain, var.windows_domain), null) != null ? format(
        "%s.%s",
        local.vms_resolved[each.key].computer_name,
        coalesce(each.value.windows_domain, var.windows_domain)
      ) : module.vm[each.key].default_ip_address
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
    } : {},
    # AD, local access, maintenance window, and SCCM inputs — optional Ansible post-provisioning inputs
    try(length(each.value.lsa_members), 0) > 0 ? {
      lsa_members = each.value.lsa_members
    } : {},
    try(length(each.value.lsu_members), 0) > 0 ? {
      lsu_members = each.value.lsu_members
    } : {},
    try(each.value.mw_adgroup, null) != null ? {
      mw_adgroup = each.value.mw_adgroup
    } : {},
    try(each.value.mw_sccm, null) != null ? {
      mw_sccm = each.value.mw_sccm
    } : {},
    try(length(each.value.sccm_device_collections), 0) > 0 ? {
      sccm_device_collections = each.value.sccm_device_collections
    } : {},
    try(length(each.value.gp_exceptions), 0) > 0 ? {
      gp_exceptions = each.value.gp_exceptions
    } : {},
    # Data disk mount points — only when at least one disk has mount_point set
    length(local.ansible_vm_data_disks[each.key]) > 0 ? {
      data_disks = local.ansible_vm_data_disks[each.key]
    } : {}
  ))
  file_permission = "0640"
}
