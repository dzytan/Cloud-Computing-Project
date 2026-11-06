# ======================================================================
#  Setup cum Kubernetes + deploy ung dung + monitoring (chay 1 lan)
#  Cach dung:  .\scripts\setup.ps1
#  Yeu cau:    Docker Desktop dang chay, da cai kind / helm / k6
# ======================================================================

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

$CLUSTER = "selfhealing-demo"

Write-Host "`n[1/7] Tao cum Kind (1 control-plane + 2 worker)..." -ForegroundColor Cyan
if (kind get clusters 2>$null | Select-String $CLUSTER) {
    Write-Host "  Cum $CLUSTER da ton tai, bo qua." -ForegroundColor DarkGray
} else {
    kind create cluster --name $CLUSTER --config k8s/kind-config.yaml
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
if (helm list -n monitoring 2>$null | Select-String "monitoring") {
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

Write-Host "`n  Dang doi pods san sang..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=selfhealing-demo --timeout=120s

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host "  SETUP HOAN TAT!" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host ""
kubectl get pods -o wide
Write-Host ""
Write-Host "  Buoc tiep theo:" -ForegroundColor Yellow
Write-Host "    1. Mo Dashboard:  python dashboard/server.py" -ForegroundColor White
Write-Host "       Truy cap:     http://localhost:5000" -ForegroundColor White
Write-Host ""
Write-Host "    2. Mo Grafana:   kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80" -ForegroundColor White
Write-Host "       Truy cap:     http://localhost:3000  (admin / prom-operator)" -ForegroundColor White
Write-Host ""
