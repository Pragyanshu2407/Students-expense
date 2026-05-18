# Screenshots — Student Expense Tracker

> **Instructions:** Take screenshots of each section below while running the app.
> Replace each `[SCREENSHOT PLACEHOLDER]` with an actual image using:
> `![Description](screenshots/filename.png)`
>
> Store screenshots in the `docs/screenshots/` folder.

---

## 1. Application UI

### Login Page

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/01-login-page.png

What to capture:
- URL bar showing http://expense-tracker.local/auth/login
  (or http://localhost for Docker Compose)
- Login form with username/password fields
- "Register" link visible
```

---

### Student Registration

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/02-register-page.png

What to capture:
- Registration form with Username, Email, Password fields
- Submit button
```

---

### Student Dashboard

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/03-student-dashboard.png

What to capture:
- Stat cards at the top (Total Spent, This Month, Expense Count)
- "Add Expense" form on the left
- Expense table on the right with delete buttons
- Navbar showing "Student" role badge
```

---

### Admin Dashboard

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/04-admin-dashboard.png

What to capture:
- Admin stat cards (Total Users, Total Expenses, Total Amount)
- Users table with "Delete User" buttons
- All Expenses table with "Delete Expense" buttons
- Navbar showing "Admin" role badge
```

---

## 2. Docker

### Docker Compose — All containers running

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/05-docker-compose-up.png

How to get this screenshot:
  docker compose up --build -d
  docker compose ps

What to capture:
- Terminal output showing all 3 services (db, web, nginx) as "running"
- "healthy" status in the STATUS column
```

---

### Docker image layers (multi-stage build)

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/06-docker-image.png

How to get this screenshot:
  docker images student-expense-tracker
  docker history student-expense-tracker:latest

What to capture:
- Final image size (should be ~150-200MB, not ~800MB)
- docker images output showing the tag and size
```

---

## 3. Kubernetes

### All pods Running

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/07-k8s-pods-running.png

How to get this screenshot:
  kubectl get pods -n expense-tracker

What to capture:
- All pods in STATUS=Running
- READY column showing 1/1 or 2/2
- Deployments: postgres, expense-web (2), expense-nginx (2)
```

---

### Kubernetes services and ingress

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/08-k8s-services.png

How to get this screenshot:
  kubectl get all -n expense-tracker

What to capture:
- Services: postgres-svc, expense-web-svc, expense-nginx-svc
- Deployments with READY=2/2 for web and nginx
- kubectl get ingress -n expense-tracker (showing ADDRESS = Minikube IP)
```

---

### PersistentVolumes and PVCs

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/09-k8s-storage.png

How to get this screenshot:
  kubectl get pv
  kubectl get pvc -n expense-tracker

What to capture:
- PV STATUS=Bound
- PVC STATUS=Bound
- CAPACITY column showing correct sizes
```

---

## 4. GitHub Actions CI/CD

### CI pipeline passing

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/10-github-actions-ci.png

What to capture:
- GitHub Actions tab showing all 4 jobs: lint ✓, security ✓, test ✓, docker-build ✓
- Green checkmarks on all jobs
- Total runtime visible
```

---

### CD pipeline — Docker Hub push

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/11-github-actions-cd.png

What to capture:
- CD workflow run showing push-image job succeeded
- Job summary with Docker image tags (latest, sha-XXXXX)
```

---

### Security scan results (Trivy)

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/12-trivy-scan.png

What to capture:
- GitHub Security tab → Code scanning alerts
- OR the Trivy SARIF output in the docker-build job logs
- Ideally showing "0 vulnerabilities" or LOW severity only
```

---

## 5. Monitoring Stack

### Grafana — Student Expense Tracker Dashboard

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/13-grafana-dashboard.png

How to get this screenshot:
  minikube service grafana-svc -n expense-tracker --url
  # Open URL → Login → Dashboards → Student Expense Tracker

What to capture:
- All 10 panels visible:
  - Request Rate graph
  - HTTP Error Rate graph
  - P95 Response Time graph
  - Flask CPU graph
  - Flask Memory graph
  - Postgres CPU graph
  - Stat panels: 5xx rate, P95, Current RPS, Flask Memory
- Time range selector showing "Last 1 hour"
```

---

### Prometheus — Targets page

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/14-prometheus-targets.png

How to get this screenshot:
  minikube service prometheus-svc -n expense-tracker --url
  # Open URL → Status → Targets

What to capture:
- All 3 scrape jobs listed:
  - flask-app (UP, green)
  - kubernetes-pods (UP, green)
  - cadvisor (UP, green)
- "State: UP" for each
```

---

### Prometheus — Query browser

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/15-prometheus-query.png

How to get this screenshot:
  # In Prometheus UI, run this query:
  flask_http_request_total

What to capture:
- Table or graph showing request counts
- Labels visible: endpoint, method, status
```

---

### Grafana — Log Explorer (Loki)

```
[SCREENSHOT PLACEHOLDER]
File: docs/screenshots/16-grafana-logs.png

How to get this screenshot:
  # In Grafana → Explore → Select Loki datasource
  # Run: {namespace="expense-tracker", app="expense-web"}

What to capture:
- Log lines streaming in the Explore panel
- JSON fields parsed (level, logger, message visible as columns)
- Filter bar showing the LogQL query
```

---

## Tips for Taking Screenshots

- Use **1280×800** window size for consistent screenshots
- Show the URL bar when capturing the app to prove it runs on the correct host
- For terminal screenshots, use a dark theme (looks cleaner in docs)
- On Mac: `Cmd+Shift+4` for region screenshot
- On Windows: `Win+Shift+S` for region screenshot
- On Linux: `gnome-screenshot -a` or `flameshot gui`

## How to embed in README

```markdown
## Screenshots

### Student Dashboard
![Student Dashboard](docs/screenshots/03-student-dashboard.png)

### Grafana Dashboard
![Grafana Monitoring](docs/screenshots/13-grafana-dashboard.png)
```
