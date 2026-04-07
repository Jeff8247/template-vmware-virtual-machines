# ─── vCenter Connection ───────────────────────────────────────────────────────

variable "vsphere_server" {
  description = "Hostname or IP address of the vCenter server"
  type        = string
}

variable "vsphere_user" {
  description = "vCenter username (UPN format, e.g. user@domain)"
  type        = string
}

variable "vsphere_password" {
  description = "vCenter password"
  type        = string
  sensitive   = true
}

variable "vsphere_allow_unverified_ssl" {
  description = "Skip TLS certificate verification for vCenter"
  type        = bool
  default     = false
}

# ─── VM List ──────────────────────────────────────────────────────────────────

variable "vms" {
  description = <<-EOT
    Map of VM name to per-VM spec. Set is_windows = true for Windows VMs, false for Linux.
    Any omitted field falls back to the corresponding global variable.
    OS-specific defaults (firmware, time_zone) are applied automatically based on is_windows.
  EOT
  type = map(object({
    # Required: determines OS-specific defaults and customization path
    is_windows = bool

    # Infrastructure Placement
    datacenter    = optional(string)
    cluster       = optional(string)
    datastore     = optional(string)
    resource_pool = optional(string)
    vm_folder     = optional(string)

    # VM Identity
    computer_name = optional(string)
    annotation    = optional(string)
    tags          = optional(map(string))

    # Template
    template_name = optional(string)

    # CPU
    num_cpus             = optional(number)
    num_cores_per_socket = optional(number)
    cpu_hot_add_enabled  = optional(bool)

    # Memory
    memory                 = optional(number)
    memory_hot_add_enabled = optional(bool)

    # Storage
    disks = optional(list(object({
      label            = string
      size             = number
      unit_number      = optional(number)
      thin_provisioned = optional(bool, false)
      eagerly_scrub    = optional(bool, false)
    })))
    scsi_type             = optional(string)
    scsi_controller_count = optional(number)

    # Networking
    network_interfaces = optional(list(object({
      network_name = string
      adapter_type = optional(string, "vmxnet3")
    })))
    ip_settings = optional(list(object({
      ipv4_address = string
      ipv4_netmask = number
    })))
    ipv4_gateway    = optional(string)
    dns_servers     = optional(list(string))
    dns_suffix_list = optional(list(string))

    # Guest OS (common)
    guest_id = optional(string)
    domain   = optional(string)

    # Guest OS (OS-specific timezone overrides — falls back to time_zone_linux / time_zone_windows globals)
    time_zone_linux   = optional(string)
    time_zone_windows = optional(number)

    # Guest OS (Windows-only)
    windows_admin_password   = optional(string)
    windows_domain           = optional(string)
    windows_domain_user      = optional(string)
    windows_domain_password  = optional(string)
    windows_domain_ou        = optional(string)
    windows_workgroup        = optional(string)
    windows_auto_logon       = optional(bool)
    windows_auto_logon_count = optional(number)
    windows_run_once         = optional(list(string))

    # Hardware (common)
    firmware                    = optional(string)
    hardware_version            = optional(number)
    tools_upgrade_policy        = optional(string)
    enable_disk_uuid            = optional(bool)
    wait_for_guest_net_timeout  = optional(number)
    wait_for_guest_net_routable = optional(bool)
    customize_timeout           = optional(number)
    extra_config                = optional(map(string))

    # Hardware (Windows-only)
    vbs_enabled             = optional(bool)
    efi_secure_boot_enabled = optional(bool)
  }))
  default = {}

  validation {
    condition     = length(var.vms) > 0
    error_message = "vms must contain at least one entry."
  }
}

# ─── Infrastructure Placement ─────────────────────────────────────────────────

variable "datacenter" {
  description = "Name of the vSphere datacenter"
  type        = string
  default     = "MYDC01"
}

variable "cluster" {
  description = "Name of the vSphere cluster"
  type        = string
  default     = "MYCLU01"
}

variable "datastore" {
  description = "Name of the datastore"
  type        = string
  default     = "MYDS01"
}

variable "resource_pool" {
  description = "Resource pool name. Defaults to the root pool of the cluster when null."
  type        = string
  default     = null
}

