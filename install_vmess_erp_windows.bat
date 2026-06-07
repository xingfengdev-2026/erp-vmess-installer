@echo off
setlocal EnableExtensions

set "PS1=%TEMP%\install_vmess_erp_%RANDOM%%RANDOM%.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $raw=Get-Content -LiteralPath '%~f0' -Raw; $marker='# POWERSHELL-BEGIN'; $pos=$raw.LastIndexOf($marker); if ($pos -lt 0) { throw 'PowerShell payload marker not found' }; $body=$raw.Substring($pos + $marker.Length).TrimStart(\"`r\", \"`n\"); Set-Content -LiteralPath '%PS1%' -Value $body -Encoding UTF8"
if errorlevel 1 exit /b 1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
del "%PS1%" >nul 2>&1
exit /b %RC%

# POWERSHELL-BEGIN
$ErrorActionPreference = 'Stop'

$Server = $env:ERP_SERVER_ADDR
$Token = $env:ERP_TOKEN
$Transport = $env:ERP_TRANSPORT
$RemotePort = $env:ERP_REMOTE_PORT
$XrayPort = $env:XRAY_LOCAL_PORT
$Uuid = $env:XRAY_UUID
$ClientId = $env:CLIENT_ID
$GithubProxyPrefix = $env:GITHUB_PROXY_PREFIX
$InstallRoot = $env:INSTALL_ROOT
$NoTasks = $false
$Interactive = $false
if ($env:INTERACTIVE -match '^(1|true|yes|y|on)$') {
  $Interactive = $true
}

function Show-Usage {
  @'
Usage:
  install_vmess_erp_windows.bat --remote-port PORT [options]

Required (unless using --interactive):
  --server ADDR            erp server control address as host:port.
  --remote-port PORT       Public TCP port opened on the erp server.

Options:
  --token TOKEN            erp shared token. Default: 19890604
  --transport NAME         erp transport. Default: raw
  --xray-port PORT         Local Xray VMess port. Default: 10086
  --uuid UUID              VMess UUID. Default: generated automatically
  --client-id ID           erp client id. Default: COMPUTERNAME
  --github-proxy-prefix URL
                           Optional GitHub download accelerator URL prefix.
                           Default: none (download from GitHub directly).
  --install-root PATH      Install root. Default: %ProgramData%\erp-vmess
  --no-tasks               Install files only; do not create or start scheduled tasks.
  --interactive            Prompt for the main parameters.
  -h, --help               Show this help.

Environment variables with the same names are also supported:
  ERP_SERVER_ADDR ERP_TOKEN ERP_TRANSPORT ERP_REMOTE_PORT XRAY_LOCAL_PORT
  XRAY_UUID CLIENT_ID GITHUB_PROXY_PREFIX INSTALL_ROOT INTERACTIVE

Example:
  install_vmess_erp_windows.bat --server example.com:6000 --remote-port 23456
  install_vmess_erp_windows.bat --interactive
'@
}

function Need-Value([string]$Name, [int]$Index, [object[]]$Values) {
  if ($Index + 1 -ge $Values.Count) {
    throw "$Name requires a value."
  }
}

