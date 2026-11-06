// ============================================
// Kubernetes Self-Healing Dashboard — Frontend
// ============================================

const socket = io();
let scenarioRunning = false;

// --- Connection ---
socket.on("connect", () => {
    const badge = document.getElementById("connectionBadge");
    badge.classList.add("connected");
    document.getElementById("connectionText").textContent = "Đã kết nối";
});

socket.on("disconnect", () => {
    const badge = document.getElementById("connectionBadge");
    badge.classList.remove("connected");
    document.getElementById("connectionText").textContent = "Mất kết nối";
});

// --- Cluster State Updates (every 2s from server) ---
socket.on("cluster_state", (data) => {
    renderNodes(data.nodes);
    renderPods(data.pods);
    renderHPA(data.hpa);
});

// --- Scenario events ---
socket.on("scenario_start", (data) => {
    scenarioRunning = true;
    updateButtons();
    const el = document.getElementById("scenarioStatus");
    el.innerHTML = `<span class="status-running">🔄 Đang chạy: ${data.name}</span>`;
    // Clear logs
    document.getElementById("logContainer").innerHTML = "";
});

socket.on("scenario_end", (data) => {
    scenarioRunning = false;
    updateButtons();
    const el = document.getElementById("scenarioStatus");
    el.innerHTML = `<span class="status-done">✅ Hoàn tất: ${data.name}</span>`;
});

socket.on("log", (entry) => {
    appendLog(entry);
});

// --- Render Functions ---
function renderNodes(nodes) {
    if (!nodes || nodes.length === 0) return;
    const grid = document.getElementById("nodesGrid");
    grid.innerHTML = nodes.map(n => {
        const statusClass = n.status === "Ready" ? "ready" : "not-ready";
        const roleIcon = n.role === "control-plane" ? "👑" : "⚙️";
        return `
            <div class="node-card">
                <div class="node-name">${roleIcon} ${n.name}</div>
                <div class="node-role">${n.role}</div>
                <span class="node-status ${statusClass}">${n.status}</span>
            </div>
        `;
    }).join("");
}

function renderPods(pods) {
    if (!pods) return;
    document.getElementById("podCount").textContent = pods.length;
    const container = document.getElementById("podsContainer");

    if (pods.length === 0) {
        container.innerHTML = '<div class="log-empty">Không có pod nào đang chạy</div>';
        return;
    }

    container.innerHTML = pods.map(p => {
        const readyText = p.ready ? "Running" : p.status;
        const badgeClass = p.ready ? "running" :
            p.status.toLowerCase().includes("terminating") ? "terminating" :
            p.status.toLowerCase().includes("pending") ? "pending" :
            p.status.toLowerCase().includes("crashloop") ? "crashloopbackoff" : "pending";

        return `
            <div class="pod-card">
                <div class="pod-name">${p.name}</div>
                <div class="pod-node">📍 ${p.node}</div>
                <div class="pod-restarts">↻ ${p.restarts}</div>
                <span class="pod-badge ${badgeClass}">${readyText}</span>
            </div>
        `;
    }).join("");
}

function renderHPA(hpa) {
    if (!hpa) return;
    document.getElementById("hpaMin").textContent = hpa.min;
    document.getElementById("hpaMax").textContent = hpa.max;
    document.getElementById("hpaCurrent").textContent = hpa.current;
    document.getElementById("hpaDesired").textContent = hpa.desired;
    document.getElementById("hpaCpu").textContent = hpa.cpu_pct !== null ? hpa.cpu_pct : "—";

    // Bar fill percentage
    const range = hpa.max - hpa.min;
    const pct = range > 0 ? ((hpa.current - hpa.min) / range) * 100 : 0;
    document.getElementById("hpaBarFill").style.width = Math.max(5, Math.min(100, pct)) + "%";
}

function appendLog(entry) {
    const container = document.getElementById("logContainer");
    // Remove placeholder if present
    const empty = container.querySelector(".log-empty");
    if (empty) empty.remove();

    const line = document.createElement("div");
    line.className = "log-line";
    line.innerHTML = `
        <span class="log-time">${entry.time}</span>
        <span class="log-msg ${entry.level}">${escapeHtml(entry.msg)}</span>
    `;
    container.appendChild(line);
    container.scrollTop = container.scrollHeight;
}

function escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
}

// --- Scenario Control ---
function runScenario(name) {
    if (scenarioRunning) return;
    socket.emit("run_scenario", { scenario: name });
}

function updateButtons() {
    document.querySelectorAll(".scenario-btn").forEach(btn => {
        btn.disabled = scenarioRunning;
    });
}

// --- Initial fetch ---
fetch("/api/status")
    .then(r => r.json())
    .then(data => {
        renderNodes(data.nodes);
        renderPods(data.pods);
        renderHPA(data.hpa);
    })
    .catch(() => {});
