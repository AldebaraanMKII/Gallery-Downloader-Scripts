# Set the date format for the file name
$date = Get-Date -Format "yyyyMMdd_HHmmss"

# Get all .sqlite3 files in the current directory
$sqliteFiles = Get-ChildItem -Path . -Filter *.sqlite3

foreach ($file in $sqliteFiles) {
    $filePath = $file.FullName
    $archivePath = "$($file.BaseName)_$date.7z"
    
    Write-Host "Creating archive for: $filePath"
    
    # Run the 7z command to create the archive
    & 7z a $archivePath $filePath
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully created archive: $archivePath" -ForegroundColor Green
    } else {
        Write-Host "Failed to create archive: $archivePath" -ForegroundColor Red
    }
}

Write-Host "Archiving completed."
[console]::beep()
pause