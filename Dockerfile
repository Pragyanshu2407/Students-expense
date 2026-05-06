# ── Stage 1: base image ───────────────────────────────────────────────────────
FROM python:3.12-slim AS base

# Keeps Python from buffering stdout/stderr (helpful for container logs)
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Install dependencies in a separate layer so Docker can cache them
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Stage 2: app ──────────────────────────────────────────────────────────────
FROM base AS app

COPY app.py .

# The SQLite database will live inside the container at /data/expenses.db.
# Mount a named volume to /data to persist data across container restarts.
ENV DB_PATH=/data/expenses.db
RUN mkdir -p /data

EXPOSE 5000

# Run with the built-in Flask dev server (replace with gunicorn for production)
CMD ["python", "app.py"]
