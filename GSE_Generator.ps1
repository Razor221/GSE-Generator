<#
.SYNOPSIS
    Goldberg Steam Emulator Generator
.DESCRIPTION
    Generates steam_settings folder, DLC lists, achievements, validates interfaces, and downloads the Goldberg emulator with automated FlareSolverr integration.
#>

param (
    [Alias("t")][switch]$Toast,
    [Alias("i")][switch]$Interfaces,
    [Alias("e")][switch]$Emulator,
    [switch]$ie,
    [Alias("h")][switch]$Help,
    [Parameter(Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$InputFile
)

$global:HOME_DIR = $PSScriptRoot
if (-not $global:HOME_DIR) { $global:HOME_DIR = (Get-Location).Path }
Set-Location -Path $global:HOME_DIR

$global:TITLE = "Goldberg Steam Emulator Generator"
$global:GameAppID = $null
$global:GameName = $null
$global:GameNameShow = $null

# Load WinForms Assembly
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -----------------------------------------------------------------------------
# FUNCTIONS - FLARESOLVERR
# -----------------------------------------------------------------------------

Function Invoke-FlareSolverr {
    param([string]$Url)
    $fsUrl = 'http://127.0.0.1:8191/v1'
    
    $isReady = $false
    try {
        $null = Invoke-WebRequest -Uri 'http://127.0.0.1:8191/' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        $isReady = $true
    } catch {}

    if (-not $isReady) {
        $exePath = Join-Path $global:HOME_DIR 'Tools\FlareSolverr\flaresolverr.exe'
        if (Test-Path $exePath) {
            Write-Host "  [ ] Starting FlareSolverr..." -ForegroundColor DarkGray
            Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath) -WindowStyle Minimized
            for ($i = 0; $i -lt 25; $i++) {
                Start-Sleep -Seconds 1
                try {
                    $null = Invoke-WebRequest -Uri 'http://127.0.0.1:8191/' -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
                    $isReady = $true
                    break
                } catch {}
            }
        }
    }

    if ($isReady) {
        $body = @{ cmd = 'request.get'; url = $Url; maxTimeout = 60000 } | ConvertTo-Json
        try {
            $res = Invoke-RestMethod -Uri $fsUrl -Method Post -ContentType 'application/json' -Body $body
            if ($res.status -eq 'ok') {
                return $res.solution.response
            }
        } catch {
            Write-Warning "FlareSolverr request failed."
        }
    }
    return $null
}

# -----------------------------------------------------------------------------
# FUNCTIONS - FILE CONTEXT & API VALIDATION
# -----------------------------------------------------------------------------

Function Get-FileContext {
    param([string]$WantedName, [string]$WantedExtension)
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.InitialDirectory = $global:HOME_DIR
    $dialog.Filter = "$WantedName (*.$WantedExtension) | *.$WantedExtension"
    $dialog.Title = "Select $WantedName"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return [PSCustomObject]@{
            FileDir  = Split-Path $dialog.FileName -Parent
            FileName = Split-Path $dialog.FileName -Leaf
            FullPath = $dialog.FileName
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("If it is more convenient:`nDrag-and-drop the $WantedName file into the GSE_Generator script!", "INFO", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return $null
    }
}

Function Test-SteamApiFile {
    param([string]$FilePath)
    $7zExe = Join-Path $global:HOME_DIR "Tools\7z\7z.exe"
    if (-not (Test-Path $7zExe)) { return [PSCustomObject]@{ Valid = $false } }

    $isPE = $false
    $isCorrectName = $false
    $apiBits = "x32"
    $apiName = "steam_api"

    $output = & $7zExe l $FilePath
    foreach ($line in $output) {
        if ($line -match "Type\s+=\s+PE") { $isPE = $true }
        if ($line -match "Name\s+=\s+steam_api\.dll") { $isCorrectName = $true }
        if ($line -match "CPU\s+=\s+x86") { $apiBits = "x32"; $apiName = "steam_api" }
        if ($line -match "CPU\s+=\s+x64") { $apiBits = "x64"; $apiName = "steam_api64" }
    }

    if ($isPE) {
        return [PSCustomObject]@{
            Valid   = $true
            ApiBits = $apiBits
            ApiName = $apiName
        }
    }
    return [PSCustomObject]@{ Valid = $false }
}

Function Get-SteamInterfaces {
    param([string]$FilePath)
    Write-Host "`n  [ ] Searching interfaces . . ." -ForegroundColor DarkGray
    
    $content = Get-Content -LiteralPath $FilePath -Raw -Encoding Default
    $pattern = 'SteamClient\d{3}|SteamGameServerStats\d{3}|SteamGameServer\d{3}|SteamMatchMakingServers\d{3}|SteamMatchMaking\d{3}|SteamUser\d{3}|SteamFriends\d{3}|SteamUtils\d{3}|STEAMUSERSTATS_INTERFACE_VERSION\d{3}|STEAMAPPS_INTERFACE_VERSION\d{3}|SteamNetworking\d{3}|STEAMREMOTESTORAGE_INTERFACE_VERSION\d{3}|STEAMSCREENSHOTS_INTERFACE_VERSION\d{3}|STEAMHTTP_INTERFACE_VERSION\d{3}|STEAMUNIFIEDMESSAGES_INTERFACE_VERSION\d{3}|STEAMCONTROLLER_INTERFACE_VERSION\d{3}|SteamController\d{3}|STEAMUGC_INTERFACE_VERSION\d{3}|STEAMAPPLIST_INTERFACE_VERSION\d{3}|STEAMMUSIC_INTERFACE_VERSION\d{3}|STEAMMUSICREMOTE_INTERFACE_VERSION\d{3}|STEAMHTMLSURFACE_INTERFACE_VERSION_\d{3}|STEAMINVENTORY_INTERFACE_V\d{3}|STEAMVIDEO_INTERFACE_V\d{3}|SteamMasterServerUpdater\d{3}'
    
    $matches = [regex]::Matches($content, $pattern) | ForEach-Object { $_.Value } | Sort-Object -Unique

    if ($matches -match "SteamUser0\d{2}") {
        $matches | Out-File -FilePath (Join-Path $global:HOME_DIR "steam_interfaces.txt") -Encoding ASCII
        Write-Host "  [x] Done!" -ForegroundColor Green
        return $true
    } else {
        [System.Windows.Forms.MessageBox]::Show("MUST BE AN ORIGINAL API FILE", $global:TITLE, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        if (Test-Path "steam_interfaces.txt") { Remove-Item "steam_interfaces.txt" -Force }
        Write-Host "  [x] Done!" -ForegroundColor Green
        return $false
    }
}

Function Invoke-GoldbergEmulatorFork {
    param([string]$FilePath, [string]$ApiName, [string]$ApiBits, [string]$DestinationDir = $null)
    
    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $fileDir = [System.IO.Path]::GetDirectoryName($FilePath)

    if (-not $DestinationDir) {
        $DestinationDir = $fileDir
    }

    if (-not (Test-Path $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir | Out-Null
    }

    $apiAnswer = $null
    $changeNameBits = $false
    $optApi = ""

    if ($fileName -ne "$ApiName.dll") {
        $msgText = ""
        if ($fileName -eq "steam_api.dll") {
            $msgText = "The steam api filename is 'steam_api.dll' but has been verified as being 64-bit`n`nPress YES: Continue with 64-bits`nPress NO: Continue with 32-bits"
        } elseif ($fileName -eq "steam_api64.dll") {
            $msgText = "The steam api filename is 'steam_api64.dll' but has been verified as being 32-bit`n`nPress YES: Continue with 32-bits`nPress NO: Continue with 64-bits"
        }
        
        if ($msgText) {
            $vbsMsg = [System.Windows.Forms.MessageBox]::Show($msgText, "INCONSISTENT STEAMAPI", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
            if ($vbsMsg -eq [System.Windows.Forms.DialogResult]::Yes) { $apiAnswer = 6 }
            if ($vbsMsg -eq [System.Windows.Forms.DialogResult]::No) { $apiAnswer = 7 }
        }
    }

    if ($apiAnswer -eq 6) {
        if ($ApiName -eq "steam_api") { $changeNameBits = $true; $optApi = "64" }
        elseif ($ApiName -eq "steam_api64") { $changeNameBits = $true; $optApi = "32" }
    } elseif ($apiAnswer -eq 7) {
        if ($ApiName -eq "steam_api") { $ApiBits = "x64"; $ApiName = "steam_api64"; $optApi = "32" }
        elseif ($ApiName -eq "steam_api64") { $ApiBits = "x32"; $ApiName = "steam_api"; $optApi = "64" }
    }

    Write-Host "`n  [ ] Searching emulator . . ." -ForegroundColor DarkGray
    $latest = $null
    $emuDir = Join-Path $global:HOME_DIR "Tools\GoldbergSteamEmulator"
    if (-not (Test-Path $emuDir)) { New-Item -ItemType Directory -Path $emuDir | Out-Null }

    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/Detanup01/gbe_fork/releases/latest" -ErrorAction Stop
        $gberelease = $release.name
        $gbefile = ($release.assets | Where-Object { $_.name -match "emu-win-release" } | Select-Object -First 1).name
        
        if ($gberelease -and $gbefile) {
            $latest = $gberelease + ($gbefile -replace "emu-win-release", "")
            $zipPath = Join-Path $emuDir $gbefile
            
            if (-not (Test-Path (Join-Path $emuDir $latest))) {
                Get-ChildItem $emuDir -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue
                Invoke-WebRequest -Uri "https://github.com/Detanup01/gbe_fork/releases/latest/download/$gbefile" -OutFile $zipPath
                Set-Content -Path (Join-Path $emuDir $latest) -Value "downloaded"
            }

            $oDllName = "${ApiName}_o.dll"
            Copy-Item -Path $FilePath -Destination (Join-Path $DestinationDir $oDllName) -Force

            $7zExe = Join-Path $global:HOME_DIR "Tools\7z\7z.exe"
            if (Test-Path $7zExe) {
                & $7zExe e -y $zipPath "release\experimental\$ApiBits\$ApiName.dll" "-o$DestinationDir" | Out-Null
            }
        }
    } catch {}

    if (-not $latest) {
        $backupZip = Join-Path $emuDir "backup.7z"
        if (-not (Test-Path $backupZip)) {
            Invoke-WebRequest -Uri "https://github.com/brunolee-GIT/GSE-Generator/releases/download/backup/backup.7z" -OutFile $backupZip -ErrorAction SilentlyContinue
        }
        if (Test-Path $backupZip) {
            $oDllName = "${ApiName}_o.dll"
            Copy-Item -Path $FilePath -Destination (Join-Path $DestinationDir $oDllName) -Force
            $7zExe = Join-Path $global:HOME_DIR "Tools\7z\7z.exe"
            if (Test-Path $7zExe) {
                & $7zExe e -y $backupZip "release\experimental\$ApiBits\$ApiName.dll" "-o$DestinationDir" | Out-Null
            }
        }
    }

    if ($changeNameBits) {
        if ($ApiName -eq "steam_api") {
            if (Test-Path (Join-Path $DestinationDir "steam_api.dll")) {
                Rename-Item -Path (Join-Path $DestinationDir "steam_api.dll") -NewName "steam_api64.dll" -Force
            }
            if (Test-Path (Join-Path $DestinationDir "steam_api_o.dll")) {
                Rename-Item -Path (Join-Path $DestinationDir "steam_api_o.dll") -NewName "steam_api64_o.dll" -Force
            }
        } elseif ($ApiName -eq "steam_api64") {
            if (Test-Path (Join-Path $DestinationDir "steam_api64.dll")) {
                Rename-Item -Path (Join-Path $DestinationDir "steam_api64.dll") -NewName "steam_api.dll" -Force
            }
            if (Test-Path (Join-Path $DestinationDir "steam_api64_o.dll")) {
                Rename-Item -Path (Join-Path $DestinationDir "steam_api64_o.dll") -NewName "steam_api_o.dll" -Force
            }
        }
    }

    if ($apiAnswer) {
        [System.Windows.Forms.MessageBox]::Show("If doesn't work, you need the api $optApi-bit version", "INCONSISTENT STEAMAPI INFORMATION", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Exclamation)
    }

    Write-Host "  [x] Done!" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# FUNCTIONS - UI & GENERATORS
# -----------------------------------------------------------------------------

Function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "                                                                                                                     " -BackgroundColor Blue -ForegroundColor White
    Write-Host "                                         GOLDBERG STEAM EMULATOR GENERATOR                                           " -BackgroundColor Blue -ForegroundColor White
    Write-Host "                                           generate steam_settings folder                                            " -BackgroundColor Blue -ForegroundColor Gray
    Write-Host "                                                                                                                     " -BackgroundColor Blue
    Write-Host ""
}

Function Show-Help {
    Write-Host "`n  ARGUMENTS " -BackgroundColor White -ForegroundColor Black
    Write-Host "`n    USAGE: " -NoNewline; Write-Host ".\GSE_Generator.ps1 " -ForegroundColor Green -NoNewline; Write-Host "[-argument]" -ForegroundColor Yellow
    Write-Host "`n`n    arguments:" -ForegroundColor Cyan
    Write-Host "        -Help or -h ------------------------------- Show this help."
    Write-Host "        -Toast or -t ------------------------------ Test achievements."
    Write-Host "        -Interfaces or -i ------------------------- Generate steam_interfaces.txt file."
    Write-Host "        -Emulator or -e --------------------------- Download last Goldberg Steam emulator."
    Write-Host "        -ie --------------------------------------- Execute both -i and -e."
    Write-Host "`n`n  DRAG-AND-DROP " -BackgroundColor White -ForegroundColor Black
    Write-Host "`n    You can pass a file directly as an argument:"
    Write-Host "        achievements.json ------------------------- Does the same as -Toast."
    Write-Host "        steam_api.dll or steam_api64.dll ---------- Does the same as -ie.`n"
}

Function Show-SearchInput {
    $form = New-Object Windows.Forms.Form -Property @{
        StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
        FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedDialog
        MaximizeBox = $false
        MinimizeBox = $false
        Size = New-Object Drawing.Size(400, 155)
        ForeColor = 'White'
        BackColor = '#282828'
        Text = $global:TITLE
        Topmost = $true
        Font = New-Object System.Drawing.Font('Consolas', 13)
    }

    $form.Controls.Add((New-Object Windows.Forms.Label -Property @{
        Location = New-Object Drawing.Point(10, 5)
        Size = New-Object Drawing.Size(380, 20)
        Text = 'Enter the name or ID of game:'
    }))

    $inputBox = New-Object Windows.Forms.TextBox -Property @{
        Location = New-Object Drawing.Point(10, 35)
        Size = New-Object Drawing.Size(360, 25)
        MaxLength = 39
    }
    $form.Controls.Add($inputBox)

    $searchBtn = New-Object Windows.Forms.Button -Property @{
        Location = New-Object Drawing.Point(100, 75)
        Size = New-Object Drawing.Size(190, 30)
        Text = 'SEARCH'
        DialogResult = [Windows.Forms.DialogResult]::OK
        Font = New-Object System.Drawing.Font('Microsoft Sans Serif', 13)
        ForeColor = 'Black'
    }
    $form.Controls.Add($searchBtn)
    $form.AcceptButton = $searchBtn

    if ($form.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        return $inputBox.Text.Trim()
    }
    return $null
}

Function Search-Game {
    param([string]$Query)
    Write-Host "`n  [ ] Searching game . . ." -ForegroundColor DarkGray

    $isNumeric = $Query -match '^\d+$'
    $GameAppID = $null
    $GameName = $null

    if ($isNumeric) {
        $GameAppID = $Query
    } else {
        # 1. Try official Steam Store Search first (fastest for active games)
        try {
            $encodedQuery = [uri]::EscapeDataString($Query)
            $searchRes = Invoke-RestMethod -Uri "https://store.steampowered.com/api/storesearch/?term=$encodedQuery&l=english&cc=US" -TimeoutSec 5
            if ($searchRes.total -gt 0) {
                $exactMatch = $null
                $normalizedMatch = $null
                $wordMatch = $null
                $containsMatch = $null
                
                $normalizedQuery = $Query -replace '[^a-zA-Z0-9]', ''
                if (-not $normalizedQuery) { $normalizedQuery = $Query }

                foreach ($item in $searchRes.items) {
                    $appName = $item.name
                    $appId = $item.id
                    
                    $cleanAppName = $appName -replace '[™®©]', ''
                    $normalizedAppName = $appName -replace '[^a-zA-Z0-9]', ''
                    
                    if (-not $exactMatch -and ($appName -eq $Query -or $cleanAppName -eq $Query)) {
                        $exactMatch = $item
                    }
                    if (-not $normalizedMatch -and ($normalizedAppName -eq $normalizedQuery)) {
                        $normalizedMatch = $item
                    }
                    if (-not $wordMatch -and ($cleanAppName -match "(?i)\b$([regex]::Escape($Query))\b")) {
                        $wordMatch = $item
                    }
                    if (-not $containsMatch -and ($normalizedAppName -match "(?i)$([regex]::Escape($normalizedQuery))")) {
                        $containsMatch = $item
                    }
                }

                $bestMatch = $null
                if ($exactMatch) { $bestMatch = $exactMatch }
                elseif ($normalizedMatch) { $bestMatch = $normalizedMatch }
                elseif ($wordMatch) { $bestMatch = $wordMatch }
                elseif ($containsMatch) { $bestMatch = $containsMatch }
                
                if ($bestMatch) {
                    $GameAppID = $bestMatch.id
                    $GameName = $bestMatch.name
                }
            }
        } catch {}

        # 2. If Steam Store search fails (e.g., delisted game), fallback to SteamDB search via FlareSolverr to get AppID only
        if (-not $GameAppID) {
            $encodedQuery = [uri]::EscapeDataString($Query)
            $dbSearchHtml = Invoke-FlareSolverr -Url "https://steamdb.info/search/?a=app&q=$encodedQuery&type=1&category=0"
            
            $appRows = [regex]::Matches($dbSearchHtml, '(?i)<tr[^>]*data-appid="(\d+)"[^>]*>([\s\S]*?)</tr>')
            
            $exactMatchAppId = $null
            $normalizedMatchAppId = $null
            $wordMatchAppId = $null
            $containsMatchAppId = $null
            $firstAppId = $null
            
            $normalizedQuery = $Query -replace '[^a-zA-Z0-9]', ''
            if (-not $normalizedQuery) { $normalizedQuery = $Query }
            
            foreach ($row in $appRows) {
                $appId = $row.Groups[1].Value
                if (-not $firstAppId) { $firstAppId = $appId }
                
                $innerHtml = $row.Groups[2].Value
                $anchors = [regex]::Matches($innerHtml, '(?i)<a[^>]*href="/app/\d+/"[^>]*>([\s\S]*?)</a>')
                
                foreach ($anchor in $anchors) {
                    $appName = ($anchor.Groups[1].Value -replace '<[^>]+>', '').Trim()
                    $appName = [System.Net.WebUtility]::HtmlDecode($appName)
                    
                    $cleanAppName = $appName -replace '[™®©]', ''
                    $normalizedAppName = $appName -replace '[^a-zA-Z0-9]', ''
                    
                    if (-not $exactMatchAppId -and ($appName -eq $Query -or $cleanAppName -eq $Query)) {
                        $exactMatchAppId = $appId
                    }
                    if (-not $normalizedMatchAppId -and ($normalizedAppName -eq $normalizedQuery)) {
                        $normalizedMatchAppId = $appId
                    }
                    if (-not $wordMatchAppId -and ($cleanAppName -match "(?i)\b$([regex]::Escape($Query))\b")) {
                        $wordMatchAppId = $appId
                    }
                    if (-not $containsMatchAppId -and ($normalizedAppName -match "(?i)$([regex]::Escape($normalizedQuery))")) {
                        $containsMatchAppId = $appId
                    }
                }
            }
            
            if ($exactMatchAppId) { $GameAppID = $exactMatchAppId }
            elseif ($normalizedMatchAppId) { $GameAppID = $normalizedMatchAppId }
            elseif ($wordMatchAppId) { $GameAppID = $wordMatchAppId }
            elseif ($containsMatchAppId) { $GameAppID = $containsMatchAppId }
            elseif ($firstAppId) { $GameAppID = $firstAppId }
            elseif ($dbSearchHtml -match 'href="/app/(\d+)/"') { $GameAppID = $matches[1] }
        }
    }

    # Once we have the GameAppID, fetch the official name cleanly from its SteamDB page or appdetails API
    if ($GameAppID -and -not $GameName) {
        try {
            $appDetails = Invoke-RestMethod -Uri "https://store.steampowered.com/api/appdetails/?filters=basic&appids=$GameAppID" -TimeoutSec 5
            if ($appDetails."$GameAppID".success) {
                $GameName = $appDetails."$GameAppID".data.name
            }
        } catch {}

        if (-not $GameName) {
            $html = Invoke-FlareSolverr -Url "https://steamdb.info/app/$GameAppID/"
            if ($html -match '(?i)<h1[^>]*itemprop="name"[^>]*>(.*?)</h1>') {
                $GameName = ($matches[1] -replace '<[^>]+>', '').Trim()
            }
        }
    }

    if (-not $GameName -or -not $GameAppID) {
        Write-Host "    GAME NOT FOUND " -ForegroundColor Red
        Start-Sleep -Seconds 3
        return $false
    }

    $GameName = $GameName.Trim()
    $global:GameNameShow = $GameName
    $global:GameAppID = $GameAppID
    $global:GameName = "$GameName ($GameAppID)" -replace '[/:<>\\|?*]', ''
    
    Write-Host "    $($global:GameName)" -ForegroundColor DarkGray
    return $true
}

Function Confirm-Game {
    $imgFile = Join-Path $global:HOME_DIR "$global:GameAppID.jpg"
    try {
        Invoke-WebRequest -Uri "https://cdn.akamai.steamstatic.com/steam/apps/$global:GameAppID/header.jpg" -OutFile $imgFile -ErrorAction Stop
    } catch {
        # Ignore 404 or other errors to continue displaying the confirmation UI
    }

    $form = New-Object Windows.Forms.Form -Property @{
        StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
        FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedDialog
        ControlBox = $false
        Size = New-Object Drawing.Size(500, 400)
        ForeColor = 'White'
        BackColor = '#282828'
        Text = $global:TITLE
        Topmost = $true
        Font = New-Object System.Drawing.Font('Consolas', 13)
    }

    $form.Controls.Add((New-Object Windows.Forms.Label -Property @{ Location = New-Object Drawing.Point(10, 5); Size = New-Object Drawing.Size(500, 20); Text = 'Found this game:' }))
    $form.Controls.Add((New-Object Windows.Forms.Label -Property @{ Location = New-Object Drawing.Point(10, 25); Size = New-Object Drawing.Size(500, 20); ForeColor = 'Gold'; Text = $global:GameNameShow; Font = New-Object System.Drawing.Font('Consolas', 13, [System.Drawing.FontStyle]::Bold) }))
    
    $hasImg = Test-Path $imgFile
    if ($hasImg) {
        $img = [System.Drawing.Image]::FromFile($imgFile)
        $pic = New-Object Windows.Forms.PictureBox -Property @{ Location = New-Object Drawing.Point(12, 55); Size = New-Object Drawing.Size(460, 215); Image = $img; SizeMode = 'StretchImage' }
        $form.Controls.Add($pic)
    } else {
        $noImgLbl = New-Object Windows.Forms.Label -Property @{ Location = New-Object Drawing.Point(12, 140); Size = New-Object Drawing.Size(460, 20); Text = '(No header image available)'; ForeColor = 'Gray'; TextAlign = 'MiddleCenter' }
        $form.Controls.Add($noImgLbl)
    }

    $form.Controls.Add((New-Object Windows.Forms.Label -Property @{ Location = New-Object Drawing.Point(10, 280); Size = New-Object Drawing.Size(500, 20); Text = 'Do you want to continue?' }))

    $btnYes = New-Object Windows.Forms.Button -Property @{ Location = New-Object Drawing.Point(30, 310); Size = New-Object Drawing.Size(200, 30); Text = 'YES'; DialogResult = [Windows.Forms.DialogResult]::Yes; ForeColor = 'Black' }
    $btnNo = New-Object Windows.Forms.Button -Property @{ Location = New-Object Drawing.Point(260, 310); Size = New-Object Drawing.Size(200, 30); Text = 'NO'; DialogResult = [Windows.Forms.DialogResult]::No; ForeColor = 'Black' }
    
    $form.Controls.Add($btnYes)
    $form.Controls.Add($btnNo)

    $res = $form.ShowDialog()
    
    if ($hasImg) {
        $img.Dispose()
    }
    
    if ($res -eq [Windows.Forms.DialogResult]::Yes) {
        $settingsDir = Join-Path $global:HOME_DIR "$global:GameName\steam_settings"
        if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir | Out-Null }
        if ($hasImg) { Move-Item -Path $imgFile -Destination $settingsDir -Force }
        Set-Content -Path (Join-Path $settingsDir "steam_appid.txt") -Value $global:GameAppID
        Write-Host "  [x] Done!" -ForegroundColor Green
        return $true
    } else {
        if ($hasImg) { Remove-Item -Path $imgFile -Force }
        Write-Host "    CANCELED " -ForegroundColor Red
        Start-Sleep -Seconds 3
        return $false
    }
}

Function Get-Dlcs {
    Write-Host "`n  [ ] Searching downloadable content . . ." -ForegroundColor DarkGray
    $settingsDir = Join-Path $global:HOME_DIR "$global:GameName\steam_settings"
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir | Out-Null }
    $configAppIni = Join-Path $settingsDir "configs.app.ini"

    $iniContent = @()
    $iniContent += "[app::dlcs]"
    $iniContent += "unlock_all=0"
    $dlcFound = $false

    # Try Steam API first
    try {
        $appDetails = Invoke-RestMethod -Uri "https://store.steampowered.com/api/appdetails/?filters=basic&appids=$global:GameAppID" -TimeoutSec 5
        if ($appDetails."$global:GameAppID".success) {
            $dlcFound = $true
            if ($appDetails."$global:GameAppID".data.dlc) {
                $dlcList = $appDetails."$global:GameAppID".data.dlc
                $count = 0
                $total = $dlcList.Count
                if ($total -gt 0) {
                    $appListMap = @{}
                    try {
                        $appListRes = Invoke-RestMethod -Uri "https://api.steampowered.com/ISteamApps/GetAppList/v2/" -TimeoutSec 10
                        foreach ($app in $appListRes.applist.apps) {
                            $appListMap[$app.appid.ToString()] = $app.name
                        }
                    } catch {}
                    
                    foreach ($dlcId in $dlcList) {
                        $count++
                        $appName = $dlcId
                        if ($appListMap.ContainsKey($dlcId.ToString())) {
                            $appName = $appListMap[$dlcId.ToString()]
                        }
                        
                        Write-Host "  [$count/$total]  $dlcId  =  $appName" -ForegroundColor Green
                        $iniContent += "$dlcId=$appName"
                    }
                }
            }
        }
    } catch {
        Write-Host "  [-] Steam API failed. Falling back to SteamDB..." -ForegroundColor Yellow
    }

    if (-not $dlcFound) {
        Write-Host "  [-] Steam API failed or returned no DLCs. Using SteamDB..." -ForegroundColor Yellow
        $html = Invoke-FlareSolverr -Url "https://steamdb.info/app/$global:GameAppID/dlc/"
        $dlcRows = [regex]::Matches($html, '(?i)<tr[^>]*data-appid="(\d+)"[^>]*>([\s\S]*?)</tr>')
        
        if ($dlcRows.Count -gt 0) {
            $count = 0
            $total = $dlcRows.Count
            foreach ($row in $dlcRows) {
                $count++
                $dlcId = $row.Groups[1].Value
                $rowInnerHtml = $row.Groups[2].Value
                $appName = $dlcId 

                $cells = [regex]::Matches($rowInnerHtml, '(?i)<td[^>]*>([\s\S]*?)</td>')
                foreach ($cell in $cells) {
                    $cellText = $cell.Groups[1].Value -replace '<[^>]+>', ''
                    $cellText = [System.Net.WebUtility]::HtmlDecode($cellText).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($cellText) -and $cellText -ne $dlcId -and $cellText -match '[a-zA-Z]') {
                        $appName = $cellText
                        break
                    }
                }

                if ($appName -eq $dlcId) {
                    $anchors = [regex]::Matches($rowInnerHtml, '(?i)<a[^>]*>([\s\S]*?)</a>')
                    foreach ($a in $anchors) {
                        $cleanText = $a.Groups[1].Value -replace '<[^>]+>', ''
                        $cleanText = [System.Net.WebUtility]::HtmlDecode($cleanText).Trim()
                        if ($cleanText -ne $dlcId -and -not [string]::IsNullOrWhiteSpace($cleanText)) {
                            $appName = $cleanText
                            break
                        }
                    }
                }

                Write-Host "  [$count/$total]  $dlcId  =  $appName" -ForegroundColor Green
                $iniContent += "$dlcId=$appName"
                $dlcFound = $true
            }
        }
    }

    if ($dlcFound) {
        $iniContent | Out-File -FilePath $configAppIni -Encoding UTF8
        Write-Host "  [x] Done!" -ForegroundColor Green
    } else {
        Write-Host "  [x] No DLCs found." -ForegroundColor Green
    }
}

Function Get-UserConfigs {
    Write-Host "`n  [ ] Searching supported languages and configuring user . . ." -ForegroundColor DarkGray
    $settingsDir = Join-Path $global:HOME_DIR "$global:GameName\steam_settings"
    $langFile = Join-Path $settingsDir "supported_languages.txt"

    try {
        $appDetails = Invoke-RestMethod -Uri "https://store.steampowered.com/api/appdetails/?filters=basic&appids=$global:GameAppID"
        if ($appDetails."$global:GameAppID".success -and $appDetails."$global:GameAppID".data.supported_languages) {
            $langs = $appDetails."$global:GameAppID".data.supported_languages -replace '<strong>\*</strong>', '' -replace '<br>languages with full audio support', ''
            
            $langMap = @{
                "Arabic"="arabic"; "Bulgarian"="bulgarian"; "Simplified Chinese"="schinese";
                "Traditional Chinese"="tchinese"; "Czech"="czech"; "Danish"="danish";
                "Dutch"="dutch"; "English"="english"; "Finnish"="finnish";
                "French"="french"; "German"="german"; "Greek"="greek";
                "Hungarian"="hungarian"; "Indonesian"="indonesian"; "Italian"="italian";
                "Japanese"="japanese"; "Korean"="koreana"; "Norwegian"="norwegian";
                "Polish"="polish"; "Portuguese - Portugal"="portuguese"; "Portuguese - Brazil"="brazilian";
                "Romanian"="romanian"; "Russian"="russian"; "Spanish - Spain"="spanish";
                "Spanish - Latin America"="latam"; "Swedish"="swedish"; "Thai"="thai";
                "Turkish"="turkish"; "Ukrainian"="ukrainian"; "Vietnamese"="vietnamese"
            }

            $validLangs = @()
            foreach ($l in ($langs -split ', ')) {
                if ($langMap.ContainsKey($l)) { $validLangs += $langMap[$l] }
            }
            $validLangs | Out-File -FilePath $langFile -Encoding UTF8
        }
    } catch {}

    $htaUser = Join-Path $global:HOME_DIR "Tools\GSE_user_configs.hta"
    if (Test-Path $htaUser) {
        $null = cmd.exe /c "mshta.exe `"$htaUser`" `"$langFile`""
    }

    $iniFile = Join-Path $global:HOME_DIR "configs.user.ini"
    if (Test-Path $iniFile) {
        Move-Item -Path $iniFile -Destination (Join-Path $settingsDir "configs.user.ini") -Force
    }
    Write-Host "  [x] Done!" -ForegroundColor Green
}

Function Get-Achievements {
    Write-Host "`n  [ ] Searching achievements . . ." -ForegroundColor DarkGray
    $settingsDir = Join-Path $global:HOME_DIR "$global:GameName\steam_settings"
    $imgDir = Join-Path $settingsDir "images"
    $langFile = Join-Path $settingsDir "supported_languages.txt"
    
    $secureKeyFile = Join-Path $global:HOME_DIR "steam_api_key.clixml"
    $plainKeyFile = Join-Path $global:HOME_DIR "key.txt"
    $apiKey = $null

    if (Test-Path $secureKeyFile) {
        try {
            $secureString = Import-Clixml -Path $secureKeyFile
            $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
            $apiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        } catch {
            Write-Host "  [-] Failed to decrypt secure API key. It may have been created on another machine or user account." -ForegroundColor Yellow
        }
    }

    if (-not $apiKey -and (Test-Path $plainKeyFile)) {
        $apiKey = (Get-Content $plainKeyFile).Trim()
        if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
            try {
                $secureString = ConvertTo-SecureString $apiKey -AsPlainText -Force
                $secureString | Export-Clixml -Path $secureKeyFile
                Remove-Item $plainKeyFile -Force
                Write-Host "  [i] Automatically encrypted key.txt into secure steam_api_key.clixml and deleted the plain-text file." -ForegroundColor Cyan
            } catch {
                Write-Host "  [-] Failed to encrypt API key." -ForegroundColor Yellow
            }
        }
    }
    
    $htaAch = Join-Path $global:HOME_DIR "Tools\GSE_achievements_language.hta"
    $achLanguage = "en"
    $forceFix = $false
    
    if (Test-Path $htaAch) {
        $achLangOut = (cmd.exe /c "mshta.exe `"$htaAch`" `"$langFile`"") | Select-Object -Last 1
        if ($achLangOut) {
            $achLangOut = $achLangOut.Trim()
            if ($achLangOut -eq "ForceFix") {
                $forceFix = $true
            } else {
                $achLanguage = $achLangOut
            }
        }
    }

    $achievementsObj = @()
    $apiSuccess = $false
    $cdnBaseUrl = "https://cdn.akamai.steamstatic.com/steamcommunity/public/images/apps/$global:GameAppID/"

    if ($apiKey) {
        try {
            $apiUrl = "https://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/?key=$apiKey&appid=$global:GameAppID&l=$achLanguage"
            $schema = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
            $apiSuccess = $true
            
            if ($schema.game.availableGameStats.stats) {
                $statsJsonPath = Join-Path $settingsDir "stats.json"
                $statsArray = @()
                foreach ($stat in $schema.game.availableGameStats.stats) {
                    $type = "int"
                    if ($stat.defaultvalue -is [double] -or $stat.defaultvalue -match "\.") {
                        $type = "float"
                    }
                    $statsArray += [ordered]@{
                        name = $stat.name
                        type = $type
                        defaultvalue = $stat.defaultvalue
                    }
                }
                $statsArray | ConvertTo-Json -Depth 3 | Out-File -FilePath $statsJsonPath -Encoding UTF8
                Write-Host "  [x] Stats generated with $($statsArray.Count) stats in stats.json!" -ForegroundColor Green
            }
            
            if ($schema.game.availableGameStats.achievements) {
                if (-not (Test-Path $imgDir)) { New-Item -ItemType Directory -Path $imgDir | Out-Null }
                
                $count = 0
                $total = $schema.game.availableGameStats.achievements.Count
                
                foreach ($ach in $schema.game.availableGameStats.achievements) {
                    $count++
                    $finalName = $ach.displayName
                    $finalDesc = $ach.description
                    $iconUrl = $ach.icon
                    $grayUrl = $ach.icongray
                    $apiName = $ach.name
                    $isHidden = [bool]($ach.hidden)

                    Write-Host "   [$count/$total]   $finalName" -ForegroundColor Green

                    $iconName = ""
                    $grayName = ""
                    
                    if ($iconUrl) {
                        $iconName = ($iconUrl -split '/')[-1]
                        $iconDest = Join-Path $imgDir $iconName
                        if (-not (Test-Path $iconDest)) { 
                            try { Invoke-WebRequest -Uri $iconUrl -OutFile $iconDest -ErrorAction Stop } catch {} 
                        }
                    }
                    if ($grayUrl) {
                        $grayName = ($grayUrl -split '/')[-1]
                        $grayDest = Join-Path $imgDir $grayName
                        if (-not (Test-Path $grayDest)) { 
                            try { Invoke-WebRequest -Uri $grayUrl -OutFile $grayDest -ErrorAction Stop } catch {} 
                        }
                    }

                    $achievementsObj += [ordered]@{
                        description = if ($finalDesc) { $finalDesc } else { "" }
                        displayName = if ($finalName) { $finalName } else { "" }
                        hidden      = $isHidden
                        icon        = if ($iconName) { "images/$iconName" } else { "" }
                        icongray    = if ($grayName) { "images/$grayName" } else { "" }
                        name        = $apiName
                    }
                }
            } elseif ($schema.game) {
                Write-Host "  [x] No achievements found on Steam." -ForegroundColor Green
                return
            }
        } catch {
            Write-Host "  [-] Steam API failed or rejected key. Falling back to SteamDB..." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [-] No valid API key found. Using SteamDB..." -ForegroundColor Yellow
    }

    if (-not $apiSuccess) {
        $dbHtml = Invoke-FlareSolverr -Url "https://steamdb.info/app/$global:GameAppID/stats/"
        if (-not $dbHtml) {
            Write-Host "  [-] No achievements found on SteamDB." -ForegroundColor Yellow
            return
        }
        
        $steamHtml = ""
        if (-not $forceFix) {
            try {
                $steamHtml = (Invoke-WebRequest -Uri "https://steamcommunity.com/stats/$global:GameAppID/achievements/" -Headers @{ "Accept-Language" = $achLanguage } -UseBasicParsing).Content
            } catch {}
        }
        
        $blocks = $dbHtml -split '<div class="achievement"'
        if ($blocks.Count -le 1) {
            Write-Host "  [x] No achievements." -ForegroundColor Green
            return
        }
        
        if (-not (Test-Path $imgDir)) { New-Item -ItemType Directory -Path $imgDir | Out-Null }
        
        $count = 0
        $total = $blocks.Count - 1
        
        foreach ($b in ($blocks | Select-Object -Skip 1)) {
            if ($b -match 'id="achievement-([^"]+)"') {
                $count++
                $apiName = $matches[1]
                $name = ""
                $desc = ""
                $iconUrl = ""
                $grayUrl = ""
                
                if ($b -match '<div class="achievement_name">([\s\S]*?)</div>') {
                    $name = $matches[1] -replace '<[^>]+>', ''
                    $name = $name.Trim() -replace '&quot;', '"' -replace '&amp;', '&' -replace '&#39;', "'"
                }
                if ($b -match '<div class="achievement_desc">([\s\S]*?)</div>') {
                    $desc = $matches[1] -replace '<[^>]+>', ''
                    $desc = $desc.Trim() -replace '&quot;', '"' -replace '&amp;', '&' -replace '&#39;', "'"
                }
                
                $imgs = [regex]::Matches($b, 'data-name="([^"]+\.jpg)"')
                if ($imgs.Count -ge 2) {
                    $grayUrl = $imgs[0].Groups[1].Value
                    $iconUrl = $imgs[1].Groups[1].Value
                } elseif ($imgs.Count -eq 1) {
                    $grayUrl = $imgs[0].Groups[1].Value
                    $iconUrl = $grayUrl
                }
                
                $isHidden = [bool]($b -match 'text-muted|achievement_hidden')
                $iconName = ($iconUrl -split '/')[-1]
                $grayName = ($grayUrl -split '/')[-1]
                
                $finalName = $name
                $finalDesc = $desc
                
                if (-not $forceFix -and $steamHtml -and $iconName) {
                    $escIcon = [regex]::Escape($iconName)
                    $locPattern = '(?s)' + $escIcon + '.*?<h3>(?<lname>[^<]+)</h3>\s*<h5[^>]*>(?<ldesc>[^<]*)</h5>'
                    if ($steamHtml -match $locPattern) {
                        $finalName = $matches['lname'].Trim() -replace '&quot;', '"' -replace '&amp;', '&' -replace '&#39;', "'"
                        $finalDesc = $matches['ldesc'].Trim() -replace '&quot;', '"' -replace '&amp;', '&' -replace '&#39;', "'"
                    }
                }
                
                Write-Host "   [$count/$total]   $finalName" -ForegroundColor Green
                
                if ($iconName) {
                    $iconDest = Join-Path $imgDir $iconName
                    if (-not (Test-Path $iconDest)) { 
                        try { Invoke-WebRequest -Uri ($cdnBaseUrl + $iconName) -OutFile $iconDest -ErrorAction Stop } catch {} 
                    }
                }
                if ($grayName) {
                    $grayDest = Join-Path $imgDir $grayName
                    if (-not (Test-Path $grayDest)) { 
                        try { Invoke-WebRequest -Uri ($cdnBaseUrl + $grayName) -OutFile $grayDest -ErrorAction Stop } catch {} 
                    }
                }
                
                $achievementsObj += [ordered]@{
                    description = $finalDesc
                    displayName = $finalName
                    hidden      = $isHidden
                    icon        = if ($iconName) { "images/$iconName" } else { "" }
                    icongray    = if ($grayName) { "images/$grayName" } else { "" }
                    name        = $apiName
                }
            }
        }
    }

    if ($achievementsObj.Count -gt 0) {
        $jsonPath = Join-Path $settingsDir "achievements.json"
        $achievementsObj | ConvertTo-Json -Depth 4 | Out-File -FilePath $jsonPath -Encoding UTF8
        Write-Host "  [x] Achievements JSON generated with $($achievementsObj.Count) achievements!" -ForegroundColor Green
    } else {
        Write-Host "  [-] Failed to parse achievements." -ForegroundColor Red
    }
}

Function Process-SteamApiInteractive {
    $gameDir = Join-Path $global:HOME_DIR $global:GameName
    $settingsDir = Join-Path $gameDir "steam_settings"
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir | Out-Null }

    $apiFiles = Get-ChildItem -Path $global:HOME_DIR -Filter "*steam_api*.dll" -File
    $apiFileToProcess = $null

    foreach ($f in $apiFiles) {
        $check = Test-SteamApiFile -FilePath $f.FullName
        if ($check.Valid) {
            $res = [System.Windows.Forms.MessageBox]::Show("This '$($f.Name)' is from this game?", "STEAM_API", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
            if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
                $apiFileToProcess = $f.FullName
                break
            }
        }
    }

    if (-not $apiFileToProcess) {
        $res = [System.Windows.Forms.MessageBox]::Show("Do you want to search the original steam_api of this game to continue?", "STEAM_API", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
        if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
            $dialog = New-Object System.Windows.Forms.OpenFileDialog
            $dialog.InitialDirectory = $global:HOME_DIR
            $dialog.Filter = "steam_api (*.dll) | *.dll"
            $dialog.Title = "Select original steam_api.dll"
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $apiFileToProcess = $dialog.FileName
            }
        }
    }

    if ($apiFileToProcess) {
        $check = Test-SteamApiFile -FilePath $apiFileToProcess
        if ($check.Valid) {
            if (Get-SteamInterfaces -FilePath $apiFileToProcess) {
                $interfacesTxt = Join-Path $global:HOME_DIR "steam_interfaces.txt"
                if (Test-Path $interfacesTxt) {
                    Move-Item -Path $interfacesTxt -Destination (Join-Path $settingsDir "steam_interfaces.txt") -Force
                }
                Invoke-GoldbergEmulatorFork -FilePath $apiFileToProcess -ApiName $check.ApiName -ApiBits $check.ApiBits -DestinationDir $gameDir
            }
        }
    }
}

