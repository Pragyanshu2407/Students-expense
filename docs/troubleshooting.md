# Troubleshooting Guide — Student Expense Tracker

Quick reference for diagnosing and fixing the most common problems.

---

## Quick Diagnostic Checklist

Run these first whenever something isn't working:

```bash
# 1. Are all pods Running?
kubectl get pods -n expense-tracker

# 2. Any recent events (errors show here first)?
kubectl get events -n expense-tracker --sort-by=.lastTimestamp | tail -20

# 3. Is the PVC bound?
kubectl get pvc -n expense-tracker

# 4. Is the Ingress assigned an IP?
kubectl get ingress -n expense-tracker
```

---

## Application Issues

### App returns 502 Bad Gateway

**Symptom:** Browser shows 502 when opening `http://expense-tracker.local`.

**Cause:** Nginx is running but Flask pods are not ready.

```bash
# Check Flask pod status
kubectl get pods -n expense-tracker -l app=expense-web

# Read Flask logs
kubectl logs -n expense-tracker -l app=expense-web --tail=50

# Read Nginx logs to confirm it's proxying
kubectl logs -n expense-tracker -l app=expense-nginx --tail=20
```

**Fix:** Flask is probably waiting for Postgres. Check Postgres pod first (see below).

---

### App returns 404 (Ingress)

**Symptom:** Browser shows 404 or "This site can't be reached".

**Cause A:** `/etc/hosts` entry missing.
```bash
grep expense-tracker.local /etc/hosts     # should show minikube IP
echo "$(minikube ip)  expense-tracker.local" | sudo tee -a /etc/hosts
```

**Cause B:** Ingress controller not enabled.
```bash
kubectl get pods -n ingress-nginx         # should show a Running pod
minikube addons enable ingress
```

**Cause C:** Ingress has no ADDRESS.
```bash
kubectl get ingress -n expense-tracker    # ADDRESS column should have an IP
kubectl describe ingress expense-ingress -n expense-tracker
```

---

### Login always fails

**Symptom:** Correct credentials but redirected back to login.

**Cause:** `SECRET_KEY` changed between pod restarts (session cookies invalidated).

```bash
# Check the secret value is set
kubectl get secret app-secrets -n expense-tracker \
  -o jsonpath='{.data.SECRET_KEY}' | base64 --decode && echo
```

**Fix:** Ensure `SECRET_KEY` is a stable value in `k8s/secret.yaml`, not regenerated.

---

### "CSRF token missing" error

**Cause:** The app is behind a proxy but Flask doesn't know about `X-Forwarded-Proto`.

**Fix:** This is already handled — Nginx sends `X-Forwarded-Proto` and Flask is configured via `ProxyFix`. If it still occurs, check that you're accessing via the Ingress, not a direct port-forward.

---

## Database Issues

### Postgres pod in CrashLoopBackOff

```bash
kubectl logs -n expense-tracker deployment/postgres --previous
kubectl describe pod -n expense-tracker -l app=postgres
```

**Cause A:** PVC not bound.
```bash
kubectl get pvc postgres-pvc -n expense-tracker
# If STATUS=Pending:
kubectl describe pvc postgres-pvc -n expense-tracker
```

**Fix:** Check the PV exists and its `storageClassName` matches the PVC.
```bash
kubectl get pv
kubectl apply -f k8s/postgres/pv.yaml
```

**Cause B:** Data directory permissions.
```bash
kubectl exec -it -n expense-tracker deployment/postgres -- ls -la /var/lib/postgresql/
```

**Fix:** Delete the PV and PVC and recreate (data will be lost):
```bash
kubectl delete pvc postgres-pvc -n expense-tracker
kubectl delete pv postgres-pv
kubectl apply -f k8s/postgres/pv.yaml
kubectl apply -f k8s/postgres/pvc.yaml
```

---

### Flask pod stuck in Init:0/1

**Symptom:** `kubectl get pods` shows `Init:0/1` for expense-web pods.

**Cause:** The initContainer is waiting for Postgres to be ready. Postgres pod hasn't started yet or is still initializing.

```bash
# Watch all pods
kubectl get pods -n expense-tracker -w

# Check init container logs
kubectl logs -n expense-tracker <expense-web-pod-name> -c wait-for-postgres
```

**Fix:** Wait. Postgres typically takes 15–30 seconds. If it's been more than 2 minutes, check Postgres itself.

---

### "could not connect to server" in Flask logs

**Cause:** `DATABASE_URL` in `k8s/secret.yaml` has wrong hostname or password.

```bash
# Decode and print the DATABASE_URL
kubectl get secret app-secrets -n expense-tracker \
  -o jsonpath='{.data.DATABASE_URL}' | base64 --decode && echo
```

The hostname must be `postgres-svc` (the Service name), not `localhost` or `postgres`.

