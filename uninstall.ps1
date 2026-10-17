<#
.SYNOPSIS
    local-embed uninstaller for Windows PowerShell.

.DESCRIPTION
    Uninstalls local-embed from uv tool install.
    User data (~\.local-embed\) is NOT removed — delete it manually if needed.

.EXAMPLE
    .\uninstall.ps1
#>

$ErrorActionPreference = "Continue"

function Write-Step($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Ok($msg)   { Write-Host "  $([char]0x2713) $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  $([char]0x2717) $msg" -ForegroundColor Red }
function Write-Dim($msg)  { Write-Host "  $msg" -ForegroundColor DarkGray }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }

Write-Host ""
Write-Host "local-embed Uninstaller" -ForegroundColor Cyan
Write-Host ""

# 1. Uninstall from uv tool
$installed = uv tool list 2>$null | Select-String "local-embed"
if ($installed) {
    Write-Step "Uninstalling local-embed..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $uninstallOutput = uv tool uninstall local-embed 2>&1
    $ok = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $prevEAP
    if ($ok) {
        Write-Ok "local-embed removed"
    } else {
        Write-Fail "uninstall failed"
        if ($uninstallOutput) {
            $uninstallOutput | Select-Object -Last 5 | ForEach-Object { Write-Dim "    $_" }
        }
    }
} else {
    Write-Dim "local-embed is not installed."
}

# 2. Clean up wrapper binaries
$localBin = "$env:USERPROFILE\.local\bin"
foreach ($bin in @("$localBin\local-embed.exe", "$localBin\local-embed.cmd")) {
    if (Test-Path $bin) {
        Remove-Item $bin -Force -ErrorAction SilentlyContinue
        Write-Dim "  Removed: $bin"
    }
}

# 3. Remaining data
Write-Host ""
$embedDir = "$env:USERPROFILE\.local-embed"
if (Test-Path $embedDir) {
    Write-Warn "Data files NOT removed (delete manually if desired):"
    Write-Dim "  ~\.local-embed\       — local_embed.yaml config"
} else {
    Write-Ok "No remaining data files."
}

Write-Host ""
Write-Dim "Model weights under ~\.cache\huggingface\hub are shared with other tools"
Write-Dim "and are never touched by this script."
Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