# -----------------------------------------------------------------------------
# MAIN EXECUTION & ARGUMENT HANDLING
# -----------------------------------------------------------------------------

if ($Help -or $h) {
    Show-Help
    Read-Host "Press Enter to exit"
    exit
}

if ($Toast -or $t) {
    $ctx = Get-FileContext -WantedName "achievements" -WantedExtension "json"
    if ($ctx) {
        Write-Host "Achievement JSON selected: $($ctx.FullPath)" -ForegroundColor Green
    }
    Read-Host "Press Enter to exit"
    exit
}

if ($Interfaces -or $i) {
    $ctx = Get-FileContext -WantedName "steam_api" -WantedExtension "dll"
    if ($ctx) {
        $apiCheck = Test-SteamApiFile -FilePath $ctx.FullPath
        if ($apiCheck.Valid) {
            $null = Get-SteamInterfaces -FilePath $ctx.FullPath
        }
    }
    Read-Host "Press Enter to exit"
    exit
}

if ($Emulator -or $e) {
    $ctx = Get-FileContext -WantedName "steam_api" -WantedExtension "dll"
    if ($ctx) {
        $apiCheck = Test-SteamApiFile -FilePath $ctx.FullPath
        if ($apiCheck.Valid) {
            Invoke-GoldbergEmulatorFork -FilePath $ctx.FullPath -ApiName $apiCheck.ApiName -ApiBits $apiCheck.ApiBits
        }
    }
    Read-Host "Press Enter to exit"
    exit
}

