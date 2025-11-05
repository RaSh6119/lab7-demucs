# Script to submit a test job and monitor worker processing

Write-Host "=== Submitting Test Job ===" -ForegroundColor Cyan
Write-Host ""

# Install jsonpickle if needed
try {
    python -c "import jsonpickle" 2>$null
} catch {
    Write-Host "Installing jsonpickle..." -ForegroundColor Yellow
    pip install jsonpickle
}

# Read a short MP3 file
$mp3File = "data\short-dreams.mp3"
if (-not (Test-Path $mp3File)) {
    Write-Host "Error: $mp3File not found!" -ForegroundColor Red
    exit 1
}

Write-Host "Reading MP3 file: $mp3File" -ForegroundColor Yellow
$mp3Bytes = [System.IO.File]::ReadAllBytes($mp3File)
$mp3Base64 = [Convert]::ToBase64String($mp3Bytes)

Write-Host "File size: $($mp3Bytes.Length) bytes" -ForegroundColor Gray
Write-Host "Base64 length: $($mp3Base64.Length) characters" -ForegroundColor Gray
Write-Host ""

# Create request payload
$payload = @{
    mp3 = $mp3Base64
    callback = @{
        url = "http://localhost:5000"
        data = @{
            mp3 = $mp3File
            test = "local worker test"
        }
    }
} | ConvertTo-Json -Depth 10

Write-Host "Submitting job to REST API..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "http://localhost:5000/apiv1/separate" `
        -Method POST `
        -Body $payload `
        -ContentType "application/json"
    
    Write-Host "✓ Job submitted successfully!" -ForegroundColor Green
    Write-Host "Response:" -ForegroundColor Cyan
    $response | ConvertTo-Json -Depth 5
    Write-Host ""
    
    $songhash = $response.hash
    Write-Host "Song hash: $songhash" -ForegroundColor Yellow
    Write-Host ""
    
    # Check queue
    Write-Host "Checking queue..." -ForegroundColor Cyan
    Start-Sleep -Seconds 2
    $queue = Invoke-RestMethod -Uri "http://localhost:5000/apiv1/queue" -Method GET
    Write-Host "Queue status:" -ForegroundColor Yellow
    $queue | ConvertTo-Json -Depth 5
    Write-Host ""
    
    # Monitor processing
    Write-Host "Monitoring queue for 60 seconds..." -ForegroundColor Cyan
    for ($i = 1; $i -le 12; $i++) {
        Start-Sleep -Seconds 5
        $queue = Invoke-RestMethod -Uri "http://localhost:5000/apiv1/queue" -Method GET
        $queueLength = $queue.queue.Count
        Write-Host "[$($i*5)s] Queue length: $queueLength" -ForegroundColor $(if ($queueLength -eq 0) { "Green" } else { "Yellow" })
        
        if ($queueLength -eq 0) {
            Write-Host "✓ Job processed! Queue is empty." -ForegroundColor Green
            break
        }
    }
    
    # Check if output files are available
    Write-Host "`nChecking for output files..." -ForegroundColor Cyan
    $tracks = @("vocals", "drums", "bass", "other", "original")
    foreach ($track in $tracks) {
        try {
            $trackUrl = "http://localhost:5000/apiv1/track/$songhash/$track"
            $response = Invoke-WebRequest -Uri $trackUrl -Method GET -TimeoutSec 5 -UseBasicParsing
            Write-Host "✓ $track available ($($response.ContentLength) bytes)" -ForegroundColor Green
        } catch {
            Write-Host "✗ $track not available yet" -ForegroundColor Red
        }
    }
    
} catch {
    Write-Host "✗ Error submitting job: $_" -ForegroundColor Red
    Write-Host $_.Exception.Message
}

