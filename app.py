from flask import Flask, request, jsonify
import sqlite3
import os

app = Flask(__name__)

DB_PATH = os.environ.get("DB_PATH", "expenses.db")


# ── Database helpers ──────────────────────────────────────────────────────────

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with get_db() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS expenses (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                title     TEXT    NOT NULL,
                amount    REAL    NOT NULL,
                category  TEXT    NOT NULL DEFAULT 'Other',
                date      TEXT    NOT NULL DEFAULT (DATE('now'))
            )
            """
        )
        conn.commit()


init_db()


# ── Routes ────────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return jsonify({
        "app": "Student Expense Tracker 🎓",
        "version": "1.0.0",
        "endpoints": {
            "GET  /expenses":            "List all expenses",
            "POST /expenses":            "Add a new expense",
            "DELETE /expenses/<id>":     "Delete an expense by ID",
        },
    })


@app.route("/expenses", methods=["GET"])
def get_expenses():
    """Return all expenses, newest first."""
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM expenses ORDER BY date DESC, id DESC"
        ).fetchall()
    expenses = [dict(row) for row in rows]
    total = sum(e["amount"] for e in expenses)
    return jsonify({"expenses": expenses, "total": round(total, 2), "count": len(expenses)})


@app.route("/expenses", methods=["POST"])
def add_expense():
    """
    Add a new expense.

    Expected JSON body:
        { "title": "Textbooks", "amount": 45.99, "category": "Education", "date": "2024-09-01" }

    `category` and `date` are optional.
    """
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "Request body must be JSON"}), 400

    title = (data.get("title") or "").strip()
    amount = data.get("amount")

    if not title:
        return jsonify({"error": "Field 'title' is required"}), 400
    if amount is None:
        return jsonify({"error": "Field 'amount' is required"}), 400

    try:
        amount = float(amount)
    except (TypeError, ValueError):
        return jsonify({"error": "'amount' must be a number"}), 400

    if amount <= 0:
        return jsonify({"error": "'amount' must be greater than zero"}), 400

    category = (data.get("category") or "Other").strip()
    date = (data.get("date") or "").strip() or None          # None → DB default (today)

    with get_db() as conn:
        if date:
            cursor = conn.execute(
                "INSERT INTO expenses (title, amount, category, date) VALUES (?, ?, ?, ?)",
                (title, amount, category, date),
            )
        else:
            cursor = conn.execute(
                "INSERT INTO expenses (title, amount, category) VALUES (?, ?, ?)",
                (title, amount, category),
            )
        conn.commit()
        new_id = cursor.lastrowid
        row = conn.execute("SELECT * FROM expenses WHERE id = ?", (new_id,)).fetchone()

    return jsonify({"message": "Expense added", "expense": dict(row)}), 201


@app.route("/expenses/<int:expense_id>", methods=["DELETE"])
def delete_expense(expense_id):
    """Delete an expense by its integer ID."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM expenses WHERE id = ?", (expense_id,)
        ).fetchone()
        if row is None:
            return jsonify({"error": f"Expense {expense_id} not found"}), 404
        conn.execute("DELETE FROM expenses WHERE id = ?", (expense_id,))
        conn.commit()

    return jsonify({"message": f"Expense {expense_id} deleted", "expense": dict(row)})


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
