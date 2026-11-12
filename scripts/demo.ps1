# ==============================================================================
#  MENU DIEU KHIEN DEMO TRUC QUAN TREN TV TAI LOP (DE TAI 26)
#  Cach chay: .\scripts\demo.ps1
# ==============================================================================

$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot\..

function Start-PortForwards {
    Write-Host "`n[*] Dang mo cong ket noi Grafana (:3000) va Prometheus (:9090)..." -ForegroundColor Cyan
    Start-Process powershell -WindowStyle Minimized -ArgumentList "-NoProfile -Command kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
    Start-Process powershell -WindowStyle Minimized -ArgumentList "-NoProfile -Command kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090"
    Start-Sleep -Seconds 2
    Start-Process "http://localhost/ui"
    Start-Process "http://localhost:3000"
    Write-Host "[+] Da mo trinh duyet:" -ForegroundColor Green
    Write-Host "    - Live Pod Traffic UI (Light Mode): http://localhost/ui"
    Write-Host "    - Grafana Dashboard (admin/admin) : http://localhost:3000 (Import monitoring/selfhealing-dashboard.json)"
}

function Start-Headlamp {
    Write-Host "`n[*] Dang trien khai Headlamp (Kubernetes Web UI) len cum..." -ForegroundColor Cyan
    helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ 2>$null
    helm repo update 2>$null
    $hl = helm list -n kube-system 2>&1 | Out-String
    if ($hl -notmatch "headlamp") {
        helm upgrade --install headlamp headlamp/headlamp --namespace kube-system
    }
    kubectl wait --namespace kube-system --for=condition=ready pod -l app.kubernetes.io/name=headlamp --timeout=90s
    kubectl create serviceaccount headlamp-admin -n kube-system 2>$null
    kubectl create clusterrolebinding headlamp-admin --serviceaccount=kube-system:headlamp-admin --clusterrole=cluster-admin 2>$null
    $token = kubectl create token headlamp-admin -n kube-system
    $token | Set-Clipboard
    Start-Process powershell -WindowStyle Minimized -ArgumentList "-NoProfile -Command kubectl port-forward -n kube-system svc/headlamp 4466:80"
    Start-Sleep -Seconds 2
    Start-Process "http://localhost:4466"
    Write-Host "[+] Token dang nhap Headlamp da duoc COPY san vao Clipboard (chi can Ctrl+V)!" -ForegroundColor Green
}

