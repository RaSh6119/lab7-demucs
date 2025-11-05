# PowerShell deployment script for Music Separation Service
# Run this script from the project root directory

Write-Host "=== Music Separation Service Deployment ===" -ForegroundColor Green

# Check prerequisites
Write-Host "`nChecking prerequisites..." -ForegroundColor Yellow

$kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
if (-not $kubectl) {
    Write-Host "ERROR: kubectl not found. Please install kubectl." -ForegroundColor Red
    exit 1
}

$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    Write-Host "ERROR: docker not found. Please install Docker Desktop." -ForegroundColor Red
    exit 1
}

# Check if Kubernetes is running
Write-Host "Checking Kubernetes cluster..." -ForegroundColor Yellow
try {
    kubectl cluster-info | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Kubernetes cluster not accessible"
    }
} catch {
    Write-Host "ERROR: Cannot access Kubernetes cluster. Is Docker Desktop Kubernetes enabled?" -ForegroundColor Red
    exit 1
}

Write-Host "Prerequisites OK!" -ForegroundColor Green

# Step 1: Deploy MinIO (check if already deployed)
Write-Host "`n=== Step 1: Checking MinIO ===" -ForegroundColor Cyan
$minioNamespace = kubectl get namespace minio-ns -o name 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "MinIO namespace not found. You need to deploy MinIO first." -ForegroundColor Yellow
    Write-Host "Please run one of the following:" -ForegroundColor Yellow
    Write-Host "  Option A (Helm): helm install minio-proj minio/minio --namespace minio-ns --create-namespace --set rootUser=rootuser --set rootPassword=rootpass123" -ForegroundColor White
    Write-Host "  Option B: See SETUP_GUIDE.md for detailed instructions" -ForegroundColor White
    $continue = Read-Host "Continue anyway? (y/n)"
    if ($continue -ne "y") {
        exit 1
    }
} else {
    Write-Host "MinIO namespace exists. Assuming MinIO is deployed." -ForegroundColor Green
}

# Step 2: Build Docker images
Write-Host "`n=== Step 2: Building Docker Images ===" -ForegroundColor Cyan

Write-Host "Building REST server image..." -ForegroundColor Yellow
docker build -f rest/Dockerfile-rest -t demucs-rest:latest rest/
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to build REST image" -ForegroundColor Red
    exit 1
}
Write-Host "REST image built successfully!" -ForegroundColor Green

Write-Host "Building Worker image (this may take a while)..." -ForegroundColor Yellow
docker build -f worker/Dockerfile -t demucs-worker:latest worker/
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to build Worker image" -ForegroundColor Red
    exit 1
}
Write-Host "Worker image built successfully!" -ForegroundColor Green

# Check if we should use local image or push to Docker Hub
$useLocal = Read-Host "Use local images (modify deployments to use 'Never' pull policy)? (y/n)"
if ($useLocal -eq "y") {
    Write-Host "Updating deployments to use local images..." -ForegroundColor Yellow
    # Update worker deployment to use local image
    (Get-Content worker/worker-deployment.yaml) -replace 'imagePullPolicy: IfNotPresent', 'imagePullPolicy: Never' -replace 'rash4560/demucs-worker:latest', 'demucs-worker:latest' | Set-Content worker/worker-deployment.yaml
    Write-Host "Deployments updated!" -ForegroundColor Green
}

# Step 3: Deploy Redis
Write-Host "`n=== Step 3: Deploying Redis ===" -ForegroundColor Cyan
kubectl apply -f redis/redis-deployment.yaml
kubectl apply -f redis/redis-service.yaml
Write-Host "Waiting for Redis to be ready..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=redis --timeout=120s
if ($LASTEXITCODE -eq 0) {
    Write-Host "Redis is ready!" -ForegroundColor Green
} else {
    Write-Host "WARNING: Redis may not be ready yet. Check with: kubectl get pods -l app=redis" -ForegroundColor Yellow
}

# Step 4: Deploy MinIO External Service
Write-Host "`n=== Step 4: Deploying MinIO External Service ===" -ForegroundColor Cyan
kubectl apply -f minio/minio-external-service.yaml

# Step 5: Deploy REST Server
Write-Host "`n=== Step 5: Deploying REST Server ===" -ForegroundColor Cyan
kubectl apply -f rest/rest-deployment.yaml
kubectl apply -f rest/rest-service.yaml
Write-Host "Waiting for REST server to be ready..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=rest --timeout=120s
if ($LASTEXITCODE -eq 0) {
    Write-Host "REST server is ready!" -ForegroundColor Green
} else {
    Write-Host "WARNING: REST server may not be ready yet. Check with: kubectl get pods -l app=rest" -ForegroundColor Yellow
}

# Step 6: Deploy Worker
Write-Host "`n=== Step 6: Deploying Worker ===" -ForegroundColor Cyan
kubectl apply -f worker/worker-deployment.yaml
Write-Host "Waiting for Worker to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 10  # Give worker a moment to start
kubectl wait --for=condition=ready pod -l app=worker --timeout=180s
if ($LASTEXITCODE -eq 0) {
    Write-Host "Worker is ready!" -ForegroundColor Green
} else {
    Write-Host "WARNING: Worker may not be ready yet. Check with: kubectl get pods -l app=worker" -ForegroundColor Yellow
}

# Step 7: Deploy Logs Service
Write-Host "`n=== Step 7: Deploying Logs Service ===" -ForegroundColor Cyan
kubectl apply -f logs/logs-deployment.yaml

# Step 8: Show status
Write-Host "`n=== Deployment Complete! ===" -ForegroundColor Green
Write-Host "`nPod Status:" -ForegroundColor Cyan
kubectl get pods

Write-Host "`nService Status:" -ForegroundColor Cyan
kubectl get svc

Write-Host "`n=== Next Steps ===" -ForegroundColor Yellow
Write-Host "1. Port forward to access REST API:" -ForegroundColor White
Write-Host "   kubectl port-forward service/rest-service 5000:5000" -ForegroundColor Gray
Write-Host "`n2. Test with short sample:" -ForegroundColor White
Write-Host "   python short-sample-request.py" -ForegroundColor Gray
Write-Host "`n3. View logs:" -ForegroundColor White
Write-Host "   kubectl logs -l app=logs -f" -ForegroundColor Gray
Write-Host "   kubectl logs -l app=rest -f" -ForegroundColor Gray
Write-Host "   kubectl logs -l app=worker -f" -ForegroundColor Gray

Write-Host "`n=== Done! ===" -ForegroundColor Green

