import os
import socket
import time
import math
import uvicorn
from fastapi import FastAPI, Request, Response, status, HTTPException
from fastapi.responses import HTMLResponse
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = FastAPI(title="Self-Healing Demo App")

# Cấu hình từ biến môi trường (ConfigMap, Secret & Downward API)
APP_NAME = os.getenv("APP_NAME", "selfhealing-demo")
ENVIRONMENT = os.getenv("ENVIRONMENT", "local")
APP_VERSION = os.getenv("APP_VERSION", "v1")
BROKEN = os.getenv("BROKEN", "false").lower() in ("true", "1", "yes")
HAS_SECRET = bool(os.getenv("API_KEY"))

POD_NAME = os.getenv("POD_NAME") or socket.gethostname()
POD_IP = os.getenv("POD_IP") or socket.gethostbyname(socket.gethostname())
NODE_NAME = os.getenv("NODE_NAME", "unknown-node")

# Trạng thái cờ phục vụ kịch bản thử nghiệm
IS_HEALTHY = True
START_TIME = time.time()

# Prometheus Metrics
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP Requests",
    ["method", "endpoint", "status"]
)

REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP Request Latency in seconds",
    ["method", "endpoint"]
)


@app.middleware("http")
async def prometheus_middleware(request: Request, call_next):
    start = time.time()
    endpoint = request.url.path
    method = request.method
    try:
        response = await call_next(request)
        duration = time.time() - start
        REQUEST_COUNT.labels(method=method, endpoint=endpoint, status=str(response.status_code)).inc()
        REQUEST_DURATION.labels(method=method, endpoint=endpoint).observe(duration)
        return response
    except Exception as exc:
        duration = time.time() - start
        REQUEST_COUNT.labels(method=method, endpoint=endpoint, status="500").inc()
        REQUEST_DURATION.labels(method=method, endpoint=endpoint).observe(duration)
        raise exc


@app.get("/")
def read_root():
    """Trang chủ JSON kiểm tra kết nối cơ bản & thông tin Pod xử lý"""
    return {
        "app": APP_NAME,
        "environment": ENVIRONMENT,
        "version": APP_VERSION,
        "pod_name": POD_NAME,
        "pod_ip": POD_IP,
        "node_name": NODE_NAME,
        "healthy": IS_HEALTHY and not BROKEN,
        "secret_configured": HAS_SECRET,
        "uptime_seconds": round(time.time() - START_TIME, 2),
    }


@app.get("/version")
def get_version():
    """Endpoint trả về phiên bản ứng dụng và Pod xử lý (v1, v2, v2-bad)"""
    return {
        "version": APP_VERSION,
        "pod": POD_NAME,
        "pod_ip": POD_IP,
        "node": NODE_NAME,
    }


@app.get("/api/info")
def get_pod_info():
    """API phục vụ giao diện Live Frontend UI (/ui)"""
    return {
        "app": APP_NAME,
        "version": APP_VERSION,
        "pod_name": POD_NAME,
        "pod_ip": POD_IP,
        "node_name": NODE_NAME,
        "status": "HEALTHY" if (IS_HEALTHY and not BROKEN) else "UNHEALTHY",
        "uptime_seconds": round(time.time() - START_TIME, 1),
        "timestamp": time.strftime("%H:%M:%S"),
    }


