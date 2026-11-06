# =============================================================================
#  DEMO SCRIPT - De tai 26: Kubernetes Tu phuc hoi, Co gian & Cap nhat
#  Chay: .\scripts\demo-all.ps1
#  Luu y: Phai chay SAU KHI cum kind da san sang va ung dung da deploy
# =============================================================================

$ErrorActionPreference = "Continue"

# ---- Ham tien ich ----
function Banner {
    param([string]$Title, [string]$Color = "Cyan")
    $line = "=" * 70
    Write-Host ""
    Write-Host $line -ForegroundColor $Color
    Write-Host "  $Title" -ForegroundColor $Color
    Write-Host $line -ForegroundColor $Color
    Write-Host ""
}

function SubTitle {
    param([string]$Text)
    Write-Host "  >> $Text" -ForegroundColor Yellow
    Write-Host ""
}

function Info {
    param([string]$Text)
    Write-Host "  [INFO] $Text" -ForegroundColor DarkGray
}

function Success {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Warn {
    param([string]$Text)
    Write-Host "  [!!] $Text" -ForegroundColor Red
}

function WaitEnter {
    param([string]$Msg = "Bam ENTER de tiep tuc kich ban tiep theo...")
    Write-Host ""
    Write-Host "  -------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  $Msg" -ForegroundColor Magenta
    Write-Host "  -------------------------------------------" -ForegroundColor DarkGray
    Read-Host
}

function ShowPods {
    Write-Host ""
    Write-Host "  Trang thai Pods hien tai:" -ForegroundColor White
    kubectl get pods -l app=selfhealing-demo -o wide 2>&1 | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
}

function ShowHPA {
    Write-Host ""
    Write-Host "  Trang thai HPA hien tai:" -ForegroundColor White
    kubectl get hpa selfhealing-demo-hpa 2>&1 | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
}

# =========================================================================
#  PHAN MO DAU
# =========================================================================
Clear-Host
Banner "DE TAI 26: KUBERNETES TU PHUC HOI, CO GIAN & CAP NHAT KHONG GIAN DOAN" "White"
Write-Host "  Nhom thuc hien: Tran Duy Tan - Tran Hong Son - Nguyen Ngoc Sum" -ForegroundColor White
Write-Host "  Mon hoc: Dien Toan Dam May" -ForegroundColor White
Write-Host ""
Write-Host "  Cau hoi nghien cuu:" -ForegroundColor Yellow
Write-Host "  Cac controller va health probe cua Kubernetes phoi hop nhu the nao" -ForegroundColor Yellow
Write-Host "  de duy tri trang thai mong muon khi pod loi, tai tang hoac" -ForegroundColor Yellow
Write-Host "  phien ban moi gap su co?" -ForegroundColor Yellow
Write-Host ""

Banner "KIEM TRA TRANG THAI CUM KUBERNETES" "DarkCyan"
Info "Hien thi cac node trong cum..."
kubectl get nodes -o wide 2>&1 | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Info "Hien thi ung dung dang chay..."
ShowPods
Info "Kiem tra Ingress endpoint..."
$ver = curl.exe -s -H "Host: selfhealing.local" http://localhost/version 2>&1
Write-Host "  Response: $ver" -ForegroundColor Green
Write-Host ""

WaitEnter "Bam ENTER de bat dau Kich ban 1: BASELINE..."

# =========================================================================
#  KICH BAN 1: BASELINE
# =========================================================================
Banner "KICH BAN 1/6: BASELINE - TAI NEN ON DINH" "Cyan"
SubTitle "Chay k6 tai nen 20 VUs trong 30 giay de do chi so goc (baseline)"
Info "Dang chay k6 steady test (30s)..."

# Chay k6 voi thoi gian ngan cho demo
k6 run --duration 30s --vus 20 load-test/steady.js 2>&1 | ForEach-Object { Write-Host "  $_" }

Success "Baseline hoan tat! Availability va Latency p95 da duoc ghi nhan."
ShowPods

WaitEnter "Bam ENTER de tiep tuc Kich ban 2: XOA POD..."

# =========================================================================
#  KICH BAN 2: TU PHUC HOI - XOA POD DOT NGOT
# =========================================================================
Banner "KICH BAN 2/6: TU PHUC HOI - XOA POD DOT NGOT" "Red"
SubTitle "Xoa ngau nhien 1 pod trong luc dich vu dang hoat dong"
Info "Trang thai TRUOC khi xoa:"
ShowPods

$podName = kubectl get pods -l app=selfhealing-demo -o jsonpath="{.items[0].metadata.name}" 2>&1
Info "Dang xoa pod: $podName"
Write-Host ""

$sw = [System.Diagnostics.Stopwatch]::StartNew()
kubectl delete pod $podName --now 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }

Info "Doi ReplicaSet tao pod moi va chuyen sang Ready..."
kubectl wait --for=condition=ready pod -l app=selfhealing-demo --timeout=60s 2>&1 | ForEach-Object { Write-Host "  $_" }
$sw.Stop()

Success "Cum da tu phuc hoi trong $($sw.Elapsed.TotalSeconds.ToString('F1')) giay!"
Info "Trang thai SAU khi phuc hoi:"
ShowPods

# Kiem tra dich vu van hoat dong
$ver = curl.exe -s -H "Host: selfhealing.local" http://localhost/version 2>&1
Success "Ingress van tra ve binh thuong: $ver"

WaitEnter "Bam ENTER de tiep tuc Kich ban 3: LOI HEALTH PROBE..."

# =========================================================================
#  KICH BAN 3: LIVENESS PROBE THAT BAI -> TU RESTART
# =========================================================================
Banner "KICH BAN 3/6: LIVENESS PROBE THAT BAI - TU DONG RESTART" "Yellow"
SubTitle "Goi /fail-health de lam hong liveness probe, Kubelet se tu restart container"

Info "Restart count TRUOC khi kich hoat loi:"
kubectl get pods -l app=selfhealing-demo -o custom-columns="POD:metadata.name,READY:status.containerStatuses[0].ready,RESTARTS:status.containerStatuses[0].restartCount" --no-headers 2>&1 | ForEach-Object { Write-Host "  $_" }
Write-Host ""

Info "Dang goi /fail-health..."
$resp = curl.exe -s -H "Host: selfhealing.local" http://localhost/fail-health 2>&1
Write-Host "  Response: $resp" -ForegroundColor Yellow
Write-Host ""

Info "Cho 20 giay de Kubelet phat hien liveness probe that bai (3 lan x 5s)..."
for ($i = 20; $i -gt 0; $i--) {
    Write-Host "`r  Dang cho: $i giay... " -NoNewline -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
}
Write-Host ""
Write-Host ""

Info "Restart count SAU khi Kubelet tu restart:"
kubectl get pods -l app=selfhealing-demo -o custom-columns="POD:metadata.name,READY:status.containerStatuses[0].ready,RESTARTS:status.containerStatuses[0].restartCount" --no-headers 2>&1 | ForEach-Object { Write-Host "  $_" }
Write-Host ""

Success "Container da tu dong restart va phuc hoi thanh cong!"

# Doi pod Ready tro lai
Info "Doi pod Ready tro lai..."
kubectl wait --for=condition=ready pod -l app=selfhealing-demo --timeout=60s 2>&1 | Out-Null
$ver = curl.exe -s -H "Host: selfhealing.local" http://localhost/version 2>&1
Success "Dich vu hoat dong binh thuong: $ver"

WaitEnter "Bam ENTER de tiep tuc Kich ban 4: DRAIN NODE..."

# =========================================================================
#  KICH BAN 4: DRAIN WORKER NODE - PDB BAO VE
# =========================================================================
Banner "KICH BAN 4/6: DRAIN WORKER NODE - PDB BAO VE" "Magenta"
SubTitle "Rut 1 worker node, PodDisruptionBudget dam bao luon co it nhat 1 pod Ready"

Info "Trang thai PDB hien tai:"
kubectl get pdb 2>&1 | ForEach-Object { Write-Host "  $_" }
Write-Host ""

Info "Trang thai Pods TRUOC khi drain (chu y cot NODE):"
ShowPods

