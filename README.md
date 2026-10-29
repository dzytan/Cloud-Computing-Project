# Cloud-Computing-Project

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
│   ├── main.py                   # Endpoint /health, /ready, /load, /version, /fail-health
│   ├── requirements.txt
│   └── Dockerfile
│
├── k8s/                          # Manifest Kubernetes / Helm chart
│   ├── kind-config.yaml          # Cụm kind: 1 control-plane + 2 worker, extraPortMappings cho Ingress
│   ├── base/
│   │   ├── deployment.yaml       # Deployment: replica, probe, resource request/limit
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── secret.yaml           # CHỈ chứa giá trị giả (CHANGE_ME) — không commit secret thật
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
│   ├── collect-metrics.py        # Script xuất dữ liệu đo thô (CSV/JSON)
│   └── plot-results.py           # Script tạo lại bảng, biểu đồ từ dữ liệu thô trong data/results/
│
├── data/
│   └── results/                  # Dữ liệu đo thô (availability, p95 latency, rollout time...)
│
├── docs/
│   ├── architecture/              # Sơ đồ kiến trúc cụm + luồng request (ảnh hoặc .drawio)
│   │   └── cluster-architecture.png
│   ├── reports/                  # Báo cáo kỹ thuật đồ án
│   ├── results/                  # Ảnh chụp dashboard, video demo (không chứa secret/thông tin nội bộ)
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
git clone https://github.com/dzytan/Cloud-Computing-Project.git
cd Cloud-Computing-Project
```

**1. Dựng cụm Kubernetes cục bộ** (chọn một trong các công cụ)

```bash
# kind — dùng kind-config.yaml để có 1 control-plane + 2 worker
# (cần tối thiểu 2 worker cho thí nghiệm drain node, xem k8s/kind-config.yaml)
kind create cluster --name selfhealing-demo --config k8s/kind-config.yaml

# hoặc k3d (thêm --agents 2 để có 2 worker)
k3d cluster create selfhealing-demo --agents 2

# hoặc minikube (thêm --nodes 3)
minikube start --nodes 3
```

**2. Cài Metrics Server và Ingress Controller** (bắt buộc trước khi apply `k8s/base/`, vì `hpa.yaml` cần Metrics Server và `ingress.yaml` cần Ingress Controller mới hoạt động)

```bash
# Metrics Server — kind cần thêm cờ TLS vì kubelet không có cert hợp lệ
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Ingress Controller (bản cài riêng cho kind)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=120s
```

**3. Build và nạp image ứng dụng vào cụm**

```bash
cd app
docker build -t selfhealing-demo:v1 .
kind load docker-image selfhealing-demo:v1 --name selfhealing-demo
cd ..
```

**4. Triển khai ứng dụng lên Kubernetes**

```bash
kubectl apply -f k8s/base/
kubectl get pods -w
```

**5. Kiểm tra ứng dụng chạy local**

```bash
kubectl port-forward svc/selfhealing-demo-svc 8080:80
```

Mở `http://localhost:8080`, thử thêm `/version` (xem version đang chạy) và `/fail-health` (bật cờ lỗi để probe đánh rớt pod, dùng cho thí nghiệm self-healing).

> Kỳ vọng sau khi áp dụng đủ `k8s/base/` (probe + HPA + PDB): pod lỗi tự được khởi động lại, hệ thống tự co giãn khi tải tăng.
> Chỉ ghi khẳng định này là **kết quả** trong báo cáo sau khi đã chạy thí nghiệm thật và có số liệu/log trong `docs/results` — ở README đây là hành vi kỳ vọng, chưa phải kết quả đã kiểm chứng.

**6. Chạy các kịch bản thử nghiệm**

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

**7. Dọn tài nguyên sau khi demo**

```bash
kind delete cluster --name selfhealing-demo
```

## Chi phí

Toàn bộ demo chạy trên cụm Kubernetes cục bộ (kind/k3d/minikube) trên máy cá nhân, **không phát
sinh chi phí cloud**. Nếu nhóm triển khai thêm bản so sánh trên dịch vụ cloud thật (tùy chọn,
ngoài phạm vi bắt buộc của đề), cần ghi ngân sách dự kiến và dọn tài nguyên ngay sau khi đo xong.

## Công nghệ sử dụng

| Thành phần | Công nghệ | Phiên bản (ghi lại khi build bản nghiệm thu) |
|:---|:---|:---|
| Cụm Kubernetes | kind / k3d / minikube | `kind version` / `k3d version` / `minikube version` |
| Kubernetes | — | `kubectl version` |
| Đóng gói triển khai | Helm (tùy chọn) | `helm version` |
| Ingress | Nginx Ingress Controller | ghi version manifest đã apply |
| Autoscaling | Horizontal Pod Autoscaler + Metrics Server | ghi version manifest đã apply |
| Giám sát | Prometheus, Grafana | theo chart/version cài đặt |
| Tạo tải | k6 | `k6 version` |
| Giả lập lỗi (tùy chọn) | Chaos Mesh | theo chart/version cài đặt |

> Chạy các lệnh version ở trên sau khi dựng môi trường final và dán kết quả vào đây hoặc vào báo cáo — đề bài yêu cầu kho sản phẩm có "danh sách phiên bản công nghệ".

## Rủi ro bảo mật còn lại

- `docker.sock`/quyền root trong container: image demo nên chạy bằng non-root user nếu có thời gian, hiện chưa bắt buộc trong phạm vi đồ án.
- Ingress và Grafana trong demo chạy HTTP/port-forward thuần, chưa có TLS/auth — chỉ dùng trong môi trường lab cục bộ, không expose ra ngoài.
- Image chưa được quét lỗ hổng (SCA/SBOM) — ngoài phạm vi bắt buộc của đề tài 26, ghi nhận là giới hạn còn lại trong báo cáo.
- `secret.yaml` chỉ chứa giá trị giả; nếu quên thay `CHANGE_ME` bằng secret thật qua `kubectl create secret` trước khi demo, ứng dụng sẽ không chạy đúng (không phải rủi ro bảo mật, nhưng cần lưu ý khi vận hành).

## Lưu ý bảo mật

`k8s/base/secret.yaml` trong repo **chỉ chứa giá trị giả** (ví dụ `CHANGE_ME`) để tham khảo
cấu trúc — không commit secret thật lên Git. Secret thật tạo trực tiếp trên máy/cụm trước khi
demo, ví dụ:

```bash
kubectl create secret generic selfhealing-demo-secret \
  --from-literal=API_KEY=<giá-trị-thật> \
  --dry-run=client -o yaml | kubectl apply -f -
```

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
| Hạ tầng & Triển khai | Trần Duy Tân | Cụm K8s, manifest/Helm chart, probe, resource limit, PDB |
| Ứng dụng & Tự động hóa | Trần Hồng Sơn | Container image, HPA, script tạo tải, kịch bản rollback |
| Kiểm thử, Quan sát & Báo cáo | Nguyễn Ngọc Sum | Dashboard Prometheus/Grafana, kịch bản kiểm thử, báo cáo, video demo |

---

<p align="center">Đồ án Điện Toán Đám Mây - Đề tài 26: Kubernetes tự phục hồi & cập nhật không gián đoạn<p>
