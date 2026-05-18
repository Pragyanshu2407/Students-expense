# Viva Questions & Answers — Student Expense Tracker

Complete question bank covering all 6 phases of the project.

---

## Section 1 — Flask Application & Architecture

**Q1. What is Flask and why did you choose it over Django?**

Flask is a micro web framework for Python — it provides routing, request handling, and templating (Jinja2) without enforcing a project structure. I chose Flask because:
- It's lightweight and easy to understand end-to-end, which suits a learning/demo project
- It gives full control over ORM, auth, and project layout (I chose SQLAlchemy + Flask-Login explicitly)
- Django would be overkill — its built-in admin and ORM features would hide the DevOps complexity I wanted to demonstrate

---

**Q2. Explain the Flask app factory pattern. Why use it instead of a global `app = Flask(__name__)`?**

The app factory is a function (`create_app(config_name)`) that creates and configures the Flask app, then returns it. Benefits:
1. **Multiple instances** — tests can create a fresh app with `TestingConfig` (SQLite in-memory) without interfering with the production app
2. **Deferred initialization** — extensions like SQLAlchemy and Flask-Login are initialized inside the function, not at import time, avoiding circular imports
3. **Config flexibility** — you pass a config name (`"development"`, `"testing"`, `"production"`) and the factory switches database URLs, debug mode, etc. automatically

---

**Q3. How does Flask-Login work? What does `@login_required` actually do?**

Flask-Login manages user sessions using a signed cookie. The flow:
1. On login, `login_user(user)` stores the user's ID in the session cookie (signed with `SECRET_KEY`)
2. On every request, Flask-Login reads the cookie, calls the `@login_manager.user_loader` callback, and loads the `User` object from the database
3. `@login_required` is a decorator that checks `current_user.is_authenticated` — if `False`, it redirects to `login_manager.login_view` (our login page)
4. Inside any view, `current_user` gives you the logged-in `User` object

---

**Q4. How did you implement role-based access control (RBAC)?**

Two levels:
1. **Route-level:** An `admin_required` decorator checks `current_user.is_admin`. If not admin, it returns a 403. This is applied to every admin blueprint route with `@admin_required`.
2. **Data-level:** Students can only delete their own expenses because the query includes `filter_by(id=expense_id, user_id=current_user.id)`. If the expense belongs to someone else, `first_or_404()` returns 404 — the student can't even confirm the expense exists.

The `is_admin` property on the User model simply returns `self.role == "admin"`.

---

**Q5. What is SQLAlchemy and what is an ORM?**

SQLAlchemy is an ORM — Object-Relational Mapper. An ORM lets you work with database tables as Python classes instead of writing raw SQL:
- `User` Python class → `users` database table
- `user = User(username="alice")` → `INSERT INTO users (username) VALUES ('alice')`
- `User.query.filter_by(username="alice").first()` → `SELECT * FROM users WHERE username='alice' LIMIT 1`

Benefits: database portability (tests use SQLite, production uses PostgreSQL), protection from SQL injection (parameterized queries by default), and Pythonic syntax.

---

## Section 2 — Docker & Containerization

**Q6. Explain your multi-stage Dockerfile. Why three stages?**

```
Stage 1: base     — python:3.12-slim + env vars (shared base)
Stage 2: builder  — installs gcc, libpq-dev, then pip-installs all packages into /opt/venv
Stage 3: app      — copies /opt/venv from builder, installs only curl (for health checks), creates non-root user
```

The key benefit: the final image does NOT contain gcc or libpq-dev (C compilers ~200MB). These are needed to compile psycopg2 but not to run it. The final image is ~150MB instead of ~800MB. Smaller images = faster pull times, smaller attack surface.

---

**Q7. Why run the container as a non-root user?**

By default, Docker containers run as root. If an attacker exploits the application (e.g., RCE via a vulnerability), they would have root inside the container. With `USER appuser` (uid 1001):
- They can't install packages, write to `/etc`, or read `/root`
- On many systems, the container process can't escape to the host even with a container breakout
- It follows the principle of least privilege

---

**Q8. What is Gunicorn and why not use Flask's built-in dev server in production?**

