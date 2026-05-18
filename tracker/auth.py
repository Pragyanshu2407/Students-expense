from flask import Blueprint, flash, redirect, render_template, request, url_for
from flask_login import current_user, login_required, login_user, logout_user

from tracker import db
from tracker.models import User

auth = Blueprint("auth", __name__)


@auth.route("/login", methods=["GET", "POST"])
def login():
    if current_user.is_authenticated:
        return _redirect_by_role(current_user)

    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        remember = bool(request.form.get("remember"))

        user = User.query.filter_by(username=username).first()
        if user and user.check_password(password):
            login_user(user, remember=remember)
            next_page = request.args.get("next")
            return redirect(next_page) if next_page else _redirect_by_role(user)

        flash("Invalid username or password.", "danger")

    return render_template("auth/login.html")


@auth.route("/register", methods=["GET", "POST"])
def register():
    if current_user.is_authenticated:
        return _redirect_by_role(current_user)

    if request.method == "POST":
        username = request.form.get("username", "").strip()
        email = request.form.get("email", "").strip()
        password = request.form.get("password", "")
        confirm = request.form.get("confirm_password", "")

        error = _validate_registration(username, email, password, confirm)
        if error:
            flash(error, "danger")
        else:
            user = User(username=username, email=email, role="student")
            user.set_password(password)
            db.session.add(user)
            db.session.commit()
            flash("Account created! Please log in.", "success")
            return redirect(url_for("auth.login"))

    return render_template("auth/register.html")


@auth.route("/logout")
@login_required
def logout():
    logout_user()
    flash("You have been logged out.", "info")
    return redirect(url_for("auth.login"))


def _redirect_by_role(user):
    if user.is_admin:
        return redirect(url_for("admin.dashboard"))
    return redirect(url_for("student.dashboard"))


def _validate_registration(username, email, password, confirm):
    if not username or not email or not password:
        return "All fields are required."
    if password != confirm:
        return "Passwords do not match."
    if len(password) < 6:
        return "Password must be at least 6 characters."
    if User.query.filter_by(username=username).first():
        return "Username already taken."
    if User.query.filter_by(email=email).first():
        return "Email already registered."
    return None
