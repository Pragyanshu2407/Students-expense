from datetime import date

from flask import Blueprint, flash, redirect, render_template, request, url_for
from flask_login import current_user, login_required

from tracker import db
from tracker.models import Expense

student = Blueprint("student", __name__)

CATEGORIES = ["Food", "Transport", "Books", "Entertainment", "Health", "Utilities", "Other"]


@student.route("/dashboard", methods=["GET", "POST"])
@login_required
def dashboard():
    if request.method == "POST":
        title = request.form.get("title", "").strip()
        amount_raw = request.form.get("amount", "")
        category = request.form.get("category", "Other").strip()
        expense_date = request.form.get("date", "") or str(date.today())

        error = _validate_expense(title, amount_raw)
        if error:
            flash(error, "danger")
        else:
            db.session.add(
                Expense(
                    title=title,
                    amount=float(amount_raw),
                    category=category,
                    date=expense_date,
                    user_id=current_user.id,
                )
            )
            db.session.commit()
            flash("Expense added successfully!", "success")
            return redirect(url_for("student.dashboard"))

    expenses = (
        Expense.query.filter_by(user_id=current_user.id).order_by(Expense.created_at.desc()).all()
    )
    total = sum(e.amount for e in expenses)
    return render_template(
        "student/dashboard.html",
        expenses=expenses,
        total=total,
        categories=CATEGORIES,
        today=str(date.today()),
    )


@student.route("/expense/<int:expense_id>/delete", methods=["POST"])
@login_required
def delete_expense(expense_id):
    # filter_by(user_id=...) ensures students can only delete their own expenses
    expense = Expense.query.filter_by(id=expense_id, user_id=current_user.id).first_or_404()
    db.session.delete(expense)
    db.session.commit()
    flash("Expense deleted.", "success")
    return redirect(url_for("student.dashboard"))


def _validate_expense(title: str, amount_raw: str):
    if not title:
        return "Title is required."
    try:
        if float(amount_raw) <= 0:
            return "Amount must be greater than 0."
    except (ValueError, TypeError):
        return "Amount must be a valid number."
    return None
