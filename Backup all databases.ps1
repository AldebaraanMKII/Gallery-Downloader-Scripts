# Set the date format for the file name
$date = Get-Date -Format "yyyyMMdd_HHmmss"

# Get all .sqlite3 files, excluding those with "-temp" or "Cache" in the name (case-insensitive)
$sqliteFiles = Get-ChildItem -Path . -Filter *.sqlite3 |
    Where-Object { $_.Name -notmatch '(?i)(-temp|cache)' }

$SaveBasePath = "I:\Database_Backups"
# $SaveBasePath = "$PSScriptRoot\Database_Backups"

if (-not (Test-Path $SaveBasePath)) {
	New-Item -ItemType Directory -Path $SaveBasePath | Out-Null
}

if ($sqliteFiles.Count -gt 0) {
	foreach ($file in $sqliteFiles) {
		$filePath = $file.FullName
		$archivePath = "$($SaveBasePath)/$($file.BaseName)_$date.7z"
		
		Write-Host "`nCreating archive for: $filePath" -ForegroundColor Cyan
		
		# Run the 7z command to create the archive
		& 7z a $archivePath $filePath | Out-Null
		
		if ($LASTEXITCODE -eq 0) {
			Write-Host "Successfully created archive: $archivePath" -ForegroundColor Green
		} else {
			Write-Host "Failed to create archive: $archivePath" -ForegroundColor Red
		}
	}
}
Write-Host "Archiving completed." -ForegroundColor Green
[console]::beep()
pause