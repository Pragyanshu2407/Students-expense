# Architecture Diagrams — Student Expense Tracker

## 1. High-Level System Architecture

```
╔══════════════════════════════════════════════════════════════════════════╗
║                        KUBERNETES CLUSTER (Minikube)                     ║
║                        Namespace: expense-tracker                        ║
║                                                                          ║
║   ┌────────────────────────────────────────────────────────────────┐     ║
║   │                      INGRESS CONTROLLER                        │     ║
║   │              nginx  (minikube addons enable ingress)           │     ║
║   │              host: expense-tracker.local → expense-nginx-svc  │     ║
║   └────────────────────┬───────────────────────────────────────────┘     ║
║                        │ HTTP :80                                         ║
║   ┌────────────────────▼───────────────────────────────────────────┐     ║
║   │                    NGINX REVERSE PROXY                          │     ║
║   │              Deployment: expense-nginx  (2 replicas)           │     ║
║   │  • Rate limiting on /auth/login (5 req/min)                    │     ║
║   │  • Security headers (X-Frame-Options, HSTS, etc.)              │     ║
║   │  • gzip compression                                             │     ║
║   │  • Blocks /metrics (403) — not exposed externally              │     ║
║   └────────────────────┬───────────────────────────────────────────┘     ║
║                        │ HTTP :5000                                        ║
║   ┌────────────────────▼───────────────────────────────────────────┐     ║
║   │                  FLASK / GUNICORN APP                           │     ║
║   │              Deployment: expense-web  (2 replicas)             │     ║
║   │  • Auth blueprints  (register, login, logout)                  │     ║
║   │  • Student dashboard (add/delete own expenses)                 │     ║
║   │  • Admin dashboard  (manage all users & expenses)              │     ║
║   │  • /health  → liveness & readiness probes                      │     ║
║   │  • /metrics → Prometheus scrape (ClusterIP only)               │     ║
║   └────────────────────┬───────────────────────────────────────────┘     ║
║                        │ TCP :5432                                         ║
║   ┌────────────────────▼───────────────────────────────────────────┐     ║
║   │                     POSTGRESQL 16                               │     ║
║   │              Deployment: postgres  (1 replica)                 │     ║
║   │  • Stores: users, expenses                                     │     ║
║   │  • PersistentVolume: 1Gi hostPath on Minikube VM               │     ║
║   └────────────────────────────────────────────────────────────────┘     ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

## 2. CI/CD Pipeline

```
  Developer
     │
     │  git push / PR
     ▼
┌─────────────────────────────────────────────────────────────────┐
│                   GitHub Actions — ci.yml                        │
│                                                                  │
│  ┌──────────┐    ┌───────────┐    ┌────────┐    ┌───────────┐  │
│  │  lint    │───▶│ security  │───▶│  test  │───▶│  docker   │  │
│  │          │    │           │    │        │    │   build   │  │
│  │ ruff     │    │ bandit    │    │ pytest │    │           │  │
│  │ check    │    │ pip-audit │    │ 17     │    │ build img │  │
│  │ format   │    │           │    │ tests  │    │ smoke test│  │
│  └──────────┘    └───────────┘    └────────┘    │ trivy scan│  │
│                                                  └───────────┘  │
└─────────────────────────────────────────────────────────────────┘
     │
     │  CI passes + push to main  OR  push v*.*.* tag
     ▼
┌─────────────────────────────────────────────────────────────────┐
│                   GitHub Actions — cd.yml                        │
│                                                                  │
│  ┌────────────┐    ┌──────────────────────────────────────────┐ │
│  │ check-ci   │───▶│           push-image                     │ │
│  │            │    │                                          │ │
│  │ gate on CI │    │ QEMU + buildx (linux/amd64 + arm64)      │ │
│  │ success    │    │ docker/metadata-action (semver tags)     │ │
│  └────────────┘    │ docker push → Docker Hub                 │ │
│                    │ Post-push Trivy scan                     │ │
│                    └──────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
     │
     ▼
  Docker Hub
  youruser/student-expense-tracker:latest
  youruser/student-expense-tracker:1.2.3
  youruser/student-expense-tracker:sha-abc1234
```

---

## 3. Docker Compose Stack (Local Development)

```
  Browser
     │ :80
     ▼
