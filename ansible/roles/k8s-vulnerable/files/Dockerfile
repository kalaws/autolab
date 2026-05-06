FROM python:3.11-slim
RUN python -m venv /venv && /venv/bin/pip install flask --quiet
WORKDIR /app
COPY webapp.py .
CMD ["/venv/bin/python", "webapp.py"]