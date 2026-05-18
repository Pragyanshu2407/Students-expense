#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Full Kubernetes deployment runbook for Student Expense Tracker
#
# Run each section step-by-step.  This script is intentionally NOT executed
# as a whole (set -e would stop on any error).  Copy-paste the commands you
# need, or source individual sections.
#
# Usage:
#   chmod +x k8s/deploy.sh
#   bash k8s/deploy.sh          # runs the DEPLOY section automatically
# =============================================================================

set -euo pipefail

# ── Colours for pretty output ─────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

NAMESPACE="expense-tracker"

# =============================================================================
# SECTION 0 — Prerequisites
# =============================================================================
# Run these ONCE before deploying.

prereqs() {
  info "Checking prerequisites..."

  # 1. Start Minikube (if not already running)
  #    --cpus 2 and --memory 2048 are the MINIMUM for this stack
  #    --driver=docker uses Docker Desktop as the VM (best for WSL2 + Windows)
  minikube start --cpus=2 --memory=2048 --driver=docker

  # 2. Enable the Nginx Ingress controller addon
  #    This installs an nginx-based ingress controller into the cluster.
  minikube addons enable ingress

  # 3. Verify the ingress controller pod is Running (may take 60–90 s)
  #    -n ingress-nginx  → look in the ingress-nginx namespace
  #    --timeout=120s    → wait up to 2 minutes for the pod to become ready
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s

  info "Prerequisites OK."
}

# =============================================================================
# SECTION 1 — Edit secret.yaml BEFORE deploying
# =============================================================================
# Replace placeholder values with real secrets.
#
#   nano k8s/secret.yaml
#   # or: vim k8s/secret.yaml
#
# Required fields to change:
#   POSTGRES_PASSWORD  →  any strong password (e.g. "Tr0ub4dor&3")
#   SECRET_KEY         →  python -c "import secrets; print(secrets.token_hex(32))"
#   DATABASE_URL       →  update the password part to match POSTGRES_PASSWORD
#   ADMIN_PASSWORD     →  password for the default admin account
#
# Also replace YOUR_DOCKERHUB_USERNAME in k8s/web/deployment.yaml with your
# Docker Hub username (e.g. pragyanshu/student-expense-tracker:latest).

# =============================================================================
# SECTION 2 — Deploy (apply all manifests in dependency order)
# =============================================================================

deploy() {
  info "Deploying to namespace: $NAMESPACE"

  # ── Namespace ───────────────────────────────────────────────────────────────
  # Creates the "expense-tracker" namespace.
  # kubectl apply is idempotent — safe to run multiple times.
  kubectl apply -f k8s/namespace.yaml

  # ── ConfigMap and Secret ───────────────────────────────────────────────────
  # Apply these before Deployments because pods reference them at startup.
  # If a ConfigMap or Secret is missing, the pod will fail with CreateContainerConfigError.
  kubectl apply -f k8s/configmap.yaml
  kubectl apply -f k8s/secret.yaml

  # ── Persistent storage for Postgres ───────────────────────────────────────
  # PV is cluster-scoped (no namespace needed), PVC is namespace-scoped.
  # Apply PV first so the PVC can bind to it immediately.
  kubectl apply -f k8s/postgres/pv.yaml
  kubectl apply -f k8s/postgres/pvc.yaml

  # Verify PVC bound before continuing
  # STATUS must be "Bound" — if "Pending", check `kubectl describe pvc postgres-pvc -n expense-tracker`
  kubectl get pvc -n "$NAMESPACE"

  # ── PostgreSQL ─────────────────────────────────────────────────────────────
  kubectl apply -f k8s/postgres/deployment.yaml
  kubectl apply -f k8s/postgres/service.yaml

  # Wait until Postgres is ready — Flask needs it before it can start
  info "Waiting for Postgres to be ready..."
  kubectl rollout status deployment/postgres -n "$NAMESPACE" --timeout=120s

  # ── Flask / Gunicorn ────────────────────────────────────────────────────────
  kubectl apply -f k8s/web/deployment.yaml
  kubectl apply -f k8s/web/service.yaml

  info "Waiting for Flask app to be ready..."
  kubectl rollout status deployment/expense-web -n "$NAMESPACE" --timeout=180s

  # ── Nginx reverse proxy ─────────────────────────────────────────────────────
  kubectl apply -f k8s/nginx/configmap.yaml
  kubectl apply -f k8s/nginx/deployment.yaml
  kubectl apply -f k8s/nginx/service.yaml

  info "Waiting for Nginx to be ready..."
  kubectl rollout status deployment/expense-nginx -n "$NAMESPACE" --timeout=60s

  # ── Ingress ─────────────────────────────────────────────────────────────────
  kubectl apply -f k8s/ingress.yaml

  info "Done! Run the ACCESS section to open the app."
}

# =============================================================================
# SECTION 3 — Verify deployment
# =============================================================================

