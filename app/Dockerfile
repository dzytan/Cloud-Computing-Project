# ===== Stage 1: Builder – cài dependencies vào virtual env =====
FROM python:3.11-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN python -m venv /app/venv && \
    /app/venv/bin/pip install --no-cache-dir -r requirements.txt


# ===== Stage 2: Runtime – image nhẹ, chỉ chứa app + venv =====
FROM python:3.11-slim

WORKDIR /app

# Tạo non-root user (appuser UID=10001) để tuân thủ securityContext
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /bin/sh -m appuser

# Copy virtual env từ builder stage
COPY --from=builder /app/venv /app/venv

# Sao chép mã nguồn ứng dụng
COPY main.py .

# Build arguments cho các kịch bản thử nghiệm
ARG APP_VERSION=v1
ARG BROKEN=false

ENV APP_VERSION=${APP_VERSION}
ENV BROKEN=${BROKEN}
ENV PORT=8000
ENV PATH="/app/venv/bin:$PATH"

# Chuyển sang non-root user
USER 10001

EXPOSE 8000

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
