FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir uv
RUN uv pip install --system \
	fastapi==0.116.1 \
	httpx==0.28.1 \
	uvicorn==0.35.0

COPY app.py /app/app.py

EXPOSE 8080

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
