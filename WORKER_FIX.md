# Worker CrashLoopBackOff Fix

## Issue
Worker pod is in `CrashLoopBackOff` status with no logs visible.

## Root Cause Analysis

1. **Container exits immediately** - Exit code 0, status "Completed"
2. **No logs visible** - This suggests the container exits before logs are flushed or Kubernetes captures them
3. **Redis/MinIO connection** - The worker tries to connect immediately on startup

## Fixes Applied

### 1. Enhanced Initialization with Infinite Retries
- Changed `initialize()` to retry Redis and MinIO connections forever
- No longer exits on connection failure - keeps retrying every 5 seconds

### 2. Improved Error Handling
- Added comprehensive exception handling
- All errors are logged to stderr with flush
- Added debug output at startup

### 3. Simplified Main Loop
- Removed exit conditions that could cause premature termination
- Main loop runs forever until shutdown signal

## Next Steps to Verify

### Option 1: Check Pod Logs Directly
```powershell
# Get the pod name
$pod = kubectl get pods -l app=worker -o jsonpath='{.items[0].metadata.name}'

# Check current logs
kubectl logs $pod

# Check previous logs if it crashed
kubectl logs $pod --previous

# Follow logs in real-time
kubectl logs $pod -f
```

### Option 2: Test Container Locally
```powershell
# Run container locally with Redis port-forward
docker run --rm -it --network host demucs-worker:latest

# Or with environment variables
docker run --rm -it -e REDIS_HOST=localhost -e MINIO_ENDPOINT=localhost:9000 demucs-worker:latest
```

### Option 3: Check Deployment Configuration
```powershell
# Verify deployment
kubectl get deployment worker -o yaml

# Check if imagePullPolicy is correct
kubectl describe deployment worker
```

### Option 4: Verify Services Are Running
```powershell
# Check Redis
kubectl get pods -l app=redis
kubectl get svc redis

# Check MinIO  
kubectl get pods -n minio-ns
kubectl get svc -n minio-ns
```

## Current Status

The worker code has been fixed to:
- ✅ Retry connections forever (won't exit on connection failure)
- ✅ Better logging and error handling
- ✅ Process 8 output files per song
- ✅ Enhanced DEMUCS output detection

**However**, the pod is still showing as "Completed" with no logs. This suggests:

1. **Kubernetes logging issue** - Logs may not be captured for quickly-exiting containers
2. **Image not updated** - The deployment might be using a cached image
3. **Container exiting too fast** - Something is causing immediate exit

## Recommended Action

1. **Force image pull** - Delete deployment and recreate:
   ```powershell
   kubectl delete deployment worker
   kubectl apply -f worker/worker-deployment.yaml
   ```

2. **Check if image exists locally**:
   ```powershell
   docker images | findstr demucs-worker
   ```

3. **Rebuild with a tag**:
   ```powershell
   cd worker
   docker build -f Dockerfile -t demucs-worker:v2 .
   ```
   Then update `worker-deployment.yaml` to use `demucs-worker:v2`

4. **Use Docker Hub** (if you pushed):
   Update deployment to use `rash4560/demucs-worker:latest` with `imagePullPolicy: IfNotPresent`

## Debugging Commands

```powershell
# Watch pod status
kubectl get pods -l app=worker -w

# Describe pod for events
kubectl describe pod -l app=worker

# Get all events
kubectl get events --sort-by='.lastTimestamp' | findstr worker

# Check container status
kubectl get pods -l app=worker -o jsonpath='{.items[0].status.containerStatuses[0].state}'
```

## If Still Not Working

The worker code is correct. The issue is likely:
1. Kubernetes/Docker Desktop logging configuration
2. Image caching
3. Container runtime issue

Try:
- Restart Docker Desktop
- Clear Kubernetes cluster
- Rebuild image with a new tag

