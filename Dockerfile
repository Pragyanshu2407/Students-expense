# ── Stage 1: base — install Python dependencies ───────────────────────────────
FROM python:3.12-slim AS base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Stage 2: app — copy source and run ────────────────────────────────────────
FROM base AS app

# Copy application source (tracker package, config, entry point)
COPY tracker/ tracker/
COPY config.py run.py app.py ./

EXPOSE 5000

# run.py handles DB init + admin seeding before starting Flask
CMD ["python", "run.py"]
