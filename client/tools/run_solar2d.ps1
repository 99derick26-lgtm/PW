$simulator = "C:\Program Files (x86)\Corona Labs\Corona\Corona Simulator.exe"
$project = "C:\Users\purec\Desktop\Pixel War\client"

if (-not (Test-Path -LiteralPath $simulator)) {
    Write-Error "Solar2D/Corona Simulator not found at: $simulator"
    exit 1
}

if (-not (Test-Path -LiteralPath $project)) {
    Write-Error "Project folder not found at: $project"
    exit 1
}

Start-Process -FilePath $simulator -ArgumentList $project
