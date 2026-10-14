#Requires -Version 5.1

$CsvPath     = Join-Path $env:USERPROFILE "scm_connections.csv"
$LogPath     = Join-Path $env:USERPROFILE "scm_logs.log"
$DefaultPort = 22
$script:ShouldExit = $false

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","DEBUG")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $line -Encoding UTF8

    switch ($Level) {
        "ERROR" { Write-Host $Message -ForegroundColor Red }
        "WARN"  { Write-Host $Message -ForegroundColor Yellow }
        "DEBUG" { Write-Host $Message -ForegroundColor DarkGray }
        default { Write-Host $Message }
    }
}

function Ensure-Modules {
    $modules = @("CredentialManager", "Posh-SSH")
    foreach ($m in $modules) {
        if (-not (Get-Module -ListAvailable -Name $m)) {
            Write-Log "Installing missing module: $m ..." "WARN"
            try {
                Install-Module $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
                Write-Log "Module $m installed successfully"
            } catch {
                Write-Log "Failed to install module $m : $_" "ERROR"
                Pause
                return
            }
        }
        try {
            Import-Module $m -ErrorAction Stop
            Write-Log "Module $m loaded" "DEBUG"
        } catch {
            Write-Log "Failed to import module $m : $_" "ERROR"
            Pause
        }
    }
}

function Get-Connections {
    if (-not (Test-Path $CsvPath)) {
        "ConnName,AuthType,User,Host,Port,KeyPath" | Set-Content -Path $CsvPath -Encoding UTF8
        Write-Log "Created new CSV at $CsvPath"
        return @()
    }
    try {
        Import-Csv -Path $CsvPath
    } catch {
        Write-Log "Failed to read CSV: $_" "ERROR"
        return @()
    }
}

function Save-Connections {
    param([array]$Connections)

    try {
        # Make sure we always have an array (even if empty)
        $toSave = @($Connections)

        if ($toSave.Count -eq 0) {
            # Write just the header when the list is empty
            "ConnName,AuthType,User,Host,Port,KeyPath" | Set-Content -Path $CsvPath -Encoding UTF8
            Write-Log "CSV saved (0 entries - header only)" "DEBUG"
        }
        else {
            $toSave | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
            Write-Log "CSV saved ($($toSave.Count) entries)" "DEBUG"
        }
    }
    catch {
        Write-Log "Failed to save CSV: $_" "ERROR"
        Pause
    }
}

function Show-Menu {
    Clear-Host
    Write-Host "=== SSH Connection Manager ===" -ForegroundColor Cyan
    Write-Host "CSV : $CsvPath"
    Write-Host "Log : $LogPath"
    Write-Host ""
    Write-Host "1. List & Connect"
    Write-Host "2. Add connection"
    Write-Host "3. Edit connection"
    Write-Host "4. Remove connection"
    Write-Host "5. Manage Credential Manager entry"
    Write-Host "6. Open CSV in notepad"
    Write-Host "7. Open log file"
    Write-Host "0. Exit"
    Write-Host ""
}

function List-And-Connect {
    $conns = @(Get-Connections)
    if ($conns.Count -eq 0) {
        Write-Log "No connections defined yet." "WARN"
        Pause
        return
    }

    Write-Host ""
    Write-Host "Available connections:" -ForegroundColor Green
    Write-Host ""
    for ($i = 0; $i -lt $conns.Count; $i++) {
        $c    = $conns[$i]
        $port = if ($c.Port) { $c.Port } else { $DefaultPort }
        $auth = $c.AuthType.ToLower()
        $num  = $i + 1
        Write-Host ("{0,2}. {1,-20} {2}@{3}:{4}  [{5}]" -f $num, $c.ConnName, $c.User, $c.Host, $port, $auth)
    }
    Write-Host ""
    $choice = Read-Host "Enter number to connect (or Enter to cancel)"
    if (-not $choice -or $choice -notmatch '^\d+$') { return }

    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $conns.Count) {
        Write-Log "Invalid selection: $choice" "WARN"
        Pause
        return
    }

    Connect-ToServer -Connection $conns[$idx]
}

