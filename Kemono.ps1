[CmdletBinding()]
param (
    [string]$Function,
    [string]$Query,
    [string]$CreatorName,
    [string]$CreatorID,
    [string]$Service,
    [string]$WordFilter = "",
    [string]$WordFilterExclude = "",
    [string]$Files_To_Exclude = ""
)

Import-Module PSSQLite

########################################################
# Import functions
. "$PSScriptRoot/(config) Kemono.ps1"
. "$PSScriptRoot/Functions.ps1"
########################################################

function Download-Files-From-Database {
    param (
        [int]$Type,
        [string]$Query = ""
    )
    Write-Host "Files Table Columns: hash, hash_extension, filename, filename_extension, url, file_index, creatorName, postID, downloaded, favorite, deleted" -ForegroundColor Cyan
	$invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''
	if ($Type -eq 1) {
		Write-Host "`nStarting download of files..." -ForegroundColor Yellow
		$temp_query = "SELECT creatorID, creatorName, service FROM Creators;"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
		if ($result.Count -gt 0) {
			Write-Host "`nFound $($result.Count) creators." -ForegroundColor Green
			Backup-Database
			foreach ($Creator in $result) {
				$CreatorID = $Creator.creatorID; $CreatorName = $Creator.creatorName; $CreatorService = $Creator.service
				$ContinueFetching = $true
				$res = Invoke-SQLiteQuery -DataSource $DBFilePath -Query "SELECT last_time_downloaded FROM Creators WHERE creatorID = '$CreatorID'"
				if ($res.Count -gt 0 -and $res[0].last_time_downloaded) {
					$DateLast = [datetime]::ParseExact($res[0].last_time_downloaded, "yyyy-MM-dd HH:mm:ss", $null)
					if (((Get-Date) - $DateLast).TotalSeconds -lt $TimeToCheckAgainDownload) {
						$ContinueFetching = $false
						Write-Host "Recently downloaded. Skipping..." -ForegroundColor Yellow
					} else {
						Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Creators SET last_time_downloaded = NULL WHERE creatorID = '$CreatorID'"
					}
				}
				if ($ContinueFetching) {
					$res = Invoke-SQLiteQuery -DataSource $DBFilePath -Query "SELECT postID, title, content, date_published, total_files FROM Posts WHERE creatorName = '$CreatorName' AND downloaded = 0 AND deleted = 0;"
					if ($res.Count -gt 0) {
						Write-Host "`nFound $($res.Count) posts for $CreatorName." -ForegroundColor Green
						foreach ($Post in $res) {
							$files = Invoke-SQLiteQuery -DataSource $DBFilePath -Query "SELECT postID, hash, hash_extension, filename, filename_extension, url, file_index, creatorID, creatorName FROM Files WHERE postID = '$($Post.postID)' AND downloaded = 0;"
							if ($files.Count -gt 0) { Start-Download -SiteName "Kemono" -FileList $files -PostContent $Post.content }
						}
					}
				}
				$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
				Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Creators SET last_time_downloaded = '$CurrentDate' WHERE creatorID = '$CreatorID'"
			}
		}
	} elseif ($Type -eq 2) {
        $WhereQuery = if ([string]::IsNullOrEmpty($Query)) { Read-Host "`nEnter WHERE query:" } else { $Query }
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query "SELECT postID, creatorName, hash, hash_extension, filename, filename_extension, url, file_index FROM Files $WhereQuery;"
		if ($result.Count -gt 0) { Start-Download -SiteName "Kemono" -FileList $result }
	}
}