while ($true) {
    Clear-Host
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "   DE TAI 26 - BANG DIEU KHIEN DEMO KUBERNETES TREN TV LOP HOC" -ForegroundColor White
    Write-Host "========================================================================" -ForegroundColor Cyan
    kubectl get pods -l app=selfhealing-demo -o wide 2>$null
    Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [0] Mo man hinh TV: Live App UI (:80/ui) + Grafana (:3000)" -ForegroundColor Yellow
    Write-Host "  [H] Cai & Mo Headlamp K8s Web UI (:4466 - tu dong copy Token)" -ForegroundColor Yellow
    Write-Host "  [1] Ban tai nen k6 Steady (20 VUs + k6 Web Dashboard :5665)" -ForegroundColor Green
    Write-Host "  [2] Self-healing: [A] Xoa Pod dot ngot  |  [B] Gay loi /fail-health" -ForegroundColor Red
    Write-Host "  [3] Drain 1 Worker Node (kiem chung PDB minAvailable:1) & Uncordon" -ForegroundColor Magenta
    Write-Host "  [4] Rollout & Rollback: [A] Len v2 (0 loi) | [B] Ban loi v2-bad + Undo | [C] Ve v1" -ForegroundColor Blue
    Write-Host "  [5] Ban tai dot bien HPA Spike (kich hoat Scale Up 2 -> 5+ Pods)" -ForegroundColor Green
    Write-Host "  [6] Thu nghiem Cau hinh sai (k8s/experiments/) & Khoi phuc chuan" -ForegroundColor DarkYellow
    Write-Host "  [7] Thu thap Metrics (JSON+CSV) & Xuat 5 Bieu do PNG" -ForegroundColor Cyan
    Write-Host "  [Q] Thoat Menu" -ForegroundColor Gray
    Write-Host "========================================================================" -ForegroundColor Cyan

    $choice = Read-Host "Chon phim chuc nang"
    switch ($choice.ToUpper()) {
        "0" {
            Start-PortForwards
            Pause
        }
        "H" {
            Start-Headlamp
            Pause
        }
        "1" {
            Write-Host "`n[*] Dang khoi chay k6 Steady Load trong cua so rieng (Web UI: http://localhost:5665)..." -ForegroundColor Green
            Start-Process powershell -ArgumentList "-NoExit -Command `$env:K6_WEB_DASHBOARD='true'; k6 run load-test/steady.js"
            Start-Sleep -Seconds 2
            Start-Process "http://localhost:5665"
            Pause
        }
        "2" {
            $sub = Read-Host "  Chon [A] Xoa Pod ngau nhien | [B] Goi /fail-health lam hong Liveness Probe"
            if ($sub.ToUpper() -eq "B") {
                Write-Host "`n[ACTION] Goi /fail-health qua Ingress..." -ForegroundColor Yellow
                curl.exe -i -H "Host: selfhealing.local" http://localhost/fail-health
                Write-Host "`n[INFO] Quan sat Headlamp/Grafana: Readiness ngat tai sau ~6s, Kubelet restart container sau ~15s!" -ForegroundColor Cyan
            } else {
                $pod = kubectl get pods -l app=selfhealing-demo -o jsonpath="{.items[0].metadata.name}"
                Write-Host "`n[ACTION] Xoa dot ngot Pod: $pod" -ForegroundColor Red
                $t0 = Get-Date
                kubectl delete pod $pod --now
                kubectl wait --for=condition=ready pod -l app=selfhealing-demo --timeout=60s
                $dt = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
                Write-Host "[OK] ReplicaSet da bu Pod Ready moi sau $dt giay!" -ForegroundColor Green
            }
            Pause
        }
        "3" {
            $worker = kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}'
            Write-Host "`n[ACTION] Dang drain node: $worker (PDB minAvailable: 1 bao ve dich vu)..." -ForegroundColor Magenta
            kubectl drain $worker --ignore-daemonsets --delete-emptydir-data --force
            kubectl get pods -l app=selfhealing-demo -o wide
            Read-Host "`nBam ENTER de Uncordon dua node $worker tro lai cum"
            kubectl uncordon $worker
            Write-Host "[OK] Da uncordon $worker thanh cong!" -ForegroundColor Green
            Pause
        }
        "4" {
            $sub = Read-Host "  Chon [A] Rollout v2 (Zero-downtime) | [B] Rollout v2-bad + Rollback | [C] Dua ve v1"
            if ($sub.ToUpper() -eq "A") {
                Write-Host "`n[ACTION] Cap nhat image sang selfhealing-demo:v2 (maxSurge:1, maxUnavailable:0)..." -ForegroundColor Cyan
                kubectl set image deployment/selfhealing-demo app=selfhealing-demo:v2
                kubectl rollout status deployment/selfhealing-demo --timeout=60s
                Write-Host "[OK] Quan sat man hinh /ui: Mau Xanh (v1) da chuyen muot sang Mau Cam (v2) voi 0 loi!" -ForegroundColor Green
            } elseif ($sub.ToUpper() -eq "B") {
                Write-Host "`n[ACTION] Tung ban loi selfhealing-demo:v2-bad..." -ForegroundColor Red
                kubectl set image deployment/selfhealing-demo app=selfhealing-demo:v2-bad
                Write-Host "[WAIT] Cho 15s quan sat Readiness Probe chan Pod loi (man hinh /ui khong he bi loi)..." -ForegroundColor Yellow
                Start-Sleep -Seconds 15
                kubectl get pods -l app=selfhealing-demo -o wide
                Read-Host "`nBam ENTER de thuc hien Rollback (kubectl rollout undo)"
                $t0 = Get-Date
                kubectl rollout undo deployment/selfhealing-demo
                kubectl rollout status deployment/selfhealing-demo --timeout=60s
                $dt = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
                Write-Host "[OK] Rollback hoan tat sau $dt giay!" -ForegroundColor Green
            } else {
                kubectl set image deployment/selfhealing-demo app=selfhealing-demo:v1
                kubectl rollout status deployment/selfhealing-demo --timeout=60s
            }
            Pause
        }
        "5" {
            Write-Host "`n[ACTION] Khoi chay k6 HPA Spike Load trong cua so rieng..." -ForegroundColor Green
            Start-Process powershell -ArgumentList "-NoExit -Command `$env:K6_WEB_DASHBOARD='true'; `$env:K6_WEB_DASHBOARD_PORT='5666'; k6 run load-test/hpa-spike.js"
            Write-Host "[INFO] Quan sat Headlamp, Grafana va bang Pod tren /ui tu dong mo rong tu 2 len 5+ Pods!" -ForegroundColor Cyan
            kubectl get hpa selfhealing-demo-hpa
            Pause
        }
        "6" {
            Write-Host "  [1] bad-liveness.yaml (CrashLoopBackOff)"
            Write-Host "  [2] low-memory-limit.yaml (OOMKilled - Exit 137)"
            Write-Host "  [3] missing-readiness.yaml (Loi 502 khi pod moi khoi dong)"
            Write-Host "  [R] Khoi phuc cau hinh chuan (k8s/base/deployment.yaml)"
            $exp = Read-Host "  Chon cau hinh"
            switch ($exp.ToUpper()) {
                "1" { kubectl apply -f k8s/experiments/bad-liveness.yaml }
                "2" { kubectl apply -f k8s/experiments/low-memory-limit.yaml }
                "3" { kubectl apply -f k8s/experiments/missing-readiness.yaml }
                "R" {
                    kubectl apply -f k8s/base/deployment.yaml
                    kubectl rollout status deployment/selfhealing-demo --timeout=90s
                }
            }
            Pause
        }
        "7" {
            $sc = Read-Host "  Nhap ten kich ban can luu (vd: baseline, delete-pod, fail-health, drain-node, rollout-v2, rollout-fail, hpa-spike)"
            if ($sc) {
                python scripts/collect-metrics.py --scenario $sc --output "data/results/$sc.json"
                python scripts/plot-results.py
            }
            Pause
        }
        "Q" { break }
    }
}
