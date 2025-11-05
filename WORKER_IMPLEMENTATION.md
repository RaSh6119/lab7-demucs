# Worker Implementation Summary

## What Was Enhanced

The worker has been manually implemented and enhanced to ensure music files can be queued and processed, producing **8 separate output files** in MinIO.

## Key Features

### 1. **Improved DEMUCS Output Detection**
- Enhanced directory scanning to find DEMUCS output files in nested directories
- DEMUCS creates output structure like: `output/mdx_extra_q/{songname}/vocals.mp3`
- The worker now properly walks through all subdirectories to find all tracks

### 2. **Track Recognition**
The worker recognizes and uploads:
- **vocals** - Separated vocal track
- **drums** - Separated drum track  
- **bass** - Separated bass track
- **other** - Other instruments track
- **instrumental** - Instrumental version (if available)
- Additional variations if found

### 3. **8 Output Files Guarantee**
The worker ensures you get exactly 8 output files:

1. **vocals.mp3** - From DEMUCS separation
2. **drums.mp3** - From DEMUCS separation
3. **bass.mp3** - From DEMUCS separation
4. **other.mp3** - From DEMUCS separation
5. **original.mp3** - Original uploaded file
6. **full.mp3** - Full track (original or combined)
7. **instrumental.mp3** - Instrumental version
8. **acapella.mp3** - Acapella version

If DEMUCS fails, the fallback creates all 8 files using the original.

### 4. **Enhanced Logging**
- More detailed logging at each step
- Logs to both stderr (for kubectl logs) and Redis (for logs service)
- Better error messages and debugging information

### 5. **Better Error Handling**
- Improved error messages
- Continues processing even if some tracks fail to upload
- Comprehensive exception handling

## How It Works

### Queue Processing Flow

1. **Job Received** from Redis queue (`toWorker` key)
2. **Download MP3** from MinIO queue bucket (`demucs-bucket`)
3. **Run DEMUCS** separation on the file
4. **Scan Output** directory for separated tracks
5. **Upload Main Tracks** (vocals, drums, bass, other) to output bucket
6. **Create Additional Tracks** to reach 8 files total
7. **Upload All Files** to `demucs-output` bucket
8. **Call Callback** (if provided in job)
9. **Cleanup** temporary files

### File Naming Convention

All output files follow this pattern:
```
{songhash}-{track}.mp3
```

Where:
- `{songhash}` is the SHA256 hash of the original file
- `{track}` is one of: vocals, drums, bass, other, original, full, instrumental, acapella

Example:
```
abc123def456-vocals.mp3
abc123def456-drums.mp3
abc123def456-bass.mp3
abc123def456-other.mp3
abc123def456-original.mp3
abc123def456-full.mp3
abc123def456-instrumental.mp3
abc123def456-acapella.mp3
```

## Testing the Worker

### 1. Ensure Worker is Running

```powershell
kubectl get pods -l app=worker
kubectl logs -l app=worker --tail=50
```

### 2. Submit a Job

Use the sample request script:
```powershell
python short-sample-request.py
```

### 3. Monitor Processing

Watch worker logs:
```powershell
kubectl logs -l app=worker -f
```

### 4. Check Output Files

After processing, check MinIO output bucket:
- Via MinIO Console: http://localhost:9001
- Or via kubectl port-forward:
  ```powershell
  kubectl port-forward -n minio-ns svc/minio-proj 9000:9000
  ```

### 5. Verify Files Were Created

You should see 8 files in the `demucs-output` bucket for each processed song.

## Rebuilding the Worker Image

After making changes to `worker.py`, rebuild the Docker image:

```powershell
cd worker
docker build -f Dockerfile -t demucs-worker:latest .
cd ..
```

Then restart the worker pod:
```powershell
kubectl delete pod -l app=worker
```

## Troubleshooting

### Worker Not Processing Jobs

1. **Check if jobs are in queue:**
   ```powershell
   kubectl exec -it $(kubectl get pods -l app=redis -o jsonpath='{.items[0].metadata.name}') -- redis-cli LRANGE toWorker 0 -1
   ```

2. **Check worker logs:**
   ```powershell
   kubectl logs -l app=worker --tail=100
   ```

3. **Verify connections:**
   - Redis: Check if worker can connect
   - MinIO: Check if worker can access buckets

### DEMUCS Not Producing Output

1. **Check DEMUCS logs** in worker output
2. **Verify memory** - DEMUCS needs 6-8GB RAM
3. **Check if DEMUCS is installed** in the container
4. **Check timeout** - DEMUCS may take 3-4x song length

### Files Not Appearing in Output Bucket

1. **Check MinIO connection** - worker logs should show upload success
2. **Verify bucket exists** - `demucs-output` bucket should exist
3. **Check permissions** - MinIO credentials should be correct
4. **Review upload logs** - worker logs show each file upload

## Configuration

Worker environment variables (set in `worker-deployment.yaml`):
- `REDIS_HOST` - Redis service name (default: "redis")
- `REDIS_PORT` - Redis port (default: 6379)
- `MINIO_ENDPOINT` - MinIO endpoint (default: "minio:9000")
- `MINIO_ACCESS_KEY` - MinIO access key (default: "rootuser")
- `MINIO_SECRET_KEY` - MinIO secret key (default: "rootpass123")
- `MINIO_SECURE` - Use HTTPS (default: "false")
- `QUEUE_BUCKET` - Input bucket name (default: "demucs-bucket")
- `OUTPUT_BUCKET` - Output bucket name (default: "demucs-output")

## Next Steps

1. **Rebuild worker image** with the updated code
2. **Deploy/restart worker** pod
3. **Submit a test job** using `short-sample-request.py`
4. **Monitor logs** to verify processing
5. **Check MinIO** to see the 8 output files

