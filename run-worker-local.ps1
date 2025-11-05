# Script to run worker locally with Kubernetes services
# This assumes Redis and MinIO are port-forwarded from Kubernetes

Write-Host "=== Running Worker Locally ===" -ForegroundColor Cyan
Write-Host ""

# Set environment variables for local execution
$env:REDIS_HOST = "localhost"
$env:REDIS_PORT = "6379"
$env:MINIO_ENDPOINT = "localhost:9000"
$env:MINIO_ACCESS_KEY = "rootuser"
$env:MINIO_SECRET_KEY = "rootpass123"
$env:MINIO_SECURE = "false"
$env:QUEUE_BUCKET = "demucs-bucket"
$env:OUTPUT_BUCKET = "demucs-output"

Write-Host "Environment variables set:" -ForegroundColor Yellow
Write-Host "  REDIS_HOST: $env:REDIS_HOST"
Write-Host "  REDIS_PORT: $env:REDIS_PORT"
Write-Host "  MINIO_ENDPOINT: $env:MINIO_ENDPOINT"
Write-Host "  MINIO_ACCESS_KEY: $env:MINIO_ACCESS_KEY"
Write-Host ""

Write-Host "Starting worker..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

# Run the worker script
cd worker
python3 worker.py
cd ..