$Arguments = @($args)
for ($i = 0; $i -lt $Arguments.Count; $i++) {
  $arg = [string]$Arguments[$i]
  switch -Regex ($arg) {
    '^(--remote-port|-RemotePort|/RemotePort)$' {
      Need-Value $arg $i $Arguments
      $i++
      $RemotePort = [string]$Arguments[$i]
      continue
    }
    '^--remote-port=(.+)$' {
      $RemotePort = $Matches[1]
      continue
    }
    '^(--server|-Server|/Server)$' {
      Need-Value $arg $i $Arguments
      $i++
      $Server = [string]$Arguments[$i]
      continue
    }
    '^--server=(.+)$' {
      $Server = $Matches[1]
      continue
    }
    '^(--token|-Token|/Token)$' {
      Need-Value $arg $i $Arguments
      $i++
      $Token = [string]$Arguments[$i]
      continue
    }
    '^--token=(.+)$' {
      $Token = $Matches[1]
      continue
    }
    '^(--transport|-Transport|/Transport)$' {
      Need-Value $arg $i $Arguments
      $i++
      $Transport = [string]$Arguments[$i]
      continue
    }
    '^--transport=(.+)$' {
      $Transport = $Matches[1]
      continue
    }
    '^(--xray-port|-XrayPort|/XrayPort)$' {
      Need-Value $arg $i $Arguments
      $i++
      $XrayPort = [string]$Arguments[$i]
      continue
    }
    '^--xray-port=(.+)$' {
      $XrayPort = $Matches[1]
      continue
    }
    '^(--uuid|-Uuid|/Uuid)$' {
      Need-Value $arg $i $Arguments
      $i++
      $Uuid = [string]$Arguments[$i]
      continue
    }
    '^--uuid=(.+)$' {
      $Uuid = $Matches[1]
      continue
    }
    '^(--client-id|-ClientId|/ClientId)$' {
      Need-Value $arg $i $Arguments
      $i++
      $ClientId = [string]$Arguments[$i]
      continue
    }
    '^--client-id=(.+)$' {
      $ClientId = $Matches[1]
      continue
    }
    '^(--github-proxy-prefix|-GithubProxyPrefix|/GithubProxyPrefix)$' {
      Need-Value $arg $i $Arguments
      $i++
      $GithubProxyPrefix = [string]$Arguments[$i]
      continue
    }
    '^--github-proxy-prefix=(.+)$' {
      $GithubProxyPrefix = $Matches[1]
      continue
    }
    '^(--install-root|-InstallRoot|/InstallRoot)$' {
      Need-Value $arg $i $Arguments
      $i++
      $InstallRoot = [string]$Arguments[$i]
      continue
    }
    '^--install-root=(.+)$' {
      $InstallRoot = $Matches[1]
      continue
    }
    '^(--no-tasks|-NoTasks|/NoTasks)$' {
      $NoTasks = $true
      continue
    }
    '^(--interactive|-Interactive|/Interactive)$' {
      $Interactive = $true
      continue
    }
    '^(-h|--help|/h|/\?)$' {
      Show-Usage
      exit 0
    }
    default {
      throw "Unknown argument: $arg"
    }
  }
}

function Write-Info([string]$Message) {
  Write-Host "[INFO] $Message"
}

function Assert-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this .bat as Administrator."
  }
}

function Is-Port([string]$Value) {
  $port = 0
  return ([int]::TryParse($Value, [ref]$port) -and $port -ge 1 -and $port -le 65535)
}

function Get-ControlPort([string]$Addr) {
  if ($Addr -match ':(\d+)$') {
    return [int]$Matches[1]
  }
  return $null
}

function Get-ServerHost([string]$Addr) {
  if ($Addr -match '^\[([^\]]+)\]:\d+$') {
    return $Matches[1]
  }
  if ($Addr -match '^(.+):\d+$') {
    return $Matches[1]
  }
  return $Addr
}

function Normalize-Defaults {
  if ([string]::IsNullOrWhiteSpace($Token)) { $script:Token = '19890604' }
  if ([string]::IsNullOrWhiteSpace($Transport)) { $script:Transport = 'raw' }
  if ([string]::IsNullOrWhiteSpace($XrayPort)) { $script:XrayPort = '10086' }
  if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $script:InstallRoot = Join-Path $env:ProgramData 'erp-vmess'
  }
  if ([string]::IsNullOrWhiteSpace($ClientId)) {
    $script:ClientId = $env:COMPUTERNAME
  }
  if ([string]::IsNullOrWhiteSpace($Uuid)) {
    $script:Uuid = [guid]::NewGuid().ToString()
  }
}

function Read-Value([string]$Label, [string]$DefaultValue) {
  if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
    return (Read-Host $Label)
  }

  $value = Read-Host "$Label [$DefaultValue]"
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $DefaultValue
  }
  return $value
}

function Prompt-InteractiveInputs {
  $remoteDefault = $RemotePort
  if ([string]::IsNullOrWhiteSpace($remoteDefault)) {
    $remoteDefault = '10086'
  }

  $script:Server = Read-Value 'erp server control address' $Server
  $script:Token = Read-Value 'erp token' $Token
  $script:Transport = Read-Value 'erp transport' $Transport
  $script:RemotePort = Read-Value 'erp server public remote port' $remoteDefault
  $script:XrayPort = Read-Value 'local Xray VMess port' $XrayPort
  $script:Uuid = Read-Value 'VMess UUID' $Uuid
  $script:ClientId = Read-Value 'erp client id' $ClientId
  $script:GithubProxyPrefix = Read-Value 'GitHub accelerator prefix' $GithubProxyPrefix
  $script:InstallRoot = Read-Value 'install root' $InstallRoot
}