function Download-Metadata-From-Creator {
    param ($CreatorName, $CreatorID, $Service, $WordFilter, $WordFilterExclude, $Files_To_Exclude)
	$Cur_Offset = 0; $FormatList = $Files_To_Exclude -split ', '; $HasMoreFiles = $true
	$CreatorName = $CreatorName -replace "'", ""
	$res = Invoke-SqliteQuery -DataSource $DBFilePath -Query "SELECT EXISTS(SELECT 1 from Creators WHERE creatorID = '$CreatorID' AND service = '$Service');"
	if ($res.'EXISTS(SELECT 1 from Creators WHERE creatorID = ''$CreatorID'' AND service = ''$Service'')' -eq 0) {
		$Response = Invoke-KemonoApi -Uri "$($BaseURL)/$Service/user/$($CreatorID)/profile"
        if ($null -eq $Response) { return }
		$Json = $Response.Content | ConvertFrom-Json
		if ($Json) {
			$DateIndexed = $Json.indexed -replace 'T', ' ' -replace '\.\d+', ''
			$DateUpdated = $Json.updated -replace 'T', ' ' -replace '\.\d+', ''
			$DateIndexedF = [datetime]::ParseExact($DateIndexed, "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss")
			$DateUpdatedF = [datetime]::ParseExact($DateUpdated, "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss")
			Invoke-SqliteQuery -DataSource $DBFilePath -Query "INSERT INTO Creators (creatorID, creatorName, service, date_indexed, date_updated) VALUES ('$CreatorID', '$CreatorName', '$Service', '$DateIndexedF', '$DateUpdatedF')"
			Write-Host "New creator $CreatorName added." -ForegroundColor Green
		}
	} else {
		Write-Host "Found creator $CreatorName in DB." -ForegroundColor Green
		$res = Invoke-SQLiteQuery -DataSource $DBFilePath -Query "SELECT deleted, last_time_fetched_metadata, page_offset FROM Creators WHERE creatorID = '$CreatorID' AND service = '$Service'"
		if ($res[0].deleted -eq 1) { Write-Host "Deleted. Skipping..."; return }
		if ($res[0].last_time_fetched_metadata) {
			$DateLast = [datetime]::ParseExact($res[0].last_time_fetched_metadata, "yyyy-MM-dd HH:mm:ss", $null)
			if (((Get-Date) - $DateLast).TotalSeconds -lt $TimeToCheckAgainMetadata) {
				$HasMoreFiles = $false; Write-Host "Recently updated. Skipping metadata." -ForegroundColor Yellow
			} else {
				$Response = Invoke-KemonoApi -Uri "$($BaseURL)/$Service/user/$($CreatorID)/profile"
                if ($null -eq $Response) { return }
				$Json = $Response.Content | ConvertFrom-Json
				if ($Json) {
					$DateUpdated = $Json.updated -replace 'T', ' ' -replace '\.\d+', ''
					$DateUpdatedF = [datetime]::ParseExact($DateUpdated, "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss")
					if ($DateLast -gt $DateUpdatedF) { $HasMoreFiles = $false; Write-Host "No updates since last fetch." -ForegroundColor Yellow }
				}
			}
		}
		if ($HasMoreFiles) { $Cur_Offset = [int]$res[0].page_offset; if ($Cur_Offset -gt 0) { Write-Host "Starting from offset $Cur_Offset." -ForegroundColor Green } }
	}
	if ($HasMoreFiles) {
		$CurrentSkips = 0
		while ($HasMoreFiles) {
			$URL = "$($BaseURL)/$Service/user/$($CreatorID)/posts?o=$Cur_Offset"
			Write-Host "`nFetching metadata for $CreatorName (Offset: $Cur_Offset)..." -ForegroundColor Green
			try {
				$ResponseRaw = Invoke-KemonoApi -Uri $URL
                if ($null -eq $ResponseRaw) { $HasMoreFiles = $false; break }
				$Response = $ResponseRaw.Content | ConvertFrom-Json
				if ($Response -and $Response.Count -gt 0) {
					Write-Host "Number of posts: $($Response.Count)" -ForegroundColor Green
					foreach ($Post in $Response) {
						$PostID = $Post.id; $PostTitle = $Post.title; $PostContent = $Post.content
						if (Check-WordFilter -Content $PostTitle -WordFilter $WordFilter -WordFilterExclude $WordFilterExclude) {
							$res = Invoke-SqliteQuery -DataSource $DBFilePath -Query "SELECT EXISTS(SELECT 1 from Posts WHERE postID = '$PostID');"
							if ($res.'EXISTS(SELECT 1 from Posts WHERE postID = ''$PostID'')' -eq 1) {
								Write-Host "Post ID $PostID exists, skipping..." -ForegroundColor Yellow
								if ($MaxSkipsBeforeAborting -gt 0 -and ++$CurrentSkips -gt $MaxSkipsBeforeAborting) { $HasMoreFiles = $false; break }
							} else {
								Write-Host "Adding post $PostTitle ($PostID)..." -ForegroundColor Green
								$TitleEscaped = $PostTitle -replace "'", "''"; $ContentEscaped = $PostContent -replace "'", "''"
								if ($PostContentSkip) { $ContentEscaped = "" }
								$DateA = if ($Post.added) { [datetime]::ParseExact(($Post.added -replace 'T', ' ' -replace '\.\d+', ''), "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
								$DateP = if ($Post.published) { [datetime]::ParseExact(($Post.published -replace 'T', ' ' -replace '\.\d+', ''), "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
								$Cur_Index = 0; $HashList = New-Object System.Collections.Generic.List[System.Object]
								$sqlScript = "BEGIN TRANSACTION; "
								$filesToProcess = @()
								if ($Post.file -and $Post.file.name) { $filesToProcess += $Post.file }
								if ($Post.attachments) { $filesToProcess += $Post.attachments }
								foreach ($File in $filesToProcess) {
									$Cur_Index++
									$parts = [regex]::Match($File.name, "^(.*\S)\s*\.\s*([^.]+)$")
									$Fn = ($parts.Groups[1].Value -replace "'", "''"); $Fe = $parts.Groups[2].Value
									$HashWithExt = Split-Path -Path $File.path -Leaf; $Fh, $He = $HashWithExt -split '\.'
									if ($FormatList -notcontains $Fe -and $HashList -notcontains $Fh) {
										$HashList.Add($Fh) | Out-Null
										$resExists = Invoke-SqliteQuery -DataSource $DBFilePath -Query "SELECT exists(SELECT 1 FROM Files WHERE hash = '$Fh');"
										if ($resExists.'EXISTS(SELECT 1 from Files WHERE hash = ''$Fh'')' -eq 0) {
											$sqlScript += "INSERT INTO Files (hash, hash_extension, filename, filename_extension, url, file_index, creatorName, postID, downloaded) VALUES ('$Fh', '$He', '$Fn', '$Fe', '$(Split-Path -Path $File.path -Parent)', '$Cur_Index', '$CreatorName', '$PostID', 0); "
										}
									}
								}
								$sqlScript += "INSERT INTO Posts (postID, creatorName, title, content, date_published, date_added, downloaded, total_files) VALUES ('$PostID', '$CreatorName', '$TitleEscaped', '$ContentEscaped', '$DateP', '$DateA', 0, '$Cur_Index'); COMMIT;"
								Invoke-SqliteQuery -DataSource $DBFilePath -Query $sqlScript
							}
						}
					}
					if ($HasMoreFiles) {
						$Cur_Offset += 50
						Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Creators SET page_offset = '$Cur_Offset' WHERE creatorID = '$CreatorID' AND service = '$Service'"
						Start-Sleep -Milliseconds $TimeToWait
					}
				} else {
					Write-Host "No more posts found." -ForegroundColor Yellow
					Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Creators SET page_offset = 0, last_time_fetched_metadata = '$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")' WHERE creatorID = '$CreatorID' AND service = '$Service'"
					$HasMoreFiles = $false; break
				}
			} catch { Write-Host "Failed to fetch: $($_.Exception.Message)" -ForegroundColor Red; $HasMoreFiles = $false; break }
		}
	}
}

function Process-Creators { foreach ($Creator in $CreatorList) { Download-Metadata-From-Creator -CreatorName $Creator[0] -CreatorID $Creator[1] -Service $Creator[2] -WordFilter $Creator[3] -WordFilterExclude $Creator[4] -Files_To_Exclude $Creator[5] } }

Create-Database-If-It-Doesnt-Exist -SiteName "Kemono" -DBFilePath $DBFilePath
Invoke-SqliteQuery -DataSource $DBFilePath -Query "PRAGMA default_cache_size = $PRAGMA_default_cache_size; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;"

function Show-Menu {
    param ([string]$Query = "")
	try {
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/Kemono_$($CurrentDate).log" -Append
		$exitScript = $false
		while (-not $exitScript) {    
			Write-Host "`nKemono Downloader`n1. Metadata and files`n2. Metadata only`n3. All files in DB`n4. Files from query`n5. Scan favorites`n6. Exit" -ForegroundColor Green
			$choice = Read-Host "`nSelect (1-6)"
			if ($choice -eq 1) { Backup-Database; Process-Creators; Download-Files-From-Database -Type 1 }
			elseif ($choice -eq 2){ Backup-Database; Process-Creators }
			elseif ($choice -eq 3){ Download-Files-From-Database -Type 1 }
			elseif ($choice -eq 4){ Download-Files-From-Database -Type 2 -Query $Query }
			elseif ($choice -eq 5){ Backup-Database; Scan-Folder-And-Add-Files-As-Favorites -Type 3 }
			elseif ($choice -eq 6){ $exitScript = $true }
		}
	} finally { Stop-Transcript }
}

if ($Function) {
	try {
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/Kemono_$($CurrentDate).log" -Append
		switch ($Function) {
			'DownloadAllMetadataAndFiles' { Backup-Database; Process-Creators; Download-Files-From-Database -Type 1 }
			'DownloadAllMetadata' { Backup-Database; Process-Creators }
			'DownloadOnlyFiles' { Download-Files-From-Database -Type 1 }
			'DownloadFilesFromQuery' { Download-Files-From-Database -Type 2 -Query $Query }
			'ScanFolderForFavorites' { Backup-Database; Scan-Folder-And-Add-Files-As-Favorites -Type 3 }
			'DownloadMetadataForSingleCreator' { Backup-Database; Download-Metadata-From-Creator -CreatorName $CreatorName -CreatorID $CreatorID -Service $Service -WordFilter $WordFilter -WordFilterExclude $WordFilterExclude -Files_To_Exclude $Files_To_Exclude }
		}
	} finally { Stop-Transcript; [console]::beep() }
} else { Show-Menu; [console]::beep() }
