FROM python:3.11-slim
RUN python -m venv /venv && /venv/bin/pip install flask gunicorn --quiet
WORKDIR /app
COPY webapp.py .
CMD ["/venv/bin/gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "webapp:app"]