function Connect-ToServer {
    param($Connection)

    $port = if ($Connection.Port) { [int]$Connection.Port } else { $DefaultPort }
    $auth = $Connection.AuthType.ToLower()

    Write-Log "=== Starting connection to $($Connection.ConnName) ==="
    Write-Log "User=$($Connection.User)  Host=$($Connection.Host)  Port=$port  Auth=$auth"

    $storedCred = $null
    try {
        $storedCred = Get-StoredCredential -Target $Connection.ConnName -ErrorAction Stop
        Write-Log "Credential found in Credential Manager for target '$($Connection.ConnName)'" "DEBUG"
    } catch {
        Write-Log "No credential found for target '$($Connection.ConnName)'" "DEBUG"
    }

    try {
        if ($auth -eq "key") {
            $key = $Connection.KeyPath
            if (-not $key) {
                $possible = @(
                    (Join-Path $env:USERPROFILE ".ssh\id_ed25519"),
                    (Join-Path $env:USERPROFILE ".ssh\id_rsa"),
                    (Join-Path (Get-Location) "id_ed25519"),
                    (Join-Path (Get-Location) "id_rsa")
                )
                $key = $possible | Where-Object { Test-Path $_ } | Select-Object -First 1
            }

            if (-not $key -or -not (Test-Path $key)) {
                Write-Log "Private key file not found. KeyPath='$($Connection.KeyPath)'" "ERROR"
                Pause
                return
            }

            Write-Log "Launching native ssh with key: $key"
            & ssh -i $key -p $port "$($Connection.User)@$($Connection.Host)"
            Write-Log "ssh exited with code $LASTEXITCODE"
        }
        elseif ($auth -eq "password") {
            if (-not $storedCred) {
                Write-Log "No credential found for '$($Connection.ConnName)'. Use option 5." "ERROR"
                Pause
                return
            }

            $plink = $null
            $plinkCandidates = @(
                "plink.exe",
                (Join-Path $env:ProgramFiles "PuTTY\plink.exe"),
                (Join-Path ${env:ProgramFiles(x86)} "PuTTY\plink.exe"),
                (Join-Path $env:USERPROFILE "scoop\apps\putty\current\plink.exe")
            )
            foreach ($p in $plinkCandidates) {
                if (Get-Command $p -ErrorAction SilentlyContinue) {
                    $plink = (Get-Command $p).Source
                    break
                }
                if (Test-Path $p) {
                    $plink = $p
                    break
                }
            }

            if ($plink) {
                Write-Log "Using plink: $plink"
                $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($storedCred.Password)
                )
                $target = "$($Connection.User)@$($Connection.Host)"
                $hostKeyArgs = @()
                # Probe in batch mode: if the host key is not cached, plink prints its fingerprint and aborts
                $probe = (& $plink -ssh -P $port -batch $target exit 2>&1 | Out-String)
                if ($probe -match "not cached") {
                    $fp = [regex]::Match($probe, '(?m)^\s*ssh-\S+\s+\d+\s+(\S+)\s*$').Groups[1].Value
                    Write-Host "The server's host key is not cached. Fingerprint:" -ForegroundColor Yellow
                    Write-Host "  $fp"
                    $ans = Read-Host "Trust this host and continue? (y/N)"
                    if ($ans -notmatch '^[yY]') {
                        Write-Log "Host key rejected by user" "WARN"
                        return
                    }
                    $hostKeyArgs = @("-hostkey", $fp)
                }
                # Enable ANSI/VT processing so remote terminal colors render
                try {
                    if (-not ("Native.ConsoleVT" -as [type])) {
                        Add-Type -Namespace Native -Name ConsoleVT -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
                    }
                    $h = [Native.ConsoleVT]::GetStdHandle(-11)
                    $mode = 0
                    if ([Native.ConsoleVT]::GetConsoleMode($h, [ref]$mode)) {
                        [void][Native.ConsoleVT]::SetConsoleMode($h, $mode -bor 0x4)
                    }
                }
                catch { Write-Log "Could not enable VT processing: $_" "WARN" }
                & $plink -ssh -P $port -pw $plainPass @hostKeyArgs $target
                Write-Log "plink exited with code $LASTEXITCODE"
            }
            else {
                Write-Log "plink.exe not found - falling back to native ssh (you will be prompted)" "WARN"
                & ssh -p $port "$($Connection.User)@$($Connection.Host)"
                Write-Log "ssh exited with code $LASTEXITCODE"
            }
        }
        else {
            Write-Log "Unknown AuthType: $auth" "ERROR"
            Pause
        }
    }
    catch {
        Write-Log "EXCEPTION during connection: $_" "ERROR"
        Write-Log $_.ScriptStackTrace "ERROR"
        Pause
    }

    Write-Log "=== Connection attempt finished ==="
    Write-Host ""
    Write-Host "Press Enter to return to menu..." -ForegroundColor DarkGray
    Pause
}

function Add-Connection {
    Write-Host ""
    Write-Host "--- Add new connection ---"
    Write-Host ""

    $name = Read-Host "Connection name (unique - used as Credential Manager target)"
    if (-not $name) { return }

    $existing = Get-Connections | Where-Object { $_.ConnName -eq $name }
    if ($existing) {
        Write-Log "Connection name already exists: $name" "WARN"
        Pause
        return
    }

    $auth = Read-Host "Auth type (password / key) [password]"
    if (-not $auth) { $auth = "password" }
    $auth = $auth.ToLower()
    if ($auth -notin @("password","key")) {
        Write-Log "Invalid auth type entered: $auth" "WARN"
        return
    }

    $user       = Read-Host "Username"
    $serverHost = Read-Host "Host / IP"
    $port       = Read-Host "Port [$DefaultPort]"
    if (-not $port) { $port = $DefaultPort }

    $keyPath = ""
    if ($auth -eq "key") {
        $keyPath = Read-Host "Full path to private key (leave empty to auto-detect)"
    }

    $new = [PSCustomObject]@{
        ConnName = $name
        AuthType = $auth
        User     = $user
        Host     = $serverHost
        Port     = $port
        KeyPath  = $keyPath
    }

    $all = @(Get-Connections) + $new
    Save-Connections $all

    # Fixed string - no more parser error
    Write-Log ("Added connection: {0} ({1}@{2})" -f $name, $user, $serverHost)

    $createCred = Read-Host "Store secret in Credential Manager now? (Y/n)"
    if ($createCred -ne "n") {
        $prompt = if ($auth -eq "key") { "Key passphrase" } else { "Login password" }
        Manage-Credential -ConnName $name -User $user -Prompt $prompt
    }
    Pause
}

