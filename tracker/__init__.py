from flask import Flask
from flask_login import LoginManager
from flask_sqlalchemy import SQLAlchemy
from prometheus_flask_exporter import PrometheusMetrics

from config import config

db = SQLAlchemy()
login_manager = LoginManager()
login_manager.login_view = "auth.login"
login_manager.login_message = "Please log in to access this page."
login_manager.login_message_category = "warning"

# Module-level handle so gunicorn.conf.py can access `metrics` if needed.
# Initialised inside create_app so the registry is per-app, not per-import.
metrics = PrometheusMetrics.for_app_factory()


def create_app(config_name: str = "default") -> Flask:
    app = Flask(__name__)
    app.config.from_object(config[config_name])

    db.init_app(app)
    login_manager.init_app(app)

    # Skip Prometheus instrumentation in tests — avoids duplicate-registry errors
    # when multiple test fixtures each call create_app().
    if not app.config.get("TESTING"):
        metrics.init_app(app)

    from tracker.admin import admin_bp
    from tracker.auth import auth as auth_bp
    from tracker.main import main as main_bp
    from tracker.student import student as student_bp

    app.register_blueprint(auth_bp, url_prefix="/auth")
    app.register_blueprint(student_bp, url_prefix="/student")
    app.register_blueprint(admin_bp, url_prefix="/admin")
    app.register_blueprint(main_bp)

    return app
