# Worker Diagnostic Script
# This script helps diagnose worker pod issues

Write-Host "=== Worker Diagnostic Script ===" -ForegroundColor Cyan
Write-Host ""

# 1. Check if worker pod exists
Write-Host "1. Checking worker pod status..." -ForegroundColor Yellow
$workerPods = kubectl get pods -l app=worker -o json | ConvertFrom-Json
if ($workerPods.items.Count -eq 0) {
    Write-Host "   ERROR: No worker pods found!" -ForegroundColor Red
    Write-Host "   Solution: Deploy worker with: kubectl apply -f worker/worker-deployment.yaml" -ForegroundColor Yellow
} else {
    foreach ($pod in $workerPods.items) {
        $podName = $pod.metadata.name
        $status = $pod.status.phase
        $ready = $pod.status.containerStatuses[0].ready
        $restarts = $pod.status.containerStatuses[0].restartCount
        
        Write-Host "   Pod: $podName" -ForegroundColor Cyan
        Write-Host "   Status: $status" -ForegroundColor $(if ($status -eq "Running") { "Green" } else { "Red" })
        Write-Host "   Ready: $ready" -ForegroundColor $(if ($ready) { "Green" } else { "Red" })
        Write-Host "   Restarts: $restarts" -ForegroundColor $(if ($restarts -gt 5) { "Red" } else { "Yellow" })
        
        # Check pod conditions
        Write-Host "   Conditions:" -ForegroundColor Cyan
        foreach ($condition in $pod.status.conditions) {
            Write-Host "     - $($condition.type): $($condition.status)" -ForegroundColor $(if ($condition.status -eq "True") { "Green" } else { "Red" })
        }
        
        # Check for image issues
        if ($pod.status.containerStatuses[0].state.waiting) {
            $reason = $pod.status.containerStatuses[0].state.waiting.reason
            Write-Host "   Waiting reason: $reason" -ForegroundColor Red
            if ($reason -eq "ImagePullBackOff" -or $reason -eq "ErrImagePull") {
                Write-Host "   ISSUE: Cannot pull image!" -ForegroundColor Red
                Write-Host "   Solution: Build image locally with:" -ForegroundColor Yellow
                Write-Host "     cd worker" -ForegroundColor Gray
                Write-Host "     docker build -f Dockerfile -t demucs-worker:latest ." -ForegroundColor Gray
                Write-Host "     cd .." -ForegroundColor Gray
            } elseif ($reason -eq "CrashLoopBackOff") {
                Write-Host "   ISSUE: Container is crashing!" -ForegroundColor Red
                Write-Host "   Check logs below for details." -ForegroundColor Yellow
            }
        }
        
        Write-Host ""
    }
}

# 2. Check worker logs
Write-Host "2. Worker Pod Logs (last 50 lines):" -ForegroundColor Yellow
Write-Host "-----------------------------------" -ForegroundColor Gray
$workerPodName = kubectl get pods -l app=worker -o jsonpath='{.items[0].metadata.name}' 2>$null
if ($workerPodName) {
    kubectl logs $workerPodName --tail=50 2>&1
} else {
    Write-Host "   No worker pod found to get logs from" -ForegroundColor Red
}
Write-Host ""

# 3. Check if Docker image exists
Write-Host "3. Checking if worker Docker image exists locally..." -ForegroundColor Yellow
$imageExists = docker images demucs-worker:latest --format "{{.Repository}}:{{.Tag}}" 2>$null
if ($imageExists) {
    Write-Host "   ✓ Image exists: $imageExists" -ForegroundColor Green
} else {
    Write-Host "   ✗ Image NOT found locally!" -ForegroundColor Red
    Write-Host "   Solution: Build the image with:" -ForegroundColor Yellow
    Write-Host "     cd worker" -ForegroundColor Gray
    Write-Host "     docker build -f Dockerfile -t demucs-worker:latest ." -ForegroundColor Gray
    Write-Host "     cd .." -ForegroundColor Gray
}
Write-Host ""

# 4. Check Redis connection
Write-Host "4. Checking Redis service..." -ForegroundColor Yellow
$redisService = kubectl get svc redis -o json 2>$null | ConvertFrom-Json
if ($redisService) {
    Write-Host "   ✓ Redis service exists" -ForegroundColor Green
    $redisPods = kubectl get pods -l app=redis -o json | ConvertFrom-Json
    if ($redisPods.items.Count -gt 0) {
        $redisPodName = $redisPods.items[0].metadata.name
        $redisStatus = $redisPods.items[0].status.phase
        Write-Host "   Redis pod: $redisPodName ($redisStatus)" -ForegroundColor $(if ($redisStatus -eq "Running") { "Green" } else { "Red" })
    }
} else {
    Write-Host "   ✗ Redis service NOT found!" -ForegroundColor Red
    Write-Host "   Solution: Deploy Redis with:" -ForegroundColor Yellow
    Write-Host "     kubectl apply -f redis/redis-deployment.yaml" -ForegroundColor Gray
    Write-Host "     kubectl apply -f redis/redis-service.yaml" -ForegroundColor Gray
}
Write-Host ""

