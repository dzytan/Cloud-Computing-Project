#!/usr/bin/env python3
"""
Script doc du lieu tu data/results/*.json va ve bieu do ket qua
Yeu cau: pip install matplotlib
Cach chay:
  python scripts/plot-results.py
"""

import os
import sys
import tempfile

# Set thu muc cache ghi duoc cho matplotlib tren Windows
os.environ.setdefault("MPLCONFIGDIR", tempfile.gettempdir())

# Dam bao terminal Windows khong bi loi Unicode charmap
if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

import glob
import json
import matplotlib.pyplot as plt

DATA_DIR = "data/results"
OUTPUT_DIR = "docs/results"


def load_data():
    results = {}
    files = glob.glob(os.path.join(DATA_DIR, "*.json"))
    for file_path in files:
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = json.load(f)
                scenario = content.get("scenario", os.path.basename(file_path))
                results[scenario] = content.get("data", {})
        except Exception as e:
            print(f"[WARN] Error reading {file_path}: {e}")
    return results


def plot_metrics(results):
    if not results:
        print("[INFO] No JSON data found in data/results/ yet. Run test scenarios first.")
        return

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    scenarios = list(results.keys())

    # --- Cấu hình chung cho biểu đồ ---
    plt.rcParams.update({
        'figure.facecolor': 'white',
        'axes.grid': True,
        'grid.color': '#e0e0e0',
        'font.size': 11
    })

    # 1. Biểu đồ Latency p95
    p95_values = [results[s].get("latency_p95", 0) or 0 for s in scenarios]
    p95_ms = [v * 1000 for v in p95_values]
    plt.figure(figsize=(10, 5))
    bars = plt.bar(scenarios, p95_ms, color="#3498db", edgecolor="#2980b9")
    plt.title("Latency p95 Comparison Across Scenarios (ms)")
    plt.ylabel("Latency p95 (ms)")
    plt.xticks(rotation=20)
    for bar in bars:
        yval = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2.0, yval, f"{yval:.1f} ms", ha='center', va='bottom')
    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "latency_p95_comparison.png"), dpi=150)
    plt.close()

    # 2. Biểu đồ Tỷ lệ lỗi 5xx
    error_values = [results[s].get("error_rate_5xx", 0) or 0 for s in scenarios]
    plt.figure(figsize=(10, 5))
    bars = plt.bar(scenarios, error_values, color="#e74c3c", edgecolor="#c0392b")
    plt.title("5xx Error Rate Comparison Across Scenarios (req/s)")
    plt.ylabel("5xx Errors / sec")
    plt.xticks(rotation=20)
    for bar in bars:
        yval = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2.0, yval, f"{yval:.3f}", ha='center', va='bottom')
    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "error_rate_comparison.png"), dpi=150)
    plt.close()

    # 3. Biểu đồ Availability (%)
    avail_values = [results[s].get("availability_pct", 0) or 0 for s in scenarios]
    plt.figure(figsize=(10, 5))
    colors = ["#2ecc71" if v >= 99.0 else "#f39c12" if v >= 95.0 else "#e74c3c" for v in avail_values]
    bars = plt.bar(scenarios, avail_values, color=colors, edgecolor="#333")
    plt.title("Availability (%) Across Scenarios")
    plt.ylabel("Availability (%)")
    plt.ylim(0, 105)
    plt.axhline(y=99.0, color='red', linestyle='--', linewidth=1, label='Target 99%')
    plt.legend()
    plt.xticks(rotation=20)
    for bar in bars:
        yval = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2.0, yval, f"{yval:.2f}%", ha='center', va='bottom')
    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "availability_comparison.png"), dpi=150)
    plt.close()

    # 4. Biểu đồ Pod Restarts (tổng tích lũy)
    restart_values = [results[s].get("pod_restarts", 0) or 0 for s in scenarios]
    plt.figure(figsize=(10, 5))
    bars = plt.bar(scenarios, restart_values, color="#9b59b6", edgecolor="#8e44ad")
    plt.title("Cumulative Pod Restarts Across Scenarios")
    plt.ylabel("Total Restarts")
    plt.xticks(rotation=20)
    for bar in bars:
        yval = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2.0, yval, f"{int(yval)}", ha='center', va='bottom')
    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "pod_restarts_comparison.png"), dpi=150)
    plt.close()

    # 5. Biểu đồ Replicas Available (tại thời điểm đo)
    replica_values = [results[s].get("replicas_available", 0) or 0 for s in scenarios]
    plt.figure(figsize=(10, 5))
    bars = plt.bar(scenarios, replica_values, color="#1abc9c", edgecolor="#16a085")
    plt.title("Available Replicas at Measurement Time")
    plt.ylabel("Replicas")
    plt.xticks(rotation=20)
    for bar in bars:
        yval = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2.0, yval, f"{int(yval)}", ha='center', va='bottom')
    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "replicas_comparison.png"), dpi=150)
    plt.close()

    print(f"[SUCCESS] Exported 5 result charts to: {OUTPUT_DIR}")
    print("  - latency_p95_comparison.png")
    print("  - error_rate_comparison.png")
    print("  - availability_comparison.png")
    print("  - pod_restarts_comparison.png")
    print("  - replicas_comparison.png")


if __name__ == "__main__":
    data = load_data()
    plot_metrics(data)
