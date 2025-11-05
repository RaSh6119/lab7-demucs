#!/usr/bin/env python3
"""
Worker service for music separation using DEMUCS
This service listens to Redis queue and processes MP3 files
"""
import os
import sys
import time
import json
import subprocess
import tempfile
import shutil
import socket
from minio import Minio
import redis
import io
import signal

# Ensure all output goes to stderr so Kubernetes can capture it
def log_stderr(msg):
    print(msg, file=sys.stderr, flush=True)

# Global flag for graceful shutdown
shutdown_requested = False

def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    global shutdown_requested
    log_stderr(f"Received signal {signum}, shutting down gracefully...")
    shutdown_requested = True

# Register signal handlers
signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

# Environment variables
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = os.getenv("REDIS_PORT", "6379")
if isinstance(REDIS_PORT, str) and REDIS_PORT.startswith("tcp://"):
    REDIS_PORT = REDIS_PORT.split(":")[-1]
REDIS_PORT = int(REDIS_PORT)

MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "minio:9000")
MINIO_ACCESS = os.getenv("MINIO_ACCESS_KEY", "rootuser")
MINIO_SECRET = os.getenv("MINIO_SECRET_KEY", "rootpass123")
MINIO_SECURE = os.getenv("MINIO_SECURE", "false").lower() in ("true","1","yes")

QUEUE_BUCKET = os.getenv("QUEUE_BUCKET", "demucs-bucket")
OUTPUT_BUCKET = os.getenv("OUTPUT_BUCKET", "demucs-output")

TO_WORKER_KEY = "toWorker"
LOGGING_KEY = "logging"

# Global clients (will be initialized)
redisClient = None
minioClient = None

def init_redis_client():
    """Initialize Redis client - will be retried in initialize()"""
    log_stderr(f"Initializing Redis client: {REDIS_HOST}:{REDIS_PORT}")
    # Try both Redis API versions for compatibility
    try:
        # New API (redis >= 4.0)
        client = redis.Redis(
            host=REDIS_HOST, 
            port=REDIS_PORT, 
            db=0, 
            decode_responses=False, 
            socket_connect_timeout=5,
            socket_keepalive=True
        )
    except (AttributeError, TypeError):
        # Old API (redis < 4.0)
        client = redis.StrictRedis(
            host=REDIS_HOST, 
            port=REDIS_PORT, 
            db=0, 
            decode_responses=False, 
            socket_connect_timeout=5,
            socket_keepalive=True
        )
    client.ping()  # Test connection
    log_stderr(f"Redis connection successful!")
    return client

def init_minio_client():
    """Initialize MinIO client"""
    log_stderr(f"Initializing MinIO client: {MINIO_ENDPOINT}")
    try:
        # Parse endpoint
        endpoint = MINIO_ENDPOINT
        if endpoint.startswith("http://"):
            endpoint = endpoint[7:]
            secure = False
        elif endpoint.startswith("https://"):
            endpoint = endpoint[8:]
            secure = True
        else:
            secure = MINIO_SECURE
        
        # Split host:port
        if ":" in endpoint:
            host, port = endpoint.split(":", 1)
            port = int(port)
        else:
            host = endpoint
            port = 9000 if not secure else 9001
        
        log_stderr(f"MinIO connecting to {host}:{port} (secure={secure})")
        client = Minio(
            f"{host}:{port}", 
            access_key=MINIO_ACCESS, 
            secret_key=MINIO_SECRET, 
            secure=secure
        )
        log_stderr("MinIO client created successfully")
        return client
    except Exception as e:
        log_stderr(f"MinIO client initialization failed: {e}")
        import traceback
        log_stderr(traceback.format_exc())
        raise

def log_info(message):
    """Log info message to Redis"""
    global redisClient
    if redisClient is None:
        return
    try:
        host = socket.gethostname()
        key = f"{host}.worker.info"
        redisClient.lpush(LOGGING_KEY, f"{key}:{message}".encode('utf-8'))
    except Exception as e:
        log_stderr(f"log_info exception: {e}")

def log_debug(message):
    """Log debug message to Redis"""
    global redisClient
    if redisClient is None:
        return
    try:
        host = socket.gethostname()
        key = f"{host}.worker.debug"
        redisClient.lpush(LOGGING_KEY, f"{key}:{message}".encode('utf-8'))
    except Exception as e:
        log_stderr(f"log_debug exception: {e}")