variable "vm_folder" {
  description = "vSphere inventory folder path for the VMs (e.g. 'VMs/AppServers'). Deploys to datacenter root when null."
  type        = string
  default     = null
}

# ─── Template ─────────────────────────────────────────────────────────────────

variable "template_name_windows" {
  description = "Default Windows VM template to clone. Can be overridden per-VM via vms[].template_name."
  type        = string
  default     = null
}

variable "template_name_linux" {
  description = "Default Linux VM template to clone. Can be overridden per-VM via vms[].template_name."
  type        = string
  default     = null
}

# ─── VM Identity ──────────────────────────────────────────────────────────────

variable "annotation" {
  description = "Notes/description applied to all VMs"
  type        = string
  default     = null
}

variable "tags" {
  description = "Map of vSphere tag category to tag name applied to all VMs (e.g. { Environment = \"prod\" })"
  type        = map(string)
  default     = {}
}

# ─── CPU ──────────────────────────────────────────────────────────────────────

variable "num_cpus" {
  description = "Total number of vCPUs"
  type        = number
  default     = 2
}

variable "num_cores_per_socket" {
  description = "Number of cores per socket. Defaults to num_cpus (single socket) when null."
  type        = number
  default     = null
}

variable "cpu_hot_add_enabled" {
  description = "Allow CPU hot-add without power cycling"
  type        = bool
  default     = false
}

# ─── Memory ───────────────────────────────────────────────────────────────────

variable "memory" {
  description = "Memory in MB (must be a multiple of 4). Windows typically requires 8192+."
  type        = number
  default     = 4096

  validation {
    condition     = var.memory % 4 == 0
    error_message = "memory must be a multiple of 4 MB."
  }
}

variable "memory_hot_add_enabled" {
  description = "Allow memory hot-add without power cycling"
  type        = bool
  default     = false
}

# ─── Storage ──────────────────────────────────────────────────────────────────

variable "disks" {
  description = <<-EOT
    List of disks to attach to each VM. Each disk object requires:
      - label            (string) — unique name per disk
      - size             (number) — size in GB
    Optional per disk:
      - unit_number      (number) — SCSI unit number (disk0 = 0, disk1 = 1, …)
      - thin_provisioned (bool)   — default false
      - eagerly_scrub    (bool)   — default false
  EOT
  type = list(object({
    label            = string
    size             = number
    unit_number      = optional(number)
    thin_provisioned = optional(bool, false)
    eagerly_scrub    = optional(bool, false)
  }))
  default = [
    {
      label       = "disk0"
      size        = 60
      unit_number = 0
    }
  ]
}

variable "scsi_type" {
  description = "SCSI controller type: pvscsi or lsilogicsas"
  type        = string
  default     = "pvscsi"

  validation {
    condition     = contains(["pvscsi", "lsilogicsas"], var.scsi_type)
    error_message = "scsi_type must be pvscsi or lsilogicsas."
  }
}

