# Copy qnap-rtorrent-recovery to NAS Public share via SMB
$ErrorActionPreference = "Stop"
$NasIp = "192.168.1.2"
$Source = Join-Path $PSScriptRoot "."
$Dest = "\\${NasIp}\Public\qnap-rtorrent-recovery"

Write-Host "Copying recovery toolkit to $Dest ..."
if (-not (Test-Path "\\${NasIp}\Public")) {
    Write-Host "ERROR: Cannot reach \\${NasIp}\Public - map the NAS share first or edit NasIp in this script."
    exit 1
}

if (Test-Path $Dest) {
    Write-Host "Removing existing $Dest ..."
    Remove-Item -Recurse -Force $Dest
}

Copy-Item -Recurse -Force $Source $Dest
Write-Host "Done. SSH to NAS and run:"
Write-Host "  chmod +x /share/Public/qnap-rtorrent-recovery/*.sh /share/Public/qnap-rtorrent-recovery/scripts/*.sh"
Write-Host "  cd /share/Public/qnap-rtorrent-recovery && ./00-run-all.sh"
