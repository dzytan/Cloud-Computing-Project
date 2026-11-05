# PowerShell script don dep tai nguyen tren Windows
$ErrorActionPreference = "SilentlyContinue"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " [CLEANUP] Bat dau don dep tai nguyen..." -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Dung tien trinh kubectl port-forward
Write-Host "[1/2] Dang kiem tra va dung cac tien trinh port-forward..." -ForegroundColor Yellow
Get-Process | Where-Object { $_.ProcessName -like "*kubectl*" } | Stop-Process -Force

# 2. Xoa cum kind
$clusterName = "selfhealing-demo"
Write-Host "[2/2] Dang xoa cum kind '$clusterName'..." -ForegroundColor Yellow
if (Get-Command kind -ErrorAction SilentlyContinue) {
    kind delete cluster --name $clusterName
    Write-Host "[+] Da xoa cum kind thanh cong!" -ForegroundColor Green
} else {
    Write-Host "[!] Khong tim thay lenh kind trong PATH." -ForegroundColor DarkGray
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " [CLEANUP] Hoan tat don dep!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
