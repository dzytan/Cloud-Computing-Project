# Phân tích Chi phí Cloud (FinOps)

Đề tài 26 – Triển khai ứng dụng trên Kubernetes với tự phục hồi, co giãn và cập nhật không gián đoạn.

## 1. Bối cảnh

Toàn bộ thực nghiệm chạy trên cụm kind cục bộ, không phát sinh chi phí cloud.
Phần này ước tính chi phí nếu đưa hệ thống lên môi trường cloud công cộng (AWS EKS, region `ap-southeast-1`), theo hướng dẫn Chương 5 mục 5.8.

## 2. Ước tính chi phí theo tháng (720 giờ)

| Thành phần | Cấu hình | Đơn giá (USD) | Tháng (USD) |
|---|---|---|---:|
| EKS Control Plane | 1 cụm managed | $0.10/giờ | 72.00 |
| Worker Nodes (EC2) | 2 x t3.medium | $0.0416/giờ/node | 59.90 |
| Load Balancer (Ingress) | NLB | $0.0225/giờ + LCU | 18.50 |
| EBS (PVC app) | gp3, 10 GiB | $0.08/GiB | 0.80 |
| EBS (Prometheus) | gp3, 20 GiB | $0.08/GiB | 1.60 |
| Data Egress | ~50 GB (free tier) | — | 0.00 |
| **Tổng On-Demand** | | | **~152.80** |

## 3. Tối ưu chi phí

### 3.1 Spot Instances cho HPA

Giữ 1 node On-Demand chạy 24/7 ($29.95/tháng), node thứ 2 và các node mở rộng khi HPA kích hoạt dùng Spot (giá ~$0.0125/giờ, tiết kiệm ~70%).
Chi phí compute giảm từ $59.90 xuống ~$38.95/tháng.

### 3.2 Rightsizing tài nguyên

Dữ liệu đo thực tế (baseline 20 VUs):

| Tài nguyên | Request | Thực tế tiêu thụ | Tỷ lệ sử dụng |
|---|---|---|---|
| CPU | 100m | 22.4m | 22.4% |
| Memory | 128Mi | 65 MiB | 50.7% |

- CPU request đặt ở 100m cho phép hấp thụ tải đột biến trước khi HPA scale, tránh dao động liên tục (flapping).
- Memory limit 256Mi đủ headroom ngăn OOMKilled mà không lãng phí RAM.
- Mật độ: mỗi node t3.medium (4 GiB) chứa được 15-20 pod loại này.

### 3.3 Chi phí trên mỗi request

- Lưu lượng baseline: 42.5 req/s ~ 110 triệu req/tháng
- Chi phí tối ưu: ~$118/tháng
- **~$0.001 / 1.000 requests** (~25 VNĐ / 1.000 lượt)

## 4. Gắn nhãn tài nguyên (Cost Allocation Tags)

Các manifest trong `k8s/base/` đã gắn labels theo khuyến nghị Slide 98:

```yaml
labels:
  cost-center: "engineering-lab"
  environment: "production"
  project: "self-healing-k8s"
  owner: "team26-tan-son-sum"
```

Bộ nhãn này tương thích với Kubecost / OpenCost để phân bổ chi phí theo nhóm.

## 5. Giới hạn co giãn (Budget Guardrails)

- `maxReplicas: 10` trong HPA ngăn scale vô hạn khi có tải bất thường hoặc tấn công.
- Nếu triển khai thật, thiết lập AWS Budget alerts ở 50% / 80% / 100% ngân sách tháng.
