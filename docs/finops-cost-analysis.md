# Báo cáo Quản trị & Tối ưu Chi phí Đám mây (FinOps & Cost Analysis)

**Đề tài 26:** Triển khai ứng dụng trên Kubernetes với tự phục hồi, co giãn và cập nhật không gián đoạn  
**Học phần:** Điện toán đám mây – Trường Đại học Giao thông Vận tải TP.HCM  
**Nhóm thực hiện:** Nhóm 26 (Trần Duy Tân, Trần Hồng Sơn, Nguyễn Ngọc Sum)

---

## 1. Giới thiệu & Mục tiêu FinOps

Theo khung hướng dẫn **Chương 5 (Mục 5.8: Quản trị và tối ưu chi phí – FinOps)**:
- Điện toán đám mây chuyển dịch mô hình tài chính từ chi phí đầu tư cố định (**CAPEX**) sang chi phí vận hành biến động (**OPEX**).
- Tài nguyên có thể khởi tạo nhanh chóng theo nhu cầu, dẫn tới nguy cơ bùng nổ chi phí ngoài tầm kiểm soát nếu thiếu cơ chế quản trị và tự động hóa.
- Mục tiêu của phân tích FinOps trong Đề tài 26 là:
  1. **Định lượng chi phí hạ tầng:** Giả định triển khai hệ thống từ môi trường mô phỏng cục bộ (kind) lên môi trường Cloud công cộng tiêu chuẩn (AWS EKS / GCP GKE).
  2. **Rightsizing tài nguyên:** Đánh giá sự tương quan giữa cấu hình tài nguyên cấp phát (`requests`/`limits`) và mức tiêu thụ thực tế để triệt tiêu tài nguyên nhàn rỗi (idle resources).
  3. **Phân bổ chi phí & Đơn vị kinh tế (Unit Economics):** Tính toán chi phí trên mỗi 1.000 lượt yêu cầu người dùng (Cost per 1k requests).

---

## 2. Ước tính Chi phí Triển khai (Public Cloud Estimation)

Giả định hệ thống `selfhealing-demo` được chuyển dịch lên nền tảng **Amazon Web Services (AWS)** tại region Singapore (`ap-southeast-1`) với SLA yêu cầu tính sẵn sàng cao (High Availability) tương đương bài lab.

### 2.1. Bảng phân rã chi phí chi tiết theo tháng (30 ngày = 720 giờ)

| Thành phần hạ tầng | Đặc tả kỹ thuật | Đơn giá AWS (USD) | Thành tiền / tháng (USD) |
|---|---|---|:---:|
| **Control Plane (EKS)** | AWS Managed Kubernetes Cluster (1 cụm) | $0.10 / giờ | $72.00 |
| **Worker Nodes (EC2)** | 2 x `t3.medium` (2 vCPU, 4 GiB RAM, Nitro) | $0.0416 / giờ / node | $59.90 |
| **Cân bằng tải (Ingress)** | AWS Network Load Balancer (NLB) cho Ingress Nginx | $0.0225 / giờ + $0.006/LCU | $18.50 |
| **Lưu trữ bền vững (PVC)** | AWS EBS Volume gp3 (10 GiB, 3000 IOPS, 125 MB/s) | $0.08 / GiB / tháng | $0.80 |
| **Lưu trữ Prometheus** | AWS EBS gp3 (20 GiB cho metrics retention 15 ngày) | $0.08 / GiB / tháng | $1.60 |
| **Lưu lượng mạng (Data Egress)** | Internet Egress ước tính 50 GB / tháng | $0.09 / GiB (sau 100GB free tier) | $0.00 |
| **Tổng chi phí On-Demand dự kiến** | | | **~$152.80 / tháng** |

---

## 3. Chiến lược Tối ưu hóa Chi phí (Cost Optimization)

Dựa trên nguyên lý FinOps (Slide 100 - 102), nhóm đề xuất 3 giải pháp giảm thiểu chi phí khi đưa vào sản xuất:

