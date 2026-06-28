$simulatorName = "Corona Simulator"
$launcher = "C:\Users\purec\Desktop\Pixel War\client\tools\run_solar2d.ps1"

$running = Get-Process -Name "Corona Simulator" -ErrorAction SilentlyContinue
if ($running) {
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 600
}

if (-not (Test-Path -LiteralPath $launcher)) {
    Write-Error "Launcher script not found at: $launcher"
    exit 1
}

powershell -ExecutionPolicy Bypass -File $launcher
