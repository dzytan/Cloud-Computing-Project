# Cloud-Computing-Project

**Đề tài 26:** Triển khai ứng dụng trên Kubernetes với tự phục hồi, co giãn và cập nhật không gián đoạn.

Demo minh họa self-healing (liveness/readiness/startup probe), autoscaling (HPA), rolling update + rollback,
PodDisruptionBudget và lưu trữ bền vững (PVC), giám sát bằng Prometheus/Grafana trên cụm Kubernetes cục bộ.

**Câu hỏi nghiên cứu:** Các controller và health probe của Kubernetes phối hợp như thế nào để duy trì trạng thái
mong muốn khi pod lỗi, tải tăng hoặc phiên bản mới gặp sự cố?

## Kiến trúc Hệ thống

### 1. Sơ đồ Kiến trúc Đa tầng (Multi-layer Architecture)

```mermaid
flowchart TB
    subgraph UserLayer["Tầng Người dùng & Kiểm thử"]
        User["Người dùng thực tế"]
        K6["k6 Load Generator<br/>(steady.js / hpa-spike.js)"]
    end

    subgraph NetworkLayer["Tầng Mạng & Cân bằng tải"]
        Ingress["Nginx Ingress Controller<br/>(Host: selfhealing.local)"]
        SVC["Kubernetes Service (ClusterIP)<br/>selfhealing-demo-svc:80"]
    end

    subgraph ComputeLayer["Tầng Tính toán (Worker Nodes Pods)"]
        subgraph Pod1["Pod Replica 1 (Node Worker 1)"]
            App1["FastAPI Container (non-root)<br/>Startup / Liveness / Readiness Probes"]
        end
        subgraph Pod2["Pod Replica 2 (Node Worker 2)"]
            App2["FastAPI Container (non-root)<br/>Startup / Liveness / Readiness Probes"]
        end
        HPA["Horizontal Pod Autoscaler (HPA)<br/>Scale: 2 - 10 replicas (CPU 50%)"]
        PDB["PodDisruptionBudget (PDB)<br/>minAvailable: 1"]
    end

    subgraph ConfigStorageLayer["Tầng Cấu hình & Dữ liệu"]
        CM["ConfigMap"]
        SEC["Secret (Opaque)"]
        PVC["PersistentVolumeClaim (PVC)"]
        StorageDemo["Storage Demo Pod<br/>(Kiểm chứng dữ liệu bền vững)"]
    end

    subgraph ObservabilityLayer["Tầng Giám sát & Quan sát (Observability)"]
        SM["ServiceMonitor"]
        Prom["Prometheus Server<br/>(Scrape /metrics mỗi 10s)"]
        Graf["Grafana Dashboard<br/>(selfhealing-dashboard.json)"]
    end

    User --> Ingress
    K6 --> Ingress
    Ingress --> SVC
    SVC --> App1
    SVC --> App2
    HPA -. Auto Scale .-> ComputeLayer
    PDB -. Protect .-> ComputeLayer
    CM -. envFrom .-> App1 & App2
    SEC -. envFrom .-> App1 & App2
    PVC --- StorageDemo
    App1 & App2 -. metrics .-> SM --> Prom --> Graf
```

### 2. Sơ đồ Luồng Tự phục hồi & Điều phối (Reconciliation Loop)

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Quản trị viên / Chaos Script
    participant K8s as Kube-Controller-Manager
    participant Kubelet as Kubelet (Worker Node)
    participant Pod as Pod Container
    participant Ingress as Ingress / Service

    Dev->>Pod: Gây lỗi / Xóa Pod / Gọi /fail-health
    alt Liveness Probe Thất bại
        Kubelet->>Pod: HTTP GET /health (fails 3 lần)
        Kubelet->>Pod: Kill & Restart Container
        Kubelet-->>Ingress: Giữ Service Endpoint sau khi Ready
    else Xóa Pod Đột ngột
        Dev->>K8s: kubectl delete pod
        K8s->>K8s: Reconciliation loop: Actual (1) != Desired (2)
        K8s->>Kubelet: Tạo Pod mới ngay lập tức
        Kubelet->>Pod: Startup & Readiness Probe OK
        Kubelet->>Ingress: Cập nhật Endpoints -> Chuyển traffic
    end
