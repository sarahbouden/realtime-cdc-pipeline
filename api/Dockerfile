FROM python:3.11-slim
ENV PYTHONUNBUFFERED=1
RUN pip install --no-cache-dir duckdb==1.1.3
WORKDIR /app
COPY main.py .
CMD ["python", "-u", "main.py"]