verify() {
  info "=== Namespace resources ==="
  # Shows all pods, services, deployments in one view
  # -n expense-tracker → only this namespace
  kubectl get all -n "$NAMESPACE"

  echo ""
  info "=== PersistentVolumes ==="
  # PVs are cluster-scoped (no -n flag)
  kubectl get pv

  echo ""
  info "=== PersistentVolumeClaims ==="
  kubectl get pvc -n "$NAMESPACE"

  echo ""
  info "=== Ingress ==="
  kubectl get ingress -n "$NAMESPACE"

  echo ""
  info "=== Pod resource usage (requires metrics-server) ==="
  # Enable metrics: minikube addons enable metrics-server
  kubectl top pods -n "$NAMESPACE" 2>/dev/null || warn "metrics-server not enabled — run: minikube addons enable metrics-server"
}

# =============================================================================
# SECTION 4 — Access the app
# =============================================================================

access() {
  MINIKUBE_IP=$(minikube ip)
  info "Minikube IP: $MINIKUBE_IP"

  # Option A — Add /etc/hosts entry (Linux/macOS)
  # This lets your browser resolve http://expense-tracker.local
  if ! grep -q "expense-tracker.local" /etc/hosts 2>/dev/null; then
    warn "Add this line to /etc/hosts (requires sudo):"
    echo "  echo '$MINIKUBE_IP  expense-tracker.local' | sudo tee -a /etc/hosts"
  else
    info "expense-tracker.local already in /etc/hosts"
  fi

  echo ""

  # Option B — Use minikube service (bypasses Ingress, opens NodePort directly)
  # Useful for quick testing without editing /etc/hosts
  info "Quick access (NodePort tunnel):"
  echo "  minikube service expense-nginx-svc -n $NAMESPACE --url"

  # Option C — Port-forward directly to the Flask pod
  info "Direct port-forward to Flask (no Nginx):"
  echo "  kubectl port-forward svc/expense-web-svc 5000:5000 -n $NAMESPACE"
  echo "  Then open: http://localhost:5000"
}

# =============================================================================
# SECTION 5 — Scaling
# =============================================================================
# Kubernetes makes scaling trivial.  These commands work live — no downtime.

scaling_examples() {
  info "--- Scaling examples ---"

  # Scale Flask to 4 replicas (more capacity)
  # kubectl scale deployment/expense-web --replicas=4 -n "$NAMESPACE"

  # Scale Flask back to 2
  # kubectl scale deployment/expense-web --replicas=2 -n "$NAMESPACE"

  # Scale Nginx to 3 replicas
  # kubectl scale deployment/expense-nginx --replicas=3 -n "$NAMESPACE"

  # Watch pods scale up/down in real time (Ctrl+C to stop)
  # kubectl get pods -n "$NAMESPACE" -l app=expense-web -w

  # HorizontalPodAutoscaler — auto-scale based on CPU usage
  # Requires: minikube addons enable metrics-server
  #
  # kubectl autoscale deployment expense-web \
  #   --namespace "$NAMESPACE" \
  #   --cpu-percent=70 \    # target CPU utilisation
  #   --min=2 \             # minimum replicas
  #   --max=6               # maximum replicas
  #
  # kubectl get hpa -n "$NAMESPACE"
  # kubectl describe hpa expense-web -n "$NAMESPACE"
  # kubectl delete hpa expense-web -n "$NAMESPACE"  # remove autoscaler

  echo "Uncomment and run the commands above as needed."
}

# =============================================================================
# SECTION 6 — Rolling updates
# =============================================================================

rolling_update() {
  NEW_TAG="${1:-latest}"
  info "Updating Flask image to tag: $NEW_TAG"

  # Update the container image — triggers an automatic rolling update.
  # Kubernetes: starts new pods → waits for readiness → removes old pods.
  # Zero downtime because maxUnavailable: 0 in the Deployment strategy.
  kubectl set image deployment/expense-web \
    expense-web="YOUR_DOCKERHUB_USERNAME/student-expense-tracker:$NEW_TAG" \
    -n "$NAMESPACE"

  # Watch the rollout progress
  kubectl rollout status deployment/expense-web -n "$NAMESPACE"

  # Rollout history — shows all previous versions
  # kubectl rollout history deployment/expense-web -n "$NAMESPACE"

  # ROLLBACK — instantly revert to the previous version
  # kubectl rollout undo deployment/expense-web -n "$NAMESPACE"

  # Rollback to a specific revision number
  # kubectl rollout undo deployment/expense-web --to-revision=2 -n "$NAMESPACE"
}

# =============================================================================
# SECTION 7 — Troubleshooting
# =============================================================================

