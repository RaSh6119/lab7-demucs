# MinIO Access Guide

## Quick Access

MinIO is running in your Kubernetes cluster. To access it from your local machine, you need to set up port-forwarding.

### Access MinIO Console (Web UI)

**Port-forward the console service:**
```powershell
kubectl port-forward -n minio-ns svc/minio-proj-console 9001:9001
```

**Then open in browser:**
- URL: http://localhost:9001
- Username: `rootuser`
- Password: `rootpass123`

### Access MinIO API

**Port-forward the API service:**
```powershell
kubectl port-forward -n minio-ns svc/minio-proj 9000:9000
```

**Access endpoint:** http://localhost:9000

---

## Verify MinIO is Running

```powershell
# Check MinIO pods
kubectl get pods -n minio-ns

# Check MinIO services
kubectl get svc -n minio-ns

# Check MinIO logs (if needed)
kubectl logs -n minio-ns -l app=minio-proj
```

---

## Check Buckets

Once you have port-forwarding set up and are logged into the console:

1. Go to http://localhost:9001
2. Login with credentials above
3. Navigate to "Buckets" in the left sidebar
4. You should see:
   - `demucs-bucket` (for input MP3 files)
   - `demucs-output` (for separated tracks)

---

## Troubleshooting

### Port-forward says "address already in use"

**Solution:** Another process is using port 9001. Either:
1. Find and stop the other process:
   ```powershell
   netstat -ano | findstr :9001
   # Find the PID and kill it
   taskkill /PID <pid> /F
   ```

2. Use a different local port:
   ```powershell
   kubectl port-forward -n minio-ns svc/minio-proj-console 9002:9001
   # Then access http://localhost:9002
   ```

### Can't connect to localhost:9001

1. **Verify port-forward is running:**
   ```powershell
   # Check if port-forward process is running
   Get-Process | Where-Object {$_.ProcessName -like "*kubectl*"}
   ```

2. **Restart port-forward:**
   ```powershell
   # Stop any existing port-forwards (Ctrl+C)
   # Then start fresh:
   kubectl port-forward -n minio-ns svc/minio-proj-console 9001:9001
   ```

3. **Check MinIO pod is healthy:**
   ```powershell
   kubectl get pods -n minio-ns
   kubectl describe pod -n minio-ns -l app=minio-proj
   ```

### Forgetting to keep port-forward running

The port-forward command needs to stay running in a terminal window. If you close the terminal, port-forwarding stops.

**Solution:** Keep the terminal window open, or run it in the background (as done automatically by the diagnostic script).

---

## Using MinIO from Your Application

Your worker and REST services access MinIO using the service name `minio:9000` (configured via the ExternalName service). They don't need port-forwarding - that's only for your local browser access.

---

## Quick Commands Summary

```powershell
# Start console port-forward (keep terminal open)
kubectl port-forward -n minio-ns svc/minio-proj-console 9001:9001

# Start API port-forward (if needed)
kubectl port-forward -n minio-ns svc/minio-proj 9000:9000

# Check MinIO status
kubectl get pods -n minio-ns
kubectl get svc -n minio-ns

# View MinIO logs
kubectl logs -n minio-ns -l app=minio-proj
```

---

## Access Credentials

- **Console URL:** http://localhost:9001 (after port-forward)
- **Username:** rootuser
- **Password:** rootpass123
- **API Endpoint:** http://localhost:9000 (after port-forward)