function Validate-Inputs {
  if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "This installer only supports Windows."
  }

  if ([string]::IsNullOrWhiteSpace($Server)) {
    $script:Server = Read-Host 'Enter erp server control address (host:port)'
  }

  if ([string]::IsNullOrWhiteSpace($RemotePort)) {
    $script:RemotePort = Read-Host 'Enter erp server public remote port'
  }

  if (-not (Is-Port $RemotePort)) { throw "ERP remote port must be an integer from 1 to 65535." }
  if (-not (Is-Port $XrayPort)) { throw "Xray local port must be an integer from 1 to 65535." }
  if ([string]::IsNullOrWhiteSpace($Server)) { throw "erp server address must not be empty." }
  if ([string]::IsNullOrWhiteSpace($Token)) { throw "erp token must not be empty." }
  if ($Transport -ne 'raw') { throw "This script implements erp raw transport only." }

  $controlPort = Get-ControlPort $Server
  if ($null -ne $controlPort -and [int]$RemotePort -eq $controlPort) {
    throw "ERP remote port must not equal the erp control port $controlPort."
  }

  $parsedGuid = [guid]::Empty
  if (-not [guid]::TryParse($Uuid, [ref]$parsedGuid)) {
    throw "VMess UUID is not valid: $Uuid"
  }
}

function Get-ProxiedUrl([string]$Url) {
  if ([string]::IsNullOrWhiteSpace($GithubProxyPrefix)) {
    return $Url
  }
  return ($GithubProxyPrefix.TrimEnd('/') + '/' + $Url)
}

function Invoke-InstallerWebRequest([string]$Url, [string]$OutFile = '') {
  $headers = @{ 'User-Agent' = 'erp-vmess-windows-installer' }
  $proxied = Get-ProxiedUrl $Url
  if ([string]::IsNullOrWhiteSpace($OutFile)) {
    return Invoke-WebRequest -Uri $proxied -Headers $headers -UseBasicParsing -TimeoutSec 120
  }
  Invoke-WebRequest -Uri $proxied -Headers $headers -UseBasicParsing -TimeoutSec 120 -OutFile $OutFile
}

function Get-LatestAssetUrl([string]$Repo, [string]$AssetName) {
  # Use GitHub's stable "latest release" redirect instead of the JSON API.
  # The unauthenticated api.github.com endpoint is rate limited to 60 requests
  # per hour per IP; hitting that limit was the usual cause of the misleading
  # "Asset not found" error. This download URL is not subject to that limit.
  return "https://github.com/$Repo/releases/latest/download/$AssetName"
}

function Install-Xray([string]$TempDir, [string]$BinDir) {
  $assetName = 'Xray-windows-64.zip'
  $assetUrl = Get-LatestAssetUrl 'XTLS/Xray-core' $assetName
  $zipPath = Join-Path $TempDir $assetName
  $unpackDir = Join-Path $TempDir 'xray'

  Write-Info "Downloading Xray $assetName from latest release"
  Invoke-InstallerWebRequest $assetUrl $zipPath | Out-Null

  New-Item -ItemType Directory -Force -Path $unpackDir | Out-Null
  Expand-Archive -LiteralPath $zipPath -DestinationPath $unpackDir -Force

  $xraySource = Get-ChildItem -LiteralPath $unpackDir -Recurse -Filter 'xray.exe' | Select-Object -First 1
  if ($null -eq $xraySource) {
    throw 'Downloaded Xray archive does not contain xray.exe.'
  }

  Copy-Item -LiteralPath $xraySource.FullName -Destination (Join-Path $BinDir 'xray.exe') -Force
  foreach ($asset in @('geoip.dat', 'geosite.dat')) {
    $assetSource = Get-ChildItem -LiteralPath $unpackDir -Recurse -Filter $asset | Select-Object -First 1
    if ($null -ne $assetSource) {
      Copy-Item -LiteralPath $assetSource.FullName -Destination (Join-Path $BinDir $asset) -Force
    }
  }
}