troubleshoot() {
  info "--- Troubleshooting cheatsheet ---"

  echo "
# ── Pod status ────────────────────────────────────────────────────────────────

# List all pods with status
kubectl get pods -n $NAMESPACE

# Wide output — shows which NODE each pod is on and its IP
kubectl get pods -n $NAMESPACE -o wide

# Watch pods in real time (updates every few seconds)
kubectl get pods -n $NAMESPACE -w

# ── Pod logs ─────────────────────────────────────────────────────────────────

# Tail logs from a specific deployment (all pods)
kubectl logs -n $NAMESPACE -l app=expense-web -f --tail=50

# Logs from a single pod
kubectl logs -n $NAMESPACE <pod-name> -f

# Logs from a CRASHED pod (the previous container instance)
kubectl logs -n $NAMESPACE <pod-name> --previous

# ── Pod details ───────────────────────────────────────────────────────────────

# Full details including events — first thing to check when a pod won't start
kubectl describe pod -n $NAMESPACE <pod-name>

# Describe a deployment — shows replica count, image, strategy, events
kubectl describe deployment expense-web -n $NAMESPACE

# ── Shell access ──────────────────────────────────────────────────────────────

# Open a shell inside a running Flask pod
kubectl exec -it -n $NAMESPACE deployment/expense-web -- sh

# Open a shell inside a Postgres pod
kubectl exec -it -n $NAMESPACE deployment/postgres -- sh

# Run psql inside the Postgres pod
kubectl exec -it -n $NAMESPACE deployment/postgres -- \
  psql -U postgres -d expense_tracker

# ── Service and networking ─────────────────────────────────────────────────────

# List all services
kubectl get services -n $NAMESPACE

# Show which pods a service is routing to (endpoints)
kubectl get endpoints -n $NAMESPACE

# Test connectivity between pods (temporary debug pod)
kubectl run curl-test --image=curlimages/curl --rm -it \
  --restart=Never -n $NAMESPACE -- \
  curl http://expense-web-svc:5000/health

# ── ConfigMap and Secret ──────────────────────────────────────────────────────

# View ConfigMap values
kubectl get configmap app-config -n $NAMESPACE -o yaml

# View Secret keys (values are base64-encoded — use the decode command below)
kubectl get secret app-secrets -n $NAMESPACE -o yaml

# Decode a specific secret value
kubectl get secret app-secrets -n $NAMESPACE \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode && echo

# ── Events ────────────────────────────────────────────────────────────────────

# All events in the namespace, sorted by time (most recent last)
kubectl get events -n $NAMESPACE --sort-by=.lastTimestamp

# Events for a specific pod only
kubectl describe pod -n $NAMESPACE <pod-name> | grep -A 20 Events:

# ── Resource usage ────────────────────────────────────────────────────────────

# CPU and memory per pod (requires metrics-server)
kubectl top pods -n $NAMESPACE

# CPU and memory per node
kubectl top nodes

# ── Common problems and fixes ─────────────────────────────────────────────────

# Problem: Pod stuck in Pending
# Cause:   Not enough CPU/memory on the node, or PVC not bound
# Fix:     kubectl describe pod <name> -n $NAMESPACE  (look at Events section)
#          kubectl get pvc -n $NAMESPACE              (check if Bound)

# Problem: Pod in CrashLoopBackOff
# Cause:   App crashes on startup (config error, DB unreachable, etc.)
# Fix:     kubectl logs <pod> -n $NAMESPACE --previous
#          kubectl describe pod <pod> -n $NAMESPACE

# Problem: ImagePullBackOff
# Cause:   Docker Hub image not found, wrong name, or not logged in
# Fix:     Check image name in deployment.yaml
#          For local images: minikube image load student-expense-tracker:latest
#          Then set imagePullPolicy: Never in deployment.yaml

# Problem: Ingress returns 404 or no address
# Cause:   Ingress addon not enabled, or /etc/hosts entry missing
# Fix:     minikube addons enable ingress
#          kubectl get ingress -n $NAMESPACE  (ADDRESS column should have an IP)
#          Add: echo \"\$(minikube ip)  expense-tracker.local\" | sudo tee -a /etc/hosts
"
}

# =============================================================================
# SECTION 8 — Teardown
# =============================================================================

teardown() {
  warn "This will delete all resources in the $NAMESPACE namespace."
  read -r -p "Are you sure? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    info "Aborted."
    return
  fi

  # Delete the entire namespace — removes ALL resources inside it at once
  # (Deployments, Services, ConfigMaps, Secrets, PVCs, etc.)
  kubectl delete namespace "$NAMESPACE"

  # The PV is cluster-scoped and NOT deleted with the namespace.
  # Delete it manually if you want to wipe the Postgres data:
  kubectl delete pv postgres-pv
  warn "PV deleted. Postgres data at /data/postgres on the Minikube VM is now available for reuse."

  # To fully wipe everything including the Minikube VM:
  # minikube delete
}

# =============================================================================
# MAIN — run deploy by default
# =============================================================================

case "${1:-deploy}" in
  prereqs)   prereqs   ;;
  deploy)    deploy    ;;
  verify)    verify    ;;
  access)    access    ;;
  scaling)   scaling_examples ;;
  update)    rolling_update "${2:-latest}" ;;
  troubleshoot) troubleshoot ;;
  teardown)  teardown  ;;
  *)
    echo "Usage: $0 {prereqs|deploy|verify|access|scaling|update|troubleshoot|teardown}"
    exit 1
    ;;
esac
