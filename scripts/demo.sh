#!/usr/bin/env bash
# ==============================================================================
#  MENU DIEU KHIEN DEMO TRUC QUAN TREN TV TAI LOP (DE TAI 26 - Linux/macOS/WSL)
#  Cach chay: bash scripts/demo.sh
# ==============================================================================
set -u
cd "$(dirname "$0")/.."

open_url() {
    local url="$1"
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1 &
    elif command -v open >/dev/null 2>&1; then
        open "$url" >/dev/null 2>&1 &
    elif command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -NoProfile -Command "Start-Process '$url'" >/dev/null 2>&1
    else
        echo "  -> Mo trinh duyet tai: $url"
    fi
}

start_port_forwards() {
    echo -e "\n[*] Dang mo cong ket noi Grafana (:3000) va Prometheus (:9090)..."
    pkill -f "kubectl port-forward -n monitoring" 2>/dev/null || true
    kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 >/dev/null 2>&1 &
    kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090 >/dev/null 2>&1 &
    sleep 2
    open_url "http://localhost/ui"
    open_url "http://localhost:3000"
    echo "[+] Live Pod Traffic UI : http://localhost/ui"
    echo "[+] Grafana (admin/admin): http://localhost:3000 (Import monitoring/selfhealing-dashboard.json)"
}

start_headlamp() {
    echo -e "\n[*] Dang trien khai Headlamp (Kubernetes Web UI)..."
    helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1 || true
    if ! helm list -n kube-system | grep -q headlamp; then
        helm upgrade --install headlamp headlamp/headlamp --namespace kube-system
    fi
    kubectl wait --namespace kube-system --for=condition=ready pod -l app.kubernetes.io/name=headlamp --timeout=90s
    kubectl create serviceaccount headlamp-admin -n kube-system 2>/dev/null || true
    kubectl create clusterrolebinding headlamp-admin --serviceaccount=kube-system:headlamp-admin --clusterrole=cluster-admin 2>/dev/null || true
    TOKEN=$(kubectl create token headlamp-admin -n kube-system)
    pkill -f "kubectl port-forward -n kube-system svc/headlamp" 2>/dev/null || true
    kubectl port-forward -n kube-system svc/headlamp 4466:80 >/dev/null 2>&1 &
    sleep 2
    open_url "http://localhost:4466"
    echo -e "\n[+] Token dang nhap Headlamp (:4466):\n$TOKEN\n"
}

while true; do
    clear
    echo "========================================================================"
    echo "   DE TAI 26 - BANG DIEU KHIEN DEMO KUBERNETES TREN TV LOP HOC"
    echo "========================================================================"
    kubectl get pods -l app=selfhealing-demo -o wide 2>/dev/null || true
    echo "------------------------------------------------------------------------"
    echo "  [0] Mo man hinh TV: Live App UI (:80/ui) + Grafana (:3000)"
    echo "  [H] Cai & Mo Headlamp K8s Web UI (:4466 + in Token)"
    echo "  [1] Ban tai nen k6 Steady (20 VUs + k6 Web Dashboard :5665)"
    echo "  [2] Self-healing: [A] Xoa Pod dot ngot  |  [B] Gay loi /fail-health"
    echo "  [3] Drain 1 Worker Node (kiem chung PDB minAvailable:1) & Uncordon"
    echo "  [4] Rollout & Rollback: [A] Len v2 (0 loi) | [B] Ban loi v2-bad + Undo | [C] Ve v1"
    echo "  [5] Ban tai dot bien HPA Spike (kich hoat Scale Up 2 -> 5+ Pods)"
    echo "  [6] Thu nghiem Cau hinh sai (k8s/experiments/) & Khoi phuc chuan"
    echo "  [7] Thu thap Metrics (JSON+CSV) & Xuat 5 Bieu do PNG"
    echo "  [Q] Thoat Menu"
    echo "========================================================================"
    read -rp "Chon phim chuc nang: " choice

    case "${choice^^}" in
        0)
            start_port_forwards
            read -rp "Bam ENTER de quay lai menu..."
            ;;
        H)
            start_headlamp
            read -rp "Bam ENTER de quay lai menu..."
            ;;
        1)
            echo "[*] Chay k6 steady load ngam (Web UI: http://localhost:5665)..."
            K6_WEB_DASHBOARD=true k6 run load-test/steady.js >/tmp/k6-steady.log 2>&1 &
            sleep 2
            open_url "http://localhost:5665"
            read -rp "k6 dang chay ngam. Bam ENTER de quay lai menu..."
            ;;
        2)
            read -rp "  Chon [A] Xoa Pod ngau nhien | [B] Goi /fail-health: " sub
            if [[ "${sub^^}" == "B" ]]; then
                curl -i -H "Host: selfhealing.local" http://localhost/fail-health
                echo -e "\n[INFO] Quan sat Headlamp/Grafana: Readiness cat tai ~6s, Liveness restart ~15s."
            else
                bash scripts/chaos-pod-delete.sh pod
            fi
            read -rp "Bam ENTER de quay lai menu..."
            ;;
        3)
            bash scripts/chaos-pod-delete.sh drain
            read -rp "Bam ENTER de quay lai menu..."
            ;;
        4)
            read -rp "  Chon [A] Rollout v2 | [B] Rollout v2-bad + Rollback | [C] Dua ve v1: " sub
            case "${sub^^}" in
                A)
                    kubectl set image deployment/selfhealing-demo app=selfhealing-demo:v2
                    kubectl rollout status deployment/selfhealing-demo --timeout=60s
                    ;;
                B)
                    bash scripts/rollout-fail.sh
                    ;;
                *)
                    kubectl set image deployment/selfhealing-demo app=selfhealing-demo:v1
                    kubectl rollout status deployment/selfhealing-demo --timeout=60s
                    ;;
            esac
            read -rp "Bam ENTER de quay lai menu..."
            ;;
        5)
            echo "[*] Dang ban tai dot bien HPA Spike (Web UI: http://localhost:5666)..."
            K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_PORT=5666 k6 run load-test/hpa-spike.js
            read -rp "Bam ENTER de quay lai menu..."
            ;;
        6)
            echo "  [1] bad-liveness.yaml | [2] low-memory-limit.yaml | [3] missing-readiness.yaml | [R] Khoi phuc"
            read -rp "  Chon: " exp
            case "${exp^^}" in
                1) kubectl apply -f k8s/experiments/bad-liveness.yaml ;;
                2) kubectl apply -f k8s/experiments/low-memory-limit.yaml ;;
                3) kubectl apply -f k8s/experiments/missing-readiness.yaml ;;
                R) kubectl apply -f k8s/base/deployment.yaml && kubectl rollout status deployment/selfhealing-demo --timeout=90s ;;
            esac
            read -rp "Bam ENTER de quay lai menu..."
            ;;
        7)
            read -rp "  Nhap ten kich ban (vd: baseline, delete-pod, drain-node, rollout-v2, hpa-spike): " sc
            if [[ -n "$sc" ]]; then
                python3 scripts/collect-metrics.py --scenario "$sc" --output "data/results/${sc}.json"
                python3 scripts/plot-results.py
            fi
            read -rp "Bam ENTER de quay lai menu..."
            ;;
        Q)
            exit 0
            ;;
    esac
done
