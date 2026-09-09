# Multi-stage build: install deps in one layer, run lean.
# Python apps can't use distroless the way Go binaries can (no static binary),
# so the runtime stage stays on python:slim with a non-root user.
FROM python:3.14-slim AS builder
WORKDIR /build
RUN python -m venv /venv
ENV PATH="/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.14-slim
WORKDIR /app
COPY --from=builder /venv /venv
ENV PATH="/venv/bin:$PATH"
COPY . ./app

# Semver (vMAJOR.MINOR.PATCH) injected by CI from the git tag or branch.
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION

RUN useradd --create-home appuser
USER appuser

EXPOSE 8080
CMD ["gunicorn", "-w", "2", "-k", "uvicorn.workers.UvicornWorker", "-b", "0.0.0.0:8080", "app.main:app"]