Gunicorn is a production WSGI server. Flask's dev server (`app.run()`) is:
- Single-threaded — serves one request at a time
- Not designed for concurrency or load
- Has debug mode enabled (auto-reloads, exposes the debugger — a security risk)

Gunicorn spawns multiple worker processes (4 by default in our config) each handling requests independently. It's battle-tested for production load, handles graceful shutdowns, and respects UNIX signals properly.

---

**Q9. How do health checks work in Docker Compose? Why does it matter?**

In `docker-compose.yml`, each service has a `healthcheck` block:
- Postgres: `pg_isready -U postgres` — checks if the DB accepts connections
- Flask: `curl --fail http://localhost:5000/health` — checks if the app responds
- Nginx: `wget --spider http://localhost/health` — checks if Nginx proxies correctly

The `depends_on: condition: service_healthy` chain means:
- Flask doesn't start until Postgres is healthy
- Nginx doesn't start until Flask is healthy

Without this, Flask would crash on startup because it can't connect to a database that's still initializing.

---

**Q10. What is a named volume in Docker Compose? How is it different from a bind mount?**

Named volume (`postgres_data`): Docker manages the storage location (usually `/var/lib/docker/volumes/`). The data persists when the container is stopped or removed. Best for databases.

Bind mount (`./nginx:/etc/nginx`): maps a host directory into the container. You see the files on your host. Best for config files you want to edit.

For Postgres data, we use a named volume because we don't want to accidentally delete or corrupt it by editing files on the host.

---

## Section 3 — GitHub Actions CI/CD

**Q11. What is CI/CD and how is it implemented in this project?**

**CI (Continuous Integration):** Every push/PR triggers automated checks that catch bugs before they reach main — linting, security scanning, tests, and a Docker build. This prevents "it works on my machine" problems.

**CD (Continuous Deployment):** When CI passes on `main` or a version tag is pushed, the pipeline automatically builds a multi-arch Docker image and pushes it to Docker Hub. The deployed image is always in sync with the merged code.

In this project: `ci.yml` handles CI (4 jobs in dependency chain); `cd.yml` handles CD (triggered by CI success or a `v*.*.*` tag).

---

**Q12. What is ruff and why use it instead of flake8 + black + isort?**

Ruff is an extremely fast Python linter and formatter written in Rust. One tool replaces three:
- flake8 (style/error checking) → `ruff check`
- black (formatting) → `ruff format`
- isort (import sorting) → ruff's built-in `I` rule set

It runs ~100x faster than the Python-based alternatives, which matters in CI where speed = cost. Configuration lives in `ruff.toml`.

---

**Q13. What does bandit check? Give an example vulnerability it would catch.**

Bandit is a static analysis security tool for Python. It scans your code for common security issues without running it. Examples:
- `subprocess.call(user_input, shell=True)` → B602: shell injection risk
- `hashlib.md5(password)` → B303: weak hashing algorithm for passwords
- `random.random()` for security tokens → B311: not cryptographically secure (use `secrets` module)
- Hardcoded passwords: `password = "admin123"` in source code → B105

---

**Q14. What is Trivy and what does it scan?**

Trivy is an open-source vulnerability scanner by Aqua Security. In this project it runs twice:
1. **In `ci.yml`** (docker-build job): scans the locally built image for OS package CVEs and Python dependency CVEs. Uploads results as SARIF to GitHub Security tab.
2. **In `cd.yml`** (after push): scans the pushed Docker Hub image as a final gate.

It checks: OS packages (Alpine APK, Debian APT), language dependencies (pip packages), misconfigurations, and secrets in the image.

---

**Q15. What is pip-audit and how is it different from Trivy?**

`pip-audit` scans your `requirements.txt` against the Python Package Advisory Database (PyPI advisory DB and OSV). It runs on your **source code** before the image is built — faster feedback.

Trivy scans the **built image** — it catches more (OS CVEs, misconfigs) but takes longer.

In this project, we had real CVEs: Flask 3.0.3 (CVE-2026-27205), Werkzeug 3.0.3 (5 CVEs), pytest 8.2.2 (CVE-2025-71176). pip-audit caught them and we upgraded to patched versions before building.

