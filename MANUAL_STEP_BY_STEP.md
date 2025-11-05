# Manual Step-by-Step Guide - Music Separation Assignment

**Docker Username:** rash4560

This guide walks you through every step needed to complete the assignment manually.

---

## Step 1: Verify Prerequisites

### 1.1 Check Docker Desktop is Running
```powershell
docker ps
```
If this works, Docker is running. If not, start Docker Desktop.

### 1.2 Check Kubernetes is Enabled
1. Open Docker Desktop
2. Go to Settings → Kubernetes
3. Ensure "Enable Kubernetes" is checked
4. Click "Apply & Restart" if you just enabled it

### 1.3 Verify kubectl Works
```powershell
kubectl version --client
kubectl cluster-info
```
You should see cluster information. If not, wait a few minutes for Kubernetes to start.

### 1.4 Check Helm Installation
```powershell
helm version
```
If Helm is not installed:
- Download from: https://helm.sh/docs/intro/install/
- Or use: `choco install kubernetes-helm` (if you have Chocolatey)

---

## Step 2: Deploy MinIO Object Storage

MinIO stores the MP3 files and separated tracks.

### 2.1 Add MinIO Helm Repository
```powershell
helm repo add minio https://charts.min.io/
helm repo update
```

### 2.2 Deploy MinIO
```powershell
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
  --set buckets[1].policy=public `
  --set resources.requests.memory=0.5Gi
```

### 2.3 Wait for MinIO to be Ready
```powershell
kubectl wait --for=condition=ready pod -l app=minio -n minio-ns --timeout=300s
```

### 2.4 Verify MinIO Deployment
```powershell
kubectl get pods -n minio-ns
kubectl get svc -n minio-ns
```

You should see:
- A pod named `minio-proj-xxx` in Running state
- A service named `minio-proj` with ports 9000 and 9001

**Expected output:**
```
NAME                           READY   STATUS    RESTARTS   AGE
minio-proj-xxxxxxxxx-xxxxx     1/1     Running   0          2m
```

---

## Step 3: Build Docker Images

### 3.1 Build REST Server Image

Navigate to the project root directory, then:

```powershell
cd rest
docker build -f Dockerfile-rest -t demucs-rest:latest .
cd ..
```

**What this does:**
- Builds a Docker image with the REST API server
- Tags it as `demucs-rest:latest`
- Installs Flask, Redis, MinIO clients, etc.

**Expected output:** `Successfully built <image-id>`

### 3.2 Tag and Push REST Image to Docker Hub (Optional but Recommended)

If you want to use the image from Docker Hub (useful for Kubernetes):

```powershell
# Login to Docker Hub first
docker login

# Tag the image
docker tag demucs-rest:latest rash4560/demucs-rest:latest

# Push to Docker Hub
docker push rash4560/demucs-rest:latest
```

**Note:** This step is optional. You can also use local images (see Step 5.1).

### 3.3 Build Worker Image

The worker image is larger (~3.5GB) and will take longer to build:

```powershell
cd worker
docker build -f Dockerfile -t demucs-worker:latest .
cd ..
```

**What this does:**
- Uses the Facebook DEMUCS base image
- Adds your worker.py code
- Installs MinIO and Redis Python clients

**Expected output:** This will take 5-10 minutes. You'll see:
```
Step 1/4 : FROM xserrat/facebook-demucs:latest
...
Successfully built <image-id>
```

### 3.4 Tag and Push Worker Image to Docker Hub

```powershell
# Tag the image
docker tag demucs-worker:latest rash4560/demucs-worker:latest

# Push to Docker Hub (this will take a while due to image size)
docker push rash4560/demucs-worker:latest
```

**Note:** The push may take 10-20 minutes depending on your internet speed.

### 3.5 Verify Images are Built

```powershell
docker images | findstr demucs
```

You should see:
- `demucs-rest:latest`
- `demucs-worker:latest`
- `rash4560/demucs-rest:latest` (if you tagged it)
- `rash4560/demucs-worker:latest` (if you tagged it)

---

## Step 4: Deploy Redis

Redis is used for job queuing and logging.

### 4.1 Deploy Redis Deployment
```powershell
kubectl apply -f redis/redis-deployment.yaml
```

### 4.2 Deploy Redis Service
```powershell
kubectl apply -f redis/redis-service.yaml
```

### 4.3 Wait for Redis to be Ready
```powershell
kubectl wait --for=condition=ready pod -l app=redis --timeout=120s
```

### 4.4 Verify Redis is Running
```powershell
kubectl get pods -l app=redis
kubectl get svc redis
```

**Expected output:**
```
NAME                    READY   STATUS    RESTARTS   AGE
redis-xxxxxxxxx-xxxxx   1/1     Running   0          30s

NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
redis        ClusterIP   10.96.xxx.xxx   <none>        6379/TCP   30s
```

---

## Step 5: Create MinIO External Service

This allows other services to connect to MinIO using the name "minio".

### 5.1 Deploy MinIO External Service
```powershell
kubectl apply -f minio/minio-external-service.yaml
```

### 5.2 Verify the Service
```powershell
kubectl get svc minio
```

**Expected output:**
```
NAME    TYPE           CLUSTER-IP   EXTERNAL-IP                        PORT(S)   AGE
minio   ExternalName   <none>       minio-proj.minio-ns.svc.cluster.local   <none>    10s
```

---

## Step 6: Deploy REST Server

### 6.1 Choose Image Strategy

**Option A: Use Local Image (if you didn't push to Docker Hub)**

Edit `rest/rest-deployment.yaml` - it already has:
```yaml
image: demucs-rest:latest
imagePullPolicy: Never
```
This is correct for local images.

**Option B: Use Docker Hub Image**

If you pushed to Docker Hub, edit `rest/rest-deployment.yaml`:
```yaml
image: rash4560/demucs-rest:latest
imagePullPolicy: IfNotPresent
```

### 6.2 Deploy REST Server
```powershell
kubectl apply -f rest/rest-deployment.yaml
```

### 6.3 Deploy REST Service
```powershell
kubectl apply -f rest/rest-service.yaml
```

### 6.4 Wait for REST Server to be Ready
```powershell
kubectl wait --for=condition=ready pod -l app=rest --timeout=120s
```

### 6.5 Verify REST Server
```powershell
kubectl get pods -l app=rest
kubectl get svc rest-service
```

**Expected output:**
```
NAME                    READY   STATUS    RESTARTS   AGE
rest-xxxxxxxxx-xxxxx    1/1     Running   0          45s

NAME           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
rest-service   ClusterIP   10.96.xxx.xxx   <none>        5000/TCP   45s
```

### 6.6 Check REST Server Logs
```powershell
kubectl logs -l app=rest
```

You should see Flask starting up:
```
 * Running on all addresses (0.0.0.0)
 * Running on http://127.0.0.1:5000
