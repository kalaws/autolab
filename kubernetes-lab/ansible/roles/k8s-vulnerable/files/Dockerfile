FROM python:3.11-slim
RUN pip install flask --quiet
WORKDIR /app
COPY webapp.py .
CMD ["python", "webapp.py"]
