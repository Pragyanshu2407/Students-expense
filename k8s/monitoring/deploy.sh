#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Monitoring stack deployment for Student Expense Tracker
#
# Deploys:  Prometheus → Grafana → Loki → Promtail
#
# Prerequisites:
#   - Minikube running with expense-tracker namespace deployed (Phase 4)
#   - kubectl pointing to Minikube context
#
# Usage:
#   chmod +x k8s/monitoring/deploy.sh
#   bash k8s/monitoring/deploy.sh deploy      # deploy the full stack
#   bash k8s/monitoring/deploy.sh verify      # check all pods are running
#   bash k8s/monitoring/deploy.sh access      # print URLs to open in browser
#   bash k8s/monitoring/deploy.sh logs        # show how to view logs in Grafana
#   bash k8s/monitoring/deploy.sh teardown    # remove all monitoring resources
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

NAMESPACE="expense-tracker"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# DEPLOY — apply all monitoring manifests in order
# =============================================================================

deploy() {
  info "Deploying monitoring stack to namespace: $NAMESPACE"

  # ── Check namespace exists ────────────────────────────────────────────────
  if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    error "Namespace $NAMESPACE not found. Deploy Phase 4 first: bash k8s/deploy.sh deploy"
  fi

  # ── Prometheus ─────────────────────────────────────────────────────────────
  info "Deploying Prometheus..."
  # RBAC must be applied BEFORE the Deployment — the pod uses the ServiceAccount
  # on startup and will fail with 403 errors if ClusterRoleBinding isn't ready.
  kubectl apply -f "$SCRIPT_DIR/prometheus/rbac.yaml"
  kubectl apply -f "$SCRIPT_DIR/prometheus/configmap.yaml"
  kubectl apply -f "$SCRIPT_DIR/prometheus/pvc.yaml"
  kubectl apply -f "$SCRIPT_DIR/prometheus/deployment.yaml"
  kubectl apply -f "$SCRIPT_DIR/prometheus/service.yaml"

  info "Waiting for Prometheus to be ready (up to 120s)..."
  kubectl rollout status deployment/prometheus -n "$NAMESPACE" --timeout=120s

  # ── Grafana ────────────────────────────────────────────────────────────────
  info "Deploying Grafana..."
  kubectl apply -f "$SCRIPT_DIR/grafana/secret.yaml"
  kubectl apply -f "$SCRIPT_DIR/grafana/configmap.yaml"
  kubectl apply -f "$SCRIPT_DIR/grafana/dashboard-configmap.yaml"
  kubectl apply -f "$SCRIPT_DIR/grafana/pvc.yaml"
  kubectl apply -f "$SCRIPT_DIR/grafana/deployment.yaml"
  kubectl apply -f "$SCRIPT_DIR/grafana/service.yaml"

  info "Waiting for Grafana to be ready (up to 120s)..."
  kubectl rollout status deployment/grafana -n "$NAMESPACE" --timeout=120s

  # ── Loki ──────────────────────────────────────────────────────────────────
  info "Deploying Loki (log store)..."
  kubectl apply -f "$SCRIPT_DIR/loki/configmap.yaml"
  kubectl apply -f "$SCRIPT_DIR/loki/pvc.yaml"
  kubectl apply -f "$SCRIPT_DIR/loki/deployment.yaml"
  kubectl apply -f "$SCRIPT_DIR/loki/service.yaml"

  info "Waiting for Loki to be ready (up to 120s)..."
  kubectl rollout status deployment/loki -n "$NAMESPACE" --timeout=120s

  # ── Promtail ──────────────────────────────────────────────────────────────
  info "Deploying Promtail (log agent)..."
  # RBAC first — Promtail uses the ServiceAccount to call the K8s API
  kubectl apply -f "$SCRIPT_DIR/promtail/rbac.yaml"
  kubectl apply -f "$SCRIPT_DIR/promtail/configmap.yaml"
  kubectl apply -f "$SCRIPT_DIR/promtail/daemonset.yaml"

  info "Waiting for Promtail DaemonSet to be ready (up to 120s)..."
  # DaemonSets use rollout status differently — wait until all desired pods are ready
  kubectl rollout status daemonset/promtail -n "$NAMESPACE" --timeout=120s

  # ── Add Loki datasource to Grafana ────────────────────────────────────────
  # Grafana's Loki datasource is NOT auto-provisioned because the Loki URL
  # can vary. Add it once via the API after both pods are ready.
  info "Adding Loki datasource to Grafana..."
  GRAFANA_URL="http://$(minikube ip):30300"

  # Wait for Grafana API to be reachable
  for i in $(seq 1 12); do
    if curl -sf "$GRAFANA_URL/api/health" >/dev/null 2>&1; then
      break
    fi
    warn "Grafana API not ready yet ($i/12)... retrying in 5s"
    sleep 5
  done

  # POST the Loki datasource via Grafana HTTP API
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$GRAFANA_URL/api/datasources" \
    -u "admin:grafana123" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Loki",
      "type": "loki",
      "url": "http://loki-svc:3100",
      "access": "proxy",
      "isDefault": false
    }')

  if [[ "$HTTP_STATUS" == "200" ]] || [[ "$HTTP_STATUS" == "409" ]]; then
    # 200 = created, 409 = already exists — both are fine
    info "Loki datasource configured in Grafana."
  else
    warn "Could not auto-configure Loki datasource (HTTP $HTTP_STATUS)."
    warn "Add it manually: Grafana → Connections → Add new datasource → Loki"
    warn "  URL: http://loki-svc:3100"
  fi

  info "✓ Monitoring stack deployed successfully!"
  echo ""
  access
}