**Fix:** Edit `k8s/secret.yaml`, then re-apply and restart:
```bash
kubectl apply -f k8s/secret.yaml
kubectl rollout restart deployment/expense-web -n expense-tracker
```

---

## Image Pull Issues

### ImagePullBackOff

**Symptom:** Pod status shows `ImagePullBackOff` or `ErrImagePull`.

```bash
kubectl describe pod -n expense-tracker <pod-name> | grep -A 5 "Events:"
```

**Cause A:** Using a Docker Hub image that doesn't exist yet.

**Fix:** Use the local image instead:
```bash
# Load local image into Minikube
docker build -t student-expense-tracker:latest .
minikube image load student-expense-tracker:latest
```
And in `k8s/web/deployment.yaml` set `imagePullPolicy: Never`.

**Cause B:** Docker Hub rate limit (unauthenticated pulls limited to 100/6h).

**Fix:** `docker login` inside Minikube:
```bash
minikube ssh -- docker login
```

---

## CI/CD Issues

### GitHub Actions: `docker/login-action` fails

**Cause:** `DOCKERHUB_USERNAME` or `DOCKERHUB_TOKEN` secret not set.

**Fix:** Repository → Settings → Secrets and variables → Actions → New repository secret.

---

### pip-audit finds CVEs

**Symptom:** Security job fails with "X known vulnerabilities found".

**Fix:** Upgrade the affected package in `requirements.txt`:
```bash
pip-audit --fix                    # auto-upgrade if safe
pip install <package>==<new-ver>   # manual upgrade
```
Then run tests locally before pushing:
```bash
python -m pytest test_app.py -v
```

---

### ruff check fails on PR

```bash
# See exactly what failed
python -m ruff check .

# Auto-fix safe issues
python -m ruff check --fix .

# Check formatting
python -m ruff format --check .

# Auto-format
python -m ruff format .
```

---

## Monitoring Issues

### Prometheus shows no targets

```bash
# Open Prometheus UI
minikube service prometheus-svc -n expense-tracker --url
# Go to: Status → Targets
```

**Cause:** Flask pods don't have the expected labels or the scrape config is wrong.

**Fix:** Check the Flask service is reachable from Prometheus:
```bash
kubectl exec -it -n expense-tracker deployment/prometheus -- \
  wget -qO- http://expense-web-svc:5000/metrics | head -20
```

---

### Grafana shows "No data"

**Cause A:** Prometheus datasource URL is wrong.
- In Grafana UI: Connections → Data Sources → Prometheus → Test

**Cause B:** Time range is set to last 5 minutes but app just started.
- Change time range to "Last 1 hour".

**Cause C:** cAdvisor scrape failing (wrong TLS config).
```bash
# Check Prometheus logs
kubectl logs -n expense-tracker deployment/prometheus | grep -i error
```

---

### Loki shows no logs in Grafana Explore

**Cause A:** Promtail can't read pod logs (permission issue).
```bash
kubectl logs -n expense-tracker -l app=promtail | grep -i error
```

**Cause B:** Namespace filter is wrong in promtail configmap.
```bash
# Verify Promtail targets
kubectl port-forward -n expense-tracker daemonset/promtail 9080:9080 &
curl http://localhost:9080/targets
```

**Cause C:** Loki datasource not added to Grafana.
- Grafana → Connections → Add new datasource → Loki
- URL: `http://loki-svc:3100`

---

## Resource Issues (Pod Pending / OOMKilled)

### Pod stuck in Pending

```bash
kubectl describe pod -n expense-tracker <pod-name>
# Look at: Events section → "0/1 nodes are available: Insufficient memory"
```

**Fix:** Increase Minikube memory:
```bash
minikube stop
minikube start --cpus=4 --memory=4096 --driver=docker
```

### Pod OOMKilled

```bash
kubectl describe pod -n expense-tracker <pod-name>
# Look at: Last State: Reason: OOMKilled
```

**Fix:** Increase the container's memory limit in its `deployment.yaml`:
```yaml
resources:
  limits:
    memory: "512Mi"   # increase this
```

---

## Useful One-Liners

```bash
# Restart all application deployments
kubectl rollout restart deployment -n expense-tracker

# Get all resource usage (requires metrics-server)
minikube addons enable metrics-server
kubectl top pods -n expense-tracker

# Open a shell in the Flask container
kubectl exec -it -n expense-tracker deployment/expense-web -- sh

# Run psql inside Postgres
kubectl exec -it -n expense-tracker deployment/postgres -- \
  psql -U postgres -d expense_tracker

# List all tables
\dt

# Count users
SELECT COUNT(*) FROM users;

# Watch pods refresh every 2 seconds
watch -n 2 kubectl get pods -n expense-tracker

# Port-forward Flask directly (bypass Nginx and Ingress)
kubectl port-forward svc/expense-web-svc 5000:5000 -n expense-tracker
# Then open: http://localhost:5000
```
