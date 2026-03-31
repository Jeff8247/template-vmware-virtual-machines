locals {
  # ─── Linux Domain Join Script ─────────────────────────────────────────────────
  # Null-safe intermediates — prevents interpolation errors when domain join is
  # disabled (vars are null). The heredoc must always be syntactically valid
  # because terraform evaluates all locals regardless of the condition below.
  _dj_domain   = try(coalesce(var.windows_domain, ""), "")
  _dj_password = try(coalesce(var.windows_domain_password, ""), "")
  _dj_netbios  = try(coalesce(var.windows_domain_netbios, var.windows_domain), "")
  _dj_user     = try(coalesce(var.windows_domain_user, ""), "")
  _dj_ou       = try(coalesce(var.windows_domain_ou, ""), "")

  _domain_join_script_content = <<-EOT
    #!/bin/bash
    # 1. Install required packages based on OS family
    if command -v dnf &> /dev/null; then
        dnf install -y realmd sssd sssd-tools adcli authselect samba-common-tools
    elif command -v apt-get &> /dev/null; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y realmd sssd sssd-tools adcli samba-common-bin packagekit
    fi

    # 2. Join the domain using NetBIOS/UPN syntax
    NETBIOS_NAME="${local._dj_netbios}"
    echo "${local._dj_password}" | realm join "$NETBIOS_NAME" \
      --computer-ou="${local._dj_ou}" \
      -U "${local._dj_user}@$NETBIOS_NAME" \
      --verbose

    # 3. Clean and Setup SSSD Configuration Hierarchy
    rm -rf /etc/sssd/conf.d/*

    # Create the domain-specific config
    cat <<EOF > "/etc/sssd/conf.d/01_${local._dj_domain}.conf"
    [domain/${local._dj_domain}]
    ad_domain = ${local._dj_domain}
    krb5_realm = ${upper(local._dj_domain)}
    realmd_tags = manages-system joined-with-adcli
    cache_credentials = True
    id_provider = ad
    krb5_store_password_if_offline = True
    default_shell = /bin/bash
    ldap_id_mapping = True
    use_fully_qualified_names = False
    fallback_homedir = /home/%u
    access_provider = ad
    EOF

    # Create primary sssd.conf
    cat <<EOF > /etc/sssd/sssd.conf
    [sssd]
    domains = ${local._dj_domain}
    config_file_version = 2
    services = nss, pam
    ad_enabled_domains = ${local._dj_domain}
    EOF

    chmod 600 /etc/sssd/sssd.conf "/etc/sssd/conf.d/01_${local._dj_domain}.conf"

    # 4. Configure Kerberos
    cat <<EOF > /etc/krb5.conf
    [libdefaults]
    default_realm = ${upper(local._dj_domain)}
    dns_lookup_realm = false
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false
    pkinit_anchors = FILE:/etc/pki/tls/certs/ca-bundle.crt
    spake_preauth_groups = edwards25519
    EOF

    # 5. Security Hardening: Authselect and PAM
    if command -v authselect &> /dev/null; then
        # Select SSSD profile with home directory creation
        authselect select sssd with-mkhomedir --force

        # Prevent login to accounts with empty passwords
        authselect enable-feature without-nullok
        authselect apply-changes -b
    else
        # Fallback for systems without authselect (Debian/Ubuntu)
        # Directly remove 'nullok' from PAM files
        sed -i 's/nullok//g' /etc/pam.d/common-auth /etc/pam.d/system-auth /etc/pam.d/password-auth 2>/dev/null || true
    fi

    # 6. Finalize Services
    systemctl restart sssd
    systemctl enable sssd
  EOT

  # Empty string when domain join is disabled.
  domain_join_script = (
    var.windows_domain != null && var.windows_domain_password != null
    ? local._domain_join_script_content
    : ""
  )

  # ─── Per-VM OS-Conditional Defaults ──────────────────────────────────────────
  vms_resolved = {
    for k, v in var.vms : k => {
      # firmware: efi for Windows, bios for Linux (overridden by per-VM or global firmware if set)
      firmware = v.firmware != null ? v.firmware : coalesce(var.firmware, v.is_windows ? "efi" : "bios")

      # time_zone: module expects a string; Windows numeric index is converted via tostring()
      time_zone = v.is_windows ? tostring(coalesce(v.time_zone_windows, var.time_zone_windows)) : coalesce(v.time_zone_linux, var.time_zone_linux)

      # computer_name: Windows truncates to 15 chars if not explicitly set; Linux uses full VM name
      computer_name = v.computer_name != null ? v.computer_name : (v.is_windows ? substr(k, 0, 15) : k)

      # linux_script_text: domain join script prepended to any per-VM or global script
      linux_script_text = trimspace("${local.domain_join_script}\n${v.linux_script_text != null ? v.linux_script_text : (var.linux_script_text != null ? var.linux_script_text : "")}")
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

check "linux_domain_join_requires_domain" {
  assert {
    condition     = var.windows_domain == null || var.domain != null
    error_message = "domain must be set when windows_domain is specified (used by the Linux realm join script)."
  }
}

check "linux_domain_join_requires_password" {
  assert {
    condition     = var.windows_domain == null || var.windows_domain_password != null
    error_message = "windows_domain_password must be set when windows_domain is specified."
  }
}

# ─── VM Deployment ────────────────────────────────────────────────────────────

module "vm" {
  for_each = var.vms
  source   = "github.com/Jeff8247/module-vmware-virtual-machine?ref=v1.0.10"

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
  windows_domain           = each.value.is_windows ? (each.value.windows_domain != null ? each.value.windows_domain : var.windows_domain) : null
  windows_domain_user      = each.value.is_windows ? (each.value.windows_domain_user != null ? each.value.windows_domain_user : var.windows_domain_user) : null
  windows_domain_password  = each.value.is_windows ? (each.value.windows_domain_password != null ? each.value.windows_domain_password : var.windows_domain_password) : null
  windows_domain_ou        = each.value.is_windows ? (each.value.windows_domain_ou != null ? each.value.windows_domain_ou : var.windows_domain_ou) : null
  windows_workgroup        = each.value.is_windows ? coalesce(each.value.windows_workgroup, var.windows_workgroup) : null
  windows_auto_logon       = each.value.is_windows ? coalesce(each.value.windows_auto_logon, var.windows_auto_logon) : null
  windows_auto_logon_count = each.value.is_windows ? coalesce(each.value.windows_auto_logon_count, var.windows_auto_logon_count) : null
  windows_run_once         = each.value.is_windows ? coalesce(each.value.windows_run_once, var.windows_run_once) : null
  vbs_enabled              = each.value.is_windows ? (each.value.vbs_enabled != null ? each.value.vbs_enabled : var.vbs_enabled) : false
  efi_secure_boot_enabled  = each.value.is_windows ? (each.value.efi_secure_boot_enabled != null ? each.value.efi_secure_boot_enabled : var.efi_secure_boot_enabled) : false

  # Guest OS (Linux-specific — ignored by module when is_windows = true)
  linux_script_text = each.value.is_windows ? null : local.vms_resolved[each.key].linux_script_text

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
