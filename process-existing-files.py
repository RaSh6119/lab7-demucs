#!/usr/bin/env python3
"""Create jobs for existing files in demucs-bucket"""
import redis
import json

# Connect to Redis
r = redis.Redis(host='localhost', port=6379, decode_responses=False)

# File hashes from the 2 files in demucs-bucket
jobs = [
    {
        "hash": "83abdba474adf043c6879343f3561e36d5d9b37d3dba90603b33affa2dc2a666",
        "bucket": "demucs-bucket",
        "object": "queue/83abdba474adf043c6879343f3561e36d5d9b37d3dba90603b33affa2dc2a666.mp3",
        "callback": None
    },
    {
        "hash": "9627ed8f6b9ddd5b86fa495161a6de2ab371e2ed8e052d659a88c51272b4fc28",
        "bucket": "demucs-bucket",
        "object": "queue/9627ed8f6b9ddd5b86fa495161a6de2ab371e2ed8e052d659a88c51272b4fc28.mp3",
        "callback": None
    }
]

print("Adding jobs to Redis queue...")
for job in jobs:
    job_json = json.dumps(job).encode('utf-8')
    r.lpush('toWorker', job_json)
    print(f"✓ Added job for {job['hash'][:20]}...")

queue_length = r.llen('toWorker')
print(f"\nQueue now has {queue_length} jobs")
print("Worker should pick them up and process them!")

