# VMware VMs — Unified Terraform Template

Terraform template for deploying multiple Windows and Linux virtual machines on vSphere in a single run. Wraps the [`Jeff8247/module-vmware-virtual-machine`](https://github.com/Jeff8247/module-vmware-virtual-machine) module using `for_each`, with a per-VM override pattern — each VM entry in the `vms` map can override any setting, falling back to the global defaults defined alongside it.

Set `is_windows = true` or `is_windows = false` per VM. OS-specific defaults (firmware, timezone) are applied automatically — no need to set them on each VM unless you want to override.

## Requirements

| Tool | Version |
|------|---------|
| Terraform | `>= 1.3, < 2.0` |
| vSphere provider | `~> 2.6` |
| `hashicorp/local` provider | `~> 2.0` |
| vCenter | 7.0+ recommended |

VM templates with VMware Tools installed must already exist in vCenter. Linux templates require `open-vm-tools` to support guest customization scripts.

## Quick Start

```bash
# 1. Copy the example vars file and fill in your values
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

# 2. Set credentials via environment variables (recommended — avoids storing them in files)
export TF_VAR_vsphere_password="..."
export TF_VAR_windows_admin_password="..."
export TF_VAR_windows_domain_password="..."   # only if joining AD

# 3. Initialize and deploy
terraform init
terraform plan
terraform apply
```

## Credentials

Passwords should **not** be stored in `terraform.tfvars`. Use environment variables instead:

```bash
export TF_VAR_vsphere_password="your-vcenter-password"
export TF_VAR_windows_admin_password="your-local-admin-password"
export TF_VAR_windows_domain_password="your-domain-join-password"   # if joining AD
```

The `.gitignore` in this repo excludes `terraform.tfvars` and `*.auto.tfvars` to prevent accidental commits of credentials.

## How It Works

All VMs are defined in the `vms` map. Each key becomes the VM name in vSphere. Set `is_windows` to control which OS path is taken. Any field omitted from a VM entry falls back to the matching global variable:

```hcl
vms = {
  "win-app-01" = {
    is_windows = true
    num_cpus   = 4
    memory     = 8192
  }
  "lnx-app-01" = {
    is_windows = false
    num_cpus   = 2
    memory     = 4096
  }
}
```

**OS-specific defaults applied automatically:**

| Setting | Windows | Linux |
|---------|---------|-------|
| `firmware` | `efi` | `bios` |
| `time_zone` | from `time_zone_windows` | from `time_zone_linux` |
| `computer_name` | truncated to 15 chars | full VM name |

## Ansible Day-2 Operations

Every `terraform apply` generates a ready-to-use Ansible inventory under `inventory/`:

```
inventory/
├── hosts.yml                  # group structure — linux, windows, domain_joined, tag_*
├── group_vars/
│   ├── all.yml                # vCenter connection vars + ISO datastore path
│   ├── linux.yml              # SSH connection vars for all Linux hosts
│   └── windows.yml            # WinRM connection vars for all Windows hosts
└── host_vars/
    ├── lnx-app-01.yml         # ansible_host (IP), computer_name, vm_uuid, domain facts
    └── win-app-01.yml
```

IPs come from VMware Tools output (`default_ip_address`), so they reflect the actual address reported after guest customization — static or DHCP.

### Prerequisites

**Ansible control node:**
- `sshpass` must be installed for password-based SSH connections to Linux VMs (`yum install sshpass` / `apt install sshpass`)
- `pywinrm` must be installed for WinRM connections to Windows VMs (`pip install pywinrm`)
- Kerberos client libraries must be installed for Windows connections (`yum install krb5-workstation` / `apt install krb5-user`)
- A valid Kerberos ticket must be obtained before running against Windows VMs: `kinit user@DOMAIN.COM`

**Linux VMs — must be in place before running playbooks:**
- The `ansible_linux_user` account (default: `ansible`) must exist on each VM
- That user must have passwordless sudo, e.g. add to sudoers: `ansible ALL=(ALL) NOPASSWD: ALL`

**Windows VMs:**
- WinRM must be enabled before Ansible can connect. Run via `windows_run_once` or bake it into the template:
  ```powershell
  winrm quickconfig -q
  ```
- VMs must be domain-joined for Kerberos authentication to work. Domain join is handled automatically via Sysprep when `windows_domain` is set.

### Running Playbooks

Credentials are not stored in the inventory — pass them at runtime:

```bash
# Inspect the inventory before running
ansible-inventory -i inventory/ --graph

# Linux — prompt for SSH password (requires sshpass on the control node)
ansible-playbook -i inventory/ site.yml --ask-pass

# Linux — prompt for SSH and sudo passwords (if sudo is not passwordless)
ansible-playbook -i inventory/ site.yml --ask-pass --ask-become-pass

# Windows post-provision — obtain a Kerberos ticket and set vCenter password first
kinit svc-ansible@CORP.LOCAL
export VMWARE_PASSWORD="your-vcenter-password"
ansible-playbook -i inventory/ post_provision.yml

# Mixed — target Linux and Windows separately
ansible-playbook -i inventory/ site.yml --limit linux --ask-pass
ansible-playbook -i inventory/ post_provision.yml --limit windows
```

For Linux non-interactive use, store credentials in an Ansible Vault file:

```bash
# Create and encrypt the vault file
ansible-vault create vault.yml
```

```yaml
# vault.yml contents
ansible_password: "YourPassword"
ansible_become_password: "YourPassword"   # if sudo requires a password
```

```bash
ansible-playbook -i inventory/ site.yml --limit linux -e @vault.yml --vault-password-file ~/.vault_pass
```

### Groups

| Group | Members |
|-------|---------|
| `linux` | All VMs with `is_windows = false` |
| `windows` | All VMs with `is_windows = true` |
| `domain_joined` | All VMs with `windows_domain` set |
| `tag_<category>_<value>` | One group per vSphere tag, e.g. `tag_environment_prod` |

### Connection Details

**Linux** (`group_vars/linux.yml`) — SSH on port 22 as `ansible_linux_user`, with `ansible_become: true` via sudo. Password supplied at runtime via `--ask-pass`.

**Windows** (`group_vars/windows.yml`) — WinRM on port 5985 as `ansible_windows_user`, using Kerberos transport by default. Authentication uses the active Kerberos ticket from `kinit` — no password flag needed at runtime. Switch to port 5986 with `ansible_winrm_cert_validation: validate` for production environments with proper certificates. Use `ntlm` transport for workgroup (non-domain) machines.

**vCenter variables** (`group_vars/all.yml`) — `vcenter_fqdn`, `vcenter_username`, `vm_datacenter`, `vm_cluster`, and `iso_datastore_path` are sourced directly from `terraform.tfvars`. Playbooks can use these without any manual configuration. The vCenter password is never written to inventory — pass it as `VMWARE_PASSWORD` at playbook runtime.

**Per-host variables** (`host_vars/<vm>.yml`) contain only what differs between hosts: `ansible_host`, `computer_name`, `vm_uuid`, and when set: `domain`, `windows_domain`, `windows_domain_ou`.

The `inventory/` directory is gitignored — it is always regenerated from Terraform state.

### Ansible Variable Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `ansible_linux_user` | `"ansible"` | SSH user Ansible connects as on Linux VMs — must exist on each VM with passwordless sudo |
| `ansible_windows_user` | `"svc-ansible@domain.local"` | WinRM user Ansible connects as on Windows VMs. Use a domain service account in UPN format for domain-joined VMs. Must be a local Administrator or member of the local Administrators group on each VM. |
| `ansible_winrm_transport` | `"kerberos"` | WinRM transport: `ntlm`, `kerberos`, or `basic` |
| `ansible_winrm_cert_validation` | `"ignore"` | Certificate validation: `ignore` for testing, `validate` for production with proper certs on port 5986 |
| `iso_datastore` | `null` (uses `datastore`) | Datastore holding the Ansible payload ISO. Defaults to the VM datastore when not set. |
| `iso_folder` | `"ISOs/"` | Folder path within `iso_datastore` where the payload ISO is stored |
| `iso_filename` | `null` | Filename of the payload ISO (e.g. `payload-2024.iso`) |
| `vlan` | `null` | VLAN number for the Ansible NIC rename (e.g. `100` → `vNIC - VLAN 100`) |

## Domain Join

The `windows_domain*` variables drive Windows domain join via Sysprep. Linux domain join is handled by Ansible post-boot.

```hcl
windows_domain      = "corp.example.com"
windows_domain_user = "svc-domainjoin@corp.example.com"
windows_domain_ou   = "OU=Servers,DC=corp,DC=example,DC=com"
# windows_domain_password via TF_VAR_windows_domain_password
```

Set `windows_domain = null` (or omit it) to deploy standalone/workgroup machines.

## Examples

### Mixed Windows and Linux deployment

```hcl
template_name_windows = "template-win2k19-ltsc-64bit-datacenter"
template_name_linux   = "template-rhel9-soe"

vms = {
  "win-app-01" = {
    is_windows = true
    num_cpus   = 4
    memory     = 8192
    ip_settings  = [{ ipv4_address = "10.0.1.101", ipv4_netmask = 24 }]
    ipv4_gateway = "10.0.1.1"
  }
  "lnx-app-01" = {
    is_windows = false
    num_cpus   = 2
    memory     = 4096
    ip_settings  = [{ ipv4_address = "10.0.2.101", ipv4_netmask = 24 }]
    ipv4_gateway = "10.0.2.1"
  }
}
```

### Windows-only deployment

```hcl
template_name_windows = "template-win2k19-ltsc-64bit-datacenter"

vms = {
  "win-app-01" = { is_windows = true, memory = 16384 }
  "win-app-02" = { is_windows = true }
  "win-app-03" = { is_windows = true }
}

num_cpus = 4
memory   = 8192
```

### Linux-only deployment

```hcl
template_name_linux = "template-rhel9-soe"

vms = {
  "lnx-app-01" = { is_windows = false }
  "lnx-app-02" = { is_windows = false }
  "lnx-app-03" = { is_windows = false }
}

num_cpus = 2
memory   = 4096
```

### Multiple disks with a second SCSI controller

```hcl
vms = {
  "win-db-01" = {
    is_windows            = true
    scsi_controller_count = 2
    disks = [
      { label = "OS",   size = 150, unit_number = 0  },
      { label = "Data", size = 500, unit_number = 16 },  # Bus 1:0
    ]
  }
}
```

For multiple SCSI controllers, calculate `unit_number` as `(bus * 16) + unit`. For example, Bus 1 Unit 0 = `16`, Bus 2 Unit 0 = `32`.

### Windows RunOnce commands

```hcl
vms = {
  "win-app-01" = {
    is_windows       = true
    windows_run_once = [
      "powershell.exe -Command \"Install-WindowsFeature Web-Server\""
    ]
  }
}
```

## Variable Reference

### vCenter Connection

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vsphere_server` | `string` | required | vCenter server hostname or IP |
| `vsphere_user` | `string` | required | vCenter username |
| `vsphere_password` | `string` | required | vCenter password (sensitive) |
| `vsphere_allow_unverified_ssl` | `bool` | `false` | Skip TLS certificate verification |

### VM List

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vms` | `map(object)` | `{}` | Map of VM name to per-VM spec. Every field except `is_windows` is optional — omit to inherit the global default. |

Each key in the `vms` map becomes the VM name in vSphere. `is_windows` is required on every entry.

### Infrastructure Placement

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `datacenter` | `string` | `"MYDC01"` | vSphere datacenter name |
| `cluster` | `string` | `"MYCLU01"` | vSphere cluster name |
| `datastore` | `string` | `"MYDS01"` | Datastore name |
| `resource_pool` | `string` | `null` | Resource pool name; `null` uses the cluster root pool |
| `vm_folder` | `string` | `null` | vSphere folder path, e.g. `"VMs/AppServers"` |

### Templates

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `template_name_windows` | `string` | `null` | Default Windows template to clone |
| `template_name_linux` | `string` | `null` | Default Linux template to clone |

Per-VM `template_name` in the `vms` map overrides these globals, allowing individual VMs to use a different template (e.g. a different OS version).

### VM Identity

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `annotation` | `string` | `null` | Notes/description applied to all VMs |
| `tags` | `map(string)` | `{}` | vSphere tags as `{ category = "tag-name" }`. Tag categories and values must already exist in vCenter. |

### CPU

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `num_cpus` | `number` | `2` | Total vCPU count |
| `num_cores_per_socket` | `number` | `null` | Cores per socket — defaults to `num_cpus` (single socket) |
| `cpu_hot_add_enabled` | `bool` | `false` | Allow CPU hot-add without power cycling |

### Memory

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `memory` | `number` | `4096` | Memory in MB — must be a multiple of 4. Windows VMs typically need 8192+. |
| `memory_hot_add_enabled` | `bool` | `false` | Allow memory hot-add without power cycling |

### Storage

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `disks` | `list(object)` | single 60 GB thin disk | List of disks — see [Disk Object](#disk-object) |
| `scsi_type` | `string` | `"pvscsi"` | SCSI controller type: `pvscsi` or `lsilogicsas` |
| `scsi_controller_count` | `number` | `1` | Number of SCSI controllers (max 4) |

#### Disk Object

```hcl
{
  label            = "disk0"   # required — unique per VM
  size             = 60        # required — size in GB
  unit_number      = 0         # optional — SCSI unit number
  thin_provisioned = true      # optional — default true
  eagerly_scrub    = false     # optional — default false
}
```

### Networking

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `network_interfaces` | `list(object)` | `[{ network_name = "NET01" }]` | List of NICs |
| `ip_settings` | `list(object)` | `[]` | Static IP per NIC — leave empty for DHCP |
| `ipv4_gateway` | `string` | `null` | Default IPv4 gateway |
| `dns_servers` | `list(string)` | `[]` | DNS server addresses |
| `dns_suffix_list` | `list(string)` | `[]` | DNS search suffixes |

One `ip_settings` entry per NIC, in the same order as `network_interfaces`. Leave `ip_settings = []` for DHCP on all NICs.

### Guest OS

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `guest_id` | `string` | inherited from template | vSphere guest OS identifier |
| `domain` | `string` | `null` | DNS search domain applied during guest customization |
| `time_zone_linux` | `string` | `"UTC"` | Default timezone for Linux VMs — Olson format (e.g. `Australia/Brisbane`) |
| `time_zone_windows` | `number` | `260` | Default timezone index for Windows VMs (0–260). 260 = Brisbane |

Per-VM `time_zone_linux` and `time_zone_windows` fields in the `vms` map override these globals for individual VMs.

Common Windows timezone indices:

| Timezone | Index |
|----------|-------|
| UTC | `0` |
| Eastern Standard Time | `85` |
| Central Standard Time | `20` |
| Pacific Standard Time | `235` |
| GMT Standard Time | `90` |
| AUS Eastern Standard Time | `260` |

Full list: [Microsoft Time Zone Index Values](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/default-time-zones)

Common Linux Olson timezones: `UTC`, `America/New_York`, `America/Chicago`, `America/Los_Angeles`, `Europe/London`, `Australia/Brisbane`, `Australia/Sydney`

### Domain Join (Windows only)

Linux domain join is handled by Ansible post-boot.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `windows_domain` | `string` | `null` | AD domain to join (e.g. `corp.example.com`). `null` skips domain join |
| `windows_domain_user` | `string` | `null` | AD user with machine join permissions |
| `windows_domain_password` | `string` | `null` | Domain join password (sensitive) — set via `TF_VAR_windows_domain_password` |
| `windows_domain_ou` | `string` | `null` | OU distinguished name for the computer object. `null` uses the default Computers container |
| `windows_workgroup` | `string` | `"WORKGROUP"` | Workgroup name for Windows VMs when not domain-joined |

### Windows-Only

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `windows_admin_password` | `string` | `null` | Local Administrator password set during Sysprep. Required for all Windows VMs. Set via `TF_VAR_windows_admin_password` |
| `windows_auto_logon` | `bool` | `false` | Automatically log on as Administrator after Sysprep |
| `windows_auto_logon_count` | `number` | `1` | Number of automatic logon sessions |
| `windows_run_once` | `list(string)` | `[]` | Commands to run once at first boot via the RunOnce registry key |
| `vbs_enabled` | `bool` | `false` | Enable Virtualization-Based Security (requires EFI firmware) |
| `efi_secure_boot_enabled` | `bool` | `false` | Enable EFI Secure Boot (recommended when VBS is enabled) |

### Hardware

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `firmware` | `string` | OS-conditional | `efi` for Windows, `bios` for Linux. Override globally or per-VM only if non-default behaviour is needed |
| `hardware_version` | `number` | `null` | VMware hardware version; `null` keeps the template version |
| `tools_upgrade_policy` | `string` | `"upgradeAtPowerCycle"` | VMware Tools upgrade policy: `manual` or `upgradeAtPowerCycle` |
| `enable_disk_uuid` | `bool` | `true` | Expose disk UUIDs to the guest OS |
| `wait_for_guest_net_timeout` | `number` | `5` | Minutes to wait for guest networking (`0` disables) |
| `wait_for_guest_net_routable` | `bool` | `true` | Require a routable IP before marking VM ready |
| `customize_timeout` | `number` | `30` | Minutes to wait for guest customization to complete |
| `extra_config` | `map(string)` | `{}` | Additional VMX key/value pairs |

## Outputs

All outputs are maps keyed by VM name.

| Output | Description |
|--------|-------------|
| `vm_names` | Name of each deployed VM |
| `vm_ids` | Managed object ID (MOID) of each VM |
| `vm_uuids` | BIOS UUID of each VM |
| `power_states` | Current power state of each VM |
| `default_ip_addresses` | Primary IP address of each VM as reported by VMware Tools |
| `ip_addresses` | All IP addresses reported by VMware Tools, per VM |

Example output:

```
default_ip_addresses = {
  "lnx-app-01" = "10.0.2.101"
  "win-app-01" = "10.0.1.101"
}
```

## File Structure

```
.
├── main.tf                    # OS-conditional defaults, module call
├── ansible.tf                 # Ansible inventory generation (local_file resources)
├── variables.tf               # All input variables with validation
├── outputs.tf                 # Map outputs keyed by VM name
├── versions.tf                # Terraform and provider version constraints
├── providers.tf               # vSphere provider configuration
├── terraform.tfvars.example   # Annotated example — copy to terraform.tfvars
└── .gitignore                 # Excludes state, .terraform/, tfvars, and inventory/
```

## Security Notes

- `vsphere_password`, `windows_admin_password`, and `windows_domain_password` are marked `sensitive = true` and will not appear in plan/apply output.
- `terraform.tfvars` is excluded by `.gitignore` to prevent accidental credential commits. All passwords should be passed via `TF_VAR_*` environment variables.
- `vsphere_allow_unverified_ssl` defaults to `false`. Only set to `true` in non-production lab environments.
- Terraform state (`terraform.tfstate`) contains all resource attributes including sensitive values. Store state in a secured remote backend (e.g. S3 with encryption, Terraform Cloud) for any shared or production use. See `versions.tf` for where to add a backend block.
- `inventory/` is excluded by `.gitignore`. Generated host_vars files contain domain and OU information — do not commit them or store them in locations accessible to unauthorised users. Ansible Vault should be used for any secrets passed to playbooks (e.g. domain join credentials, become passwords).
