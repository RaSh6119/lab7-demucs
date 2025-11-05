# Local Worker Setup Guide

This guide explains how to run the worker locally instead of deploying it in Kubernetes.

## Why Run Worker Locally?

- **Easier debugging** - See logs directly in your terminal
- **Faster development cycle** - No need to rebuild Docker images
- **Better error visibility** - Immediate feedback on issues
- **Works around Kubernetes issues** - If pod deployment has problems

## Prerequisites

1. **Kubernetes services running**:
   - Redis pod and service
   - MinIO pod and service
   - REST API pod and service

2. **Python dependencies**:
   ```powershell
   pip install minio redis requests
   ```

## Setup Steps

### Step 1: Set Up Port-Forwarding

You need to forward Redis and MinIO from Kubernetes to your local machine:

```powershell
# Forward Redis (in one terminal)
kubectl port-forward service/redis 6379:6379

# Forward MinIO (in another terminal)
kubectl port-forward -n minio-ns svc/minio-proj 9000:9000
```

Or run them in background:
```powershell
Start-Job -ScriptBlock { kubectl port-forward service/redis 6379:6379 }
Start-Job -ScriptBlock { kubectl port-forward -n minio-ns svc/minio-proj 9000:9000 }
```

### Step 2: Set Environment Variables

```powershell
$env:REDIS_HOST = "localhost"
$env:REDIS_PORT = "6379"
$env:MINIO_ENDPOINT = "localhost:9000"
$env:MINIO_ACCESS_KEY = "rootuser"
$env:MINIO_SECRET_KEY = "rootpass123"
$env:MINIO_SECURE = "false"
$env:QUEUE_BUCKET = "demucs-bucket"
$env:OUTPUT_BUCKET = "demucs-output"
```

### Step 3: Run Worker

```powershell
cd worker
python worker.py
```

Or use the helper script:
```powershell
.\run-worker-local.ps1
```

## Testing

### Submit a Test Job

1. **Using the helper script**:
   ```powershell
   .\test-job-local.ps1
   ```

2. **Using Python script**:
   ```powershell
   python short-sample-request.py
   ```

3. **Using REST API directly**:
   ```powershell
   # Make sure REST API port-forward is active
   kubectl port-forward service/rest-service 5000:5000
   
   # Then use the test script or curl
   ```

### Monitor Processing

Watch the worker terminal output to see:
- Connection attempts
- Job processing
- DEMUCS execution
- File uploads
- Any errors

### Check Results

1. **Check queue**:
   ```powershell
   Invoke-RestMethod -Uri "http://localhost:5000/apiv1/queue" -Method GET
   ```

2. **Check MinIO output bucket**:
   - Access http://localhost:9001 (MinIO console)
   - Login with rootuser/rootpass123
   - Check `demucs-output` bucket

3. **Download tracks**:
   ```powershell
   # Get songhash from queue response
   $songhash = "your-songhash-here"
   Invoke-WebRequest -Uri "http://localhost:5000/apiv1/track/$songhash/vocals" -OutFile "vocals.mp3"
   ```

## Troubleshooting

### Worker can't connect to Redis

**Check:**
```powershell
# Verify port-forward is running
netstat -an | findstr :6379

# Test connection
Test-NetConnection -ComputerName localhost -Port 6379
```

**Solution:** Restart Redis port-forward

### Worker can't connect to MinIO

**Check:**
```powershell
# Verify port-forward is running
netstat -an | findstr :9000

# Test connection
Test-NetConnection -ComputerName localhost -Port 9000
```

**Solution:** Restart MinIO port-forward

### Jobs not being processed

1. **Check if job is in queue**:
   ```powershell
   # Via REST API
   Invoke-RestMethod -Uri "http://localhost:5000/apiv1/queue"
   
   # Via Redis directly
   kubectl exec -it <redis-pod> -- redis-cli LRANGE toWorker 0 -1
   ```

2. **Check worker logs** - Look for errors in worker terminal

3. **Verify connections** - Worker should show successful Redis/MinIO connections

### DEMUCS not working

- **Memory issue** - DEMUCS needs 6-8GB RAM
- **Missing dependencies** - Check if DEMUCS is installed in your Python environment
- **File path issues** - Check worker logs for file path errors

## Advantages of Local Development

1. **Faster iteration** - No Docker rebuild needed
2. **Better debugging** - Use Python debugger, print statements work immediately
3. **Easier testing** - Test changes instantly
4. **Log visibility** - See all output in real-time

## Switching Back to Kubernetes

When ready to deploy to Kubernetes:

1. **Rebuild Docker image**:
   ```powershell
   cd worker
   docker build -f Dockerfile -t demucs-worker:latest .
   ```

2. **Update deployment**:
   ```powershell
   kubectl apply -f worker/worker-deployment.yaml
   ```

3. **Stop local worker** (Ctrl+C)

4. **Stop port-forwards** (if not needed)

## Quick Reference

```powershell
# Start port-forwards
Start-Job -ScriptBlock { kubectl port-forward service/redis 6379:6379 }
Start-Job -ScriptBlock { kubectl port-forward -n minio-ns svc/minio-proj 9000:9000 }
Start-Job -ScriptBlock { kubectl port-forward service/rest-service 5000:5000 }

# Set environment
$env:REDIS_HOST = "localhost"; $env:REDIS_PORT = "6379"
$env:MINIO_ENDPOINT = "localhost:9000"
$env:MINIO_ACCESS_KEY = "rootuser"; $env:MINIO_SECRET_KEY = "rootpass123"

# Run worker
cd worker; python worker.py

# Submit test job
python ..\short-sample-request.py
```

