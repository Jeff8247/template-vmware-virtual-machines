# Changelog

All notable changes to this template will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Ansible inventory generation via `ansible.tf`. On `terraform apply`, writes a ready-to-use inventory under `inventory/`:
  - `inventory/hosts.yml` — group structure: `linux`, `windows`, `domain_joined`, and one group per vSphere tag (`tag_<category>_<value>`)
  - `inventory/group_vars/linux.yml` — shared SSH connection vars (`ansible_connection`, `ansible_port`, `ansible_user`, `ansible_become`)
  - `inventory/group_vars/windows.yml` — shared WinRM connection vars (`ansible_connection`, `ansible_port`, `ansible_winrm_transport`, `ansible_winrm_server_cert_validation`)
  - `inventory/host_vars/<vm>.yml` — per-VM: `ansible_host` (IP from VMware Tools), `computer_name`, `vm_uuid`, and conditional domain facts
- Four new variables: `ansible_linux_user` (default `"ansible"`), `ansible_windows_user` (default `"Administrator"`), `ansible_winrm_transport` (default `"ntlm"`), `ansible_winrm_cert_validation` (default `"ignore"`)
- `inventory/` added to `.gitignore`
- `hashicorp/local ~> 2.0` added to `required_providers`

## [1.0.16] - 2026-04-04

### Added
- Linux AD domain join via `realmd`/`sssd` script generated and run during VMware guest customization. Activated when `windows_domain` and `windows_domain_password` are set on a Linux VM. The script installs required packages, performs an idempotent realm join with 5 retries, configures SSSD and Kerberos, and hardens PAM. Works on both RHEL-family and Debian/Ubuntu guests.
- `windows_domain_netbios` variable (global and per-VM in the `vms` map) — NetBIOS/short domain name for the Linux realm join command. Falls back to `windows_domain` when null.
- `proxy_url` variable (global and per-VM) — HTTP/HTTPS proxy URL applied as `HTTP_PROXY` / `HTTPS_PROXY` for the package install step only; unset immediately after. Set via `TF_VAR_proxy_url`. Overridden per-VM via `vms[].proxy_url`.
- Initial tagged release of the unified Windows + Linux VMware VM template.

## [1.0.15] - 2026-04-02

### Changed
- Bumped module source ref to `v1.0.15`. Linux domain join removed from module at this version; domain join for Linux VMs is now handled in the template via `linux_script_text`.
