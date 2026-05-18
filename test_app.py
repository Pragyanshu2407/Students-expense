"""
Pytest suite for the Student Expense Tracker — Phase 1 (auth + roles).

All tests use an in-memory SQLite database via the 'testing' config, so no
Postgres instance is required to run the test suite.
"""

import pytest

from tracker import create_app, db
from tracker.models import Expense, User

# ── Fixtures ──────────────────────────────────────────────────────────────────


@pytest.fixture
def app():
    app = create_app("testing")
    with app.app_context():
        db.create_all()
        yield app
        db.session.remove()
        db.drop_all()


@pytest.fixture
def client(app):
    return app.test_client()


def _make_user(app, username, password, role="student"):
    """Helper: create a user directly in the DB and return it."""
    with app.app_context():
        user = User(username=username, email=f"{username}@test.com", role=role)
        user.set_password(password)
        db.session.add(user)
        db.session.commit()
        return user.id


def _login(client, username, password):
    return client.post(
        "/auth/login",
        data={"username": username, "password": password},
        follow_redirects=True,
    )


# ── Auth tests ────────────────────────────────────────────────────────────────


def test_register_new_user(client):
    """A new student can register and is redirected to login."""
    resp = client.post(
        "/auth/register",
        data={
            "username": "alice",
            "email": "alice@test.com",
            "password": "secret123",
            "confirm_password": "secret123",
        },
        follow_redirects=True,
    )
    assert resp.status_code == 200
    assert b"Account created" in resp.data


def test_register_duplicate_username(client, app):
    """Registration with an existing username shows an error."""
    _make_user(app, "bob", "pass123")
    resp = client.post(
        "/auth/register",
        data={
            "username": "bob",
            "email": "bob2@test.com",
            "password": "pass123",
            "confirm_password": "pass123",
        },
        follow_redirects=True,
    )
    assert b"already taken" in resp.data


def test_login_valid_credentials(client, app):
    """A registered user can log in successfully."""
    _make_user(app, "carol", "mypass")
    resp = _login(client, "carol", "mypass")
    assert resp.status_code == 200


def test_login_wrong_password(client, app):
    """Login with wrong password shows an error and stays on login page."""
    _make_user(app, "dave", "correct")
    resp = _login(client, "dave", "wrong")
    assert b"Invalid username or password" in resp.data


def test_logout(client, app):
    """Logged-in user can log out and is redirected."""
    _make_user(app, "eve", "pass123")
    _login(client, "eve", "pass123")
    resp = client.get("/auth/logout", follow_redirects=True)
    assert resp.status_code == 200


# ── Unauthenticated access ────────────────────────────────────────────────────


def test_unauthenticated_redirected_from_student_dashboard(client):
    """Unauthenticated request to student dashboard is redirected to login."""
    resp = client.get("/student/dashboard")
    assert resp.status_code == 302
    assert "/auth/login" in resp.headers["Location"]


def test_unauthenticated_redirected_from_admin_dashboard(client):
    """Unauthenticated request to admin dashboard is redirected."""
    resp = client.get("/admin/dashboard")
    assert resp.status_code == 302


# ── Student role tests ────────────────────────────────────────────────────────


def test_student_can_view_dashboard(client, app):
    _make_user(app, "stu", "pass123", role="student")
    _login(client, "stu", "pass123")
    resp = client.get("/student/dashboard")
    assert resp.status_code == 200
    assert b"Add Expense" in resp.data


def test_student_can_add_expense(client, app):
    _make_user(app, "stu2", "pass123", role="student")
    _login(client, "stu2", "pass123")
    resp = client.post(
        "/student/dashboard",
        data={"title": "Textbook", "amount": "45.00", "category": "Books", "date": "2024-09-01"},
        follow_redirects=True,
    )
    assert resp.status_code == 200
    assert b"Textbook" in resp.data


def test_student_can_delete_own_expense(client, app):
    uid = _make_user(app, "stu3", "pass123", role="student")
    with app.app_context():
        exp = Expense(title="Lunch", amount=10.0, category="Food", date="2024-01-01", user_id=uid)
        db.session.add(exp)
        db.session.commit()
        eid = exp.id

    _login(client, "stu3", "pass123")
    resp = client.post(f"/student/expense/{eid}/delete", follow_redirects=True)
    assert resp.status_code == 200

    with app.app_context():
        assert db.session.get(Expense, eid) is None


def test_student_cannot_delete_other_users_expense(client, app):
    uid1 = _make_user(app, "stu4", "pass123", role="student")
    _make_user(app, "stu5", "pass123", role="student")

    with app.app_context():
        exp = Expense(title="Mine", amount=5.0, category="Other", date="2024-01-01", user_id=uid1)
        db.session.add(exp)
        db.session.commit()
        eid = exp.id

    _login(client, "stu5", "pass123")
    resp = client.post(f"/student/expense/{eid}/delete")
    # 404 because filter_by(user_id=current_user.id) won't find it
    assert resp.status_code == 404


def test_student_cannot_access_admin_dashboard(client, app):
    _make_user(app, "stu6", "pass123", role="student")
    _login(client, "stu6", "pass123")
    resp = client.get("/admin/dashboard", follow_redirects=True)
    assert b"Admin access required" in resp.data


# ── Admin role tests ──────────────────────────────────────────────────────────


def test_admin_can_view_dashboard(client, app):
    _make_user(app, "adm", "adminpass", role="admin")
    _login(client, "adm", "adminpass")
    resp = client.get("/admin/dashboard")
    assert resp.status_code == 200
    assert b"All Users" in resp.data


def test_admin_can_delete_any_expense(client, app):
    uid = _make_user(app, "student_x", "pass123", role="student")
    _make_user(app, "adm2", "adminpass", role="admin")

    with app.app_context():
        exp = Expense(
            title="ToDelete", amount=9.0, category="Other", date="2024-01-01", user_id=uid
        )
        db.session.add(exp)
        db.session.commit()
        eid = exp.id

    _login(client, "adm2", "adminpass")
    resp = client.post(f"/admin/expense/{eid}/delete", follow_redirects=True)
    assert resp.status_code == 200

    with app.app_context():
        assert db.session.get(Expense, eid) is None


def test_admin_can_delete_user(client, app):
    uid = _make_user(app, "student_y", "pass123", role="student")
    _make_user(app, "adm3", "adminpass", role="admin")

    _login(client, "adm3", "adminpass")
    resp = client.post(f"/admin/user/{uid}/delete", follow_redirects=True)
    assert resp.status_code == 200

    with app.app_context():
        assert db.session.get(User, uid) is None


def test_admin_cannot_delete_own_account(client, app):
    uid = _make_user(app, "adm4", "adminpass", role="admin")
    _login(client, "adm4", "adminpass")
    resp = client.post(f"/admin/user/{uid}/delete", follow_redirects=True)
    # Redirect back to admin dashboard — the account must still exist
    assert resp.status_code == 200
    with app.app_context():
        assert db.session.get(User, uid) is not None


# ── Health endpoint ───────────────────────────────────────────────────────────


def test_health_endpoint(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"
