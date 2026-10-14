# SSH Credential Manager (ssh-cred-man)

A lightweight PowerShell SSH connection manager for Windows that stores connection details in a simple CSV file and keeps secrets (passwords / key passphrases) securely in **Windows Credential Manager**.

No plain-text passwords. No extra encrypted files. Just native Windows security.

---

## Features

- Interactive menu to list, add, edit, and remove connections
- Supports both **password** and **key + passphrase** authentication
- Secrets are stored in Windows Credential Manager (never in the CSV)
- Optional non-interactive password login via `plink` (PuTTY)
- Native OpenSSH for key-based connections
- Logging to `~/ssh_manager.log`
- Simple CSV inventory (`~/ssh_connections.csv`) that is easy to edit and back up

---

## Requirements

- Windows 10 / 11 (or Windows Server with OpenSSH client)
- PowerShell 5.1 or later (Windows PowerShell or PowerShell 7+)
- OpenSSH Client (usually already installed on modern Windows)

### Required PowerShell modules

```powershell
Install-Module CredentialManager -Scope CurrentUser -Force
Install-Module Posh-SSH -Scope CurrentUser -Force   # optional but recommended