---

## Section 4 — Kubernetes

**Q16. What is Kubernetes and how is it different from Docker Compose?**

Kubernetes (K8s) is a container orchestration platform. Key differences:

| Feature | Docker Compose | Kubernetes |
|---|---|---|
| Scope | Single machine | Cluster of many machines |
| Self-healing | Manual restart | Automatic (restartPolicy) |
| Scaling | `--scale` flag | `kubectl scale` + HPA |
| Rolling updates | Stop + start | Zero-downtime rollout |
| Service discovery | Docker DNS | K8s DNS (CoreDNS) |
| Load balancing | Round-robin by Docker | kube-proxy |

Docker Compose is for development; Kubernetes is for production.

---

**Q17. Explain the difference between a Deployment, Service, and Pod.**

- **Pod:** The smallest deployable unit. One or more containers that share a network and storage. Pods are ephemeral — if a pod crashes, its IP changes.
- **Deployment:** Manages a set of identical Pods. Declares "I want 2 replicas of expense-web." K8s ensures that's always true — if a pod dies, a new one is created. Also handles rolling updates.
- **Service:** A stable network endpoint (fixed IP and DNS name) that load-balances traffic across all healthy pods matching its selector. Because pod IPs change, you always connect to the Service, not the Pod directly.

---

**Q18. What is an Ingress? How is it different from a Service of type NodePort?**