@app.get("/ui", response_class=HTMLResponse)
def live_pod_ui():
    """
    Giao diện Frontend Light-Mode (High Contrast) hiển thị trực tiếp Pod xử lý,
    phiên bản (v1 xanh dương, v2 cam) và phân bổ cân bằng tải trên màn hình TV lớp học.
    """
    return """<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Live Pod Traffic Visualizer - Đề tài 26</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    background: #f8fafc; color: #0f172a; padding: 16px 22px;
  }
  .top-bar {
    display: flex; justify-content: space-between; align-items: center;
    border-bottom: 2px solid #cbd5e1; padding-bottom: 10px; margin-bottom: 14px;
  }
  .top-bar h1 { font-size: 1.35rem; font-weight: 800; color: #0f172a; }
  .controls { display: flex; gap: 8px; align-items: center; }
  button {
    font-size: 0.95rem; font-weight: 700; padding: 6px 14px; border-radius: 6px;
    border: 2px solid #0f172a; background: #ffffff; cursor: pointer;
  }
  button.active { background: #0f172a; color: #ffffff; }
  .hero {
    display: grid; grid-template-columns: 180px 1fr; gap: 16px;
    background: #ffffff; border: 3px solid #0f172a; border-radius: 12px;
    padding: 16px; margin-bottom: 14px; box-shadow: 0 4px 0 #0f172a;
  }
  .ver-box {
    display: flex; flex-direction: column; justify-content: center; align-items: center;
    border-radius: 10px; color: #ffffff; font-weight: 900; padding: 12px;
    transition: background 0.2s ease;
  }
  .ver-v1 { background: #0284c7; }
  .ver-v2 { background: #ea580c; }
  .ver-other { background: #dc2626; }
  .ver-label { font-size: 0.85rem; text-transform: uppercase; letter-spacing: 1px; opacity: 0.9; }
  .ver-num { font-size: 2.8rem; line-height: 1.1; }
  .meta-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; align-content: center; }
  .meta-item { background: #f1f5f9; padding: 8px 12px; border-radius: 8px; border: 1px solid #cbd5e1; }
  .meta-item span { display: block; font-size: 0.78rem; font-weight: 700; color: #475569; text-transform: uppercase; }
  .meta-item strong { font-size: 1.1rem; font-family: Consolas, monospace; color: #0f172a; }
  .badge-ok { color: #15803d !important; }
  .badge-err { color: #dc2626 !important; }
  .stats-bar {
    display: flex; gap: 16px; margin-bottom: 12px; font-size: 1rem; font-weight: 700;
  }
  .stat-pill { background: #e2e8f0; padding: 6px 12px; border-radius: 6px; }
  .stat-ok { background: #dcfce7; color: #166534; border: 1px solid #86efac; }
  .stat-err { background: #fee2e2; color: #991b1b; border: 1px solid #fca5a5; }
  table { width: 100%; border-collapse: collapse; background: #ffffff; border: 2px solid #cbd5e1; }
  th, td { padding: 8px 12px; text-align: left; border-bottom: 1px solid #cbd5e1; font-size: 0.98rem; }
  th { background: #e2e8f0; font-weight: 800; text-transform: uppercase; font-size: 0.82rem; }
  .mono { font-family: Consolas, monospace; font-weight: 700; }
  .tag { padding: 2px 8px; border-radius: 4px; color: #fff; font-weight: 800; font-size: 0.85rem; }
  .stream { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 12px; }
  .dot {
    padding: 4px 10px; border-radius: 6px; color: #fff; font-weight: 800;
    font-family: Consolas, monospace; font-size: 0.85rem;
  }
</style>
</head>
<body>
  <div class="top-bar">
    <h1>Kubernetes Live Load-Balancer & Zero-Downtime Monitor</h1>
    <div class="controls">
      <button id="toggleBtn" class="active" onclick="togglePoll()">Auto-Reload: ON (1s)</button>
      <button onclick="resetStats()">Reset bộ đếm</button>
    </div>
  </div>

  <div class="hero">
    <div id="verBox" class="ver-box ver-v1">
      <span class="ver-label">Version</span>
      <span id="verText" class="ver-num">--</span>
    </div>
    <div class="meta-grid">
      <div class="meta-item"><span>Pod xử lý hiện tại</span><strong id="podName">Đang kết nối...</strong></div>
      <div class="meta-item"><span>Pod IP / Worker Node</span><strong id="podNode">--</strong></div>
      <div class="meta-item"><span>Trạng thái Health</span><strong id="healthStatus" class="badge-ok">--</strong></div>
      <div class="meta-item"><span>Uptime của Pod</span><strong id="podUptime">--</strong></div>
    </div>
  </div>

  <div class="stats-bar">
    <div class="stat-pill">Tổng Request: <span id="totalReq">0</span></div>
    <div class="stat-pill stat-ok">Thành công (200 OK): <span id="okReq">0</span></div>
    <div class="stat-pill stat-err">Lỗi kết nối / 5xx: <span id="errReq">0</span></div>
  </div>

  <table>
    <thead>
      <tr>
        <th>Pod Replica (Nhận Traffic)</th>
        <th>Pod IP</th>
        <th>Worker Node</th>
        <th>Version</th>
        <th>Số Request</th>
      </tr>
    </thead>
    <tbody id="podTable"></tbody>
  </table>

  <div class="stream" id="reqStream"></div>

<script>
  let running = true;
  let total = 0, ok = 0, err = 0;
  const pods = {};
  const recent = [];

  function verClass(v) {
    if (v === 'v1') return 'ver-v1';
    if (v === 'v2') return 'ver-v2';
    return 'ver-other';
  }

  async function poll() {
    if (!running) return;
    total++;
    try {
      const res = await fetch('/api/info', { cache: 'no-store' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const d = await res.json();
      ok++;

      const box = document.getElementById('verBox');
      box.className = 'ver-box ' + verClass(d.version);
      document.getElementById('verText').textContent = d.version;
      document.getElementById('podName').textContent = d.pod_name;
      document.getElementById('podNode').textContent = d.pod_ip + ' @ ' + d.node_name;
      const hs = document.getElementById('healthStatus');
      hs.textContent = d.status;
      hs.className = d.status === 'HEALTHY' ? 'badge-ok' : 'badge-err';
      document.getElementById('podUptime').textContent = d.uptime_seconds + 's';

      if (!pods[d.pod_name]) {
        pods[d.pod_name] = { ip: d.pod_ip, node: d.node_name, ver: d.version, count: 0 };
      }
      pods[d.pod_name].ver = d.version;
      pods[d.pod_name].count++;

      recent.unshift({ ver: d.version, short: d.pod_name.slice(-5), ok: true });
    } catch (e) {
      err++;
      document.getElementById('healthStatus').textContent = 'REQUEST ERROR';
      document.getElementById('healthStatus').className = 'badge-err';
      recent.unshift({ ver: 'ERR', short: '5xx', ok: false });
    }
    if (recent.length > 16) recent.pop();
    render();
  }

  function render() {
    document.getElementById('totalReq').textContent = total;
    document.getElementById('okReq').textContent = ok;
    document.getElementById('errReq').textContent = err;

    const tbody = document.getElementById('podTable');
    tbody.innerHTML = Object.entries(pods).map(([name, p]) => `
      <tr>
        <td class="mono">${name}</td>
        <td class="mono">${p.ip}</td>
        <td>${p.node}</td>
        <td><span class="tag ${verClass(p.ver)}">${p.ver}</span></td>
        <td class="mono">${p.count} (${Math.round(p.count * 100 / Math.max(1, ok))}%)</td>
      </tr>
    `).join('');

    document.getElementById('reqStream').innerHTML = recent.map(r =>
      `<span class="dot ${r.ok ? verClass(r.ver) : 'ver-other'}">${r.ver}:${r.short}</span>`
    ).join('');
  }

  function togglePoll() {
    running = !running;
    const btn = document.getElementById('toggleBtn');
    btn.textContent = running ? 'Auto-Reload: ON (1s)' : 'Auto-Reload: PAUSED';
    btn.className = running ? 'active' : '';
  }

  function resetStats() {
    total = 0; ok = 0; err = 0;
    for (const k in pods) delete pods[k];
    recent.length = 0;
    render();
  }

  setInterval(poll, 1000);
  poll();
</script>
</body>
</html>"""


