[README.md](https://github.com/user-attachments/files/34114348/README.md)
# Cloud-Computing-Project# Cloud-Computing-Project

**Đề tài 26:** Triển khai ứng dụng trên Kubernetes với tự phục hồi, co giãn và cập nhật không gián đoạn
(Deploying a self-healing, auto-scaling, zero-downtime application on Kubernetes).

Demo **K8s-SelfHealing-Demo** minh họa: self-healing (liveness/readiness probe,
reconciliation loop), autoscaling (HPA), rolling update + rollback, và giám sát
bằng Prometheus/Grafana trên một cụm Kubernetes.

## Cấu trúc project

```text
Cloud-Computing-Project/
│
├── app/                          # Ứng dụng mẫu (API demo)
│   ├── main.py                   # Endpoint /health, /ready, /load (giả lập CPU)
│   ├── requirements.txt
│   └── Dockerfile
│
├── k8s/                          # Manifest Kubernetes / Helm chart
│   ├── base/
│   │   ├── deployment.yaml       # Deployment: replica, probe, resource request/limit
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── secret.yaml
│   │   ├── ingress.yaml
│   │   ├── hpa.yaml              # HorizontalPodAutoscaler
│   │   └── pdb.yaml              # PodDisruptionBudget
│   └── helm-chart/               # (tùy chọn nếu đóng gói bằng Helm)
│
├── monitoring/
│   ├── prometheus/
│   │   └── prometheus-values.yaml
│   └── grafana/
│       └── dashboards/
│           └── selfhealing-dashboard.json
│
├── load-test/
│   └── k6-script.js              # Script tạo tải để kích hoạt HPA
│
├── scripts/
│   ├── chaos-pod-delete.sh       # Kịch bản xóa pod / drain node (quan sát self-healing)
│   ├── rollout-fail.sh           # Kịch bản phát hành bản lỗi + rollback
│   └── collect-metrics.py        # Script xuất dữ liệu đo (CSV/JSON)
│
├── data/
│   └── results/                  # Dữ liệu đo thô (availability, p95 latency, rollout time...)
│
├── docs/
│   ├── reports/                  # Báo cáo kỹ thuật đồ án
│   ├── results/                  # Ảnh chụp dashboard, video demo
│   ├── DEMO.md                   # Hướng dẫn demo từng bước (kịch bản bình thường + lỗi)
│   └── huong-dan-chay-tung-buoc.md  # Runbook CLI gõ lệnh từng bước
│
├── .gitignore
├── .gitattributes
└── README.md
```

## Run guide

**Clone project**

```bash
git clone https://github.com/<tên-nhóm>/Cloud-Computing-Project.git
cd Cloud-Computing-Project
```

**1. Dựng cụm Kubernetes cục bộ** (chọn một trong các công cụ)

```bash
# kind
kind create cluster --name selfhealing-demo

# hoặc k3d
k3d cluster create selfhealing-demo

# hoặc minikube
minikube start
```

**2. Build và nạp image ứng dụng vào cụm**

```bash
cd app
docker build -t selfhealing-demo:v1 .
kind load docker-image selfhealing-demo:v1 --name selfhealing-demo
cd ..
```

**3. Triển khai ứng dụng lên Kubernetes**

```bash
kubectl apply -f k8s/base/
kubectl get pods -w
```

**4. Kiểm tra ứng dụng chạy local**

```bash
kubectl port-forward svc/selfhealing-demo-svc 8080:80
```

Mở `http://localhost:8080`

> Trạng thái **⚠️ chưa cấu hình HPA/probe** sẽ không tự phục hồi khi pod lỗi.<br>
> Sau khi áp dụng đủ `k8s/base/` (probe + HPA + PDB), hệ thống sẽ tự khởi động lại pod lỗi và tự co giãn khi tải tăng.

**5. Chạy các kịch bản thử nghiệm**

```bash
# Tạo tải để kiểm tra HPA
k6 run load-test/k6-script.js

# Giả lập lỗi pod / self-healing
bash scripts/chaos-pod-delete.sh

# Phát hành bản lỗi và rollback
bash scripts/rollout-fail.sh
kubectl rollout status deployment/selfhealing-demo
kubectl rollout undo deployment/selfhealing-demo
```

## Công nghệ sử dụng

| Thành phần | Công nghệ |
|:---|:---|
| Cụm Kubernetes | kind / k3d / minikube |
| Đóng gói triển khai | Helm (tùy chọn) |
| Ingress | Nginx Ingress Controller |
| Autoscaling | Horizontal Pod Autoscaler + Metrics Server |
| Giám sát | Prometheus, Grafana |
| Tạo tải | k6 |
| Giả lập lỗi (tùy chọn) | Chaos Mesh |

## Tài liệu

| File | Nội dung | Ghi chú |
|:---|:---|:---|
| [`docs/reports`](docs/reports) | Báo cáo kỹ thuật đồ án Điện Toán Đám Mây (đề tài 26) | Final report |
| [`docs/results`](docs/results) | Ảnh chụp dashboard, kết quả đo, số liệu kiểm thử | Giải thích chi tiết trong báo cáo |
| [`docs/DEMO.md`](docs/DEMO.md) | Hướng dẫn demo từng bước: triển khai, self-healing, rollout, rollback, HPA | Luồng bình thường + ít nhất 1 tình huống lỗi |
| [`docs/huong-dan-chay-tung-buoc.md`](docs/huong-dan-chay-tung-buoc.md) | Runbook CLI — gõ từng lệnh `kubectl`/`helm`/`k6`, ghi rõ thao tác và kết quả mong đợi | Setup trước khi demo |

> Nên đọc trước 2 file trên để hiểu cách triển khai và chạy demo.

## Phân công nhóm

| Vai trò | Thành viên | Phụ trách chính |
|:---|:---|:---|
| Hạ tầng & Triển khai | Sinh viên 1 | Cụm K8s, manifest/Helm chart, probe, resource limit, PDB |
| Ứng dụng & Tự động hóa | Sinh viên 2 | Container image, HPA, script tạo tải, kịch bản rollback |
| Kiểm thử, Quan sát & Báo cáo | Sinh viên 3 | Dashboard Prometheus/Grafana, kịch bản kiểm thử, báo cáo, video demo |

---

<p align="center">Đồ án Điện Toán Đám Mây - Đề tài 26: Kubernetes tự phục hồi & cập nhật không gián đoạn<p>