```

## Cấu trúc project

```text
Cloud-Computing-Project/
├── app/                        # Ứng dụng mẫu
│   ├── main.py                 # /, /health, /ready, /load, /version, /metrics, /fail-health
│   ├── requirements.txt
│   └── Dockerfile              # multi-stage build, chạy non-root
├── k8s/
│   ├── kind-config.yaml        # 1 control-plane + 2 worker nodes
│   ├── secret.example.yaml     # chỉ giá trị giả (CHANGE_ME), nằm ngoài base/
│   ├── base/                   # deployment, service, configmap, ingress, hpa, pdb, pvc, storage-demo
│   └── experiments/            # cấu hình cố ý sai: liveness quá gắt, memory limit quá thấp, thiếu readiness
├── monitoring/
│   ├── prometheus-values.yaml  # values cho kube-prometheus-stack
│   ├── servicemonitor.yaml     # scrape /metrics của app
│   └── selfhealing-dashboard.json
├── load-test/
│   ├── steady.js               # tải nền ổn định 20 VUs (baseline, xóa pod, drain, rollout)
│   └── hpa-spike.js            # tải tăng đột biến CPU để kích hoạt HPA
├── scripts/
│   ├── chaos-pod-delete.sh     # xóa pod / drain node
│   ├── rollout-fail.sh         # phát hành bản lỗi + rollback
│   ├── collect-metrics.py      # xuất số liệu thô từ Prometheus
│   ├── plot-results.py         # vẽ biểu đồ từ data/results/
│   ├── cleanup.sh              # script dọn dẹp cụm (Linux/macOS)
│   └── cleanup.ps1             # script dọn dẹp cụm (Windows PowerShell)
├── data/results/               # số liệu đo thô dạng JSON và CSV
│   ├── baseline.json
│   ├── delete-pod.json
│   ├── fail-health.json
│   ├── drain-node.json
│   ├── rollout-v2.json
│   ├── rollout-fail.json
│   ├── hpa-spike.json
│   └── summary_metrics.csv
├── docs/
│   ├── test-plan.md            # bảng kiểm thử + tiêu chí đạt chuẩn khoa học
│   ├── finops-cost-analysis.md # báo cáo FinOps & tối ưu chi phí Cloud theo Chương 5
│   ├── demo-script.md          # kịch bản phân vai quay video demo 10 phút
│   ├── reports/                # báo cáo đồ án (Word docx)
│   └── results/                # 5 ảnh biểu đồ kết quả (latency, error, avail, restarts, replicas)
└── README.md
```

## Run guide

**Yêu cầu:** Docker, `kubectl`, `kind`, `helm`, `k6`, Python 3.10+. Máy nên có tối thiểu 4 CPU / 8 GB RAM.

**1. Dựng cụm**

```bash
git clone https://github.com/dzytan/Cloud-Computing-Project.git
cd Cloud-Computing-Project
kind create cluster --name selfhealing-demo --config k8s/kind-config.yaml
```

`kind-config.yaml` cần label `ingress-ready=true` trên control-plane và `extraPortMappings` 80/443,
nếu không Ingress sẽ không lên. Dùng k3d/minikube được nhưng phải có ít nhất 2 worker để thử drain node.

**2. Cài Metrics Server và Ingress** (ghim phiên bản, không dùng `latest`/`main`)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=120s
```

**3. Cài Prometheus/Grafana**

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f monitoring/prometheus-values.yaml
```

**4. Build 3 image và nạp vào cụm** (`v1`, `v2` tốt, `v2-bad` cố ý lỗi để thử rollback)

```bash
cd app
docker build -t selfhealing-demo:v1 .
docker build -t selfhealing-demo:v2 --build-arg APP_VERSION=v2 .
docker build -t selfhealing-demo:v2-bad --build-arg APP_VERSION=v2-bad --build-arg BROKEN=true .
cd ..
for t in v1 v2 v2-bad; do kind load docker-image selfhealing-demo:$t --name selfhealing-demo; done
```

**5. Tạo Secret thật rồi mới apply manifest**

```bash
kubectl create secret generic selfhealing-demo-secret \
  --from-literal=API_KEY=<giá-trị-thật> --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f k8s/base/
