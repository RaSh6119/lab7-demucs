#!/usr/bin/env python3
"""Test script to verify worker can connect and process one job"""
import os
import sys
import json
import time

# Set environment
os.environ['REDIS_HOST'] = 'localhost'
os.environ['REDIS_PORT'] = '6379'
os.environ['MINIO_ENDPOINT'] = 'localhost:9000'
os.environ['MINIO_ACCESS_KEY'] = 'rootuser'
os.environ['MINIO_SECRET_KEY'] = 'rootpass123'
os.environ['MINIO_SECURE'] = 'false'
os.environ['QUEUE_BUCKET'] = 'demucs-bucket'
os.environ['OUTPUT_BUCKET'] = 'demucs-output'

print("=== Testing Worker Connections ===")
print()

# Test Redis
print("1. Testing Redis connection...")
try:
    import redis
    r = redis.StrictRedis(host='localhost', port=6379, decode_responses=False)
    r.ping()
    print("   ✓ Redis connected")
    
    length = r.llen('toWorker')
    print(f"   Queue length: {length}")
    
    if length > 0:
        job = r.brpop('toWorker', timeout=2)
        if job:
            print(f"   ✓ Got job from queue!")
            job_data = json.loads(job[1].decode('utf-8'))
            print(f"   Job hash: {job_data.get('hash', 'unknown')}")
            # Put it back for actual processing
            r.lpush('toWorker', job[1])
            print("   (Job put back in queue)")
    else:
        print("   ⚠ No jobs in queue")
        
except Exception as e:
    print(f"   ✗ Redis failed: {e}")
    sys.exit(1)

# Test MinIO
print("\n2. Testing MinIO connection...")
try:
    from minio import Minio
    m = Minio('localhost:9000', access_key='rootuser', secret_key='rootpass123', secure=False)
    buckets = m.list_buckets()
    print(f"   ✓ MinIO connected")
    print(f"   Buckets: {[b.name for b in buckets]}")
    
    # Check queue bucket
    if m.bucket_exists('demucs-bucket'):
        print("   ✓ demucs-bucket exists")
        objects = list(m.list_objects('demucs-bucket', prefix='queue/', recursive=True))
        print(f"   Files in queue: {len(objects)}")
    else:
        print("   ⚠ demucs-bucket not found")
        
    # Check output bucket
    if m.bucket_exists('demucs-output'):
        print("   ✓ demucs-output exists")
        objects = list(m.list_objects('demucs-output', recursive=True))
        print(f"   Files in output: {len(objects)}")
    else:
        print("   ⚠ demucs-output not found")
        
except Exception as e:
    print(f"   ✗ MinIO failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("\n✓ All connections OK!")
print("\nWorker should be able to process jobs now.")
print("Run: python worker/worker.py")

