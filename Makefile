# ==============================================================================
#  Makefile - Dieu khien nhanh De tai 26 tren TV tai lop
# ==============================================================================
.PHONY: help setup demo k6-steady delete-pod fail-health drain rollout-v2 rollout-bad rollback-v1 hpa-spike restore teardown

help:
	@echo "De tai 26 - Cac lenh dieu khien nhanh:"
	@echo "  make demo          - Mo menu dieu khien 1 phim bam (demo.sh)"
	@echo "  make k6-steady     - Phim 1: Ban tai nen k6 + k6 Web Dashboard (:5665)"
	@echo "  make delete-pod    - Phim 2a: Xoa dot ngot 1 Pod & do thoi gian phuc hoi"
	@echo "  make fail-health   - Phim 2b: Gay loi /fail-health kiem chung Liveness/Readiness"
	@echo "  make drain         - Phim 3: Drain 1 Worker Node kiem chung PDB"
	@echo "  make rollout-v2    - Phim 4a: Cap nhat khong gian doan v1 -> v2"
	@echo "  make rollout-bad   - Phim 4b: Tung ban loi v2-bad & tu dong Rollback"
	@echo "  make hpa-spike     - Phim 5: Tang tai dot bien kich hoat HPA Scale Up"
	@echo "  make restore       - Dua Deployment ve cau hinh chuan v1"

demo:
	bash scripts/demo.sh

k6-steady:
	K6_WEB_DASHBOARD=true k6 run load-test/steady.js

delete-pod:
	bash scripts/chaos-pod-delete.sh pod

fail-health:
	curl -i -H "Host: selfhealing.local" http://localhost/fail-health

drain:
	bash scripts/chaos-pod-delete.sh drain

rollout-v2:
	kubectl set image deployment/selfhealing-demo app=selfhealing-demo:v2
	kubectl rollout status deployment/selfhealing-demo --timeout=60s

rollout-bad:
	bash scripts/rollout-fail.sh

restore:
	kubectl apply -f k8s/base/deployment.yaml
	kubectl rollout status deployment/selfhealing-demo --timeout=90s

hpa-spike:
	K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_PORT=5666 k6 run load-test/hpa-spike.js
