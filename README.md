# Student Expense Tracker

A production-grade DevOps project demonstrating the full lifecycle from application development to Kubernetes deployment and observability.

---

## Project Overview

A web application where students can track their expenses and admins can manage users and data — built as a vehicle to demonstrate six DevOps phases:

| Phase | What was built |
|---|---|
| 1 | Flask app with PostgreSQL, authentication, and role-based access control |
| 2 | Production Docker setup — multi-stage build, docker-compose, Nginx, health checks |
| 3 | GitHub Actions CI/CD — linting, security scanning, automated tests, Docker Hub publishing |
| 4 | Kubernetes deployment on Minikube — 15+ manifests, rolling updates, probes, Ingress |
| 5 | Observability — Prometheus metrics, Grafana dashboards, Loki + Promtail log aggregation |
| 6 | Documentation — architecture diagrams, deployment guide, troubleshooting, viva Q&A |

---

## Quick Start

### Option A — Docker Compose (5 minutes)

```bash
git clone https://github.com/YOUR_USERNAME/student-expense-tracker.git
cd student-expense-tracker
cp .env.example .env          # edit SECRET_KEY and POSTGRES_PASSWORD
docker compose up --build -d
open http://localhost          # or: start http://localhost on Windows
```

Login: `admin` / `admin123`

### Option B — Kubernetes (Minikube)

```bash
# 1. Start cluster
minikube start --cpus=2 --memory=4096 --driver=docker
minikube addons enable ingress

# 2. Build and load image
docker build -t student-expense-tracker:latest .
minikube image load student-expense-tracker:latest

# 3. Configure secrets
cp k8s/secret.yaml.example k8s/secret.yaml   # fill in passwords
# Edit k8s/web/deployment.yaml — update image name

# 4. Deploy
bash k8s/deploy.sh deploy

# 5. Add /etc/hosts entry
echo "$(minikube ip)  expense-tracker.local" | sudo tee -a /etc/hosts

# 6. Open
open http://expense-tracker.local
```

### Option C — Add Monitoring (after Option B)

```bash
bash k8s/monitoring/deploy.sh deploy
# Grafana:    http://$(minikube ip):30300   (admin/grafana123)
# Prometheus: http://$(minikube ip):30900
```

---

## Project Structure