**NodePort Service:** exposes a port on every node's IP (e.g., `:30080`). Simple but:
- Exposes a random high port, not standard port 80/443
- No hostname-based routing (can't serve `app1.example.com` and `app2.example.com` on the same port)

**Ingress:** An HTTP router at the edge of the cluster. It:
- Listens on standard ports 80/443
- Routes by hostname and path: `expense-tracker.local/` → `expense-nginx-svc:80`
- Can terminate TLS, add authentication, rate-limit
- Requires an Ingress Controller (we use `minikube addons enable ingress` which installs nginx-ingress)

---

**Q19. Explain the three probe types (startup, liveness, readiness). Why do we need all three?**

- **startupProbe:** Runs only during startup. Gives the app extra time to initialize (e.g., DB migration, large data load). Once it passes, K8s switches to the other probes. Without this, a slow-starting app would be killed by the liveness probe before it's ready.

- **livenessProbe:** Runs continuously. If it fails, K8s restarts the container. Catches: deadlocks, infinite loops, crashed processes.

- **readinessProbe:** Runs continuously. If it fails, K8s removes the pod from the Service's endpoints — no traffic is routed to it. Used for: app not ready (e.g., still warming up cache), or temporarily unhealthy but shouldn't be killed.

Our Flask app uses `/health` for all three. The startup probe has `failureThreshold=30, period=5s` (150s total) to allow DB init on first boot.

---

**Q20. What is a PersistentVolume (PV) and PersistentVolumeClaim (PVC)?**

Without persistent storage, all data in a pod is lost when the pod restarts.

- **PersistentVolume (PV):** A piece of storage provisioned in the cluster. On Minikube we use `hostPath` — a directory on the Minikube VM (`/data/postgres`). In production, this would be AWS EBS, GCP Persistent Disk, or NFS.
- **PersistentVolumeClaim (PVC):** A request for storage by a pod. "I need 1Gi of ReadWriteOnce storage." K8s binds the PVC to a matching PV.

The separation allows pods to request storage without knowing the underlying infrastructure.

---

**Q21. What is a ConfigMap vs a Secret? When do you use each?**

Both store key-value pairs for pods to consume. The difference:
- **ConfigMap:** Plain text, not sensitive. Examples: `FLASK_ENV=production`, `GUNICORN_WORKERS=4`, log levels.
- **Secret:** Base64-encoded (not encrypted by default, but treated as sensitive). Examples: passwords, API keys, connection strings with credentials.

In Kubernetes, Secrets can be encrypted at rest (with KMS), restricted by RBAC, and excluded from logs. Never put passwords in ConfigMaps.

---

**Q22. What is a rolling update? How does `maxUnavailable: 0` help?**

A rolling update replaces pods one at a time instead of all at once, keeping the app available during the update.

With `maxUnavailable: 0, maxSurge: 1`:
1. K8s starts 1 NEW pod (now 3 total: 2 old + 1 new)
2. Waits for the new pod to pass readinessProbe
3. Removes 1 old pod (back to 2 total)
4. Repeats until all pods are on the new version

At no point are there fewer than 2 ready pods. Zero downtime guaranteed. Without this, `maxUnavailable: 1` would remove an old pod BEFORE the new one is ready — causing a brief 503 gap.

---

## Section 5 — Monitoring & Logging

**Q23. What is Prometheus and how does it collect metrics?**

Prometheus is a time-series metrics database. It uses a **pull model** — it scrapes HTTP endpoints that expose metrics in the Prometheus text format.

In this project:
- `prometheus-flask-exporter` adds a `/metrics` endpoint to Flask
- Every 15 seconds, Prometheus fetches `http://expense-web-svc:5000/metrics`
- The scraped data is stored in the TSDB (time-series database) on the PVC
- You query it with PromQL (Prometheus Query Language)

---

**Q24. What metrics does prometheus-flask-exporter expose?**

Key metrics:
- `flask_http_request_total` — counter, labeled by `method`, `endpoint`, `status`. Use `rate()` to get req/s.
- `flask_http_request_duration_seconds` — histogram of response times. Use `histogram_quantile(0.95, ...)` for P95 latency.
- `flask_http_request_exceptions_total` — unhandled exceptions (500 errors)
- `process_resident_memory_bytes` — Flask process memory (RSS)
- `process_cpu_seconds_total` — Flask process CPU time

Container-level CPU/memory comes from cAdvisor (built into the kubelet): `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`.

---

**Q25. What is Loki? How is it different from Elasticsearch?**

Loki is a log aggregation system by Grafana Labs that follows the same label-based model as Prometheus. Key difference from Elasticsearch:

| | Loki | Elasticsearch |
|---|---|---|
| Indexing | Labels only (not full text) | Full-text index of every field |
| Storage | Very cheap (compressed chunks) | Expensive (inverted index) |
| Query | LogQL (label filter + text search) | Lucene/DSL |
| Best for | Log streams with labels | Full-text search, complex analytics |
| Resource use | Low (fits on a laptop) | High (needs significant RAM/disk) |

For a student project (or most real apps), Loki is sufficient. Elasticsearch is overkill unless you need full-text search across petabytes.

---

**Q26. What is Promtail and why does it run as a DaemonSet?**

Promtail is the log shipper for Loki. It:
1. Reads container log files from the node filesystem (`/var/log/pods/`)
2. Attaches labels using Kubernetes pod metadata (namespace, pod name, app)
3. Parses JSON log lines into structured fields
4. Pushes batches to Loki's HTTP API

It must run as a **DaemonSet** (one pod per node) because log files are physically on the node's disk. A Deployment with 1 pod would only read logs from whatever node it schedules on, missing all other nodes. DaemonSet ensures every node is covered.

---

**Q27. What is PromQL? Give a real query you used.**

PromQL (Prometheus Query Language) is used to query time-series data. Real queries from this project:

```promql
# HTTP request rate per second (5-minute window)
rate(flask_http_request_total[5m])

# P95 response time — 95% of requests complete within this many seconds
histogram_quantile(0.95,
  sum(rate(flask_http_request_duration_seconds_bucket[5m])) by (le, endpoint)
)

# HTTP error rate (4xx + 5xx)
sum(rate(flask_http_request_total{status=~"4..|5.."}[5m]))

# Flask container memory usage (bytes)
container_memory_working_set_bytes{container="expense-web"}
```

---

**Q28. What is LogQL? How is it different from SQL?**

LogQL is Loki's query language, inspired by PromQL. It works on log streams:

```logql
# Get all Flask logs
{namespace="expense-tracker", app="expense-web"}

# Filter to ERROR logs only
{app="expense-web"} | json | level="ERROR"

# Count ERROR logs per minute (metric from logs)
sum(rate({app="expense-web"} | json | level="ERROR" [1m])) by (app)
```

Difference from SQL: LogQL operates on **streams** (continuous time-ordered log lines) not tables. `{...}` selects a stream by labels, `|` pipes filters. SQL would require a rigid schema; LogQL can filter unstructured text or parse JSON on the fly.

---

## Section 6 — General DevOps Concepts

**Q29. What is the difference between horizontal and vertical scaling?**

- **Vertical scaling (scale up):** Give the existing machine/pod more CPU and memory. Simple but has a physical limit and causes downtime during resizing.
- **Horizontal scaling (scale out):** Add more instances (pods/machines). No downtime, theoretically unlimited, but the app must be stateless (no local state between requests). Our Flask app is stateless (sessions in cookies, data in Postgres) so it scales horizontally.

In Kubernetes: `kubectl scale deployment/expense-web --replicas=5`

---

**Q30. What is a namespace in Kubernetes? Why do we use `expense-tracker`?**

A namespace is a logical partition inside a Kubernetes cluster. It groups related resources together and provides:
- **Isolation:** Resources in one namespace can't accidentally conflict with another's (same name, different namespace = different resource)
- **Access control:** RBAC can restrict who can modify resources in a namespace
- **Resource quotas:** Limit CPU/memory per namespace

We use `expense-tracker` to keep all app resources (pods, services, secrets, PVCs) in one place, separate from `ingress-nginx`, `kube-system`, and the monitoring stack (which we also put in `expense-tracker` for simplicity — in production you'd use a separate `monitoring` namespace).

---

**Q31. What is RBAC in Kubernetes? Why does Prometheus need it?**

RBAC (Role-Based Access Control) controls what Kubernetes API actions a ServiceAccount can perform.

Prometheus uses `kubernetes_sd_configs` to auto-discover pods and nodes to scrape. This requires:
- `GET /api/v1/pods` — list pods in the namespace
- `GET /api/v1/nodes` — list nodes for cAdvisor
- `GET /api/v1/nodes/{name}/proxy/metrics/cadvisor` — scrape container metrics

Without RBAC grants, the Prometheus pod would get 403 Forbidden errors and show no targets. We create a `ClusterRole` with those permissions and bind it to the `prometheus` ServiceAccount via a `ClusterRoleBinding`.

---

**Q32. What is the purpose of the `.env` file and why is it gitignored?**

`.env` stores environment-specific secrets and configuration (database password, Flask secret key, admin password). It's gitignored because:
1. **Security:** Secrets in git history are exposed to anyone who clones the repo — even after deletion, they remain in old commits
2. **Environment separation:** Dev, staging, and production have different values for the same variables
3. **Best practice:** The 12-factor app methodology separates config from code

We provide `.env.example` (committed) with placeholder values so developers know what variables to set.

---

**Q33. What is a zero-downtime deployment? How do you achieve it here?**

A zero-downtime deployment ensures users never see an error during an update.

We achieve it through:
1. **Rolling update strategy** (`maxUnavailable: 0`) — always keeps 2 healthy pods available
2. **readinessProbe** — new pods only receive traffic after `/health` passes; old pods are only removed after the new ones are ready
3. **terminationGracePeriodSeconds: 30** — gives Gunicorn time to finish in-flight requests before the pod is killed (Gunicorn's `graceful_timeout` is also set)
4. **Multiple replicas (2)** — so during rollout there's always at least 1 pod serving traffic

---

**Q34. What would you improve if this were a real production system?**

Good answer (pick 3-4):
1. **TLS/HTTPS** — cert-manager + Let's Encrypt for automatic certificate renewal
2. **Horizontal Pod Autoscaler** — scale Flask pods automatically when CPU > 70%
3. **External secrets management** — HashiCorp Vault or AWS Secrets Manager instead of K8s Secrets (which are base64, not encrypted by default)
4. **Multi-node cluster** — real K8s cluster (EKS/GKE/AKS) for actual HA
5. **Postgres replication** — primary + read replica for HA; or use a managed RDS
6. **Alertmanager** — Prometheus alerts → Slack/PagerDuty for on-call
7. **Rate limiting at the application layer** — in addition to Nginx, to prevent abuse
8. **Log retention policy** — Loki compactor with a TTL, or ship to S3 for long-term storage