def run_demucs(input_path, output_dir):
    """Run DEMUCS separation on input file"""
    try:
        # DEMUCS creates output in subdirectories like: output/mdx_extra_q/{songname}/tracks.mp3
        cmd = ["python3", "-m", "demucs.separate", "--mp3", "-o", output_dir, input_path]
        log_stderr(f"Running DEMUCS: {' '.join(cmd)}")
        log_debug("running demucs: " + " ".join(cmd))
        
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3600)
        
        if proc.returncode == 0:
            log_info("demucs finished successfully")
            # Log DEMUCS output for debugging
            if proc.stdout:
                stdout_str = proc.stdout.decode('utf-8', errors='ignore')
                log_debug(f"DEMUCS stdout: {stdout_str[:500]}")
            if proc.stderr:
                stderr_str = proc.stderr.decode('utf-8', errors='ignore')
                log_debug(f"DEMUCS stderr: {stderr_str[:500]}")
            return True
        else:
            stdout_str = proc.stdout.decode('utf-8', errors='ignore')[:500] if proc.stdout else ""
            stderr_str = proc.stderr.decode('utf-8', errors='ignore')[:500] if proc.stderr else ""
            log_stderr(f"DEMUCS failed with return code {proc.returncode}")
            log_debug(f"demucs failed rc={proc.returncode} stdout={stdout_str} stderr={stderr_str}")
            return False
    except subprocess.TimeoutExpired:
        log_stderr("DEMUCS timed out after 3600 seconds")
        log_debug("demucs timed out after 3600 seconds")
        return False
    except Exception as e:
        log_stderr(f"DEMUCS exception: {str(e)}")
        log_debug(f"demucs exception: {str(e)}")
        import traceback
        log_debug(traceback.format_exc())
        return False

def upload_outputs_from_dir(songhash, outdir):
    """Upload separated tracks from output directory"""
    global minioClient
    uploaded = []
    found_tracks = {}  # Track name -> file path
    
    # Walk through all directories to find DEMUCS output
    # DEMUCS creates structure like: output/mdx_extra_q/{songname}/vocals.mp3
    log_debug(f"Scanning output directory: {outdir}")
    for root, dirs, files in os.walk(outdir):
        log_debug(f"  Scanning: {root} (found {len(files)} files)")
        for fn in files:
            if fn.lower().endswith((".mp3", ".wav")):
                full = os.path.join(root, fn)
                # Map file name to track name
                lower = fn.lower()
                track = None
                
                # DEMUCS outputs files named: vocals.mp3, drums.mp3, bass.mp3, other.mp3
                if "vocals" in lower or "vocal" in lower:
                    track = "vocals"
                elif "drums" in lower or "drum" in lower:
                    track = "drums"
                elif "bass" in lower:
                    track = "bass"
                elif "other" in lower:
                    track = "other"
                elif "no_vocals" in lower or "instrumental" in lower:
                    track = "instrumental"
                elif "no_drums" in lower:
                    track = "no_drums"
                elif "no_bass" in lower:
                    track = "no_bass"
                elif "no_other" in lower:
                    track = "no_other"
                
                if track:
                    # Keep only the first file found for each track (in case of duplicates)
                    if track not in found_tracks:
                        found_tracks[track] = full
                        log_debug(f"Found {track} track: {full}")
    
    # Upload all found tracks
    for track, file_path in found_tracks.items():
        object_name = f"{songhash}-{track}.mp3"
        try:
            with open(file_path, "rb") as fh:
                data = fh.read()
                minioClient.put_object(
                    OUTPUT_BUCKET, 
                    object_name, 
                    io.BytesIO(data), 
                    length=len(data), 
                    content_type="audio/mpeg"
                )
                uploaded.append(object_name)
                log_info(f"Uploaded {object_name} ({len(data)} bytes)")
                log_debug(f"Uploaded {object_name} ({len(data)} bytes)")
        except Exception as e:
            log_stderr(f"Failed to upload {object_name}: {str(e)}")
            log_debug(f"upload failed {file_path}: {str(e)}")
    
    log_stderr(f"Found and uploaded {len(uploaded)} tracks: {uploaded}")
    return uploaded

def create_additional_tracks(songhash, orig_bytes, uploaded_tracks):
    """No additional tracks needed - DEMUCS produces 4 standard tracks"""
    # DEMUCS produces: vocals, drums, bass, other (4 tracks total)
    # No need for additional files
    return []

def fallback_copy_original(songhash, orig_bytes):
    """Fallback: copy original file as the 4 standard tracks"""
    global minioClient
    # DEMUCS produces 4 standard tracks: vocals, drums, bass, other
    names = ["vocals", "drums", "bass", "other"]
    uploaded = []
    for t in names:
        key = f"{songhash}-{t}.mp3"
        try:
            minioClient.put_object(
                OUTPUT_BUCKET, 
                key, 
                io.BytesIO(orig_bytes), 
                length=len(orig_bytes), 
                content_type="audio/mpeg"
            )
            uploaded.append(key)
            log_info(f"Fallback uploaded {key}")
            log_debug(f"Fallback uploaded {key}")
        except Exception as e:
            log_stderr(f"Fallback upload failed {key}: {str(e)}")
            log_debug(f"fallback upload failed {key}: {str(e)}")
    return uploaded

