# FFmpeg Auto Download Script

$ffmpegUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
$zipPath = "ffmpeg_temp.zip"
$tempDir = "ffmpeg_temp"
$targetDir = "windows\ffmpeg"

Write-Host "Downloading FFmpeg..." -ForegroundColor Green

# Create target directory
if (!(Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

# Download
Invoke-WebRequest -Uri $ffmpegUrl -OutFile $zipPath -UseBasicParsing
Write-Host "Download complete" -ForegroundColor Green

# Extract
Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
Write-Host "Extraction complete" -ForegroundColor Green

# Find and copy ffmpeg.exe
$ffmpegExe = Get-ChildItem -Path $tempDir -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
if ($ffmpegExe) {
    Copy-Item -Path $ffmpegExe.FullName -Destination "$targetDir\ffmpeg.exe" -Force
    Write-Host "FFmpeg copied successfully" -ForegroundColor Green
} else {
    Write-Host "ERROR: ffmpeg.exe not found" -ForegroundColor Red
    exit 1
}

# Cleanup
Remove-Item -Path $zipPath -Force
Remove-Item -Path $tempDir -Recurse -Force
Write-Host "Cleanup complete" -ForegroundColor Green

# Test
& "$targetDir\ffmpeg.exe" -version
Write-Host "FFmpeg setup complete!" -ForegroundColor Green
