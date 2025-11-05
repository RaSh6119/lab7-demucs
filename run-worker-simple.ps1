# Simple worker runner - ensures everything is set up correctly

Write-Host "=== Worker Setup and Runner ===" -ForegroundColor Cyan
Write-Host ""

# Check if port-forwards are needed
Write-Host "Checking port-forwards..." -ForegroundColor Yellow
$redisForward = Get-NetTCPConnection -LocalPort 6379 -ErrorAction SilentlyContinue
$minioForward = Get-NetTCPConnection -LocalPort 9000 -ErrorAction SilentlyContinue

if (-not $redisForward) {
    Write-Host "Starting Redis port-forward..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "kubectl port-forward service/redis 6379:6379" -WindowStyle Minimized
    Start-Sleep -Seconds 3
}

if (-not $minioForward) {
    Write-Host "Starting MinIO port-forward..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "kubectl port-forward -n minio-ns svc/minio-proj 9000:9000" -WindowStyle Minimized
    Start-Sleep -Seconds 3
}

Write-Host "✓ Port-forwards checked" -ForegroundColor Green

# Set environment
$env:REDIS_HOST = "localhost"
$env:REDIS_PORT = "6379"
$env:MINIO_ENDPOINT = "localhost:9000"
$env:MINIO_ACCESS_KEY = "rootuser"
$env:MINIO_SECRET_KEY = "rootpass123"
$env:MINIO_SECURE = "false"
$env:QUEUE_BUCKET = "demucs-bucket"
$env:OUTPUT_BUCKET = "demucs-output"

Write-Host "`nEnvironment variables set" -ForegroundColor Green
Write-Host "`nStarting worker..." -ForegroundColor Cyan
Write-Host "Watch for connection messages and job processing..." -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Gray

# Run worker
Set-Location worker
python worker.py