┌──────────────────────────────────────────────┐
│   nginx:1.25-alpine                           │
│   nginx/nginx.conf (rate limit, headers,gzip) │
│   health: wget /health                        │
└───────────────────────┬──────────────────────┘
                        │ :5000 (internal)
┌───────────────────────▼──────────────────────┐
│   Flask + Gunicorn                            │
│   image: student-expense-tracker:latest       │
│   gunicorn.conf.py (workers, timeout)         │
│   health: curl /health                        │
└───────────────────────┬──────────────────────┘
                        │ :5432 (internal)
┌───────────────────────▼──────────────────────┐
│   PostgreSQL 16-alpine                        │
│   volume: postgres_data (named volume)        │
│   health: pg_isready                          │
└──────────────────────────────────────────────┘
```

---

## 4. Monitoring Stack

```
   ┌──────────────────────────────────────────────────────────────┐
   │              MONITORING  (namespace: expense-tracker)         │
   │                                                              │
   │  ┌─────────────┐     scrapes      ┌────────────────────┐    │
   │  │  Prometheus  │◀────/metrics────│  Flask pods        │    │
   │  │  :9090       │                 │  (expense-web)     │    │
   │  │  TSDB 15d    │◀──cAdvisor──────│  Kubelet nodes     │    │
   │  │  NodePort    │                 └────────────────────┘    │
   │  │  30900       │                                            │
   │  └──────┬───────┘                                            │
   │         │ PromQL                                             │
   │  ┌──────▼───────┐                                            │
   │  │   Grafana     │  NodePort :30300                          │
   │  │   :3000       │  admin/grafana123                         │
   │  │   Dashboard   │  "Student Expense Tracker" dashboard      │
   │  └──────┬───────┘                                            │
   │         │ LogQL                                              │
   │  ┌──────▼───────┐     push       ┌─────────────────────┐    │
   │  │    Loki       │◀──────────────│  Promtail (DaemonSet)│    │
   │  │   :3100       │               │  reads /var/log/pods │    │
   │  │  TSDB logs    │               │  parses JSON logs    │    │
   │  │  NodePort     │               │  labels: app,ns,pod  │    │
   │  │  30310        │               └─────────────────────┘    │
   │  └───────────────┘                                            │
   └──────────────────────────────────────────────────────────────┘
```

---

## 5. Request Flow (end-to-end)

```
Browser
  │
  │  GET http://expense-tracker.local/student/dashboard
  │
  ▼
/etc/hosts resolves → Minikube IP
  │
  ▼
K8s Ingress (nginx controller)
  │  matches host: expense-tracker.local
  ▼
Service: expense-nginx-svc (ClusterIP :80)
  │  load-balances across 2 Nginx pods
  ▼
Nginx pod
  │  proxy_pass http://flask_app (upstream → expense-web-svc:5000)
  │  adds: X-Real-IP, X-Forwarded-For, security headers
  ▼
Service: expense-web-svc (ClusterIP :5000)
  │  load-balances across 2 Flask/Gunicorn pods
  ▼
Flask pod (Gunicorn worker)
  │  Flask-Login checks session cookie
  │  SQLAlchemy ORM query → expense-web-svc → postgres-svc:5432
  ▼
Service: postgres-svc (ClusterIP :5432)
  │  routes to single Postgres pod
  ▼
PostgreSQL pod
  │  reads/writes data on PersistentVolume
  ▼
Response bubbles back up the same path
```

---

## 6. Database Schema

```
┌──────────────────────────────┐        ┌──────────────────────────────┐
│            users             │        │           expenses            │
├──────────────────────────────┤        ├──────────────────────────────┤
│ id          INTEGER  PK      │        │ id          INTEGER  PK      │
│ username    VARCHAR  UNIQUE  │◀───┐   │ title       VARCHAR          │
│ email       VARCHAR  UNIQUE  │    │   │ amount      FLOAT            │
│ password_hash VARCHAR        │    │   │ category    VARCHAR          │
│ role        VARCHAR          │    │   │ date        DATE             │
│             ('student'|      │    │   │ created_at  DATETIME         │
│              'admin')        │    └───│ user_id     INTEGER  FK      │
│ created_at  DATETIME         │        └──────────────────────────────┘
└──────────────────────────────┘
```
