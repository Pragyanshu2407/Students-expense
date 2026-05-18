# Deployment Guide — Student Expense Tracker

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Docker Desktop | 4.x+ | Container runtime |
| Minikube | 1.32+ | Local Kubernetes cluster |
| kubectl | 1.29+ | Kubernetes CLI |
| Git | any | Clone the repo |
| Python | 3.12+ | Local dev / running tests |

> **Windows users:** All commands below run in **WSL2** (Ubuntu terminal), not PowerShell.

---

## Option A — Docker Compose (quickest, no Kubernetes needed)

Best for: local development, quick demos.

### 1. Clone and configure

```bash
git clone https://github.com/YOUR_USERNAME/student-expense-tracker.git
cd student-expense-tracker

# Copy the example env file and edit it
cp .env.example .env
```

Edit `.env` — at minimum change these three values:
```
SECRET_KEY=any-random-string-here
POSTGRES_PASSWORD=your-db-password
DATABASE_URL=postgresql://postgres:your-db-password@db:5432/expense_tracker
```

### 2. Build and start

```bash
docker compose up --build -d
```

This starts three containers:
- `db`    — PostgreSQL 16 on port 5432 (internal only)
- `web`   — Flask/Gunicorn on port 5000 (internal only)
- `nginx` — Nginx on port **80** (exposed to host)

### 3. Open the app

```
http://localhost
```

Default admin account:
- **Username:** `admin`
- **Password:** `admin123`

### 4. Stop

```bash
docker compose down          # stop containers, keep data
docker compose down -v       # stop containers + delete database volume
```

---

## Option B — Kubernetes on Minikube (full production-like setup)

### Step 1 — Start Minikube

```bash
minikube start --cpus=2 --memory=4096 --driver=docker
```

> `--memory=4096` is recommended when also running the monitoring stack.
> Minimum without monitoring: `--memory=2048`.

### Step 2 — Enable the Ingress addon

```bash
minikube addons enable ingress

# Wait until the ingress controller pod is Running (~60-90 seconds)
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

### Step 3 — Build and load the Docker image

```bash
# Build the image
docker build -t student-expense-tracker:latest .

# Load it into the Minikube VM (so K8s can pull it without Docker Hub)
minikube image load student-expense-tracker:latest
```

### Step 4 — Configure secrets

```bash
cp k8s/secret.yaml.example k8s/secret.yaml   # if example exists, else edit directly
nano k8s/secret.yaml
```

Fill in these fields in `k8s/secret.yaml`:
```yaml
stringData:
  POSTGRES_PASSWORD: "your-strong-password"
  SECRET_KEY: "run: python -c \"import secrets; print(secrets.token_hex(32))\""
  DATABASE_URL: "postgresql://postgres:your-strong-password@postgres-svc:5432/expense_tracker"
  ADMIN_PASSWORD: "your-admin-password"
```

> `k8s/secret.yaml` is gitignored — it will never be committed.

Also update the image name in `k8s/web/deployment.yaml`:
```yaml
image: student-expense-tracker:latest   # local image (already done)
# OR for Docker Hub:
image: YOUR_DOCKERHUB_USERNAME/student-expense-tracker:latest
```

### Step 5 — Deploy the application

```bash
bash k8s/deploy.sh deploy
```

This applies all manifests in dependency order and waits for each rollout:
1. Namespace
2. ConfigMap + Secret
3. Postgres PV + PVC + Deployment + Service
4. Flask web Deployment + Service
5. Nginx ConfigMap + Deployment + Service
6. Ingress

### Step 6 — Add /etc/hosts entry

```bash
echo "$(minikube ip)  expense-tracker.local" | sudo tee -a /etc/hosts
```

> **Windows (WSL2):** also run this in PowerShell as Administrator:
> ```powershell
> Add-Content -Path C:\Windows\System32\drivers\etc\hosts `
>   "$(minikube ip)  expense-tracker.local"
> ```

### Step 7 — Open the app

```
http://expense-tracker.local
```

---

## Option C — Deploy Monitoring Stack (after Option B)

```bash
bash k8s/monitoring/deploy.sh deploy
```

This deploys: Prometheus → Grafana → Loki → Promtail (in order).

Access URLs after deployment:

| Service | URL | Credentials |
|---|---|---|
| Grafana | `http://$(minikube ip):30300` | admin / grafana123 |
| Prometheus | `http://$(minikube ip):30900` | none |
| Loki health | `http://$(minikube ip):30310/ready` | none |

Or use the Minikube service tunnel (useful on WSL2):
```bash
minikube service grafana-svc -n expense-tracker --url
```

---

## CI/CD — GitHub Actions

The pipeline runs automatically on every push and pull request.

### Required GitHub Secrets

Go to: **Repository → Settings → Secrets and variables → Actions**

| Secret name | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token (not your password) |

> Get a Docker Hub token: hub.docker.com → Account Settings → Security → New Access Token

### Pipeline jobs

```
push/PR
  └── lint         (ruff check + format)
        └── security  (bandit + pip-audit CVE scan)
              └── test     (pytest, 17 tests, SQLite in-memory)
                    └── docker-build  (build + smoke test + Trivy scan)

push to main / v*.*.* tag
  └── check-ci  (gates on CI success)
        └── push-image  (multi-arch build → Docker Hub + Trivy post-push scan)
```

### Branch protection (recommended settings)

In **Repository → Settings → Branches → Add rule** for `main`:
- Require status checks: `lint`, `security`, `test`, `docker-build`
- Require branches to be up to date before merging
- Require pull request reviews: 1

---

## Rolling Updates (Kubernetes)

To deploy a new version without downtime:

```bash
# Update the image tag
bash k8s/deploy.sh update v1.2.3

# OR manually:
kubectl set image deployment/expense-web \
  expense-web=YOUR_DOCKERHUB_USERNAME/student-expense-tracker:v1.2.3 \
  -n expense-tracker

# Watch the rollout
kubectl rollout status deployment/expense-web -n expense-tracker

# Rollback if something goes wrong
kubectl rollout undo deployment/expense-web -n expense-tracker
```

The Deployment uses `maxUnavailable: 0` — new pods are started before old ones are removed, guaranteeing zero-downtime.

---

## Teardown

```bash
# Remove monitoring stack only
bash k8s/monitoring/deploy.sh teardown

# Remove entire application (all namespaced resources)
bash k8s/deploy.sh teardown

# Completely wipe Minikube (loses all data)
minikube delete
```
