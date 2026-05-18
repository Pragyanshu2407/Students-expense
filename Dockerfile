# =============================================================================
# Multi-stage Dockerfile — Student Expense Tracker
# =============================================================================
#
# Stage 1 (base)    — shared Python base image with common env vars
# Stage 2 (builder) — installs ALL Python packages into an isolated virtualenv
# Stage 3 (app)     — lean production image; only copies the venv from builder
#
# Why three stages?
#   The builder stage needs compilers and header files (gcc, libpq-dev) to
#   compile any C-extension wheels.  Those tools are NOT copied to the final
#   image, so the production image stays small and has a smaller attack surface.
# =============================================================================


# ── Stage 1: base ─────────────────────────────────────────────────────────────
FROM python:3.12-slim AS base

# PYTHONUNBUFFERED  → print() and log output appear immediately in `docker logs`
# PYTHONDONTWRITEBYTECODE → skip .pyc files (useless inside a container)
# PIP_*             → speed up pip, suppress noise
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1


# ── Stage 2: builder ──────────────────────────────────────────────────────────
FROM base AS builder

WORKDIR /build

# Build-time OS packages needed to compile C-extension wheels (e.g. psycopg2).
# These stay in THIS stage only — they are never copied to the app image.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Create a virtualenv and install everything into it.
# Using a venv makes it trivial to COPY --from=builder the whole thing.
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip && \
    /opt/venv/bin/pip install -r requirements.txt


# ── Stage 3: app (production) ─────────────────────────────────────────────────
FROM base AS app

WORKDIR /app

# curl is the only extra OS package we need — used by the Docker health check.
# libpq5 is the PostgreSQL client runtime library (needed by psycopg2-binary
# on some platforms).  Not needed for binary wheels, but harmless to include.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        libpq5 \
    && rm -rf /var/lib/apt/lists/*

# ── Security: run as a non-root user ──────────────────────────────────────────
# Running as root inside a container is unnecessary and dangerous.
# If the app is ever exploited, the attacker gets a non-privileged shell.
RUN groupadd --system --gid 1001 appgroup && \
    useradd  --system --uid 1001 --gid appgroup --no-create-home appuser

# Copy the entire virtualenv from the builder stage.
# This is the key multi-stage trick: we get all packages WITHOUT the compilers.
COPY --from=builder /opt/venv /opt/venv

# Put the venv's bin/ directory on PATH so `gunicorn`, `python`, etc. resolve
# to the venv versions automatically.
ENV PATH="/opt/venv/bin:$PATH" \
    VIRTUAL_ENV="/opt/venv"

# Copy application source and assign ownership to the non-root user.
COPY --chown=appuser:appgroup tracker/         tracker/
COPY --chown=appuser:appgroup config.py        .
COPY --chown=appuser:appgroup run.py           .
COPY --chown=appuser:appgroup app.py           .
COPY --chown=appuser:appgroup gunicorn.conf.py .

# Switch to non-root before the final CMD
USER appuser

# Flask / gunicorn listen on 5000 inside the container.
# Nginx (defined in docker-compose) listens on 80 externally.
EXPOSE 5000

# gunicorn reads all settings (workers, timeouts, hooks, logging) from
# gunicorn.conf.py.  The `run:app` argument tells it which WSGI application
# object to serve (the `app` variable inside run.py).
CMD ["gunicorn", "--config", "gunicorn.conf.py", "run:app"]