### 3.1. Kết hợp Spot Instances cho Worker Node mở rộng (HPA)
- **Node cố định (Baseline):** 1 node `t3.medium` On-Demand chạy 24/7 để duy trì Control Plane components và Pod tối thiểu ($29.95/tháng).
- **Node dự phòng & mở rộng:** Sử dụng **AWS Spot Instances** (tiết kiệm đến 70% so với On-Demand, giá ~$0.0125/giờ) cho worker node thứ 2 và các node sinh ra khi HPA kích hoạt.
- **Kết quả:** Giảm chi phí compute từ $59.90 xuống còn **~$38.95/tháng** (tiết kiệm **35%** chi phí compute).

### 3.2. Đánh giá Rightsizing tài nguyên (Resource Rightsizing)
Thực nghiệm đo lường thực tế trên cụm với 20 VUs tải nền (`steady.js`):
- **CPU:** Pod tiêu thụ trung bình `22.4m` (~22.4% so với `requests: 100m`). Ngưỡng HPA kích hoạt là 50% (~50m), giúp pod hấp thụ được các đợt tăng tải ngắn hạn mà không cần scale ngay, tránh hiện tượng dao động (flapping/thrashing).
- **Memory:** Pod tiêu thụ `65 MiB` (~50.7% so với `requests: 128Mi`). Giới hạn `limits: 256Mi` đủ an toàn ngăn ngừa lỗi tràn bộ nhớ (OOMKilled) mà không làm lãng phí RAM của Worker Node.
- **Mật độ triển khai (Density):** Mỗi node `t3.medium` (4 GiB RAM) có thể chứa tối đa 15-20 pod ứng dụng loại này, tối ưu hóa triệt để mật độ tài nguyên.

### 3.3. Đơn vị kinh tế (Unit Economics)
- Lưu lượng đo được ở kịch bản chuẩn: `42.5 requests/giây` ≈ `110,160,000 requests/tháng`.
- Tổng chi phí hạ tầng tối ưu: **$118.00 / tháng**.
- **Chi phí trên 1.000 requests:**  
  $$\text{Unit Cost} = \frac{\$118.00}{110,160} \approx \mathbf{\$0.00107} \text{ USD / 1.000 requests}$$  
  *(Chưa tới 30 VNĐ cho mỗi 1.000 lượt truy cập dịch vụ).*

---

## 4. Gắn nhãn Tài nguyên (Cost Allocation Tagging)

Tuân thủ khuyến nghị tại **Slide 98 (Gắn nhãn và phân bổ chi phí)**, tất cả các đối tượng Kubernetes trong thư mục `k8s/base/` đều được quy định bộ metadata chuẩn để tích hợp các công cụ FinOps (như Kubecost hoặc OpenCost):

```yaml
metadata:
  labels:
    app.kubernetes.io/name: selfhealing-demo
    app.kubernetes.io/part-of: cloud-computing-project
    cost-center: "engineering-lab"
    environment: "production"
    project: "self-healing-k8s"
    owner: "team26-tan-son-sum"
```

---

## 5. Chính sách Ngân sách & Cảnh báo (Budget Guardrails)

Tuân thủ **Slide 99 (Ngân sách và cảnh báo chi phí)**:
1. **Thiết lập trần co giãn HPA:** Đặt `maxReplicas: 10` trong `hpa.yaml` để ngăn chặn kịch bản tấn công DoS / lỗi vòng lặp vô hạn làm cụm tự động scale không giới hạn dẫn đến bùng nổ hóa đơn.
2. **Cảnh báo đa ngưỡng (Tiered Budget Alerts):**
   - **Ngưỡng 50% ($75):** Gửi thông báo Slack/Email thông tin thường kỳ.
   - **Ngưỡng 80% ($120):** Cảnh báo kỹ sư kiểm tra tốc độ tiêu hao ngân sách (Burn rate).
   - **Ngưỡng 100% ($150):** Tự động khóa việc mở rộng tài nguyên không thiết yếu.