@app.get("/health")
def health_probe():
    """
    Liveness probe:
    Nếu IS_HEALTHY = False (do gọi /fail-health), trả về 500 để kubelet restart container.
    """
    if not IS_HEALTHY:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"status": "unhealthy", "pod": POD_NAME, "reason": "Manually triggered failure via /fail-health"}
        )
    return {"status": "healthy", "pod": POD_NAME}


@app.get("/ready")
def readiness_probe():
    """
    Readiness probe:
    Nếu BROKEN = true (bản lỗi v2-bad) hoặc IS_HEALTHY = False, trả về 500.
    Kubernetes sẽ ngắt traffic khỏi pod này mà không đưa request người dùng vào.
    """
    if BROKEN:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"status": "not_ready", "pod": POD_NAME, "reason": "Simulated broken release (BROKEN=true)"}
        )
    if not IS_HEALTHY:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"status": "not_ready", "pod": POD_NAME, "reason": "Application is in unhealthy state"}
        )
    return {"status": "ready", "pod": POD_NAME}


@app.get("/fail-health")
def trigger_fail_health():
    """Chủ động làm hỏng liveness probe của Pod nhận request để kiểm thử self-healing"""
    global IS_HEALTHY
    IS_HEALTHY = False
    return {
        "message": "Health failure triggered! Next /health and /ready calls on this pod will return 500.",
        "affected_pod": POD_NAME,
        "node": NODE_NAME,
    }


@app.get("/load")
def compute_load(duration_ms: int = 200):
    """
    Endpoint tạo tải CPU giả lập để kích hoạt HPA scale pod.
    """
    end_time = time.time() + (duration_ms / 1000.0)
    x = 0.0001
    while time.time() < end_time:
        x += math.sqrt(x) + math.sin(x)
    return {"status": "load_simulated", "duration_ms": duration_ms, "pod": POD_NAME}


@app.get("/metrics")
def get_metrics():
    """Endpoint cho Prometheus scrape"""
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(app, host="0.0.0.0", port=port)
