# =============================================================================
# Simulator Dockerfile — using Poetry for dependency management
# =============================================================================

FROM python:3.11-slim

# -----------------------------------------------------------------------------
# Environment variables controlling Python and Poetry behaviour
# -----------------------------------------------------------------------------
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    POETRY_VERSION=1.8.3 \
    POETRY_HOME="/opt/poetry" \
    POETRY_VIRTUALENVS_CREATE=false \
    # KEY FIX: never create a virtualenv — install directly into system Python.
    # In Docker the container itself is the isolation layer, so virtualenvs
    # are redundant and cause the exact "module not found" error we just hit.
    POETRY_NO_INTERACTION=1

ENV PATH="$POETRY_HOME/bin:$PATH"

WORKDIR /app

# -----------------------------------------------------------------------------
# Install Poetry via the official installer
# We remove curl immediately after to reduce the image attack surface
# -----------------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && curl -sSL https://install.python-poetry.org | python3 - \
    && apt-get remove -y curl \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install Python dependencies
# Copy lock files first so Docker caches this layer — if pyproject.toml and
# poetry.lock don't change, Docker reuses the cache even if simulate.py changes
# -----------------------------------------------------------------------------
COPY pyproject.toml poetry.lock ./

RUN poetry install --only=main --no-root
# --only=main : production deps only, skips dev group (black, ruff)
# --no-root   : don't install the project itself as a package

# -----------------------------------------------------------------------------
# Application code — copied last to avoid busting the dependency cache
# -----------------------------------------------------------------------------
COPY simulate.py .

# Run as non-root user for security
RUN useradd --create-home --shell /bin/bash simulator
USER simulator

# Call Python directly — no need for 'poetry run' since packages are
# installed into the system Python (POETRY_VIRTUALENVS_CREATE=false)
CMD ["python", "-u", "simulate.py"]