# 5. Check MinIO connection
Write-Host "5. Checking MinIO service..." -ForegroundColor Yellow
$minioService = kubectl get svc minio -o json 2>$null | ConvertFrom-Json
if ($minioService) {
    Write-Host "   ✓ MinIO service exists" -ForegroundColor Green
    $minioPods = kubectl get pods -n minio-ns -o json 2>$null | ConvertFrom-Json
    if ($minioPods -and $minioPods.items.Count -gt 0) {
        $minioPodName = $minioPods.items[0].metadata.name
        $minioStatus = $minioPods.items[0].status.phase
        Write-Host "   MinIO pod: $minioPodName ($minioStatus)" -ForegroundColor $(if ($minioStatus -eq "Running") { "Green" } else { "Red" })
    } else {
        Write-Host "   ⚠ MinIO pod not found in minio-ns namespace" -ForegroundColor Yellow
        Write-Host "   Solution: Deploy MinIO with Helm:" -ForegroundColor Yellow
        Write-Host "     helm install minio-proj minio/minio --namespace minio-ns --create-namespace --set rootUser=rootuser --set rootPassword=rootpass123 --set mode=standalone --set replicas=1 --set buckets[0].name=demucs-bucket --set buckets[0].policy=public --set buckets[1].name=demucs-output --set buckets[1].policy=public" -ForegroundColor Gray
    }
} else {
    Write-Host "   ✗ MinIO service NOT found!" -ForegroundColor Red
    Write-Host "   Solution: Create MinIO external service with:" -ForegroundColor Yellow
    Write-Host "     kubectl apply -f minio/minio-external-service.yaml" -ForegroundColor Gray
}
Write-Host ""

# 6. Check worker deployment configuration
Write-Host "6. Checking worker deployment configuration..." -ForegroundColor Yellow
$deployment = kubectl get deployment worker -o json 2>$null | ConvertFrom-Json
if ($deployment) {
    $image = $deployment.spec.template.spec.containers[0].image
    $pullPolicy = $deployment.spec.template.spec.containers[0].imagePullPolicy
    Write-Host "   Image: $image" -ForegroundColor Cyan
    Write-Host "   Pull Policy: $pullPolicy" -ForegroundColor Cyan
    if ($pullPolicy -eq "Never" -and -not $imageExists) {
        Write-Host "   ⚠ WARNING: PullPolicy is 'Never' but image doesn't exist locally!" -ForegroundColor Red
        Write-Host "   Solution: Build the image or change pullPolicy to 'IfNotPresent'" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ✗ Worker deployment NOT found!" -ForegroundColor Red
}
Write-Host ""

# 7. Check resource availability
Write-Host "7. Checking node resources..." -ForegroundColor Yellow
$nodes = kubectl top nodes --no-headers 2>$null
if ($nodes) {
    Write-Host "   Node resources:" -ForegroundColor Cyan
    $nodes | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
    Write-Host "   ⚠ Worker needs 8GB memory - ensure nodes have enough!" -ForegroundColor Yellow
} else {
    Write-Host "   ⚠ Cannot get node metrics (metrics-server may not be enabled)" -ForegroundColor Yellow
}
Write-Host ""

# 8. Test Redis connection from worker pod (if running)
if ($workerPodName -and (kubectl get pod $workerPodName -o jsonpath='{.status.phase}' 2>$null) -eq "Running") {
    Write-Host "8. Testing Redis connection from worker pod..." -ForegroundColor Yellow
    $redisTest = kubectl exec $workerPodName -- python3 -c "import redis; r=redis.StrictRedis(host='redis', port=6379); print('OK' if r.ping() else 'FAIL')" 2>&1
    if ($redisTest -match "OK") {
        Write-Host "   ✓ Redis connection successful" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Redis connection failed: $redisTest" -ForegroundColor Red
    }
    Write-Host ""
}

# 9. Check queue status
Write-Host "9. Checking Redis queue..." -ForegroundColor Yellow
$redisPodName = kubectl get pods -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>$null
if ($redisPodName) {
    $queueLength = kubectl exec $redisPodName -- redis-cli LLEN toWorker 2>$null
    if ($queueLength -match "^\d+$") {
        Write-Host "   Queue length: $queueLength" -ForegroundColor Cyan
        if ([int]$queueLength -gt 0) {
            Write-Host "   ⚠ There are $queueLength jobs waiting to be processed!" -ForegroundColor Yellow
        }
    }
}
Write-Host ""

# Summary
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Common fixes:" -ForegroundColor Yellow
Write-Host "1. Build worker image: cd worker && docker build -f Dockerfile -t demucs-worker:latest ." -ForegroundColor Gray
Write-Host "2. Check worker logs: kubectl logs -l app=worker" -ForegroundColor Gray
Write-Host "3. Describe pod for details: kubectl describe pod -l app=worker" -ForegroundColor Gray
Write-Host "4. Restart worker: kubectl delete pod -l app=worker" -ForegroundColor Gray
Write-Host ""