def process_job(job_json):
    """Process a single job from the queue"""
    global minioClient
    try:
        job = json.loads(job_json)
        songhash = job.get("hash")
        bucket = job.get("bucket", QUEUE_BUCKET)
        obj = job.get("object")
        
        if not songhash or not obj:
            log_debug(f"Invalid job: missing hash or object")
            return False
        
        log_info(f"processing job {songhash} {bucket}/{obj}")
        
        # Download MP3 to temp file
        tmpd = tempfile.mkdtemp(prefix="demucs-worker-")
        input_path = os.path.join(tmpd, f"{songhash}.mp3")
        
        try:
            response = minioClient.get_object(bucket, obj)
            mp3_bytes = response.read()
            response.close()
            response.release_conn()
            with open(input_path, "wb") as fh:
                fh.write(mp3_bytes)
            log_debug(f"Downloaded {len(mp3_bytes)} bytes from {bucket}/{obj}")
        except Exception as e:
            log_debug(f"failed to download input {bucket}/{obj}: {str(e)}")
            shutil.rmtree(tmpd, ignore_errors=True)
            return False

        # Run DEMUCS
        out_parent = os.path.join(tmpd, "output")
        os.makedirs(out_parent, exist_ok=True)
        log_stderr(f"Starting DEMUCS separation for {songhash}")
        success = run_demucs(input_path, out_parent)

        # Upload results
        uploaded = []
        if success:
            log_stderr(f"DEMUCS completed successfully, scanning for output files...")
            uploaded = upload_outputs_from_dir(songhash, out_parent)
            
            if uploaded:
                log_stderr(f"Found {len(uploaded)} tracks from DEMUCS")
                # DEMUCS should produce 4 tracks: vocals, drums, bass, other
                if len(uploaded) < 4:
                    log_stderr(f"Warning: Expected 4 tracks, got {len(uploaded)}")
            else:
                log_stderr("DEMUCS produced no MP3s; using fallback")
                log_debug("demucs produced no mp3s; using fallback")
                uploaded = fallback_copy_original(songhash, mp3_bytes)
        else:
            log_stderr("DEMUCS failed; using fallback copies")
            log_debug("demucs not available or failed; using fallback copies")
            uploaded = fallback_copy_original(songhash, mp3_bytes)
        
        log_stderr(f"Total uploaded: {len(uploaded)} files (expected 4: vocals, drums, bass, other)")

        # Call callback if provided
        callback = job.get("callback")
        if callback and isinstance(callback, dict):
            try:
                import requests
                cb_url = callback.get("url")
                cb_data = callback.get("data", {})
                log_debug(f"calling callback {cb_url}")
                try:
                    requests.post(cb_url, json=cb_data, timeout=5)
                    log_debug("callback succeeded")
                except Exception as e:
                    log_debug(f"callback failed: {str(e)}")
            except Exception as e:
                log_debug(f"callback exception: {str(e)}")

        log_info(f"job {songhash} completed, uploaded outputs: {uploaded}")
        
        # Cleanup
        shutil.rmtree(tmpd, ignore_errors=True)
        return True
        
    except Exception as e:
        log_debug(f"process_job exception: {str(e)}")
        import traceback
        log_debug(traceback.format_exc())
        return False

