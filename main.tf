locals {
  # ─── Per-VM OS-Conditional Defaults ──────────────────────────────────────────
  vms_resolved = {
    for k, v in var.vms : k => {
      # firmware: efi for both Windows and Linux (overridden by per-VM or global firmware if set)
      firmware = v.firmware != null ? v.firmware : coalesce(var.firmware, "efi")

      # time_zone: module expects a string; Windows numeric index is converted via tostring()
      time_zone = v.is_windows ? tostring(coalesce(v.time_zone_windows, var.time_zone_windows)) : coalesce(v.time_zone_linux, var.time_zone_linux)

      # computer_name: Windows truncates to 15 chars if not explicitly set; Linux uses full VM name
      computer_name = v.computer_name != null ? v.computer_name : (v.is_windows ? substr(k, 0, 15) : k)
    }
  }
}

# ─── Checks ───────────────────────────────────────────────────────────────────

check "windows_admin_password_required" {
  assert {
    condition = alltrue([
      for k, v in var.vms :
      !v.is_windows || coalesce(v.windows_admin_password, var.windows_admin_password, "") != ""
    ])
    error_message = "All Windows VMs require windows_admin_password to be set (globally or per-VM in the vms map)."
  }
}

check "windows_computer_name_limit" {
  assert {
    condition = alltrue([
      for k, v in var.vms :
      !v.is_windows || v.computer_name != null || length(k) <= 15
    ])
    error_message = "One or more Windows VM names exceed 15 characters and don't have a 'computer_name' set. Windows will truncate them."
  }
}

# ─── VM Deployment ────────────────────────────────────────────────────────────

module "vm" {
  for_each = var.vms
  source   = "github.com/Jeff8247/module-vmware-virtual-machine?ref=v1.0.22"

  # Infrastructure placement
  datacenter    = coalesce(each.value.datacenter, var.datacenter)
  cluster       = coalesce(each.value.cluster, var.cluster)
  datastore     = coalesce(each.value.datastore, var.datastore)
  resource_pool = each.value.resource_pool != null ? each.value.resource_pool : var.resource_pool
  vm_folder     = each.value.vm_folder != null ? each.value.vm_folder : var.vm_folder

  # VM identity
  vm_name       = each.key
  computer_name = local.vms_resolved[each.key].computer_name
  annotation    = each.value.annotation != null ? each.value.annotation : var.annotation
  tags          = coalesce(each.value.tags, var.tags)

  # Template
  template_name = each.value.template_name != null ? each.value.template_name : (each.value.is_windows ? var.template_name_windows : var.template_name_linux)

  # CPU
  num_cpus             = coalesce(each.value.num_cpus, var.num_cpus)
  num_cores_per_socket = each.value.num_cores_per_socket != null ? each.value.num_cores_per_socket : var.num_cores_per_socket
  cpu_hot_add_enabled  = coalesce(each.value.cpu_hot_add_enabled, var.cpu_hot_add_enabled)

  # Memory
  memory                 = coalesce(each.value.memory, var.memory)
  memory_hot_add_enabled = coalesce(each.value.memory_hot_add_enabled, var.memory_hot_add_enabled)

  # Storage
  disks                 = coalesce(each.value.disks, var.disks)
  scsi_type             = coalesce(each.value.scsi_type, var.scsi_type)
  scsi_controller_count = coalesce(each.value.scsi_controller_count, var.scsi_controller_count)

  # Networking
  network_interfaces = coalesce(each.value.network_interfaces, var.network_interfaces)
  ip_settings        = coalesce(each.value.ip_settings, var.ip_settings)
  ipv4_gateway       = each.value.ipv4_gateway != null ? each.value.ipv4_gateway : var.ipv4_gateway
  dns_servers        = coalesce(each.value.dns_servers, var.dns_servers)
  dns_suffix_list    = coalesce(each.value.dns_suffix_list, var.dns_suffix_list)

  # Guest OS (common)
  is_windows = each.value.is_windows
  guest_id   = each.value.guest_id != null ? each.value.guest_id : var.guest_id
  domain     = each.value.domain != null ? each.value.domain : var.domain
  time_zone  = local.vms_resolved[each.key].time_zone

  # Guest OS (Windows-specific — ignored by module when is_windows = false)
  windows_admin_password   = each.value.is_windows ? coalesce(each.value.windows_admin_password, var.windows_admin_password) : null
  windows_workgroup        = each.value.is_windows ? coalesce(each.value.windows_workgroup, var.windows_workgroup) : null
  windows_auto_logon       = each.value.is_windows ? coalesce(each.value.windows_auto_logon, var.windows_auto_logon) : null
  windows_auto_logon_count = each.value.is_windows ? coalesce(each.value.windows_auto_logon_count, var.windows_auto_logon_count) : null
  windows_run_once         = each.value.is_windows ? coalesce(each.value.windows_run_once, var.windows_run_once) : null
  vbs_enabled              = each.value.is_windows ? (each.value.vbs_enabled != null ? each.value.vbs_enabled : var.vbs_enabled) : false
  efi_secure_boot_enabled  = each.value.is_windows ? (each.value.efi_secure_boot_enabled != null ? each.value.efi_secure_boot_enabled : var.efi_secure_boot_enabled) : false

  # Domain join — Windows uses Sysprep (handled by module)
  windows_domain          = each.value.windows_domain != null ? each.value.windows_domain : var.windows_domain
  windows_domain_user     = each.value.windows_domain_user != null ? each.value.windows_domain_user : var.windows_domain_user
  windows_domain_password = each.value.windows_domain_password != null ? each.value.windows_domain_password : var.windows_domain_password
  windows_domain_ou       = each.value.windows_domain_ou != null ? each.value.windows_domain_ou : var.windows_domain_ou

  # Hardware
  firmware                    = local.vms_resolved[each.key].firmware
  hardware_version            = each.value.hardware_version != null ? each.value.hardware_version : var.hardware_version
  tools_upgrade_policy        = coalesce(each.value.tools_upgrade_policy, var.tools_upgrade_policy)
  enable_disk_uuid            = coalesce(each.value.enable_disk_uuid, var.enable_disk_uuid)
  wait_for_guest_net_timeout  = coalesce(each.value.wait_for_guest_net_timeout, var.wait_for_guest_net_timeout)
  wait_for_guest_net_routable = coalesce(each.value.wait_for_guest_net_routable, var.wait_for_guest_net_routable)
  customize_timeout           = coalesce(each.value.customize_timeout, var.customize_timeout)
  extra_config                = coalesce(each.value.extra_config, var.extra_config)
}
