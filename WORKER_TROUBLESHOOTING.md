# Worker Node Troubleshooting Guide

## Quick Diagnostic Commands

Run these commands to diagnose worker issues:

```powershell
# 1. Check worker pod status
kubectl get pods -l app=worker

# 2. Get detailed pod information
kubectl describe pod -l app=worker

# 3. Check worker logs
kubectl logs -l app=worker --tail=100

# 4. Check if Docker image exists locally
docker images | findstr demucs-worker

# 5. Check all pods status
kubectl get pods

# 6. Check Redis is running
kubectl get pods -l app=redis

# 7. Check MinIO is running
kubectl get pods -n minio-ns
```

## Common Issues and Solutions

### Issue 1: ImagePullBackOff or ErrImagePull

**Symptoms:**
- Pod status shows `ImagePullBackOff` or `ErrImagePull`
- Pod is in `Pending` or `Error` state

**Cause:** Worker deployment uses `imagePullPolicy: Never`, so it expects the image to be built locally.

**Solution:**
```powershell
# Build the worker image
cd worker
docker build -f Dockerfile -t demucs-worker:latest .
cd ..

# Verify image was created
docker images | findstr demucs-worker

# Delete and recreate the worker pod
kubectl delete pod -l app=worker
```

**Alternative:** If you want to use Docker Hub image instead:
1. Push your image to Docker Hub:
   ```powershell
   docker tag demucs-worker:latest rash4560/demucs-worker:latest
   docker push rash4560/demucs-worker:latest
   ```

2. Update `worker/worker-deployment.yaml`:
   ```yaml
   image: rash4560/demucs-worker:latest
   imagePullPolicy: IfNotPresent
   ```

3. Apply the updated deployment:
   ```powershell
   kubectl apply -f worker/worker-deployment.yaml
   ```

---

### Issue 2: CrashLoopBackOff

**Symptoms:**
- Pod status shows `CrashLoopBackOff`
- Pod keeps restarting
- High restart count

**Causes & Solutions:**

#### A. Redis Connection Failed
**Check logs:**
```powershell
kubectl logs -l app=worker --tail=50
```

Look for: `Redis connection failed` or `Redis connection attempt failed`

**Solution:**
```powershell
# Ensure Redis is deployed
kubectl get pods -l app=redis

# If not running, deploy it:
kubectl apply -f redis/redis-deployment.yaml
kubectl apply -f redis/redis-service.yaml

# Wait for Redis to be ready
kubectl wait --for=condition=ready pod -l app=redis --timeout=120s
```

#### B. MinIO Connection Failed
**Check logs:**
```powershell
kubectl logs -l app=worker --tail=50 | findstr -i minio
```

**Solution:**
```powershell
# Check MinIO is deployed
kubectl get pods -n minio-ns

# If not, deploy MinIO:
helm repo add minio https://charts.min.io/
helm repo update
helm install minio-proj minio/minio `
  --namespace minio-ns `
  --create-namespace `
  --set rootUser=rootuser `
  --set rootPassword=rootpass123 `
  --set mode=standalone `
  --set replicas=1 `
  --set buckets[0].name=demucs-bucket `
  --set buckets[0].policy=public `
  --set buckets[1].name=demucs-output `
  --set buckets[1].policy=public

# Deploy MinIO external service
kubectl apply -f minio/minio-external-service.yaml
```

#### C. Out of Memory (OOMKilled)
**Check logs:**
```powershell
kubectl describe pod -l app=worker | findstr -i "oom\|memory"
```

**Solution:**
- Increase Docker Desktop memory allocation (Settings → Resources → Memory → 8GB+)
- Restart Docker Desktop
- Reduce worker replicas to 1

---

### Issue 3: Pod Stuck in Pending

**Symptoms:**
- Pod status is `Pending`
- No events or errors in describe output

**Causes & Solutions:**

#### A. Insufficient Resources
**Check:**
```powershell
kubectl describe pod -l app=worker | findstr -i "insufficient\|resources"
```

**Solution:**
- Increase Docker Desktop resources (CPU/Memory)
- Check node resources: `kubectl top nodes`

#### B. Node Not Ready
**Check:**
```powershell
kubectl get nodes
```

**Solution:**
- Ensure Docker Desktop Kubernetes is enabled
- Restart Docker Desktop

---

### Issue 4: Worker Running but Not Processing Jobs

**Symptoms:**
- Pod is `Running` and `Ready`
- No jobs being processed
- Queue has items but worker isn't processing them

**Diagnosis:**
```powershell
# Check if jobs are in queue
kubectl exec -it $(kubectl get pods -l app=redis -o jsonpath='{.items[0].metadata.name}') -- redis-cli LRANGE toWorker 0 -1

# Check worker logs for errors
kubectl logs -l app=worker --tail=100

# Check if worker can connect to Redis
kubectl exec -it $(kubectl get pods -l app=worker -o jsonpath='{.items[0].metadata.name}') -- python3 -c "import redis; r=redis.StrictRedis(host='redis', port=6379); print('OK' if r.ping() else 'FAIL')"
```

**Solutions:**
1. Restart worker pod:
   ```powershell
   kubectl delete pod -l app=worker
   ```

2. Check worker logs for connection errors

3. Verify environment variables are correct:
   ```powershell
   kubectl describe pod -l app=worker | findstr -i "env\|redis\|minio"
   ```

---

### Issue 5: DEMUCS Not Working

**Symptoms:**
- Worker processes jobs but DEMUCS fails
- Logs show: `demucs failed` or `demucs not available`

**Solution:**
1. Check if DEMUCS is installed in the image:
   ```powershell
   kubectl exec -it $(kubectl get pods -l app=worker -o jsonpath='{.items[0].metadata.name}') -- python3 -m demucs --help
   ```

2. Verify the base image is correct:
   - Worker Dockerfile should use: `FROM xserrat/facebook-demucs:latest`

3. Rebuild the worker image:
   ```powershell
   cd worker
   docker build -f Dockerfile -t demucs-worker:latest .
   cd ..
   kubectl delete pod -l app=worker
   ```

---

## Step-by-Step Recovery

If worker is completely broken, follow these steps:

```powershell
# 1. Delete the worker pod
kubectl delete pod -l app=worker

# 2. Verify all dependencies are running
kubectl get pods -l app=redis
kubectl get pods -n minio-ns

# 3. Build/rebuild worker image
cd worker
docker build -f Dockerfile -t demucs-worker:latest .
cd ..

# 4. Verify image exists
docker images | findstr demucs-worker

# 5. Redeploy worker
kubectl apply -f worker/worker-deployment.yaml

# 6. Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=worker --timeout=180s

# 7. Check logs
kubectl logs -l app=worker --tail=50

# 8. Verify worker is processing
kubectl logs -l app=worker -f
```

---

## Using the Diagnostic Script

Run the automated diagnostic script:

```powershell
.\diagnose-worker.ps1
```

This will check:
- Pod status and conditions
- Image availability
- Redis/MinIO connectivity
- Resource availability
- Queue status
- Recent logs

---

## Getting Help

If issues persist:

1. **Get full pod description:**
   ```powershell
   kubectl describe pod -l app=worker > worker-describe.txt
   ```

2. **Get full logs:**
   ```powershell
   kubectl logs -l app=worker > worker-logs.txt
   ```

3. **Check all events:**
   ```powershell
   kubectl get events --sort-by='.lastTimestamp' | findstr worker
   ```

4. **Share these outputs for debugging**