# =============================================================================
# VERIFY — show pod and PVC status
# =============================================================================

verify() {
  info "=== Monitoring pods ==="
  # Show only monitoring pods
  kubectl get pods -n "$NAMESPACE" -l 'app in (prometheus,grafana,loki,promtail)'

  echo ""
  info "=== Monitoring PVCs ==="
  kubectl get pvc -n "$NAMESPACE" | grep -E 'NAME|prometheus|grafana|loki'

  echo ""
  info "=== Monitoring services ==="
  kubectl get services -n "$NAMESPACE" | grep -E 'NAME|prometheus|grafana|loki'

  echo ""
  info "=== Promtail DaemonSet ==="
  kubectl get daemonset promtail -n "$NAMESPACE"
}

# =============================================================================
# ACCESS — print URLs for browser access
# =============================================================================

access() {
  MINIKUBE_IP=$(minikube ip)
  echo ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  Monitoring URLs"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Grafana (dashboards + logs):"
  echo "    http://$MINIKUBE_IP:30300"
  echo "    Login: admin / grafana123"
  echo ""
  echo "  Prometheus (raw metrics browser):"
  echo "    http://$MINIKUBE_IP:30900"
  echo ""
  echo "  Loki (health check):"
  echo "    http://$MINIKUBE_IP:30310/ready"
  echo ""
  info "  Or use minikube service tunnels (WSL2 / no direct IP access):"
  echo "    minikube service grafana-svc     -n $NAMESPACE --url"
  echo "    minikube service prometheus-svc  -n $NAMESPACE --url"
  echo ""
}

# =============================================================================
# LOGS — guide for viewing logs in Grafana / kubectl
# =============================================================================

