# ======================================================================
#  Setup cum Kubernetes + deploy ung dung + monitoring (chay 1 lan)
#  Cach dung:  .\scripts\setup.ps1
#  Yeu cau:    Docker Desktop dang chay, da cai kind / helm / k6
# ======================================================================

$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot\..

$CLUSTER = "selfhealing-demo"

Write-Host "`n[1/7] Tao cum Kind (1 control-plane + 2 worker)..." -ForegroundColor Cyan
$existing = kind get clusters 2>&1 | Out-String
if ($existing -match $CLUSTER) {
    Write-Host "  Cum $CLUSTER da ton tai, bo qua." -ForegroundColor DarkGray
} else {
    kind create cluster --name $CLUSTER --config k8s/kind-config.yaml
    if ($LASTEXITCODE -ne 0) { Write-Host "  LOI: Khong tao duoc cum!" -ForegroundColor Red; exit 1 }
}

Write-Host "`n[2/7] Cai Ingress Nginx Controller..." -ForegroundColor Cyan
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/kind/deploy.yaml 2>$null
Write-Host "  Dang doi Ingress Controller san sang..."
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s

Write-Host "`n[3/7] Cai Metrics Server (de HPA doc CPU)..." -ForegroundColor Cyan
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml 2>$null
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]' 2>$null

Write-Host "`n[4/7] Cai Prometheus va Grafana..." -ForegroundColor Cyan
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>$null
helm repo update 2>$null
$helmList = helm list -n monitoring 2>&1 | Out-String
if ($helmList -match "monitoring") {
    Write-Host "  Prometheus stack da cai, bo qua." -ForegroundColor DarkGray
} else {
    helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f monitoring/prometheus-values.yaml
}

Write-Host "`n[5/7] Build 3 Docker images (v1, v2, v2-bad)..." -ForegroundColor Cyan
Push-Location app
docker build -t selfhealing-demo:v1 . 2>$null
docker build -t selfhealing-demo:v2 --build-arg APP_VERSION=v2 . 2>$null
docker build -t selfhealing-demo:v2-bad --build-arg APP_VERSION=v2-bad --build-arg BROKEN=true . 2>$null
Pop-Location

Write-Host "`n[6/7] Nap images vao cum Kind..." -ForegroundColor Cyan
kind load docker-image selfhealing-demo:v1 --name $CLUSTER
kind load docker-image selfhealing-demo:v2 --name $CLUSTER
kind load docker-image selfhealing-demo:v2-bad --name $CLUSTER

Write-Host "`n[7/7] Deploy ung dung va monitoring..." -ForegroundColor Cyan
kubectl create secret generic selfhealing-demo-secret --from-literal=API_KEY=production-key --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/base/
kubectl apply -f monitoring/servicemonitor.yaml
kubectl rollout restart deployment/selfhealing-demo 2>$null

Write-Host "`n  Dang doi pods san sang..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=selfhealing-demo --timeout=120s

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host "  SETUP HOAN TAT!" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host ""
kubectl get pods -o wide
Write-Host ""
Write-Host "  Buoc tiep theo (Demo tren TV tai lop):" -ForegroundColor Yellow
Write-Host "    Chay Menu Dieu Khien 1 Phim Bam:  .\scripts\demo.ps1" -ForegroundColor White
Write-Host "    - Live Pod Traffic UI:            http://localhost/ui" -ForegroundColor White
Write-Host "    - Grafana (admin / admin):        http://localhost:3000" -ForegroundColor White
Write-Host ""
