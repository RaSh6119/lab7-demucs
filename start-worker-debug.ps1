# Debug script to start worker with full output visible
# Run this in a separate terminal window to see what's happening

Write-Host "=== Starting Worker in Debug Mode ===" -ForegroundColor Cyan
Write-Host ""

# Set environment variables
$env:REDIS_HOST = "localhost"
$env:REDIS_PORT = "6379"
$env:MINIO_ENDPOINT = "localhost:9000"
$env:MINIO_ACCESS_KEY = "rootuser"
$env:MINIO_SECRET_KEY = "rootpass123"
$env:MINIO_SECURE = "false"
$env:QUEUE_BUCKET = "demucs-bucket"
$env:OUTPUT_BUCKET = "demucs-output"

Write-Host "Environment configured:" -ForegroundColor Green
Write-Host "  REDIS_HOST: $env:REDIS_HOST"
Write-Host "  REDIS_PORT: $env:REDIS_PORT"
Write-Host "  MINIO_ENDPOINT: $env:MINIO_ENDPOINT"
Write-Host ""

# Test connections first
Write-Host "Testing Redis connection..." -ForegroundColor Yellow
try {
    python -c "import redis; r = redis.StrictRedis(host='localhost', port=6379); r.ping(); print('✓ Redis connection OK')" 2>&1
} catch {
    Write-Host "✗ Redis connection failed!" -ForegroundColor Red
    Write-Host "Make sure port-forward is running: kubectl port-forward service/redis 6379:6379" -ForegroundColor Yellow
    exit 1
}

Write-Host "`nTesting MinIO connection..." -ForegroundColor Yellow
try {
    python -c "from minio import Minio; m = Minio('localhost:9000', access_key='rootuser', secret_key='rootpass123', secure=False); m.list_buckets(); print('✓ MinIO connection OK')" 2>&1
} catch {
    Write-Host "✗ MinIO connection failed!" -ForegroundColor Red
    Write-Host "Make sure port-forward is running: kubectl port-forward -n minio-ns svc/minio-proj 9000:9000" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n✓ All connections OK!" -ForegroundColor Green
Write-Host "`nStarting worker..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

# Change to worker directory and run
cd worker
python worker.py

