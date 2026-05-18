from flask import Blueprint, jsonify, redirect, url_for
from flask_login import current_user

main = Blueprint("main", __name__)


@main.route("/")
def index():
    if current_user.is_authenticated:
        if current_user.is_admin:
            return redirect(url_for("admin.dashboard"))
        return redirect(url_for("student.dashboard"))
    return redirect(url_for("auth.login"))


@main.route("/health")
def health():
    return jsonify({"status": "ok"}), 200
