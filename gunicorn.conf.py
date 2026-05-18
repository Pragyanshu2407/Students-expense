"""
Gunicorn configuration — used in production (inside Docker).

Why gunicorn instead of Flask's built-in server:
  - Flask dev server is single-threaded and not safe for production traffic.
  - Gunicorn spawns multiple worker processes that each handle requests
    independently, giving better throughput and crash isolation.

Worker math:
  A common starting point is (2 × CPU_cores) + 1.
  We keep it low here (2) because the DB is the real bottleneck, not the CPU.
  Raise GUNICORN_WORKERS in .env as the server grows.
"""

import os
import time

# ── Network ───────────────────────────────────────────────────────────────────

bind = f"0.0.0.0:{os.environ.get('PORT', '5000')}"

# ── Workers ───────────────────────────────────────────────────────────────────

# Each worker is a separate OS process.  Threads let a worker handle multiple
# requests concurrently while one is waiting on I/O (e.g. a slow DB query).
workers = int(os.environ.get("GUNICORN_WORKERS", 2))
threads = int(os.environ.get("GUNICORN_THREADS", 2))
worker_class = "sync"  # switch to "gthread" if you increase threads > 1

# Kill and restart a worker if it takes longer than this to handle a request.
timeout = int(os.environ.get("GUNICORN_TIMEOUT", 60))

# ── Logging ───────────────────────────────────────────────────────────────────

# "-" means write to stdout/stderr, which Docker captures as container logs.
accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("LOG_LEVEL", "info")

# Include timestamp + remote IP in every access log line.
access_log_format = '%(t)s %(h)s "%(r)s" %(s)s %(b)s'

# ── Lifecycle hooks ───────────────────────────────────────────────────────────


def on_starting(server):
    """
    Runs once in the master process BEFORE any worker is forked.

    This is the correct place to:
      1. Wait for the PostgreSQL container to accept connections.
      2. Run db.create_all() so every table exists.
      3. Seed a default admin account on first boot.

    We do NOT put this in run.py's module body because gunicorn imports
    `run.app` without executing the `if __name__ == '__main__'` block.
    """
    from sqlalchemy.exc import OperationalError

    from tracker import create_app, db
    from tracker.models import User

    env = os.environ.get("FLASK_ENV", "production")
    app = create_app(env)

    max_retries = 15
    for attempt in range(1, max_retries + 1):
        try:
            with app.app_context():
                db.create_all()

                if not User.query.filter_by(role="admin").first():
                    admin_password = os.environ.get("ADMIN_PASSWORD", "admin123")
                    admin = User(
                        username="admin",
                        email="admin@example.com",
                        role="admin",
                    )
                    admin.set_password(admin_password)
                    db.session.add(admin)
                    db.session.commit()
                    server.log.info("Default admin account created (username: admin)")

                server.log.info("Database initialised successfully")
            return
        except OperationalError:
            if attempt == max_retries:
                raise RuntimeError("Database is not reachable — giving up after %d attempts" % max_retries)
            server.log.warning(
                "Database not ready (attempt %d/%d) — retrying in 3 s…",
                attempt,
                max_retries,
            )
            time.sleep(3)
