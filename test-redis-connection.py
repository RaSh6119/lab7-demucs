#!/usr/bin/env python3
"""Quick test to verify Redis connection and queue"""
import redis

try:
    # Try new API first, fallback to old
    try:
        r = redis.Redis(host='localhost', port=6379, decode_responses=False)
    except:
        r = redis.StrictRedis(host='localhost', port=6379, decode_responses=False)
    r.ping()
    print("✓ Redis connection OK")
    
    length = r.llen('toWorker')
    print(f"Queue length: {length}")
    
    if length > 0:
        print("\nJobs in queue:")
        jobs = r.lrange('toWorker', 0, -1)
        for i, job in enumerate(jobs, 1):
            print(f"  Job {i}: {job[:80]}...")
    
except Exception as e:
    print(f"✗ Redis connection failed: {e}")
    print("Make sure port-forward is running:")
    print("  kubectl port-forward service/redis 6379:6379")

