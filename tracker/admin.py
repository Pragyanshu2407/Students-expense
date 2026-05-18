from functools import wraps

from flask import Blueprint, flash, redirect, render_template, url_for
from flask_login import current_user, login_required

from tracker import db
from tracker.models import Expense, User

admin_bp = Blueprint("admin", __name__)


def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not current_user.is_authenticated or not current_user.is_admin:
            flash("Admin access required.", "danger")
            return redirect(url_for("auth.login"))
        return f(*args, **kwargs)

    return decorated


@admin_bp.route("/dashboard")
@login_required
@admin_required
def dashboard():
    users = User.query.order_by(User.created_at.desc()).all()
    expenses = Expense.query.order_by(Expense.created_at.desc()).all()
    total = sum(e.amount for e in expenses)
    return render_template("admin/dashboard.html", users=users, expenses=expenses, total=total)


@admin_bp.route("/expense/<int:expense_id>/delete", methods=["POST"])
@login_required
@admin_required
def delete_expense(expense_id):
    expense = db.session.get(Expense, expense_id)
    if not expense:
        flash("Expense not found.", "warning")
        return redirect(url_for("admin.dashboard"))
    db.session.delete(expense)
    db.session.commit()
    flash("Expense deleted.", "success")
    return redirect(url_for("admin.dashboard"))


@admin_bp.route("/user/<int:user_id>/delete", methods=["POST"])
@login_required
@admin_required
def delete_user(user_id):
    if user_id == current_user.id:
        flash("You cannot delete your own account.", "danger")
        return redirect(url_for("admin.dashboard"))
    user = db.session.get(User, user_id)
    if not user:
        flash("User not found.", "warning")
        return redirect(url_for("admin.dashboard"))
    db.session.delete(user)
    db.session.commit()
    flash(f"User '{user.username}' and all their expenses have been deleted.", "success")
    return redirect(url_for("admin.dashboard"))
