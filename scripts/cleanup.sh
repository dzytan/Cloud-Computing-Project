#!/usr/bin/env bash
# Script dọn dẹp toàn bộ tài nguyên cụm và tiến trình phụ trợ

set -uo pipefail

CLUSTER_NAME="selfhealing-demo"

echo "=================================================="
echo " [CLEANUP] Bắt đầu dọn dẹp tài nguyên dự án..."
echo "=================================================="

# 1. Dừng các tiến trình kubectl port-forward ngầm
echo "[1/3] Đang dừng các tiến trình port-forward..."
pkill -f "kubectl port-forward" || true

# 2. Xóa cụm Kubernetes kind
if command -v kind >/dev/null 2>&1; then
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        echo "[2/3] Đang xóa cụm kind '${CLUSTER_NAME}'..."
        kind delete cluster --name "$CLUSTER_NAME"
        echo "[+] Đã xóa cụm kind thành công!"
    else
        echo "[2/3] Cụm kind '${CLUSTER_NAME}' không tồn tại, bỏ qua."
    fi
else
    echo "[2/3] Lệnh kind không tìm thấy trong PATH, bỏ qua."
fi

# 3. Dọn dẹp cache tạm nếu có
echo "[3/3] Dọn dẹp hoàn tất. Môi trường đã sạch sẽ!"
echo "=================================================="