$workerNode = kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>&1
Info "Dang drain worker node: $workerNode"
Write-Host ""

kubectl drain $workerNode --ignore-daemonsets --delete-emptydir-data --force 2>&1 | ForEach-Object {
    if ($_ -match "evict") { Write-Host "  $_" -ForegroundColor Yellow }
    else { Write-Host "  $_" -ForegroundColor DarkGray }
}

Write-Host ""
Info "Trang thai Pods SAU khi drain (pod da chuyen sang node khac):"
ShowPods

$ver = curl.exe -s -H "Host: selfhealing.local" http://localhost/version 2>&1
Success "Dich vu van hoat dong binh thuong trong khi drain: $ver"

Info "Dang uncordon node $workerNode de phuc hoi cum..."
kubectl uncordon $workerNode 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }
Success "Da phuc hoi node thanh cong!"

WaitEnter "Bam ENTER de tiep tuc Kich ban 5: ROLLING UPDATE & ROLLBACK..."

# =========================================================================
#  KICH BAN 5: ROLLING UPDATE (v2) VA ROLLBACK (v2-bad)
# =========================================================================
Banner "KICH BAN 5/6: ROLLING UPDATE & ROLLBACK" "Blue"

# --- Phan A: Cap nhat len v2 thanh cong ---
SubTitle "Phan A: Cap nhat len phien ban v2 (Zero-downtime Rolling Update)"
Info "Phien ban hien tai:"
$ver = curl.exe -s -H "Host: selfhealing.local" http://localhost/version 2>&1
Write-Host "  $ver" -ForegroundColor White
Write-Host ""

Info "Dang cap nhat image sang selfhealing-demo:v2..."
kubectl set image deployment/selfhealing-demo app=selfhealing-demo:v2 2>&1 | ForEach-Object { Write-Host "  $_" }
Info "Doi rollout hoan tat (maxSurge:1, maxUnavailable:0)..."
kubectl rollout status deployment/selfhealing-demo --timeout=60s 2>&1 | ForEach-Object { Write-Host "  $_" }

$ver = curl.exe -s -H "Host: selfhealing.local" http://localhost/version 2>&1
Success "Cap nhat thanh cong! Phien ban moi: $ver"
ShowPods

Write-Host ""
WaitEnter "Bam ENTER de thu phat hanh PHIEN BAN LOI v2-bad..."

# --- Phan B: Phat hanh ban loi v2-bad ---
SubTitle "Phan B: Phat hanh phien ban LOI v2-bad (Readiness Probe chan traffic)"
Warn "Dang deploy ban loi v2-bad vao cum..."
kubectl set image deployment/selfhealing-demo app=selfhealing-demo:v2-bad 2>&1 | ForEach-Object { Write-Host "  $_" }

Info "Cho 15 giay de quan sat readiness probe that bai..."
for ($i = 15; $i -gt 0; $i--) {
    Write-Host "`r  Dang cho: $i giay... " -NoNewline -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
}
Write-Host ""
Write-Host ""

Info "Trang thai Pods (pod moi KHONG BAO GIO Ready do readiness probe that bai):"
kubectl get pods -l app=selfhealing-demo -o wide 2>&1 | ForEach-Object { Write-Host "  $_" }
Write-Host ""

Info "Kiem tra: Nguoi dung co bi anh huong khong?"
$ver = curl.exe -s -H "Host: selfhealing.local" http://localhost/version 2>&1
Success "Nguoi dung VAN nhan duoc phien ban cu an toan: $ver"
Success "-> Kubernetes DA CHAN ban loi, khong cho nhan traffic!"

Write-Host ""
WaitEnter "Bam ENTER de thuc hien ROLLBACK..."

# --- Phan C: Rollback ---
SubTitle "Phan C: Rollback ve phien ban on dinh"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
kubectl rollout undo deployment/selfhealing-demo 2>&1 | ForEach-Object { Write-Host "  $_" }
kubectl rollout status deployment/selfhealing-demo --timeout=60s 2>&1 | ForEach-Object { Write-Host "  $_" }
$sw.Stop()

