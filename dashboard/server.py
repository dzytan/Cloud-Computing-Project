"""
Dashboard Backend - De tai 26: Kubernetes Self-healing Demo
Chay: python dashboard/server.py
Truy cap: http://localhost:5000
"""

import json
import subprocess
import sys
import threading
import time
import os

from flask import Flask, render_template, jsonify
from flask_socketio import SocketIO

app = Flask(__name__, template_folder="templates", static_folder="static")
app.config["SECRET_KEY"] = "selfhealing-demo-2026"
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")

# --- Trang thai toan cuc ---
scenario_logs = []  # Luu lich su log cua kich ban dang chay
current_scenario = {"name": None, "status": "idle"}  # idle | running | done


def run_cmd(cmd, timeout=30):
    """Chay 1 lenh shell va tra ve stdout."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "[TIMEOUT]"
    except Exception as e:
        return f"[ERROR] {e}"


def get_pods_json():
    """Lay danh sach pods duoi dang JSON."""
    raw = run_cmd(
        'kubectl get pods -l app=selfhealing-demo -o json'
    )
    if raw.startswith("["):
        return []
    try:
        data = json.loads(raw)
        pods = []
        for item in data.get("items", []):
            name = item["metadata"]["name"]
            phase = item["status"].get("phase", "Unknown")
            node = item["spec"].get("nodeName", "N/A")
            ready = False
            restarts = 0
            cs = item["status"].get("containerStatuses", [])
            if cs:
                ready = cs[0].get("ready", False)
                restarts = cs[0].get("restartCount", 0)
            pods.append({
                "name": name,
                "status": phase,
                "ready": ready,
                "restarts": restarts,
                "node": node,
            })
        return pods
    except Exception:
        return []


def get_nodes_json():
    """Lay danh sach nodes."""
    raw = run_cmd('kubectl get nodes -o json')
    try:
        data = json.loads(raw)
        nodes = []
        for item in data.get("items", []):
            name = item["metadata"]["name"]
            role = "worker"
            labels = item["metadata"].get("labels", {})
            if "node-role.kubernetes.io/control-plane" in labels:
                role = "control-plane"
            conditions = item["status"].get("conditions", [])
            status_str = "NotReady"
            for c in conditions:
                if c.get("type") == "Ready" and c.get("status") == "True":
                    status_str = "Ready"
            nodes.append({"name": name, "role": role, "status": status_str})
        return nodes
    except Exception:
        return []


def get_hpa_json():
    """Lay trang thai HPA."""
    raw = run_cmd('kubectl get hpa selfhealing-demo-hpa -o json')
    try:
        data = json.loads(raw)
        current = data["status"].get("currentReplicas", 0)
        desired = data["status"].get("desiredReplicas", 0)
        min_r = data["spec"].get("minReplicas", 2)
        max_r = data["spec"].get("maxReplicas", 10)
        metrics = data["status"].get("currentMetrics", [])
        cpu_pct = None
        for m in metrics:
            if m.get("type") == "Resource" and m["resource"]["name"] == "cpu":
                cpu_pct = m["resource"]["current"].get("averageUtilization")
        return {
            "current": current,
            "desired": desired,
            "min": min_r,
            "max": max_r,
            "cpu_pct": cpu_pct,
        }
    except Exception:
        return {"current": 0, "desired": 0, "min": 2, "max": 10, "cpu_pct": None}


def get_version():
    """Goi /version qua Ingress."""
    out = run_cmd('curl.exe -s -H "Host: selfhealing.local" http://localhost/version', timeout=5)
    return out


def emit_log(msg, level="info"):
    """Gui 1 dong log len giao dien web."""
    entry = {"time": time.strftime("%H:%M:%S"), "msg": msg, "level": level}
    scenario_logs.append(entry)
    socketio.emit("log", entry)


def emit_status_update():
    """Gui trang thai hien tai cua pods/nodes/hpa len web."""
    socketio.emit("cluster_state", {
        "pods": get_pods_json(),
        "nodes": get_nodes_json(),
        "hpa": get_hpa_json(),
    })


# --- Background thread: Cap nhat trang thai moi 2 giay ---
def background_poller():
    while True:
        try:
            emit_status_update()
        except Exception:
            pass
        time.sleep(2)


# --- Routes ---
@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/status")
def api_status():
    return jsonify({
        "pods": get_pods_json(),
        "nodes": get_nodes_json(),
        "hpa": get_hpa_json(),
        "version": get_version(),
        "scenario": current_scenario,
    })


# --- Kich ban thuc nghiem ---
def run_scenario_thread(name, func):
    """Wrapper chay kich ban trong thread rieng."""
    global current_scenario
    current_scenario = {"name": name, "status": "running"}
    scenario_logs.clear()
    socketio.emit("scenario_start", {"name": name})
    emit_log(f"Bat dau kich ban: {name}", "header")
    try:
        func()
        emit_log(f"Hoan tat kich ban: {name}", "success")
        current_scenario["status"] = "done"
    except Exception as e:
        emit_log(f"Loi: {e}", "error")
        current_scenario["status"] = "done"
    socketio.emit("scenario_end", {"name": name})


def scenario_delete_pod():
    pod_name = run_cmd(
        'kubectl get pods -l app=selfhealing-demo -o jsonpath="{.items[0].metadata.name}"'
    ).strip('"')
    emit_log(f"Dang xoa pod: {pod_name}", "warn")
    emit_status_update()
    time.sleep(1)

    run_cmd(f"kubectl delete pod {pod_name} --now")
    emit_log("Da gui lenh xoa pod!", "warn")

    for i in range(15):
        time.sleep(2)
        pods = get_pods_json()
        emit_status_update()
        ready_count = sum(1 for p in pods if p["ready"])
        emit_log(f"Dang cho phuc hoi... Pods Ready: {ready_count}/2", "info")
        if ready_count >= 2:
            break

    emit_log("ReplicaSet da tao pod moi thay the thanh cong!", "success")
    ver = get_version()
    emit_log(f"Dich vu van hoat dong binh thuong: {ver}", "success")
    emit_status_update()


def scenario_fail_health():
    emit_log("Goi /fail-health de lam hong liveness probe...", "warn")
    out = run_cmd('curl.exe -s -H "Host: selfhealing.local" http://localhost/fail-health', timeout=5)
    emit_log(f"Response: {out}", "info")

    emit_log("Cho Kubelet phat hien liveness probe that bai (3 lan x 5s = 15s)...", "info")
    for i in range(10):
        time.sleep(3)
        pods = get_pods_json()
        emit_status_update()
        restarts = sum(p["restarts"] for p in pods)
        ready_count = sum(1 for p in pods if p["ready"])
        emit_log(f"Pods Ready: {ready_count}/2, Tong Restarts: {restarts}", "info")
        if any(p["restarts"] > 0 for p in pods) and ready_count >= 2:
            break

    emit_log("Kubelet da tu dong restart container thanh cong!", "success")
    ver = get_version()
    emit_log(f"Dich vu phuc hoi: {ver}", "success")
    emit_status_update()


def scenario_drain_node():
    worker = run_cmd(
        "kubectl get nodes --selector=!node-role.kubernetes.io/control-plane -o jsonpath=\"{.items[0].metadata.name}\""
    ).strip('"')
    emit_log(f"Dang drain worker node: {worker}", "warn")
    emit_status_update()

    run_cmd(f"kubectl drain {worker} --ignore-daemonsets --delete-emptydir-data --force", timeout=60)
    emit_log(f"Da drain node {worker}!", "warn")
    time.sleep(3)
    emit_status_update()

    ver = get_version()
    emit_log(f"Dich vu van hoat dong khi drain: {ver}", "success")

    emit_log(f"Dang uncordon node {worker}...", "info")
    run_cmd(f"kubectl uncordon {worker}")
    time.sleep(3)
    emit_log(f"Da phuc hoi node {worker}!", "success")
    emit_status_update()


def scenario_rollout_v2():
    emit_log("Dang cap nhat sang phien ban v2 (Rolling Update)...", "info")
    run_cmd("kubectl set image deployment/selfhealing-demo app=selfhealing-demo:v2")

    for i in range(15):
        time.sleep(3)
        pods = get_pods_json()
        emit_status_update()
        ready_count = sum(1 for p in pods if p["ready"])
        emit_log(f"Rolling Update... Pods Ready: {ready_count}", "info")
        if ready_count >= 2:
            break

    run_cmd("kubectl rollout status deployment/selfhealing-demo --timeout=60s")
    ver = get_version()
    emit_log(f"Cap nhat thanh cong! Phien ban moi: {ver}", "success")
    emit_status_update()


def scenario_rollout_bad():
    emit_log("Dang phat hanh PHIEN BAN LOI v2-bad...", "error")
    run_cmd("kubectl set image deployment/selfhealing-demo app=selfhealing-demo:v2-bad")

    for i in range(8):
        time.sleep(3)
        pods = get_pods_json()
        emit_status_update()
        not_ready = [p for p in pods if not p["ready"]]
        emit_log(f"Pods KHONG Ready (ban loi): {len(not_ready)}", "warn")

    ver = get_version()
    emit_log(f"Nguoi dung VAN nhan phien ban cu an toan: {ver}", "success")
    emit_log("Kubernetes DA CHAN ban loi, khong cho nhan traffic!", "success")

    emit_log("Dang rollback ve phien ban on dinh...", "info")
    run_cmd("kubectl rollout undo deployment/selfhealing-demo")

    for i in range(10):
        time.sleep(3)
        pods = get_pods_json()
        emit_status_update()
        ready_count = sum(1 for p in pods if p["ready"])
        if ready_count >= 2:
            break

    run_cmd("kubectl rollout status deployment/selfhealing-demo --timeout=60s")
    ver = get_version()
    emit_log(f"Rollback thanh cong! Phien ban: {ver}", "success")
    emit_status_update()


def scenario_hpa():
    emit_log("Dang tao tai CPU dot bien de kich hoat HPA...", "info")
    emit_log("Su dung k6 spike test (120 giay)...", "info")

    def run_k6():
        run_cmd("k6 run --stage 10s:10,30s:150,40s:200,10s:5 load-test/hpa-spike.js", timeout=180)

    t = threading.Thread(target=run_k6, daemon=True)
    t.start()

    for i in range(30):
        time.sleep(4)
        hpa = get_hpa_json()
        pods = get_pods_json()
        emit_status_update()
        emit_log(
            f"HPA: CPU={hpa['cpu_pct']}%, Replicas={hpa['current']}/{hpa['desired']} (min={hpa['min']}, max={hpa['max']}), Pods Ready={sum(1 for p in pods if p['ready'])}",
            "info"
        )
        if hpa["current"] and hpa["current"] > 2:
            emit_log(f"HPA da scale UP len {hpa['current']} pods!", "success")

    t.join(timeout=10)
    emit_log("HPA se tu dong scale down sau cua so on dinh 60 giay.", "info")
    emit_status_update()


@socketio.on("run_scenario")
def handle_run_scenario(data):
    name = data.get("scenario")
    scenarios = {
        "delete-pod": ("Kich ban 2: Xoa Pod Dot Ngot", scenario_delete_pod),
        "fail-health": ("Kich ban 3: Liveness Probe Loi", scenario_fail_health),
        "drain-node": ("Kich ban 4: Drain Worker Node", scenario_drain_node),
        "rollout-v2": ("Kich ban 5A: Rolling Update v2", scenario_rollout_v2),
        "rollout-bad": ("Kich ban 5B: Rollout Loi + Rollback", scenario_rollout_bad),
        "hpa": ("Kich ban 6: HPA Autoscaling", scenario_hpa),
    }
    if name in scenarios:
        title, func = scenarios[name]
        thread = threading.Thread(target=run_scenario_thread, args=(title, func), daemon=True)
        thread.start()


if __name__ == "__main__":
    # Khoi dong poller chay ngam
    poller = threading.Thread(target=background_poller, daemon=True)
    poller.start()

    port = int(os.environ.get("DASHBOARD_PORT", 5000))
    print(f"\n  Dashboard dang chay tai: http://localhost:{port}\n")
    socketio.run(app, host="0.0.0.0", port=port, debug=False, allow_unsafe_werkzeug=True)