```

---

## Step 7: Deploy Worker

### 7.1 Choose Image Strategy

**Option A: Use Local Image**

Edit `worker/worker-deployment.yaml`:
```yaml
image: demucs-worker:latest
imagePullPolicy: Never
```

**Option B: Use Docker Hub Image**

Keep `worker/worker-deployment.yaml` as is (it already has):
```yaml
image: rash4560/demucs-worker:latest
imagePullPolicy: IfNotPresent
```

### 7.2 Deploy Worker
```powershell
kubectl apply -f worker/worker-deployment.yaml
```

### 7.3 Wait for Worker to be Ready
```powershell
kubectl wait --for=condition=ready pod -l app=worker --timeout=180s
```

**Note:** The worker may take longer to start because it needs to download the DEMUCS model on first run.

### 7.4 Verify Worker
```powershell
kubectl get pods -l app=worker
```

**Expected output:**
```
NAME                      READY   STATUS    RESTARTS   AGE
worker-xxxxxxxxx-xxxxx    1/1     Running   0          2m
```

### 7.5 Check Worker Logs
```powershell
kubectl logs -l app=worker
```

You should see:
```
worker started
```

---

## Step 8: Deploy Logs Service

The logs service monitors and displays logs from all components.

### 8.1 Deploy Logs Service
```powershell
kubectl apply -f logs/logs-deployment.yaml
```

### 8.2 Wait for Logs Service
```powershell
kubectl wait --for=condition=ready pod -l app=logs --timeout=120s
```

### 8.3 Verify Logs Service
```powershell
kubectl get pods -l app=logs
```

---

## Step 9: Verify Complete Deployment

### 9.1 Check All Pods
```powershell
kubectl get pods
```

**Expected output:**
```
NAME                      READY   STATUS    RESTARTS   AGE
logs-xxxxxxxxx-xxxxx      1/1     Running   0          1m
redis-xxxxxxxxx-xxxxx     1/1     Running   0          5m
rest-xxxxxxxxx-xxxxx      1/1     Running   0          4m
worker-xxxxxxxxx-xxxxx    1/1     Running   0          3m
```

All pods should be in **Running** status with **1/1 READY**.

### 9.2 Check All Services
```powershell
kubectl get svc
```

**Expected output:**
```
NAME           TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
kubernetes     ClusterIP      10.96.0.1       <none>        443/TCP    1h
minio          ExternalName   <none>          minio-proj...  <none>    5m
redis          ClusterIP      10.96.xxx.xxx   <none>        6379/TCP   5m
rest-service   ClusterIP      10.96.xxx.xxx   <none>        5000/TCP   4m
```

### 9.3 Test Internal Connectivity

Test if REST can reach Redis:
```powershell
kubectl exec -it <rest-pod-name> -- python -c "import redis; r=redis.StrictRedis(host='redis', port=6379); print(r.ping())"
```

Replace `<rest-pod-name>` with the actual pod name from `kubectl get pods`.

---

## Step 10: Access the REST API

### 10.1 Port Forward REST Service

In a new PowerShell window, run:
```powershell
kubectl port-forward service/rest-service 5000:5000
```

Keep this window open. You should see:
```
Forwarding from 127.0.0.1:5000 -> 5000
Forwarding from [::1]:5000 -> 5000
```

### 10.2 Test the API

In another PowerShell window, test the root endpoint:
```powershell
curl http://localhost:5000/
```

**Expected output:**
```
<h1>Music Separation Server</h1><p>Use /apiv1 endpoints</p>
```

### 10.3 Check Queue Status
```powershell
curl http://localhost:5000/apiv1/queue
```

**Expected output:**
```json
{
  "queue": []
}
```

---

## Step 11: Test with Sample Data

### 11.1 Install Python Dependencies (if needed)

```powershell
pip install requests jsonpickle
```

### 11.2 Test with Short Sample

Make sure you're in the project root directory:
```powershell
python short-sample-request.py
```

**What this does:**
1. Reads MP3 files from `data/short-*.mp3`
2. Encodes them in base64
3. Sends POST request to `/apiv1/separate`
4. Gets back a songhash
5. Checks the queue

**Expected output:**
```
Separate data/short-dreams.mp3
Response to http://localhost:5000/apiv1/separate request is <class 'dict'>
Make request http://localhost:5000/apiv1/separate with json dict_keys(['mp3', 'callback'])
mp3 is of type <class 'str'> and length 123456
{
    "hash": "abc123def456...",
    "reason": "Song enqueued for separation"
}
Cache from server is
Response to http://localhost:5000/apiv1/queue request is <class 'NoneType'>
{
    "queue": [
        {
            "hash": "abc123def456...",
            "bucket": "demucs-bucket",
            "object": "queue/abc123def456....mp3"
        }
    ]
}
```

### 11.3 Monitor Processing

Watch the logs to see the worker processing:
```powershell
# Worker logs
kubectl logs -l app=worker -f

# OR logs service
kubectl logs -l app=logs -f

# OR REST server logs
kubectl logs -l app=rest -f
```

Press `Ctrl+C` to stop watching logs.

### 11.4 Check if Processing is Complete

Wait a few minutes (processing takes 3-4x the song length), then check the queue again:
```powershell
curl http://localhost:5000/apiv1/queue
```

The queue should be empty (or have fewer items) if processing completed.

### 11.5 Download Separated Tracks

Use the songhash from the response to download tracks:
```powershell
# Get the songhash from the response (replace with actual hash)
$songhash = "abc123def456..."

# Download vocals
curl http://localhost:5000/apiv1/track/$songhash/vocals -o vocals.mp3

# Download drums
curl http://localhost:5000/apiv1/track/$songhash/drums -o drums.mp3

# Download bass
curl http://localhost:5000/apiv1/track/$songhash/bass -o bass.mp3

# Download other
curl http://localhost:5000/apiv1/track/$songhash/other -o other.mp3
```

### 11.6 Verify Files Downloaded

Check if files were created:
```powershell
ls *.mp3
```

You should see the separated track files.

---

## Step 12: Test Full API Endpoints

### 12.1 Test /apiv1/separate (POST)

```powershell
# Read a file and encode it
$fileContent = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes("data\short-dreams.mp3"))
$body = @{
    mp3 = $fileContent
    callback = @{
        url = "http://localhost:5000"
        data = @{test = "data"}
    }
} | ConvertTo-Json -Depth 10

# Send request
Invoke-RestMethod -Uri "http://localhost:5000/apiv1/separate" -Method POST -Body $body -ContentType "application/json"
```

### 12.2 Test /apiv1/queue (GET)

```powershell
Invoke-RestMethod -Uri "http://localhost:5000/apiv1/queue" -Method GET
```

### 12.3 Test /apiv1/track/<songhash>/<track> (GET)

```powershell
# Replace with actual songhash
$songhash = "your-songhash-here"
Invoke-RestMethod -Uri "http://localhost:5000/apiv1/track/$songhash/vocals" -Method GET -OutFile "vocals.mp3"
```

### 12.4 Test /apiv1/remove/<songhash>/<track> (GET)

```powershell
$songhash = "your-songhash-here"
Invoke-RestMethod -Uri "http://localhost:5000/apiv1/remove/$songhash/vocals" -Method GET
```

---

## Step 13: Monitor and Debug

### 13.1 View All Logs

```powershell
# REST server logs
kubectl logs -l app=rest -f