```
student-expense-tracker/
│
├── tracker/                        # Flask application package
│   ├── __init__.py                 # App factory, Prometheus metrics init
│   ├── models.py                   # SQLAlchemy models: User, Expense
│   ├── auth.py                     # Blueprint: /auth/login, /register, /logout
│   ├── student.py                  # Blueprint: /student/dashboard, /delete
│   ├── admin.py                    # Blueprint: /admin/dashboard, delete user/expense
│   ├── main.py                     # Blueprint: /, /health
│   └── templates/
│       ├── base.html               # Bootstrap 5 layout, navbar, flash messages
│       ├── auth/                   # login.html, register.html
│       ├── student/                # dashboard.html (add/view/delete own expenses)
│       └── admin/                  # dashboard.html (manage all users & expenses)
│
├── config.py                       # DevelopmentConfig, TestingConfig, ProductionConfig
├── run.py                          # Entry point — DB init, JSON logging, app creation
├── app.py                          # Thin shim for gunicorn: app = create_app()
├── gunicorn.conf.py                # Worker config, on_starting hook (DB init + seed)
├── test_app.py                     # 17 pytest tests (SQLite in-memory)
│
├── Dockerfile                      # 3-stage: base → builder → app (non-root, ~150MB)
├── docker-compose.yml              # db + web + nginx (health-check-gated startup)
├── nginx/nginx.conf                # Rate limiting, security headers, gzip
│
├── requirements.txt                # Production dependencies (pinned versions)
├── requirements-dev.txt            # Linting/security tools: ruff, bandit, pip-audit
├── ruff.toml                       # Ruff linter config
├── .env.example                    # Environment variable template
├── .dockerignore                   # Excludes __pycache__, .env, tests from image
├── .gitignore                      # Excludes .env, *.db, k8s/secret.yaml
│
├── k8s/                            # Kubernetes manifests
│   ├── namespace.yaml
│   ├── configmap.yaml              # Non-secret env vars
│   ├── secret.yaml                 # [gitignored] Passwords, SECRET_KEY
│   ├── ingress.yaml                # expense-tracker.local → expense-nginx-svc
│   ├── postgres/
│   │   ├── pv.yaml                 # 1Gi hostPath PersistentVolume
│   │   ├── pvc.yaml                # PersistentVolumeClaim
│   │   ├── deployment.yaml         # postgres:16-alpine, Recreate strategy
│   │   └── service.yaml            # ClusterIP postgres-svc:5432
│   ├── web/
│   │   ├── deployment.yaml         # 2 replicas, initContainer, probes, rolling update
│   │   └── service.yaml            # ClusterIP expense-web-svc:5000
│   ├── nginx/
│   │   ├── configmap.yaml          # nginx.conf (blocks /metrics, rate limits login)
│   │   ├── deployment.yaml         # 2 replicas
│   │   └── service.yaml            # ClusterIP expense-nginx-svc:80
│   ├── monitoring/
│   │   ├── deploy.sh               # deploy/verify/access/logs/teardown
│   │   ├── prometheus/             # RBAC, ConfigMap, PVC, Deployment, Service
│   │   ├── grafana/                # Secret, ConfigMap, dashboards, PVC, Deployment, Service
│   │   ├── loki/                   # ConfigMap, PVC, Deployment, Service
│   │   └── promtail/               # RBAC, ConfigMap, DaemonSet
│   └── deploy.sh                   # Full app deploy runbook (8 sections)
│
├── .github/
│   └── workflows/
│       ├── ci.yml                  # lint → security → test → docker-build
│       └── cd.yml                  # push multi-arch image to Docker Hub on main/tag
│
└── docs/
    ├── architecture.md             # ASCII architecture diagrams (6 diagrams)
    ├── deployment-guide.md         # Step-by-step deploy for Docker, K8s, monitoring
    ├── troubleshooting.md          # 20+ common problems and fixes
    ├── screenshots.md              # Screenshot placeholders and instructions
    ├── viva-questions.md           # 34 Q&A covering all phases
    └── resume-description.md       # 6 resume formats + skills list
```

---

## Architecture

### Traffic Flow (Kubernetes)

```
Browser → /etc/hosts → Minikube IP
  → K8s Ingress (nginx-controller)
    → expense-nginx-svc:80
      → Nginx pods (2 replicas)
        → expense-web-svc:5000
          → Flask/Gunicorn pods (2 replicas)
            → postgres-svc:5432
              → PostgreSQL pod
```

### Monitoring Flow

```
Flask pods  ──/metrics──▶  Prometheus  ──PromQL──▶  Grafana
Node logs   ──Promtail──▶  Loki        ──LogQL───▶  Grafana
cAdvisor    ──scrape───▶   Prometheus
```

See [docs/architecture.md](docs/architecture.md) for full ASCII diagrams.

---

## CI/CD Pipeline

```
git push / PR
  └─▶ lint     (ruff check + format)
        └─▶ security  (bandit + pip-audit)
              └─▶ test     (pytest 17 tests, SQLite in-memory)
                    └─▶ docker-build  (build + smoke + Trivy SARIF)

main merge / v*.*.* tag
  └─▶ check-ci  (gate on CI success)
        └─▶ push-image  (QEMU + buildx → linux/amd64,arm64 → Docker Hub)
```

**Required GitHub Secrets:** `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`

---

## Application Features

### Student
- Register and login
- Add expenses (title, amount, category, date)
- View own expense history with running total
- Delete own expenses

### Admin
- View all users and all expenses
- Delete any expense
- Delete any user (cascades to their expenses)
- Cannot delete own account

---

## Kubernetes Features