function Edit-Connection {
    $conns = @(Get-Connections)
    if ($conns.Count -eq 0) {
        Write-Log "Nothing to edit" "WARN"
        Pause
        return
    }

    Write-Host ""
    Write-Host "Select connection to edit:"
    Write-Host ""
    for ($i = 0; $i -lt $conns.Count; $i++) {
        Write-Host "$($i+1). $($conns[$i].ConnName)"
    }
    $choice = Read-Host "Number"
    if (-not $choice -or $choice -notmatch '^\d+$') { return }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $conns.Count) { return }

    $c = $conns[$idx]
    Write-Host ""
    Write-Host "Editing $($c.ConnName) (press Enter to keep current value)"
    Write-Host ""

    $newName = Read-Host "ConnName [$($c.ConnName)]"
    if ($newName) { $c.ConnName = $newName }

    $newAuth = Read-Host "AuthType [$($c.AuthType)]"
    if ($newAuth) { $c.AuthType = $newAuth.ToLower() }

    $newUser = Read-Host "User [$($c.User)]"
    if ($newUser) { $c.User = $newUser }

    $newHost = Read-Host "Host [$($c.Host)]"
    if ($newHost) { $c.Host = $newHost }

    $newPort = Read-Host "Port [$($c.Port)]"
    if ($newPort) { $c.Port = $newPort }

    if ($c.AuthType -eq "key") {
        $newKey = Read-Host "KeyPath [$($c.KeyPath)]"
        if ($null -ne $newKey) { $c.KeyPath = $newKey }
    }

    Save-Connections $conns
    Write-Log "Updated connection: $($c.ConnName)"
    Pause
}

function Remove-Connection {
    $conns = @(Get-Connections)
    if ($conns.Count -eq 0) {
        Write-Log "Nothing to remove" "WARN"
        Pause
        return
    }

    Write-Host ""
    Write-Host "Select connection to remove:"
    Write-Host ""
    for ($i = 0; $i -lt $conns.Count; $i++) {
        Write-Host "$($i+1). $($conns[$i].ConnName)"
    }
    $choice = Read-Host "Number"
    if (-not $choice -or $choice -notmatch '^\d+$') { return }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $conns.Count) { return }

    $name = $conns[$idx].ConnName
    $confirm = Read-Host "Really delete '$name'? (y/N)"
    if ($confirm -eq "y") {
        $conns = $conns | Where-Object { $_.ConnName -ne $name }
        Save-Connections $conns
        Write-Log "Removed connection: $name"

        $delCred = Read-Host "Also delete Credential Manager entry? (y/N)"
        if ($delCred -eq "y") {
            try {
                Remove-StoredCredential -Target $name -ErrorAction Stop
                Write-Log "Credential removed for $name"
            } catch {
                Write-Log "Could not remove credential: $_" "WARN"
            }
        }
    }
    Pause
}

function Manage-Credential {
    param(
        [string]$ConnName,
        [string]$User,
        [string]$Prompt = "Password / Passphrase"
    )

    if (-not $ConnName) {
        $ConnName = Read-Host "Connection / Credential target name"
    }
    if (-not $User) {
        $User = Read-Host "Username"
    }

    Write-Host ""
    Write-Host "Creating/updating Credential Manager entry for target: $ConnName"
    $securePass = Read-Host $Prompt -AsSecureString

    try {
        $cred = New-Object System.Management.Automation.PSCredential ($User, $securePass)
        New-StoredCredential -Target $ConnName -Credential $cred -Type Generic -Persist LocalMachine | Out-Null
        Write-Log "Credential stored for target '$ConnName' (user $User)"
    } catch {
        Write-Log "Failed to store credential: $_" "ERROR"
    }
    Pause
}

# ---------- Main ----------
Write-Log "=== SSH Manager started ==="
Ensure-Modules

do {
    Show-Menu
    $opt = Read-Host "Choose"

    switch ($opt) {
        "1" { List-And-Connect }
        "2" { Add-Connection }
        "3" { Edit-Connection }
        "4" { Remove-Connection }
        "5" { Manage-Credential }
        "6" { notepad $CsvPath; Pause }
        "7" { notepad $LogPath; Pause }
        "0" { $script:ShouldExit = $true }
        default { }
    }
} while (-not $script:ShouldExit)

Write-Log "=== SSH Manager exited ==="
Write-Host "Bye!" -ForegroundColor Cyan