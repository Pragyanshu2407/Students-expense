import logging
import os
import time

from pythonjsonlogger import jsonlogger
from sqlalchemy.exc import OperationalError

from tracker import create_app, db
from tracker.models import User


def _configure_logging() -> None:
    """Switch the root logger to JSON format so log shippers (Promtail/Loki) can
    parse fields like level, message, and timestamp without regex gymnastics."""
    handler = logging.StreamHandler()
    handler.setFormatter(
        jsonlogger.JsonFormatter(
            fmt="%(asctime)s %(levelname)s %(name)s %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S",
        )
    )
    root = logging.getLogger()
    root.handlers = []
    root.addHandler(handler)
    level = os.environ.get("LOG_LEVEL", "INFO").upper()
    root.setLevel(getattr(logging, level, logging.INFO))


_configure_logging()

env = os.environ.get("FLASK_ENV", "development")
app = create_app(env)


def _seed_admin() -> None:
    """Create a default admin account on first boot if none exists."""
    if not User.query.filter_by(role="admin").first():
        admin = User(username="admin", email="admin@example.com", role="admin")
        admin.set_password("admin123")
        db.session.add(admin)
        db.session.commit()
        print("Default admin created  →  username: admin  /  password: admin123")


def _init_db(max_retries: int = 10, delay: int = 3) -> None:
    """Wait for the database to be ready, then create tables and seed data."""
    for attempt in range(1, max_retries + 1):
        try:
            with app.app_context():
                db.create_all()
                _seed_admin()
            return
        except OperationalError as exc:
            if attempt == max_retries:
                raise RuntimeError(f"Database unreachable after {max_retries} attempts") from exc
            print(f"DB not ready ({attempt}/{max_retries}) — retrying in {delay}s…")
            time.sleep(delay)


if __name__ == "__main__":
    _init_db()
    app.run(host="0.0.0.0", port=5000, debug=app.config.get("DEBUG", False))