# Worker logs
kubectl logs -l app=worker -f

# Logs service (aggregated)
kubectl logs -l app=logs -f

# Redis logs
kubectl logs -l app=redis -f
```

### 13.2 Check Pod Status

```powershell
kubectl get pods -w
```

Press `Ctrl+C` to stop watching.

### 13.3 Describe Pods (if issues)

```powershell
kubectl describe pod <pod-name>
```

### 13.4 Check Resource Usage

```powershell
kubectl top pods
kubectl top nodes
```

### 13.5 Check Redis Queue Directly

```powershell
# Get Redis pod name
$redisPod = kubectl get pods -l app=redis -o jsonpath='{.items[0].metadata.name}'

# Connect to Redis CLI
kubectl exec -it $redisPod -- redis-cli

# Inside Redis CLI:
LRANGE toWorker 0 -1
LRANGE logging 0 -1
exit
```

---

## Step 14: Troubleshooting Common Issues

### Issue: Pods in CrashLoopBackOff

**Solution:**
```powershell
# Check logs
kubectl logs <pod-name>

# Check events
kubectl describe pod <pod-name>

# Common causes:
# - Image pull errors: Check imagePullPolicy and image name
# - Resource limits: Check if you have enough memory/CPU
# - Missing environment variables: Check deployment YAML
```

### Issue: Worker Not Processing Jobs

**Solution:**
```powershell
# Check if jobs are in queue
kubectl exec -it <redis-pod> -- redis-cli LRANGE toWorker 0 -1

# Check worker logs
kubectl logs -l app=worker

# Restart worker
kubectl delete pod -l app=worker
```

### Issue: MinIO Connection Failed

**Solution:**
```powershell
# Check MinIO is running
kubectl get pods -n minio-ns

# Check MinIO service
kubectl get svc -n minio-ns

# Test connection from a pod
kubectl run -it --rm test --image=minio/mc --restart=Never -- bash
# Inside: mc alias set myminio http://minio-proj.minio-ns.svc.cluster.local:9000 rootuser rootpass123
```

### Issue: REST API Not Responding

**Solution:**
```powershell
# Check REST pod is running
kubectl get pods -l app=rest

# Check REST logs
kubectl logs -l app=rest

# Check service
kubectl get svc rest-service

# Verify port-forward is running
kubectl port-forward service/rest-service 5000:5000
```

### Issue: Out of Memory

**Solution:**
- Worker needs at least 6GB RAM
- Check Docker Desktop settings → Resources → Memory (increase to 8GB+)
- Reduce worker replicas to 1
- Use shorter audio samples

---

## Step 15: Cleanup (Optional)

When you're done testing:

```powershell
# Delete deployments
kubectl delete -f worker/worker-deployment.yaml
kubectl delete -f logs/logs-deployment.yaml
kubectl delete -f rest/rest-service.yaml
kubectl delete -f rest/rest-deployment.yaml
kubectl delete -f minio/minio-external-service.yaml
kubectl delete -f redis/redis-service.yaml
kubectl delete -f redis/redis-deployment.yaml

# Delete MinIO (if using Helm)
helm uninstall minio-proj -n minio-ns
kubectl delete namespace minio-ns
```

---

## Summary Checklist

- [ ] Docker Desktop running with Kubernetes enabled
- [ ] MinIO deployed and running
- [ ] REST server image built
- [ ] Worker image built
- [ ] Images pushed to Docker Hub (optional)
- [ ] Redis deployed
- [ ] MinIO external service created
- [ ] REST server deployed
- [ ] Worker deployed
- [ ] Logs service deployed
- [ ] All pods running
- [ ] Port-forward active
- [ ] API responding to requests
- [ ] Test request submitted
- [ ] Worker processing jobs
- [ ] Separated tracks downloaded

---

## Next Steps After Setup

1. **Test with longer samples** (once short samples work)
2. **Scale worker replicas** (if you have resources)
3. **Set up ingress** (for production-like access)
4. **Monitor resource usage** (ensure stability)
5. **Document any issues** (for assignment submission)

---

**Congratulations!** You've successfully deployed the Music Separation as a Service application!

