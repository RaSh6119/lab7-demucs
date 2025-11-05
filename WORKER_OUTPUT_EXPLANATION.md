# Worker Output Explanation

## Standard DEMUCS Output

DEMUCS (Deep Music Source Separation) produces **4 standard tracks** per song:

1. **vocals.mp3** - Separated vocal track
2. **drums.mp3** - Separated drum track
3. **bass.mp3** - Separated bass track
4. **other.mp3** - All other instruments combined

## File Naming Convention

Files are named: `{songhash}-{track}.mp3`

Example:
- `83abdba474adf043c6879343f3561e36d5d9b37d3dba90603b33affa2dc2a666-vocals.mp3`
- `83abdba474adf043c6879343f3561e36d5d9b37d3dba90603b33affa2dc2a666-drums.mp3`
- `83abdba474adf043c6879343f3561e36d5d9b37d3dba90603b33affa2dc2a666-bass.mp3`
- `83abdba474adf043c6879343f3561e36d5d9b37d3dba90603b33affa2dc2a666-other.mp3`

## For Multiple Songs

If you have 2 songs in the queue:
- **Song 1**: 4 files (vocals, drums, bass, other)
- **Song 2**: 4 files (vocals, drums, bass, other)
- **Total**: 8 files (4 per song)

## Accessing Files

### Via REST API:
```
http://localhost:5000/apiv1/track/{songhash}/vocals
http://localhost:5000/apiv1/track/{songhash}/drums
http://localhost:5000/apiv1/track/{songhash}/bass
http://localhost:5000/apiv1/track/{songhash}/other
```

### Via MinIO Console:
1. Go to http://localhost:9001
2. Login with rootuser/rootpass123
3. Navigate to `demucs-output` bucket
4. You'll see all the separated files

## Fallback Mode

If DEMUCS is not available or fails, the worker uses fallback mode:
- Copies the original file as all 4 tracks
- This ensures you always get 4 output files per song
- Files will have the same content but different names

## Verification

To verify files were created correctly:
```powershell
# Get song hash from queue response
$songhash = "your-song-hash-here"

# Check each track
Invoke-WebRequest -Uri "http://localhost:5000/apiv1/track/$songhash/vocals" -OutFile "vocals.mp3"
Invoke-WebRequest -Uri "http://localhost:5000/apiv1/track/$songhash/drums" -OutFile "drums.mp3"
Invoke-WebRequest -Uri "http://localhost:5000/apiv1/track/$songhash/bass" -OutFile "bass.mp3"
Invoke-WebRequest -Uri "http://localhost:5000/apiv1/track/$songhash/other" -OutFile "other.mp3"
```

Each file should be playable as an MP3.