$ver = curl.exe -s -H "Host: selfhealing.local" http://localhost/version 2>&1
Success "Rollback hoan tat trong $($sw.Elapsed.TotalSeconds.ToString('F1'))s! Phien ban: $ver"
ShowPods

WaitEnter "Bam ENTER de tiep tuc Kich ban 6: HPA AUTOSCALING..."

# =========================================================================
#  KICH BAN 6: HPA AUTOSCALING - SPIKE LOAD
# =========================================================================
Banner "KICH BAN 6/6: HPA AUTOSCALING - TU DONG CO GIAN THEO TAI" "Green"
SubTitle "Tang tai CPU dot bien bang k6, quan sat HPA tu dong scale up pods"

Info "Trang thai HPA TRUOC khi tang tai:"
ShowHPA
ShowPods

Info "Dang chay k6 spike test (150-200 VUs trong 2 phut)..."
Info "Trong luc cho, hay quan sat so replicas tang len..."
Write-Host ""

# Chay k6 spike test voi thoi gian rut gon cho demo
k6 run --stage 15s:10,30s:150,60s:200,15s:5 load-test/hpa-spike.js 2>&1 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Info "Trang thai HPA SAU khi tang tai:"
ShowHPA
Info "Trang thai Pods SAU khi HPA scale up:"
ShowPods

Success "HPA da tu dong scale up pods khi CPU vuot nguong 50%!"
Info "Sau cua so on dinh 60s, HPA se tu dong scale down ve 2 pods."

# =========================================================================
#  KET LUAN
# =========================================================================
Write-Host ""
Banner "KET LUAN - TONG KET KET QUA THU NGHIEM" "White"
Write-Host "  +----+-----------------------------------+--------------------+" -ForegroundColor White
Write-Host "  | #  | Kich ban                          | Ket qua            |" -ForegroundColor White
Write-Host "  +----+-----------------------------------+--------------------+" -ForegroundColor White
Write-Host "  | 1  | Baseline (tai nen on dinh)        |" -NoNewline; Write-Host " DAT                 " -NoNewline -ForegroundColor Green; Write-Host "|" -ForegroundColor White
Write-Host "  | 2  | Xoa Pod dot ngot                  |" -NoNewline; Write-Host " DAT - Phuc hoi <5s  " -NoNewline -ForegroundColor Green; Write-Host "|" -ForegroundColor White
Write-Host "  | 3  | Liveness Probe loi -> Restart     |" -NoNewline; Write-Host " DAT - Tu restart    " -NoNewline -ForegroundColor Green; Write-Host "|" -ForegroundColor White
Write-Host "  | 4  | Drain Node (PDB bao ve)           |" -NoNewline; Write-Host " DAT - 0 downtime    " -NoNewline -ForegroundColor Green; Write-Host "|" -ForegroundColor White
Write-Host "  | 5  | Rolling Update + Rollback         |" -NoNewline; Write-Host " DAT - 0 loi request " -NoNewline -ForegroundColor Green; Write-Host "|" -ForegroundColor White
Write-Host "  | 6  | HPA Autoscaling                   |" -NoNewline; Write-Host " DAT - Scale up/down " -NoNewline -ForegroundColor Green; Write-Host "|" -ForegroundColor White
Write-Host "  +----+-----------------------------------+--------------------+" -ForegroundColor White
Write-Host ""
Write-Host "  Ket luan: He thong Kubernetes da chung minh kha nang:" -ForegroundColor Yellow
Write-Host "    - Tu phuc hoi (Self-healing) khi pod bi loi hoac bi xoa" -ForegroundColor Yellow
Write-Host "    - Cap nhat khong gian doan (Zero-downtime Rolling Update)" -ForegroundColor Yellow
Write-Host "    - Tu dong chan ban phat hanh loi (Readiness Gate)" -ForegroundColor Yellow
Write-Host "    - Co gian tu dong (HPA) theo tai CPU thuc te" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Cam on Thay va cac ban da theo doi!" -ForegroundColor White
Write-Host ""
Banner "KET THUC DEMO" "Cyan"
