[CmdletBinding()]
param (
    [string]$Function,
    [string]$Query,
    [string]$Username
)

Import-Module PSSQLite

###############################
# Import functions and configuration
. "$PSScriptRoot/(config) CivitAI.ps1"
. "$PSScriptRoot/Functions.ps1"
###############################

function Download-Files-From-Database {
    param (
        [int]$Type,
        [string]$Query = ""
    )
    Write-Host "Files Table Columns (for download operations): id[int], filename[string], extension[string], width[int], height[int], url[string], createdAt[string], postId[int], username[string], rating[string], downloaded[int/0-1], favorite[int/0-1], deleted[int/0-1]" -ForegroundColor Cyan

	# Define the invalid characters for Windows file names
	$invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''

	if ($Type -eq 1) {
		Write-Host "Starting download of files..." -ForegroundColor Yellow
		$temp_query = "SELECT username FROM Users;"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
		if ($result.Count -gt 0) {
			Write-Host "Found $($result.Count) users." -ForegroundColor Green
			Backup-Database
			foreach ($User in $result) {
				$Username = $User.username
				Write-Host "`nProcessing username $Username..." -ForegroundColor Yellow
				$ContinueFetching = $true
				$temp_query = "SELECT last_time_downloaded FROM Users WHERE username = '$Username'"
				$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
				if ($result.Count -gt 0) {
					if (-not [string]::IsNullOrWhiteSpace($result[0].last_time_downloaded)) {
						$DateLastDownloaded = $result[0].last_time_downloaded
						$CurrentDate = [datetime]::ParseExact((Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "yyyy-MM-dd HH:mm:ss", $null)
						$DateLastDownloaded = [datetime]::ParseExact($DateLastDownloaded, "yyyy-MM-dd HH:mm:ss", $null)
						$TimeDifference = $CurrentDate - $DateLastDownloaded
						if ($TimeDifference.TotalSeconds -lt $TimeToCheckAgainDownload) {
							$ContinueFetching = $false
							Write-Host "This user's gallery was downloaded recently. Skipping..." -ForegroundColor Yellow
						} else {
							Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Users SET last_time_downloaded = NULL WHERE username = '$Username'"
						}
					}
				}
				if ($ContinueFetching) {
					$temp_query = "SELECT id, filename, extension, width, height, url, createdAt, username FROM Files WHERE username = '$Username' AND downloaded = 0 AND deleted = 0;"
					$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
					if ($result.Count -gt 0) {
						Start-Download -SiteName "CivitAI" -FileList $result
					} else {
						Write-Host "Found 0 files for username $Username." -ForegroundColor Yellow
						$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
						Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Users SET last_time_downloaded = '$CurrentDate' WHERE username = '$Username'"
					}
				}
				$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
				Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Users SET last_time_downloaded = '$CurrentDate' WHERE username = '$Username'"
			}
		} else {
			Write-Host "Found 0 users in database." -ForegroundColor Red
		}
	} elseif ($Type -eq 2) {
        if ([string]::IsNullOrEmpty($Query)) { $WhereQuery = Read-Host "`nEnter WHERE query:" } else { $WhereQuery = $Query }
		$temp_query = "SELECT username, id, filename, extension, width, height, url, createdAt FROM Files $WhereQuery;"
        $stopwatch_temp = [System.Diagnostics.Stopwatch]::StartNew()
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
        $stopwatch_temp.Stop()
        Write-Host "`nFetched results in $($stopwatch_temp.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
		if ($result.Count -gt 0) {
			Start-Download -SiteName "CivitAI" -FileList $result
		} else {
			Write-Host "Found 0 files for query." -ForegroundColor Red
		}
	}
}

function Download-Metadata-From-User {
    param ([string]$Username)
	$CursorString = ""; $ContinueFetching = $true; $TotalFiles = 0
	$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query "SELECT EXISTS(SELECT 1 from Users WHERE username = '$Username');"
	if ($result.'EXISTS(SELECT 1 from Users WHERE username = ''$Username'')' -eq 0) {
        Invoke-SqliteQuery -DataSource $DBFilePath -Query "INSERT INTO Users (username, url, cur_cursor) VALUES ('$Username', 'https://civitai.com/user/$Username/images', NULL)"
        Write-Host "`nNew user $Username added." -ForegroundColor Green
	} else {
		Write-Host "`nFound user $Username in DB." -ForegroundColor Green
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query "SELECT deleted, last_time_fetched_metadata, cur_cursor FROM Users WHERE username = '$Username'"
		if ($result[0].deleted -eq 1) { Write-Host "User $Username is deleted. Skipping..."; return }
		if (-not [string]::IsNullOrWhiteSpace($result[0].last_time_fetched_metadata)) {
			$DateLast = [datetime]::ParseExact($result[0].last_time_fetched_metadata, "yyyy-MM-dd HH:mm:ss", $null)
			if (((Get-Date) - $DateLast).TotalSeconds -lt $TimeToCheckAgainMetadata) {
				$ContinueFetching = $false
				Write-Host "Recently updated. Skipping metadata." -ForegroundColor Yellow
			} else {
				Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Users SET last_time_fetched_metadata = NULL WHERE username = '$Username'"
			}
		}
        if ($result[0].cur_cursor) { $Cursor = $result[0].cur_cursor; $CursorString = "&cursor=$Cursor"; Write-Host "Starting from cursor $Cursor." -ForegroundColor Green }
	}
	$RatingList = if ($AllowSFWFiles -and $AllowNSFWFiles) { @("X","Mature","Soft","None") } elseif ($AllowSFWFiles) { @("Soft","None") } else { @("X","Mature") }
	if ($ContinueFetching) {
		$CurrentSkips = 0
		foreach ($Rating in $RatingList) {
			$HasMoreFiles = $true
			while ($HasMoreFiles) {
				$URL = "$($BaseURL)?username=$Username&limit=$Limit&period=AllTime&sort=Newest&nsfw=$($Rating)$($CursorString)"
				Write-Host "`nFetching metadata (Rating: $Rating)..." -ForegroundColor Yellow
				try {
					$ResponseRaw = Invoke-CivitAIApi -Uri $URL -Method Get
                    if ($null -eq $ResponseRaw) { $HasMoreFiles = $false; break }
					$Response = $ResponseRaw.Content | ConvertFrom-Json -AsHashTable
					if ($Response.items -and $Response.items.Count -gt 0) {
						Write-Host "Found $($Response.items.Count) items." -ForegroundColor Green
						$sqlScript = "BEGIN TRANSACTION; " 
						foreach ($File in $Response.items) {
							$FileID = $File.id
							$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query "SELECT EXISTS(SELECT 1 FROM Files WHERE id = '$FileID');"
							if ($result.'EXISTS(SELECT 1 FROM Files WHERE id = ''$FileID'')' -eq 1) {
								Write-Host "FileID $FileID exists, skipping..." -ForegroundColor Yellow
								if ($MaxSkipsBeforeAborting -gt 0 -and ++$CurrentSkips -gt $MaxSkipsBeforeAborting) {
									Write-Host "Max skips reached. Skipping user." -ForegroundColor Yellow
									$HasMoreFiles = $false; break
								}
							} else {
								$FileUrlRaw = $File.url; $FileWidth = $File.width; $FileHeight = $File.height
								$formattedDate = [datetime]::ParseExact($File.createdAt, "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss")
								$filenameWithExt = ([uri]$FileUrlRaw).Segments[-1]; $filename, $extension = $filenameWithExt -split '\.'
								if ($DownloadPromptMetadata) {
									$meta = $File.meta
									$q = "INSERT INTO Files (id, filename, extension, width, height, url, createdAt, postId, username, rating, meta_size, meta_seed, meta_model, meta_steps, meta_prompt, meta_sampler, meta_cfgScale, meta_clip_skip, meta_hires_upscale, meta_hires_upscaler, meta_negativePrompt, meta_denoising_strength, downloaded)
										VALUES ('$FileID', '$filename', '$extension', '$FileWidth', '$FileHeight', '', '$formattedDate', '$($File.postId)', '$($File.username)', '$Rating', '$($meta.Size)', '$($meta.seed)', '$($meta.Model -replace "'", "")', '$($meta.steps)', '$($meta.prompt -replace "'", "")', '$($meta.sampler -replace "'", "")', '$($meta.cfgScale)', '$($meta.'Clip skip')', '$($meta.'Hires upscale')', '$($meta.'Hires upscaler')', '$($meta.negativePrompt -replace "'", "")', '$($meta.'Denoising strength')', 0);"
								} else {
									$q = "INSERT INTO Files (id, filename, extension, width, height, url, createdAt, postId, username, rating, downloaded)
										VALUES ('$FileID', '$filename', '$extension', '$FileWidth', '$FileHeight', '', '$formattedDate', '$($File.postId)', '$($File.username)', '$Rating', 0);"
								}
								$sqlScript += $q + " "; Write-Host "Added FileID $FileID." -ForegroundColor Green
							}
						}
						$sqlScript += "COMMIT;"; Invoke-SqliteQuery -DataSource $DBFilePath -Query $sqlScript
						$res = Invoke-SqliteQuery -DataSource $DBFilePath -Query "SELECT COUNT(*) AS FileCount FROM Files WHERE username = '$Username'"
						Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Users SET total_files = '$($res.FileCount)' WHERE username = '$Username'"
						if ($HasMoreFiles -and $Response.metadata.nextCursor) {
							$Cursor = $Response.metadata.nextCursor; $CursorString = "&cursor=$Cursor"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Users SET cur_cursor = '$Cursor' WHERE username = '$Username'"
							Start-Sleep -Milliseconds $TimeToWait
						} else {
							Write-Host "No more files for user $Username" -ForegroundColor Yellow
							Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Users SET cur_cursor = NULL WHERE username = '$Username'"
							$HasMoreFiles = $false; break
						}
					} else { Write-Host "No items found."; $HasMoreFiles = $false; break }
				} catch {
					if ($_.Exception.Response.StatusCode -eq 500) {
						Write-Host "Error 500. User likely doesn't exist. Marking deleted." -ForegroundColor Red
						Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Users SET deleted = 1 WHERE username = '$Username'"
						$HasMoreFiles = $false; return
					} else { Write-Host "Failed to fetch: $($_.Exception.Message)" -ForegroundColor Red; $HasMoreFiles = $false; break }
				}
			}
			Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Users SET cur_cursor = NULL WHERE username = '$Username'"; $CursorString = ""
		}
		$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
		Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Users SET last_time_fetched_metadata = '$CurrentDate' WHERE username = '$Username'"
	}
}

function Process-Users { foreach ($User in $UserList) { Download-Metadata-From-User -Username $User } }

Create-Database-If-It-Doesnt-Exist -SiteName "CivitAI" -DBFilePath $DBFilePath
Invoke-SqliteQuery -DataSource $DBFilePath -Query "PRAGMA default_cache_size = $PRAGMA_default_cache_size; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;"

function Show-Menu {
    param ([string]$Query = "")
	try {
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/CivitAI_$($CurrentDate).log" -Append
        if (-not [string]::IsNullOrEmpty($Query)) { $choice = 4 } else {
			Write-Host "`nCivitAI Powershell Downloader`n1. Metadata and files`n2. Metadata only`n3. All files in DB`n4. Files from query`n5. Scan favorites`n6. Exit" -ForegroundColor Green
			$choice = Read-Host "`nSelect (1-6)"
		}
		if ($choice -eq 1) { Backup-Database; Process-Users; Download-Files-From-Database -Type 1 }
		elseif ($choice -eq 2){ Backup-Database; Process-Users }
		elseif ($choice -eq 3){ Download-Files-From-Database -Type 1 }
		elseif ($choice -eq 4){ Download-Files-From-Database -Type 2 -Query $Query }
		elseif ($choice -eq 5){ Backup-Database; Scan-Folder-And-Add-Files-As-Favorites -Type 2 }
	} finally { Stop-Transcript }
}

if ($Function) {
	try {
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/CivitAI_$($CurrentDate).log" -Append
		switch ($Function) {
			'DownloadAllMetadataAndFiles' { Backup-Database; Process-Users; Download-Files-From-Database -Type 1 }
			'DownloadAllMetadata' { Backup-Database; Process-Users }
			'DownloadOnlyFiles' { Download-Files-From-Database -Type 1 }
			'DownloadFilesFromQuery' { Download-Files-From-Database -Type 2 -Query $Query }
			'ScanFolderForFavorites' { Backup-Database; Scan-Folder-And-Add-Files-As-Favorites -Type 2 }
			'DownloadMetadataForSingleUser' { Backup-Database; Download-Metadata-From-User -Username $Username }
		}
	} finally { Stop-Transcript; [console]::beep() }
} else { Show-Menu; [console]::beep() }
