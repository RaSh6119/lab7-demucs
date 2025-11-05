FROM xserrat/facebook-demucs:latest

WORKDIR /srv

COPY worker.py /srv/worker.py

# Install only lightweight Python clients
RUN pip install --no-cache-dir minio redis requests

# Run worker on container start
# Use -u for unbuffered output so logs appear immediately in Kubernetes
# Add explicit error handling
CMD ["sh", "-c", "python3 -u /srv/worker.py 2>&1"]
