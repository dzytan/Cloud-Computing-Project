# Xoa cum Kind va don dep
$ErrorActionPreference = "SilentlyContinue"
Write-Host "Dang xoa cum kind..." -ForegroundColor Yellow
kind delete cluster --name selfhealing-demo
kind delete cluster --name selfhealing
Get-Process | Where-Object { $_.ProcessName -like "*kubectl*" } | Stop-Process -Force
Write-Host "Da xoa xong!" -ForegroundColor Green