logs() {
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  How to View Logs"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  echo "
── Option A: Grafana → Explore (LogQL) ──────────────────────────────────────

  1. Open Grafana: http://$(minikube ip):30300
  2. Click  Explore  (compass icon in the left sidebar)
  3. Select datasource: Loki
  4. Use these LogQL queries:

  # All logs from the Flask app
  {namespace=\"expense-tracker\", app=\"expense-web\"}

  # Only ERROR and WARNING logs
  {namespace=\"expense-tracker\", app=\"expense-web\"} | json | level=~\"ERROR|WARNING\"

  # Authentication events (login/logout)
  {namespace=\"expense-tracker\", app=\"expense-web\"} |= \"auth\"

  # Filter by specific logger (Python module)
  {namespace=\"expense-tracker\", app=\"expense-web\"} | json | logger=\"tracker.auth\"

  # Show all logs from all pods in the namespace
  {namespace=\"expense-tracker\"}

  # Count ERROR logs per minute (metric query from logs)
  sum(rate({namespace=\"expense-tracker\"} | json | level=\"ERROR\" [1m])) by (app)

── Option B: Grafana Dashboard ───────────────────────────────────────────────

  1. Open Grafana: http://$(minikube ip):30300
  2. Click  Dashboards → Student Expense Tracker

  The dashboard shows:
    • Request rate, error rate, P95 latency
    • Flask and Postgres CPU/memory usage
    • Stat panels: current RPS, P95, error rate, memory

── Option C: kubectl (no Grafana needed) ────────────────────────────────────

  # Tail Flask app logs (all replicas, last 50 lines)
  kubectl logs -n $NAMESPACE -l app=expense-web -f --tail=50

  # Tail Nginx logs
  kubectl logs -n $NAMESPACE -l app=expense-nginx -f --tail=50

  # Tail Postgres logs
  kubectl logs -n $NAMESPACE -l app=postgres -f --tail=50

  # Logs from a specific pod
  kubectl logs -n $NAMESPACE <pod-name> -f

  # Previous container logs (after a crash)
  kubectl logs -n $NAMESPACE <pod-name> --previous

── Option D: Prometheus query browser ────────────────────────────────────────

  Open: http://$(minikube ip):30900

  Useful queries to try:

  # Total HTTP requests received (all time)
  flask_http_request_total

  # Request rate per second (last 5 minutes)
  rate(flask_http_request_total[5m])

  # P95 response time in seconds
  histogram_quantile(0.95, rate(flask_http_request_duration_seconds_bucket[5m]))

  # Flask container CPU usage (fraction of a core)
  rate(container_cpu_usage_seconds_total{container=\"expense-web\"}[5m])

  # Flask container memory (bytes)
  container_memory_working_set_bytes{container=\"expense-web\"}

  # Number of healthy Flask pods
  count(up{job=\"flask-app\"} == 1)

── How to analyze a failure ──────────────────────────────────────────────────

  1. Check if the pod is running:
     kubectl get pods -n $NAMESPACE

  2. If CrashLoopBackOff — read the crash logs:
     kubectl logs -n $NAMESPACE <pod> --previous

  3. If pod won't start — read the events:
     kubectl describe pod -n $NAMESPACE <pod>

  4. Check Prometheus for the error spike:
     rate(flask_http_request_total{status=~\"5..\"}[5m])

  5. Find the exact error in Loki (Grafana → Explore):
     {app=\"expense-web\"} | json | level=\"ERROR\"

  6. Correlate with deployment timing:
     kubectl rollout history deployment/expense-web -n $NAMESPACE
"
}

# =============================================================================
# TEARDOWN — remove all monitoring resources
# =============================================================================

teardown() {
  warn "This will delete all monitoring resources (Prometheus, Grafana, Loki, Promtail)."
  warn "Application deployments (Flask, Postgres, Nginx) are NOT affected."
  read -r -p "Are you sure? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    info "Aborted."
    return
  fi

  info "Removing monitoring stack..."

  kubectl delete -f "$SCRIPT_DIR/promtail/daemonset.yaml"   --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/promtail/configmap.yaml"   --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/promtail/rbac.yaml"        --ignore-not-found

  kubectl delete -f "$SCRIPT_DIR/loki/service.yaml"         --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/loki/deployment.yaml"      --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/loki/pvc.yaml"             --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/loki/configmap.yaml"       --ignore-not-found

  kubectl delete -f "$SCRIPT_DIR/grafana/service.yaml"      --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/grafana/deployment.yaml"   --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/grafana/pvc.yaml"          --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/grafana/dashboard-configmap.yaml" --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/grafana/configmap.yaml"    --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/grafana/secret.yaml"       --ignore-not-found

  kubectl delete -f "$SCRIPT_DIR/prometheus/service.yaml"   --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/prometheus/deployment.yaml" --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/prometheus/pvc.yaml"       --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/prometheus/configmap.yaml" --ignore-not-found
  kubectl delete -f "$SCRIPT_DIR/prometheus/rbac.yaml"      --ignore-not-found

  info "Monitoring stack removed."
}

# =============================================================================
# MAIN
# =============================================================================

case "${1:-deploy}" in
  deploy)    deploy    ;;
  verify)    verify    ;;
  access)    access    ;;
  logs)      logs      ;;
  teardown)  teardown  ;;
  *)
    echo "Usage: $0 {deploy|verify|access|logs|teardown}"
    exit 1
    ;;
esac