if ($ie) {
    $ctx = Get-FileContext -WantedName "steam_api" -WantedExtension "dll"
    if ($ctx) {
        $apiCheck = Test-SteamApiFile -FilePath $ctx.FullPath
        if ($apiCheck.Valid) {
            if (Get-SteamInterfaces -FilePath $ctx.FullPath) {
                Invoke-GoldbergEmulatorFork -FilePath $ctx.FullPath -ApiName $apiCheck.ApiName -ApiBits $apiCheck.ApiBits
            }
        }
    }
    Read-Host "Press Enter to exit"
    exit
}

if ($InputFile) {
    $FilePath = $InputFile[0]
    if (Test-Path $FilePath) {
        $name = [System.IO.Path]::GetFileName($FilePath)
        
        if ($name -eq "achievements.json") {
            Write-Host "Achievement JSON dropped. Validating..."
            try {
                $json = Get-Content $FilePath | ConvertFrom-Json
                Write-Host "JSON is valid with $($json.Count) achievements." -ForegroundColor Green
            } catch {
                Write-Host "Invalid JSON syntax." -ForegroundColor Red
            }
            Read-Host "Press Enter to exit"
            exit
        } elseif ($name -match "steam_api") {
            $apiCheck = Test-SteamApiFile -FilePath $FilePath
            if ($apiCheck.Valid) {
                if (Get-SteamInterfaces -FilePath $FilePath) {
                    Invoke-GoldbergEmulatorFork -FilePath $FilePath -ApiName $apiCheck.ApiName -ApiBits $apiCheck.ApiBits
                }
            }
            Read-Host "Press Enter to exit"
            exit
        }
    }
}

while ($true) {
    Show-Banner
    $searchQuery = Show-SearchInput
    
    if (-not $searchQuery) { break }
    if (Search-Game -Query $searchQuery) {
        if (Confirm-Game) {
            Get-Dlcs
            Get-UserConfigs
            Get-Achievements
            Process-SteamApiInteractive
            
            Write-Host "`n`nPress any key to return to search . . ." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
}

Write-Host "Exiting..."