variable "scsi_controller_count" {
  description = "Number of SCSI controllers"
  type        = number
  default     = 1
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "network_interfaces" {
  description = "List of network interfaces. Each object requires network_name; adapter_type defaults to vmxnet3."
  type = list(object({
    network_name = string
    adapter_type = optional(string, "vmxnet3")
  }))
  default = [
    { network_name = "NET01" }
  ]
}

variable "ip_settings" {
  description = "Static IP settings per NIC. Leave empty ([]) to use DHCP on all NICs."
  type = list(object({
    ipv4_address = string
    ipv4_netmask = number
  }))
  default = []
}

variable "ipv4_gateway" {
  description = "Default IPv4 gateway. Only required when using static IPs."
  type        = string
  default     = null
}

variable "dns_servers" {
  description = "DNS server IP addresses"
  type        = list(string)
  default     = []
}

variable "dns_suffix_list" {
  description = "DNS search suffixes"
  type        = list(string)
  default     = []
}

# ─── Guest OS ─────────────────────────────────────────────────────────────────

variable "guest_id" {
  description = "vSphere guest OS identifier. Inherited from template when null."
  type        = string
  default     = null
}

variable "domain" {
  description = "DNS domain applied during guest customization (e.g. corp.example.com)."
  type        = string
  default     = null
}

variable "time_zone_linux" {
  description = "Default timezone for Linux VMs in Olson format (e.g. Australia/Brisbane, UTC). Override per-VM via vms[].time_zone_linux."
  type        = string
  default     = "UTC"
}

variable "time_zone_windows" {
  description = "Default timezone index for Windows VMs (0–260). 260 = Brisbane. Override per-VM via vms[].time_zone_windows."
  type        = number
  default     = 260

  validation {
    condition     = var.time_zone_windows >= 0 && var.time_zone_windows <= 260
    error_message = "time_zone_windows must be between 0 and 260."
  }
}

# ─── Domain Join ──────────────────────────────────────────────────────────────
# Windows: Sysprep-based — set windows_domain, windows_domain_user, and windows_domain_password.
# Linux: domain join is handled by Ansible post-boot.

variable "windows_domain" {
  description = "Active Directory domain to join (e.g. corp.example.com). Set to null to skip domain join."
  type        = string
  default     = null
}

variable "windows_domain_user" {
  description = "AD user with permission to join computers to the domain"
  type        = string
  default     = null
}

variable "windows_domain_password" {
  description = "Password for windows_domain_user. Use TF_VAR_windows_domain_password env var."
  type        = string
  sensitive   = true
  default     = null
}

variable "windows_domain_ou" {
  description = "Distinguished name of the OU for the computer object (e.g. OU=Servers,DC=corp,DC=example,DC=com). Uses default Computers container when null."
  type        = string
  default     = null
}

variable "windows_workgroup" {
  description = "Workgroup name for Windows VMs when not domain-joined"
  type        = string
  default     = "WORKGROUP"
}

# ─── Windows-Only: Credentials & First-Boot ───────────────────────────────────

variable "windows_admin_password" {
  description = "Local Administrator password set during Sysprep. Required for all Windows VMs. Use TF_VAR_windows_admin_password env var."
  type        = string
  sensitive   = true
  default     = null
}

variable "windows_auto_logon" {
  description = "Automatically log on as Administrator after Sysprep (Windows only)"
  type        = bool
  default     = false
}

variable "windows_auto_logon_count" {
  description = "Number of automatic Administrator logon sessions (Windows only)"
  type        = number
  default     = 1
}

variable "windows_run_once" {
  description = "List of commands to execute once at first boot via the RunOnce registry key (Windows only)"
  type        = list(string)
  default     = []
}

# ─── Hardware ─────────────────────────────────────────────────────────────────

variable "firmware" {
  description = "VM firmware type: efi or bios. When null (default), efi is used for Windows VMs and bios for Linux VMs."
  type        = string
  default     = null

  validation {
    condition     = var.firmware == null || contains(["efi", "bios"], var.firmware)
    error_message = "firmware must be efi or bios."
  }
}

variable "vbs_enabled" {
  description = "Enable Virtualization-Based Security (Windows only, requires EFI firmware)"
  type        = bool
  default     = false
}

variable "efi_secure_boot_enabled" {
  description = "Enable EFI Secure Boot (Windows only, recommended when VBS is enabled)"
  type        = bool
  default     = false
}

variable "tools_upgrade_policy" {
  description = "VMware Tools upgrade policy: manual or upgradeAtPowerCycle"
  type        = string
  default     = "upgradeAtPowerCycle"
}

variable "hardware_version" {
  description = "VMware hardware compatibility version (e.g. 19, 20, 21). Null inherits from template."
  type        = number
  default     = null
}

variable "enable_disk_uuid" {
  description = "Expose disk UUIDs to the guest OS"
  type        = bool
  default     = true
}

variable "wait_for_guest_net_timeout" {
  description = "Minutes to wait for guest networking to come up after customization (0 to disable)"
  type        = number
  default     = 5
}

variable "wait_for_guest_net_routable" {
  description = "Require a routable IP address before considering the VM ready"
  type        = bool
  default     = true
}

variable "customize_timeout" {
  description = "Minutes to wait for guest customization to complete"
  type        = number
  default     = 30
}

variable "extra_config" {
  description = "Additional VMX key/value pairs (advanced VM settings)"
  type        = map(string)
  default     = {}
}