| Feature | Implementation |
|---|---|
| Zero-downtime updates | `maxUnavailable: 0, maxSurge: 1` rolling update |
| Self-healing | Liveness probes restart unresponsive pods |
| Traffic management | Readiness probes keep unhealthy pods out of rotation |
| Startup safety | initContainer waits for Postgres; startupProbe gives 150s to initialize |
| Secret management | K8s Secrets (gitignored), loaded via `envFrom` |
| Data persistence | PV/PVC for Postgres, Prometheus TSDB, Grafana, and Loki |
| Metrics security | `/metrics` blocked at Nginx; Prometheus scrapes via ClusterIP only |
| Auto-scaling ready | HPA-compatible; metrics-server can target `flask_http_request_total` |

---

## Observability

### Grafana Dashboard Panels
- Request rate (req/s) by endpoint
- HTTP error rate (4xx + 5xx)
- P95 response time
- Flask pod CPU usage (from cAdvisor)
- Flask pod memory usage
- Postgres pod CPU usage
- Stat cards: current RPS, P95 latency, 5xx rate, Flask memory

### Useful PromQL Queries
```promql
# Request rate
rate(flask_http_request_total[5m])

# P95 latency
histogram_quantile(0.95, rate(flask_http_request_duration_seconds_bucket[5m]))

# Error rate
sum(rate(flask_http_request_total{status=~"5.."}[5m]))
```

### Useful LogQL Queries (Grafana Explore → Loki)
```logql
# All Flask logs
{namespace="expense-tracker", app="expense-web"}

# Errors only
{app="expense-web"} | json | level="ERROR"

# Auth events
{app="expense-web"} | json | logger="tracker.auth"
```

---

## Screenshots

> See [docs/screenshots.md](docs/screenshots.md) for the full list with instructions.

| What | Where |
|---|---|
| Student dashboard | `docs/screenshots/03-student-dashboard.png` |
| Admin dashboard | `docs/screenshots/04-admin-dashboard.png` |
| GitHub Actions CI passing | `docs/screenshots/10-github-actions-ci.png` |
| Grafana dashboard | `docs/screenshots/13-grafana-dashboard.png` |
| Prometheus targets | `docs/screenshots/14-prometheus-targets.png` |

---

## Technology Stack

| Layer | Technology |
|---|---|
| Language | Python 3.12 |
| Web Framework | Flask 3.1 + Gunicorn 22 |
| Database | PostgreSQL 16 / SQLite (tests) |
| ORM | SQLAlchemy 3.1 |
| Auth | Flask-Login 0.6 + Werkzeug PBKDF2 |
| Proxy | Nginx 1.25-alpine |
| Containerization | Docker (multi-stage), Docker Compose |
| Orchestration | Kubernetes 1.29+, Minikube |
| CI/CD | GitHub Actions, Docker Hub |
| Linting | ruff 0.11 |
| Security | bandit 1.8, pip-audit 2.9, Trivy |
| Metrics | Prometheus 2.51, prometheus-flask-exporter 0.23 |
| Dashboards | Grafana 10.4 |
| Log storage | Loki 3.0 |
| Log shipping | Promtail 3.0 |
| Logging format | python-json-logger 3.2 |

---

## Documentation

| Document | Description |
|---|---|
| [Architecture Diagrams](docs/architecture.md) | 6 ASCII diagrams: system, CI/CD, docker-compose, monitoring, request flow, DB schema |
| [Deployment Guide](docs/deployment-guide.md) | Step-by-step instructions for Docker Compose, Kubernetes, and monitoring |
| [Troubleshooting Guide](docs/troubleshooting.md) | 20+ common problems, causes, and fixes |
| [Screenshots Guide](docs/screenshots.md) | 16 screenshot placeholders with capture instructions |
| [Viva Questions & Answers](docs/viva-questions.md) | 34 Q&A across all 6 phases |
| [Resume Description](docs/resume-description.md) | 6 resume formats + skills list + interview talking points |

---

## License

MIT