kubectl apply -f monitoring/servicemonitor.yaml
kubectl get pods -o wide        # các replica phải nằm ở các node khác nhau
```

**6. Kiểm tra qua Ingress**

```bash
curl -H "Host: selfhealing.local" http://localhost/version
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80    # Grafana
```

**7. Dọn dẹp**

```bash
kind delete cluster --name selfhealing-demo
```

> Các hành vi nêu trong README là **kỳ vọng**. Chỉ ghi là kết quả trong báo cáo sau khi đã chạy thật
> và có số liệu/log trong `data/results` và `docs/results`.

## Kịch bản thử nghiệm

Mỗi kịch bản chạy **cùng lúc với tải nền k6** (`steady.js`), lặp **3 lần** và lấy trung bình.

| # | Kịch bản | Cách thực hiện | Quan sát |
|:--|:---|:---|:---|
| 1 | Baseline | Không can thiệp | availability, p95 làm mốc |
| 2 | Xóa pod | `bash scripts/chaos-pod-delete.sh pod` | thời gian về đủ replica, số lỗi |
| 3 | Lỗi health endpoint | gọi `/fail-health` | restart count, thời gian phục hồi |
| 4 | Drain node | `bash scripts/chaos-pod-delete.sh drain` | PDB có giữ pod Ready, downtime |
| 5 | Rollout bản tốt | `kubectl set image ... selfhealing-demo:v2` | thời gian rollout, lỗi khi cập nhật |
| 6 | Rollout bản lỗi + rollback | `bash scripts/rollout-fail.sh` | bản lỗi không nhận traffic, thời gian rollback |
| 7 | Autoscaling | `k6 run load-test/hpa-spike.js` | thời gian scale up, scale down |

**Thử nghiệm bổ sung**

- **Cấu hình sai** (`k8s/experiments/`): apply từng file, ghi triệu chứng, lệnh chẩn đoán và ảnh hưởng đến dashboard.
- **Storage:** xóa pod `storage-demo` rồi kiểm tra file ghi trên PVC còn nguyên.

Rolling update dùng `maxSurge: 1`, `maxUnavailable: 0` nên pod mới phải Ready thì pod cũ mới bị gỡ.
Deployment dùng `topologySpreadConstraints` để các replica không rơi cùng một node.

## Tiêu chí đạt

Ngưỡng dưới đây là đề xuất, nhóm chốt lại trong [`docs/test-plan.md`](docs/test-plan.md) **trước khi đo**, sau khi có số liệu baseline.

| Kịch bản | Tiêu chí đạt (đề xuất) |
|:---|:---|
| Xóa pod | availability ≥ 99%, về đủ replica < 30 s |
| Lỗi health endpoint | container tự restart, restart count tăng |
| Drain node | luôn còn ≥ 1 pod Ready, availability ≥ 99% |
| Rollout bản tốt | số lỗi ≈ 0 |
| Rollout bản lỗi | không request nào tới bản lỗi, rollback < 60 s |
| HPA | scale up < 3 phút, scale down sau cửa sổ stabilization |
| PVC | dữ liệu giữ nguyên sau khi xóa pod |

## Công nghệ

| Thành phần | Công nghệ | Phiên bản (ghi khi nghiệm thu) |
|:---|:---|:---|
| Cụm K8s | kind | `kind version`, `kubectl version` |
| Ingress | Nginx Ingress Controller | tag đã ghim ở trên |
| Autoscaling | HPA + Metrics Server | tag đã ghim ở trên |
| Giám sát | kube-prometheus-stack | `helm list -n monitoring` |
| Tạo tải | k6 | `k6 version` |

## Bảo mật

- `secret.example.yaml` chỉ chứa giá trị giả, không commit secret thật. Secret thật tạo bằng `kubectl create secret` trước khi apply.
- Container chạy non-root (`USER` trong Dockerfile, `securityContext.runAsNonRoot: true`).
- Giới hạn còn lại: Ingress/Grafana chạy HTTP, chưa có TLS/auth (chỉ dùng trong lab cục bộ); image chưa quét lỗ hổng;
  Secret mới chỉ mã hóa base64.

## Quản trị Chi phí (FinOps) & Rightsizing

- **Môi trường thử nghiệm:** Toàn bộ demo chạy trên cụm kind cục bộ, **không phát sinh chi phí cloud**.
- **Mô hình kinh tế đám mây (Public Cloud):** Nhóm đã thực hiện nghiên cứu chuyên sâu về **FinOps & Resource Rightsizing** theo đúng tinh thần **Chương 5 (Mục 5.8: Slide 96 - 102)**.
- Chi tiết bảng phân tích ước tính chi phí trên AWS EKS, chiến lược Spot Instances, Rightsizing CPU/RAM, Cost Allocation Tags và Unit Economics xem tại:
  👉 **[`docs/finops-cost-analysis.md`](docs/finops-cost-analysis.md)**

## Video Demo & Kịch bản Thuyết trình

- Thời lượng chuẩn: 10 phút (video) / 15-20 phút (vấn đáp trực tiếp).
- Kịch bản chi tiết từng phút, phân công rõ vai trò SV1, SV2, SV3 và danh mục lệnh checklist xem tại:
  👉 **[`docs/demo-script.md`](docs/demo-script.md)**
- 5 biểu đồ phân tích kết quả đo lường đã được tự động xuất bản tại:
  👉 **[`docs/results/`](docs/results/)**

## Phân công Nhóm

| Thành viên | Vai trò chính | Trách nhiệm trọng tâm |
|:---|:---|:---|
| **Trần Duy Tân** | SV1 - Kiến trúc, hạ tầng, IaC & triển khai | Cụm K8s đa node, manifest `base/`, probe, resource limit, PDB, PVC, `experiments/`, kịch bản drain |
| **Trần Hồng Sơn** | SV2 - Ứng dụng, dữ liệu, tích hợp & tự động hóa | FastAPI app + `/metrics`, Dockerfile multi-stage (3 image), HPA, `chaos-pod-delete.sh`, `rollout-fail.sh` |
| **Nguyễn Ngọc Sum** | SV3 - Kiểm thử, quan sát, đo lường & báo cáo | Grafana dashboard, k6 load test, `collect-metrics.py`, `plot-results.py`, `test-plan.md`, FinOps, video demo |

---

<p align="center">Đồ án Điện Toán Đám Mây - Đề tài 26: Kubernetes tự phục hồi và cập nhật không gián đoạn</p>