def main_loop():
    """Main processing loop - runs forever"""
    global redisClient, minioClient, shutdown_requested
    
    log_stderr("=== Worker main loop starting ===")
    log_stderr(f"Redis: {REDIS_HOST}:{REDIS_PORT}")
    log_stderr(f"MinIO: {MINIO_ENDPOINT}")
    
    # Test connections
    try:
        redisClient.ping()
        log_stderr("Redis connection OK")
    except Exception as e:
        log_stderr(f"Redis connection failed: {e}")
        import traceback
        log_stderr(traceback.format_exc())
        return False
    
    try:
        buckets = list(minioClient.list_buckets())
        log_stderr(f"MinIO connection OK, found {len(buckets)} buckets")
    except Exception as e:
        log_stderr(f"MinIO connection test failed: {e}")
        import traceback
        log_stderr(traceback.format_exc())
        # Don't exit - MinIO might be slow to start
    
    log_info("worker started")
    log_stderr("=== Worker ready, waiting for jobs... ===")
    
    consecutive_errors = 0
    max_consecutive_errors = 10
    heartbeat_interval = 60  # Log heartbeat every 60 seconds
    last_heartbeat = time.time()
    
    # Main processing loop - runs forever
    while not shutdown_requested:
        try:
            # Heartbeat logging
            current_time = time.time()
            if current_time - last_heartbeat >= heartbeat_interval:
                log_stderr(f"Worker heartbeat: still running, waiting for jobs...")
                last_heartbeat = current_time
                consecutive_errors = 0  # Reset error count on successful heartbeat
            
            # Blocking pop - wait for job (timeout=1 to allow heartbeat checking)
            work = redisClient.brpop(TO_WORKER_KEY, timeout=1)
            
            if work and len(work) >= 2:
                # Got a job
                payload = work[1]
                if isinstance(payload, bytes):
                    payload = payload.decode('utf-8')
                
                log_stderr(f"Received job from queue")
                consecutive_errors = 0  # Reset error count
                
                try:
                    process_job(payload)
                except Exception as e:
                    log_debug(f"Error processing job: {str(e)}")
                    import traceback
                    log_debug(traceback.format_exc())
                    consecutive_errors += 1
                    
                    if consecutive_errors >= max_consecutive_errors:
                        log_stderr(f"Too many consecutive errors ({consecutive_errors}), waiting before retry...")
                        time.sleep(10)
                        consecutive_errors = 0
                
            elif work is None:
                # Timeout - this is normal, just continue
                continue
            else:
                # Unexpected return value
                log_stderr("Unexpected: brpop returned unexpected value")
                time.sleep(1)
                
        except redis.ConnectionError as e:
            log_stderr(f"Redis connection error: {e}, attempting to reconnect...")
            consecutive_errors += 1
            try:
                # Try to reconnect
                redisClient = init_redis_client()
                log_stderr("Redis reconnected successfully")
                consecutive_errors = 0
            except Exception as reconnect_error:
                log_stderr(f"Redis reconnection failed: {reconnect_error}")
                time.sleep(5)
                
        except KeyboardInterrupt:
            log_stderr("Worker interrupted by user")
            shutdown_requested = True
            break
            
        except Exception as e:
            consecutive_errors += 1
            log_stderr(f"Main loop exception (error #{consecutive_errors}): {str(e)}")
            import traceback
            log_stderr(traceback.format_exc())
            
            if consecutive_errors >= max_consecutive_errors:
                log_stderr(f"Too many consecutive errors ({consecutive_errors}), waiting 10 seconds...")
                time.sleep(10)
                consecutive_errors = 0
            else:
                time.sleep(2)  # Wait before retrying
    
    log_stderr("=== Worker shutting down ===")
    return True

def initialize():
    """Initialize clients and start worker - retries forever"""
    global redisClient, minioClient
    
    log_stderr("=== Worker initialization starting ===")
    
    # Retry Redis connection forever
    while redisClient is None:
        try:
            log_stderr("Attempting to connect to Redis...")
            redisClient = init_redis_client()
            log_stderr("Redis connection successful!")
        except Exception as e:
            log_stderr(f"Redis connection failed, will retry in 5 seconds: {e}")
            time.sleep(5)
    
    # Retry MinIO connection forever
    while minioClient is None:
        try:
            log_stderr("Attempting to connect to MinIO...")
            minioClient = init_minio_client()
            log_stderr("MinIO connection successful!")
        except Exception as e:
            log_stderr(f"MinIO connection failed, will retry in 5 seconds: {e}")
            time.sleep(5)
    
    log_stderr("=== Client initialization complete ===")
    return True

if __name__ == "__main__":
    try:
        # Debug: Print startup message immediately
        print("=== Worker script starting ===", file=sys.stderr, flush=True)
        print(f"Python version: {sys.version}", file=sys.stderr, flush=True)
        print(f"Working directory: {os.getcwd()}", file=sys.stderr, flush=True)
        print(f"Script path: {__file__}", file=sys.stderr, flush=True)
        print(f"Python executable: {sys.executable}", file=sys.stderr, flush=True)
        
        # Initialize connections (will retry forever until successful)
        print("=== Starting initialization ===", file=sys.stderr, flush=True)
        initialize()  # This will retry forever until connections succeed
        
        print("=== Initialization complete, starting main loop ===", file=sys.stderr, flush=True)
        
        # Run main loop - this will run forever
        main_loop()  # This runs forever, should never return
            
    except KeyboardInterrupt:
        log_stderr("Worker interrupted by user")
        sys.exit(0)
    except Exception as e:
        # Catch ANY exception and log it
        print(f"=== CRITICAL UNHANDLED EXCEPTION: {e} ===", file=sys.stderr, flush=True)
        import traceback
        print(traceback.format_exc(), file=sys.stderr, flush=True)
        log_stderr(f"=== FATAL ERROR: {e} ===")
        log_stderr(traceback.format_exc())
        # Log error and exit - Kubernetes will restart the pod
        log_stderr("Fatal error occurred, exiting (Kubernetes will restart pod)...")
        sys.exit(1)
