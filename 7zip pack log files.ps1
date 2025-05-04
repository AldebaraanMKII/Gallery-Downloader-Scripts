# Set the date format for the file name
$date = Get-Date -Format "yyyyMMdd_HHmmss"

# Define the subfolder path
$logPath = "./logs"

# Compress all .log files in the 'log' subfolder into a 7z archive
& 7z a "$logPath/Logs backup $date.7z" "$logPath/*.log"

# Delete the original log files after compression
Remove-Item -Path "$logPath/*.log"