function Install-Erp([string]$TempDir, [string]$BinDir) {
  $assetName = 'erp-x86_64-pc-windows-msvc.exe'
  $assetUrl = Get-LatestAssetUrl 'xingfengdev-2026/erp' $assetName
  $downloadPath = Join-Path $TempDir $assetName

  Write-Info "Downloading erp $assetName from latest release"
  Invoke-InstallerWebRequest $assetUrl $downloadPath | Out-Null

  Copy-Item -LiteralPath $downloadPath -Destination (Join-Path $BinDir 'erp.exe') -Force
}

function ConvertTo-TomlString([string]$Value) {
  return (($Value -replace '\\', '\\') -replace '"', '\"')
}

function Set-Utf8NoBomContent([string]$Path, [string]$Value) {
  $encoding = New-Object Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Write-XrayConfig([string]$ConfigPath) {
  Write-Info "Writing Xray config: $ConfigPath"
  $config = [ordered]@{
    log = [ordered]@{
      loglevel = 'warning'
    }
    inbounds = @(
      [ordered]@{
        tag = 'vmess-in'
        listen = '127.0.0.1'
        port = [int]$XrayPort
        protocol = 'vmess'
        settings = [ordered]@{
          clients = @(
            [ordered]@{
              id = $Uuid
              alterId = 0
            }
          )
        }
        streamSettings = [ordered]@{
          network = 'tcp'
          security = 'none'
        }
      }
    )
    outbounds = @(
      [ordered]@{
        tag = 'direct'
        protocol = 'freedom'
      }
    )
  }

  Set-Utf8NoBomContent $ConfigPath ($config | ConvertTo-Json -Depth 20)
}

function Write-ErpConfig([string]$ConfigPath) {
  Write-Info "Writing erp client config: $ConfigPath"
  $tokenEscaped = ConvertTo-TomlString $Token
  $serverEscaped = ConvertTo-TomlString $Server
  $clientEscaped = ConvertTo-TomlString $ClientId
  $content = @"
role = "client"
token = "$tokenEscaped"
transport = "$Transport"

[client]
server_addr = "$serverEscaped"
client_id = "$clientEscaped"

[[client.mappings]]
name = "vmess-tcp"
protocol = "tcp"
local_addr = "127.0.0.1:$XrayPort"
remote_port = $RemotePort
"@
  Set-Utf8NoBomContent $ConfigPath $content
}

function Write-LauncherScripts([string]$Root, [string]$BinDir, [string]$ConfigDir, [string]$LogDir) {
  $xrayExe = Join-Path $BinDir 'xray.exe'
  $erpExe = Join-Path $BinDir 'erp.exe'
  $xrayConfig = Join-Path $ConfigDir 'xray-config.json'
  $erpConfig = Join-Path $ConfigDir 'client.raw.toml'
  $xrayLog = Join-Path $LogDir 'xray.log'
  $erpLog = Join-Path $LogDir 'erp-client.log'
  $xrayStart = Join-Path $Root 'start-xray.ps1'
  $erpStart = Join-Path $Root 'start-erp-client.ps1'

  $xrayLauncher = @"
`$ErrorActionPreference = 'Continue'
`$env:XRAY_LOCATION_ASSET = '$BinDir'
while (`$true) {
  & '$xrayExe' run -config '$xrayConfig' *>> '$xrayLog'
  Start-Sleep -Seconds 3
}
"@
  Set-Utf8NoBomContent $xrayStart $xrayLauncher

  $erpLauncher = @"
`$ErrorActionPreference = 'Continue'
`$env:RUST_LOG = 'info'
`$env:ERP_NOFILE = '1048576'
while (`$true) {
  & '$erpExe' client --config '$erpConfig' *>> '$erpLog'
  Start-Sleep -Seconds 3
}
"@
  Set-Utf8NoBomContent $erpStart $erpLauncher

  return @{
    XrayStart = $xrayStart
    ErpStart = $erpStart
  }
}

function Reset-ScheduledTask([string]$Name, [string]$ScriptPath) {
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $taskRun = '"' + $ps + '" -NoProfile -ExecutionPolicy Bypass -File "' + $ScriptPath + '"'

  & schtasks.exe /End /TN $Name 2>$null | Out-Null
  & schtasks.exe /Delete /TN $Name /F 2>$null | Out-Null
  & schtasks.exe /Create /TN $Name /SC ONSTART /TR $taskRun /RU SYSTEM /RL HIGHEST /F | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to create scheduled task $Name."
  }

  & schtasks.exe /Run /TN $Name | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to start scheduled task $Name."
  }
}

function Write-Result([string]$ConfigDir, [string]$LogDir) {
  $serverHost = Get-ServerHost $Server
  $vmess = [ordered]@{
    v = '2'
    ps = "erp-vmess-$ClientId"
    add = $serverHost
    port = "$RemotePort"
    id = $Uuid
    aid = '0'
    scy = 'auto'
    net = 'tcp'
    type = 'none'
    host = ''
    path = ''
    tls = ''
    sni = ''
    alpn = ''
    fp = ''
  }
  $vmessJson = $vmess | ConvertTo-Json -Compress
  $vmessLink = 'vmess://' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($vmessJson))

  Write-Host ''
  Write-Host 'Installed.'
  Write-Host ''
  Write-Host "erp server:      $Server"
  Write-Host "erp remote port: $RemotePort"
  Write-Host "Xray local:      127.0.0.1:$XrayPort"
  Write-Host "VMess UUID:      $Uuid"
  Write-Host 'transport:       vmess + tcp + no TLS, erp raw'
  Write-Host "config dir:      $ConfigDir"
  Write-Host "log dir:         $LogDir"
  Write-Host ''
  Write-Host 'VMess link:'
  Write-Host $vmessLink
  Write-Host ''
  Write-Host 'VMess JSON:'
  Write-Host $vmessJson
  Write-Host ''
  Write-Host 'Useful commands:'
  Write-Host '  schtasks /Query /TN erp-vmess-xray /V /FO LIST'
  Write-Host '  schtasks /Query /TN erp-vmess-client /V /FO LIST'
  Write-Host '  schtasks /End /TN erp-vmess-xray'
  Write-Host '  schtasks /End /TN erp-vmess-client'
}

Normalize-Defaults
if ($Interactive) {
  Prompt-InteractiveInputs
}
Validate-Inputs

if ((-not $NoTasks) -or $InstallRoot.StartsWith($env:ProgramData, [StringComparison]::OrdinalIgnoreCase)) {
  Assert-Admin
}

if (-not [Environment]::Is64BitOperatingSystem) {
  throw 'This release-based installer requires 64-bit Windows.'
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BinDir = Join-Path $InstallRoot 'bin'
$ConfigDir = Join-Path $InstallRoot 'config'
$LogDir = Join-Path $InstallRoot 'logs'
New-Item -ItemType Directory -Force -Path $InstallRoot, $BinDir, $ConfigDir, $LogDir | Out-Null

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('erp-vmess-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
  Install-Xray $tempDir $BinDir
  Install-Erp $tempDir $BinDir

  $xrayConfig = Join-Path $ConfigDir 'xray-config.json'
  $erpConfig = Join-Path $ConfigDir 'client.raw.toml'
  Write-XrayConfig $xrayConfig
  Write-ErpConfig $erpConfig

  $xrayExe = Join-Path $BinDir 'xray.exe'
  $erpExe = Join-Path $BinDir 'erp.exe'

  & $xrayExe run -test -config $xrayConfig
  if ($LASTEXITCODE -ne 0) {
    throw 'Xray config test failed.'
  }

  & $erpExe --version | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'erp binary did not run.'
  }

  $launchers = Write-LauncherScripts $InstallRoot $BinDir $ConfigDir $LogDir

  if ($NoTasks) {
    Write-Warning 'Scheduled tasks were skipped by --no-tasks.'
    Write-Warning "Manual Xray command: powershell -NoProfile -ExecutionPolicy Bypass -File `"$($launchers.XrayStart)`""
    Write-Warning "Manual erp command: powershell -NoProfile -ExecutionPolicy Bypass -File `"$($launchers.ErpStart)`""
  } else {
    Write-Info 'Creating and starting scheduled tasks'
    Reset-ScheduledTask 'erp-vmess-xray' $launchers.XrayStart
    Reset-ScheduledTask 'erp-vmess-client' $launchers.ErpStart
  }

  Write-Result $ConfigDir $LogDir
}
finally {
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
