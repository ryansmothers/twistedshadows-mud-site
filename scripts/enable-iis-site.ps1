#Requires -RunAsAdministrator
<#
  Twisted Shadows IIS bring-up script
  Run in elevated PowerShell:
    powershell -ExecutionPolicy Bypass -File C:\Users\Ryan\Source\Repos\twistedshadows-mud-site\scripts\enable-iis-site.ps1
#>
$ErrorActionPreference = "Stop"
$siteName = "TwistedShadows"
$sitePath = "C:\inetpub\wwwroot\TwistedShadows"
$hostHeader = "www.twistedshadows.com"

Write-Host "Ensuring IIS features..."
$features = @(
  "IIS-WebServerRole",
  "IIS-WebServer",
  "IIS-CommonHttpFeatures",
  "IIS-StaticContent",
  "IIS-DefaultDocument",
  "IIS-HttpErrors",
  "IIS-ApplicationDevelopment",
  "IIS-HealthAndDiagnostics",
  "IIS-HttpLogging",
  "IIS-Security",
  "IIS-RequestFiltering",
  "IIS-Performance",
  "IIS-HttpCompressionStatic",
  "IIS-WebServerManagementTools",
  "IIS-ManagementConsole"
)
foreach ($f in $features) {
  $state = (Get-WindowsOptionalFeature -Online -FeatureName $f).State
  if ($state -ne "Enabled") {
    Write-Host "  Enabling $f..."
    Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart | Out-Null
  }
}

Import-Module WebAdministration -ErrorAction Stop

if (-not (Test-Path "IIS:\Sites\$siteName")) {
  Write-Host "Creating site $siteName..."
  New-Website -Name $siteName -PhysicalPath $sitePath -Port 80 -HostHeader $hostHeader -Force | Out-Null
} else {
  Write-Host "Site exists. Ensuring bindings and path..."
  Set-ItemProperty "IIS:\Sites\$siteName" -Name physicalPath -Value $sitePath
}

# Ensure both host-header and catch-all HTTP bindings
$existing = Get-WebBinding -Name $siteName -Protocol http -ErrorAction SilentlyContinue
$needHost = $true
$needAny = $true
foreach ($b in $existing) {
  if ($b.bindingInformation -eq "*:80:$hostHeader") { $needHost = $false }
  if ($b.bindingInformation -eq "*:80:") { $needAny = $false }
}
if ($needHost) { New-WebBinding -Name $siteName -Protocol http -Port 80 -HostHeader $hostHeader }
if ($needAny) { New-WebBinding -Name $siteName -Protocol http -Port 80 -IPAddress "*" }

# Firewall
$fwRules = @(
  @{ Name = "IIS HTTP (TCP 80)"; Port = 80 },
  @{ Name = "IIS HTTPS (TCP 443)"; Port = 443 }
)
foreach ($r in $fwRules) {
  if (-not (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Allow -Protocol TCP -LocalPort $r.Port | Out-Null
    Write-Host "Created firewall rule: $($r.Name)"
  } else {
    Enable-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue
    Write-Host "Firewall rule present: $($r.Name)"
  }
}

Write-Host "Restarting IIS..."
iisreset

Start-Website -Name $siteName
Start-Sleep -Seconds 2

Write-Host "`nSite state:"
Get-Website -Name $siteName | Format-List Name, State, PhysicalPath
Get-WebBinding -Name $siteName | Format-Table protocol, bindingInformation -AutoSize

Write-Host "`nListening on 80/443:"
netstat -ano | findstr "LISTENING" | findstr ":80 :443"

Write-Host "`nLocal smoke test:"
try {
  $resp = Invoke-WebRequest -Uri "http://127.0.0.1/" -Headers @{ Host = $hostHeader } -UseBasicParsing -TimeoutSec 8
  Write-Host "OK $($resp.StatusCode) - content length $($resp.RawContentLength)"
} catch {
  Write-Host "FAILED: $($_.Exception.Message)"
}

Write-Host ''
Write-Host 'Next (router / DNS):'
Write-Host '1. Router port-forward external TCP 80 (and 443 if HTTPS) to this PC LAN IP (see ipconfig)'
Write-Host '2. GoDaddy A record for www and the apex domain should point to your public IP'
Write-Host '3. Test from phone/cellular: http://www.twistedshadows.com/'
