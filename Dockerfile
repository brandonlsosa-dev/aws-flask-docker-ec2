FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
run pip install --no-cache-dir -r requirements.txt
COPY app/ .
EXPOSE 5000
CMD ["gunicorn", "-b", "0.0.0.0:5000", "app:app"]
