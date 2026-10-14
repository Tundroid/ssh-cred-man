# SSH Credential Manager (ssh-cred-man)

A lightweight, menu-driven PowerShell SSH connection manager for Windows. Connection details live in a simple CSV file, and secrets (passwords / key passphrases) are kept in **Windows Credential Manager**, never in plain text.

---

## Features

- Interactive menu to list, connect, add, edit and remove connections
- **Password** authentication via `plink` (PuTTY), using the password saved in Credential Manager
- **Key** authentication via native OpenSSH (`ssh -i`), with key auto-detection
- Secrets stored in Windows Credential Manager (never in the CSV)
- Host-key verification: unknown servers show their fingerprint and ask for confirmation before connecting
- ANSI colour support in the remote terminal
- Automatic installation of required PowerShell modules
- Logging of all actions to a log file
- Plain CSV inventory that is easy to edit and back up

---

## Requirements

| Requirement | Notes |
|---|---|
| Windows 10 / 11 | Uses Windows Credential Manager |
| PowerShell 5.1+ | Windows PowerShell or PowerShell 7+ |
| [PuTTY](https://www.putty.org/) (`plink.exe`) | Needed for password logins |
| OpenSSH Client | Needed for key logins (and as a fallback if `plink` is missing) |
| `CredentialManager` module | Auto-installed on first run |
| `Posh-SSH` module | Auto-installed on first run |

`plink.exe` is searched for, in order, in: `PATH`, `%ProgramFiles%\PuTTY`, `%ProgramFiles(x86)%\PuTTY`, and `%USERPROFILE%\scoop\apps\putty\current`.

---

## Installation

1. Install PuTTY (for `plink.exe`):
   ```powershell
   winget install PuTTY.PuTTY
   ```
2. Install the OpenSSH Client if it's missing (Settings > Apps > Optional features), or:
   ```powershell
   Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
   ```
3. Clone or download this repository:
   ```powershell
   git clone https://github.com/Tundroid/ssh-cred-man.git
   cd ssh-cred-man
   ```
4. Allow the script to run if your execution policy blocks it:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```
5. (Optional) Install the modules yourself instead of letting the script do it:
   ```powershell
   Install-Module CredentialManager -Scope CurrentUser -Force
   Install-Module Posh-SSH -Scope CurrentUser -Force
   ```

---

## Usage

Start the manager:

```powershell
.\ssh-cred-man.ps1
```

### Menu

| Option | Action |
|---|---|
| 1 | **List & Connect**: show saved connections and connect to one |
| 2 | **Add connection**: create a new entry (and optionally save its secret) |
| 3 | **Edit connection**: change fields; press Enter to keep the current value |
| 4 | **Remove connection**: delete an entry (and optionally its stored credential) |
| 5 | **Manage Credential Manager entry**: create or update a stored password / passphrase |
| 6 | Open the CSV in Notepad |
| 7 | Open the log file |
| 0 | Exit |

### Adding a connection

Choose option 2 and answer the prompts:

- **Connection name**: unique; also used as the Credential Manager target name
- **Auth type**: `password` (default) or `key`
- **Username**, **Host / IP**, **Port** (default `22`)
- **Key path** (key auth only): leave empty to auto-detect
- Whether to store the secret in Credential Manager now

### Connecting

- **Password auth**: the saved password is passed to `plink`. If no credential is stored, add one with option 5. If `plink.exe` isn't found, the script falls back to native `ssh` and you type the password yourself.
- **Key auth**: runs `ssh -i <key>`. If no key path is set, it looks for `~\.ssh\id_ed25519`, `~\.ssh\id_rsa`, then `id_ed25519` / `id_rsa` in the current directory. Passphrase prompts are handled by `ssh` itself.

### Host key verification

On the first connection to a server, the script prints the host key fingerprint and asks `Trust this host and continue? (y/N)`. **Compare the fingerprint with your server's before answering `y`.** Answering `y` trusts the key for that session only; it isn't saved. To cache it permanently, connect once manually:

```powershell
plink -ssh user@host
```

and answer `y` to the "Store key in cache?" prompt. After that, no prompt appears.

---

## Files

| File | Location | Purpose |
|---|---|---|
| `scm_connections.csv` | `%USERPROFILE%` | Connection inventory |
| `scm_logs.log` | `%USERPROFILE%` | Timestamped log |

CSV columns:

```csv
ConnName,AuthType,User,Host,Port,KeyPath
MyServer,password,admin,192.0.2.10,22,
MyKeyServer,key,deploy,example.com,2222,C:\Users\me\.ssh\id_ed25519
```

Secrets are stored in Credential Manager (Control Panel > Credential Manager > Windows Credentials) under the target name equal to `ConnName`. If you rename a connection, re-save its credential with option 5 under the new name.

---

## Troubleshooting

- **"Connection abandoned" on first connect**: the host key isn't trusted yet; answer `y` at the prompt (see above).
- **No colours in the remote terminal**: use Windows Terminal or a recent console host. The script enables VT processing automatically.
- **"No credential found"**: use option 5 with the connection name as the target.
- **`plink.exe` not found**: install PuTTY or add it to `PATH`; otherwise the script uses `ssh` and prompts you.
- **Module install fails**: run PowerShell as your user with internet access, or install the modules manually (see Installation).
- Check the log (menu option 7) for details.

---

## Security notes

- Passwords are never written to the CSV or log.
- `plink` receives the password via the `-pw` argument, which is visible to other processes on the same machine while the session runs. Prefer key authentication on shared machines.
- Credentials are stored with `LocalMachine` persistence in Credential Manager for the current Windows user.
