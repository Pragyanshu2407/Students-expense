"""
Pytest test suite for the Student Expense Tracker Flask app.
Uses an isolated in-memory SQLite database so tests never touch production data.
"""

import os
import tempfile
import pytest

# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture
def client(tmp_path):
    """Return a Flask test client backed by a fresh temporary SQLite DB."""
    # Point the app at a unique temp file BEFORE importing so init_db() uses it.
    db_file = str(tmp_path / "test_expenses.db")
    os.environ["DB_PATH"] = db_file

    # Import (or re-use) the app module after the env var is set.
    import importlib
    import app as flask_app
    # Reload so DB_PATH is re-read at module level and init_db() runs fresh.
    importlib.reload(flask_app)

    flask_app.app.config["TESTING"] = True

    with flask_app.app.test_client() as c:
        yield c


# ── Test 1: Add an expense and verify the response ────────────────────────────

def test_add_expense(client):
    """POST /expenses should create a new expense and return 201."""
    payload = {
        "title": "Python Textbook",
        "amount": 39.99,
        "category": "Education",
        "date": "2024-09-01",
    }
    response = client.post("/expenses", json=payload)

    assert response.status_code == 201, response.get_json()

    body = response.get_json()
    assert body["message"] == "Expense added"
    expense = body["expense"]
    assert expense["title"] == "Python Textbook"
    assert expense["amount"] == 39.99
    assert expense["category"] == "Education"
    assert expense["date"] == "2024-09-01"
    assert "id" in expense


# ── Test 2: View all expenses ─────────────────────────────────────────────────

def test_view_expenses(client):
    """GET /expenses should return all stored expenses with correct totals."""
    # Seed two expenses
    client.post("/expenses", json={"title": "Lunch",    "amount": 8.50,  "category": "Food"})
    client.post("/expenses", json={"title": "Bus Pass",  "amount": 30.00, "category": "Transport"})

    response = client.get("/expenses")
    assert response.status_code == 200

    body = response.get_json()
    assert body["count"] == 2
    assert abs(body["total"] - 38.50) < 0.001    # float-safe comparison

    titles = {e["title"] for e in body["expenses"]}
    assert "Lunch" in titles
    assert "Bus Pass" in titles


# ── Test 3: Delete an expense ─────────────────────────────────────────────────

def test_delete_expense(client):
    """DELETE /expenses/<id> should remove the expense; a second call returns 404."""
    # Create an expense and grab its ID
    create_resp = client.post(
        "/expenses",
        json={"title": "Coffee", "amount": 3.50, "category": "Food"},
    )
    expense_id = create_resp.get_json()["expense"]["id"]

    # Delete it
    del_resp = client.delete(f"/expenses/{expense_id}")
    assert del_resp.status_code == 200
    assert del_resp.get_json()["message"] == f"Expense {expense_id} deleted"

    # Confirm it's gone – the list should now be empty
    list_resp = client.get("/expenses")
    assert list_resp.get_json()["count"] == 0

    # Attempting to delete again should yield 404
    second_del = client.delete(f"/expenses/{expense_id}")
    assert second_del.status_code == 404
