[CmdletBinding()]
param (
    [string]$Function,
    [string]$Query,
    [string]$Username,
    [string]$WordFilter = "",
    [string]$WordFilterExclude = ""
)

Import-Module PSSQLite

###############################
# Import functions
. "$PSScriptRoot/(config) DeviantArt.ps1"
. "$PSScriptRoot/Functions.ps1"
########################################################
function Download-Files-From-Database {
    param (
        [int]$Type,
        [string]$Query = ""
    )
    Write-Host "Files Table Columns (for download operations): deviationID[string], url[string], src_url[string], extension[string], width[int], height[int], title[string], username[string], published_time[string], downloaded[int/0-1], favorite[int/0-1], deleted[int/0-1]" -ForegroundColor Cyan

	# Define the invalid characters for Windows file names
	$invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''

	
	if ($Type -eq 1) {
		Write-Host "`nStarting download of files..." -ForegroundColor Yellow
		#same query for all
		$temp_query = "SELECT username FROM Users;"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
###################
		if ($result.Count -gt 0) {
			Write-Host "Found $($result.Count) users." -ForegroundColor Green
			Backup-Database
###################
			foreach ($User in $result) {
				$Username = $User.username
				Write-Host "`nProcessing username $Username..." -ForegroundColor Yellow
				
				$ContinueFetching = $true
				#load last_time_downloaded and start search from there
				$temp_query = "SELECT last_time_downloaded FROM Users WHERE username = '$Username'"
				$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
									
				# Check the result
				if ($result.Count -gt 0) {
					if (-not [string]::IsNullOrWhiteSpace($result[0].last_time_downloaded)) {
						$DateLastDownloaded = $result[0].last_time_downloaded
						
						# Ensure both dates are DateTime objects
						$CurrentDate = [datetime]::ParseExact((Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "yyyy-MM-dd HH:mm:ss", $null)
						$DateLastDownloaded = [datetime]::ParseExact($DateLastDownloaded, "yyyy-MM-dd HH:mm:ss", $null)
		
						$TimeDifference = $CurrentDate - $DateLastDownloaded
						$SecondsDifference = $TimeDifference.TotalSeconds
	
						if ($SecondsDifference -lt $TimeToCheckAgainDownload) {
							$ContinueFetching = $false
							Write-Host "This user's gallery was downloaded less than $TimeToCheckAgainDownload seconds ago. Skipping..." -ForegroundColor Yellow
						} else {
							#update the last_time_downloaded column to NULL
							$temp_query = "UPDATE Users SET last_time_downloaded = NULL WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
###########################
						}
###########################
					}
				}
###########################
				if ($ContinueFetching) {
###########################
					$temp_query = "SELECT deviationID, src_url, extension, height, width, title, published_time, username FROM Files WHERE UPPER(username) = UPPER('$Username') AND downloaded = 0 AND deleted = 0;"
	
					# Write-Host "temp_query: $temp_query" -ForegroundColor Yellow
					$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
##################################
					if ($result.Count -gt 0) {
						Start-Download -SiteName "DeviantArt" -FileList $result
############################################
					} else {
						Write-Host "Found 0 files that meet the query requirements for username $Username. Skipping..." -ForegroundColor Red
						
						$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
						#update the last_time_downloaded column
						$temp_query = "UPDATE Users SET last_time_downloaded = '$CurrentDate' WHERE username = '$Username'"
						Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
					}
######################################
				}
				
				$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
				#update the last_time_downloaded column
				$temp_query = "UPDATE Users SET last_time_downloaded = '$CurrentDate' WHERE username = '$Username'"
				Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
######################################
			}
######################################
		} else {
			Write-Host "Found 0 users in database. Terminating..." -ForegroundColor Red
		}
######################################
	} elseif ($Type -eq 2) {
        if (-not [string]::IsNullOrEmpty($Query)) {
            $WhereQuery = $Query
            Write-Host "`nUsing provided query: '$WhereQuery'" -ForegroundColor Blue
        } else {
            $WhereQuery = $(Write-Host "`nEnter WHERE query:" -ForegroundColor cyan -NoNewLine; Read-Host)
        }
		
		$temp_query = "SELECT username, deviationID, src_url, extension, height, width, title, published_time FROM Files $WhereQuery;"
	
        $stopwatch_temp = [System.Diagnostics.Stopwatch]::StartNew()
		# Write-Host "temp_query: $temp_query" -ForegroundColor Yellow
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
        $stopwatch_temp.Stop()
        Write-Host "`nFetched results in $($stopwatch_temp.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
######################################
		if ($result.Count -gt 0) {
			Start-Download -SiteName "DeviantArt" -FileList $result
######################################
		} else {
			Write-Host "Found 0 files that meet the query conditions." -ForegroundColor Red
		}
######################################
	}
######################################
}
######################################

########################################################
# Function to download metadata
function Download-Metadata-From-User {
    param (
        [string]$Username,
        [string]$WordFilter,
        [string]$WordFilterExclude
    )
########################################################
	# Set initial parameters for paging
	$Cur_Offset = 0
	
	$ContinueFetching = $true
########################################################
	
######### Add user if it doesn`t exist
	$temp_query = "SELECT EXISTS(SELECT 1 from Users WHERE username = '$Username');"
	$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
	$exists = $result."EXISTS(SELECT 1 from Users WHERE username = '$Username')"
########################################################
	# Check the result
	if ($exists -eq 0) {
		$URL = "https://www.deviantart.com/api/v1/oauth2/user/profile/$($Username)?ext_collections=1&ext_galleries=1"
		Write-Host "`nURL: $URL" -ForegroundColor Yellow
		
		Write-Host "Fetching username $username metadata..." -ForegroundColor Yellow
		$retryCount = 0
		while ($retryCount -lt $maxRetries) {
			try {
				$Response = Invoke-DeviantArtApi -Uri $URL -Method Get
                if ($null -eq $Response) {
                    Write-Host "Failed to fetch user $Username profile." -ForegroundColor Red
                    $ContinueFetching = $false
                    return
                }
				$Json = $Response.Content | ConvertFrom-Json
			
				if ($Json.user.username) {
					# normal success path
					Write-Host "User found" -ForegroundColor Green
					$UserID = $Json.user.userid
					$Country = $Json.country
					#fix backtick issues
					$Country = $Country -replace "'", ""
					$User_Deviations = $Json.stats.user_deviations
					
					$username_url = "https://www.deviantart.com/$($Username)/gallery/all"
					
					$temp_query = "INSERT INTO Users (username, userID, url, country, total_user_deviations)
												VALUES ('$Username', '$UserID', '$username_url', '$Country', '$User_Deviations')"
					
					Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
					
					Write-Host "New user $Username added to database." -ForegroundColor Green
					Start-Sleep -Milliseconds 3000
					break
########################################################
				} elseif ($Json.error_code -in 1,400,404 -or $Json.error_description -in @("Sorry, we have blocked access to this profile.", "Account is inactive.")) {
					Write-Host "User $Username not found, deleted or blocked (error_description: $($Json.error_description)). Marking user as deleted." -ForegroundColor Red
					$temp_query = "UPDATE Users SET deleted = 1 WHERE username = '$Username'"
					Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
					$ContinueFetching = $false
					return
				} elseif ($Json.error_code -eq 429) {
					$delay = Calculate-Delay -retryCount $retryCount
					$retryCount++
					Write-Host "error 429 encountered. Retrying in $delay ms..." -ForegroundColor Yellow
					Start-Sleep -Milliseconds $delay
				} else {
					Write-Host "(Download-Metadata-From-User 1) Error: $($Json.error) | Description: $($Json.error_description) | Code: $($Json.error_code) | Status: $($Json.status)" -ForegroundColor Red
					$ContinueFetching = $false
					return
				}
			} catch {
				Write-Host "Network/transport error: $($_.Exception.Message)" -ForegroundColor Red
				$ContinueFetching = $false
				return
			}
		}
	} else {
		Write-Host "`nFound user $Username in database." -ForegroundColor Green
		#check if deleted
		$temp_query = "SELECT deleted FROM Users WHERE username = '$Username'"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
		$deleted = $result[0].deleted
		if ($deleted -eq 1) {
			Write-Host "User $Username is deleted. Skipping..." -ForegroundColor Yellow
			return #go to next user
		}
		#load last_time_fetched_metadata and start search from there
		$temp_query = "SELECT last_time_fetched_metadata FROM Users WHERE username = '$Username'"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
		if ($result.Count -gt 0) {
			if (-not [string]::IsNullOrWhiteSpace($result[0].last_time_fetched_metadata)) {
				$DateLastDownloaded = $result[0].last_time_fetched_metadata
				$CurrentDate = [datetime]::ParseExact((Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "yyyy-MM-dd HH:mm:ss", $null)
				$DateLastDownloaded = [datetime]::ParseExact($DateLastDownloaded, "yyyy-MM-dd HH:mm:ss", $null)
				$TimeDifference = $CurrentDate - $DateLastDownloaded
				$SecondsDifference = $TimeDifference.TotalSeconds
				if ($SecondsDifference -lt $TimeToCheckAgainMetadata) {
					$ContinueFetching = $false
					Write-Host "This user was updated less than $TimeToCheckAgainMetadata seconds ago. Skipping..." -ForegroundColor Yellow
				} else {
					$URL = "https://www.deviantart.com/api/v1/oauth2/user/profile/$($Username)?ext_collections=1&ext_galleries=1"
					try {
						$Response = Invoke-DeviantArtApi -Uri $URL -Method Get
                        if ($null -eq $Response) {
                            Write-Host "Failed to update user $Username deviations count." -ForegroundColor Red
                            $ContinueFetching = $false
                            return
                        }
						$Json     = $Response.Content | ConvertFrom-Json
						if ($Json.stats.user_deviations) {
							Write-Host "Found user in DeviantArt`s database." -ForegroundColor Yellow
							$User_Deviations = $Json.stats.user_deviations
							$temp_query = "UPDATE Users SET total_user_deviations = '$User_Deviations' WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							Start-Sleep -Milliseconds 3000
						} elseif ($Json.error_code -in 1,400,404 -or $Json.error_description -in @("Sorry, we have blocked access to this profile.", "Account is inactive.")) {
							Write-Host "User $Username not found, deleted or blocked (error_description: $($Json.error_description)). Marking user as deleted." -ForegroundColor Red
							$temp_query = "UPDATE Users SET deleted = 1 WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							$ContinueFetching = $false
							return
						} elseif ($Json.error_code -eq 429) {
							$delay = Calculate-Delay -retryCount $retryCount
							$retryCount++
							Write-Host "error 429 encountered. Retrying in $delay milliseconds..." -ForegroundColor Yellow
							Start-Sleep -Milliseconds $delay
						} else {
							Write-Host "(Download-Metadata-From-User 2) Error: $($Json.error) | Description: $($Json.error_description) | Code: $($Json.error_code) | Status: $($Json.status)" -ForegroundColor Red
							$ContinueFetching = $false
							return
						}
					} catch {
						Write-Host "Network/transport error: $($_.Exception.Message)" -ForegroundColor Red
						$ContinueFetching = $false
						return
					}
				}
			}
			$temp_query = "SELECT cur_offset FROM Users WHERE username = '$Username'"
			$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
			if ($result.Count -gt 0) {
				if ($result[0].cur_offset -gt 0) {
					$Cur_Offset = $result[0].cur_offset
					Write-Host "Starting from offset $Cur_Offset." -ForegroundColor Green
				} else {
					$Cur_Offset = 0
				}
			}
		}
	}
	$CurrentSkips = 0
	if ($ContinueFetching) {
		$HasMoreFiles = $true
		while ($HasMoreFiles) {
			$retryCount = 0
			while ($retryCount -lt $maxRetries) {
				if ($Cur_Offset -gt 0) {
					Write-Host "`nFetching metadata for offset $Cur_Offset for user $Username..." -ForegroundColor Yellow
				} else {
					Write-Host "`nFetching metadata for user $Username..." -ForegroundColor Yellow
				}
				try {
					$URL = "https://www.deviantart.com/api/v1/oauth2/gallery/all?username=$($Username)&offset=$($Cur_Offset)&limit=$($Limit)&mature_content=$($AllowMatureContent)"
					Write-Host "URL: $URL" -ForegroundColor Yellow
					$Result = Invoke-DeviantArtApi -Uri $URL -Method Get
                    if ($null -eq $Result) {
                        Write-Host "Failed to fetch gallery for user $Username." -ForegroundColor Red
                        $HasMoreFiles = $false
                        break
                    }
					$Response = $Result.Content | ConvertFrom-Json
					if ($Response.results -and $Response.results.Count -gt 0) {
						Write-Host "Number of results found: $($Response.results.Count)" -ForegroundColor Green
						$stopwatchCursor = [System.Diagnostics.Stopwatch]::StartNew()
						$sqlScript = "BEGIN TRANSACTION; " 
						foreach ($File in $Response.results) {
							$DeviationID = $File.deviationid
							$FileTitle = $File.title
							$Continue = $false
							if ($File.PSObject.Properties['tier_access']) {
								$TierAcess = $File.tier_access
								if ($TierAcess = "locked") {
									$Continue = $false
									Write-Host "File $DeviationID ($FileTitle) belongs to a tier that is locked from your account. Skipping..." -ForegroundColor Yellow
								} else { $Continue = $true }
							} else { $Continue = $true }
							if ($Continue) {
								if ($File.PSObject.Properties['premium_folder_data']) {
									$PremiumAccess = $File.premium_folder_data.has_access
									if ($PremiumAccess = "false") {
										$Continue = $false
										Write-Host "File $DeviationID ($FileTitle) belongs to a premium folder that is locked from your account. Skipping..." -ForegroundColor Yellow
									} else { $Continue = $true }
								} else { $Continue = $true }
								if ($Continue) {
									$Continue = $false
									$result = Check-WordFilter -Content $FileTitle -WordFilter $WordFilter -WordFilterExclude $WordFilterExclude
									if ($result) { $Continue = $true } else {
										Write-Host "File $DeviationID ($FileTitle) failed the title word filter." -ForegroundColor Yellow
									}
									if ($Continue) {
										$temp_query = "SELECT EXISTS(SELECT 1 from Files WHERE deviationid = '$DeviationID');"
										$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
										$exists = $result."EXISTS(SELECT 1 from Files WHERE deviationid = '$DeviationID')"
										if ($exists -eq 1) {
											Write-Host "File $DeviationID ($FileTitle) already exists in database, skipping..." -ForegroundColor Yellow
											$CurrentSkips++
											if ($MaxSkipsBeforeAborting -gt 0) {
												if ($CurrentSkips -gt $MaxSkipsBeforeAborting) {
													Write-Host "Reached maximum amount of skipped items. Skipping user $Username" -ForegroundColor Yellow
													$HasMoreFiles = $false
													break
												}
											}
										} else {
											$FileUrlRaw = $File.url
											$FileUrl = $FileUrlRaw -replace "https://www.deviantart.com/$($Username)/art/", ''
											$FileHeight = $File.content.height
											$FileWidth = $File.content.width
											$FileUsername = $File.author.username
											$FileTitle = $FileTitle -replace "'", "''"
											$FilePublishedTimeRaw = $File.published_time
											$FilePublishedTime = [System.DateTime]::UnixEpoch.AddSeconds($FilePublishedTimeRaw).ToString("yyyy-MM-dd HH:mm:ss")
											if ($File.PSObject.Properties['content']) {
												$FileSrcURLRaw = $File.content.src
												$FileSrcURL = $FileSrcURLRaw -replace "https://images-wixmp-", ""
												$FileSrcURL = $FileSrcURL -replace ",q_\d{1,3}", ",q_100"
												$firstFileType = [regex]::Match($FileSrcURL, "\.(bmp|png|jpg|jpeg|webp|avif|gif)").Value
												$lastFileType = [regex]::Match($FileSrcURL, "\.(bmp|png|jpg|jpeg|webp|avif|gif)(?=\?|$)").Value
												$FileExtension = $firstFileType
												if ($firstFileType -ne $lastFileType) {
													$FileSrcURL = $FileSrcURL -replace [regex]::Escape($lastFileType), $firstFileType
												}
												$temp_query = "INSERT INTO Files (deviationID, url, src_url, extension, height, width, title, username, published_time)
																			VALUES ('$DeviationID', '$FileUrl', '$FileSrcURL', '$FileExtension', '$FileHeight', '$FileWidth', '$FileTitle', '$FileUsername', '$FilePublishedTime');"
												$sqlScript += $temp_query + " "
												Write-Host "Added File $DeviationID ($FileTitle) ($FileExtension) to database." -ForegroundColor Green
											} elseif ($File.PSObject.Properties['videos'] -and $File.videos.Count -gt 0) {
												$highestResolutionVideo = $File.videos | Sort-Object { [int]($_.quality -replace 'p', '') } -Descending | Select-Object -First 1
												if ($highestResolutionVideo) {
													$VideoSrcURL = $highestResolutionVideo.src
													switch ($highestResolutionVideo.quality) {
														"2160p" { $FileWidth = ""; $FileHeight = "2160" }
														"1440p" { $FileWidth = ""; $FileHeight = "1440" }
														"1080p" { $FileWidth = ""; $FileHeight = "1080" }
														"720p" { $FileWidth = ""; $FileHeight = "720" }
														"480p" { $FileWidth = ""; $FileHeight = "480" }
														"360p" { $FileWidth = ""; $FileHeight = "360" }
														"240p" { $FileWidth = ""; $FileHeight = "240" }
														"144p" { $FileWidth = ""; $FileHeight = "144" }
													}
												}
												$VideoSrcURL = $VideoSrcURL -replace "https://wixmp-", ""
												if ($VideoSrcURL -match "\.\w+$") { $FileExtension = $matches[0] } else { $FileExtension = ".mp4" }
												$temp_query = "INSERT INTO Files (deviationID, url, src_url, extension, height, width, title, username, published_time)
																			VALUES ('$DeviationID', '$FileUrl', '$VideoSrcURL', '$FileExtension', '$FileHeight', '$FileWidth', '$FileTitle', '$FileUsername', '$FilePublishedTime');"
												$sqlScript += $temp_query + " "
												Write-Host "Added File $DeviationID ($FileTitle) ($FileExtension) to database." -ForegroundColor Green
											}
										}
									}
								}
							}
						}
						$sqlScript += "COMMIT;"  
						Invoke-SqliteQuery -DataSource $DBFilePath -Query $sqlScript
						$stopwatchCursor.Stop()
						if ($Cur_Offset -gt 0) {
							Write-Host "Fetched metadata for offset $Cur_Offset for user $Username in $($stopwatchCursor.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
						} else {
							Write-Host "Fetched metadata for user $Username in $($stopwatchCursor.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
						}
						if ($HasMoreFiles) {
							if ($Response.has_more -eq $true) {
								$Cur_Offset = $Response.next_offset
								$temp_query = "UPDATE Users SET Cur_Offset = '$Cur_Offset' WHERE username = '$Username'"
								Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								Start-Sleep -Milliseconds $TimeToWait
							} else {
								Write-Host "No more files found for user $UserName" -ForegroundColor Yellow
								$temp_query = "UPDATE Users SET Cur_Offset = 0 WHERE username = '$Username'"
								Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
								$temp_query = "UPDATE Users SET last_time_fetched_metadata = '$CurrentDate' WHERE username = '$Username'"
								Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								$temp_query = "SELECT COUNT(*) FROM Files WHERE UPPER(username) = UPPER('$Username')"
								$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								$Count = [int]$result[0].'COUNT(*)'
								$temp_query = "UPDATE Users SET deviations_in_database = '$Count' WHERE username = '$Username'"
								Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								$temp_query = "SELECT total_user_deviations FROM Users WHERE username = '$Username'"
								$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
								$User_Deviations = $result[0].total_user_deviations
								$LockedCount = $User_Deviations - $Count
								$temp_query = "UPDATE Users SET locked_deviations = '$LockedCount' WHERE username = '$Username'"
								Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								Start-Sleep -Milliseconds $TimeToWait
								$HasMoreFiles = $false
								break
							}
						} else {
							$temp_query = "UPDATE Users SET Cur_Offset = 0 WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
							$temp_query = "UPDATE Users SET last_time_fetched_metadata = '$CurrentDate' WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							$temp_query = "SELECT COUNT(*) FROM Files WHERE UPPER(username) = UPPER('$Username')"
							$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							$Count = [int]$result[0].'COUNT(*)'
							$temp_query = "UPDATE Users SET deviations_in_database = '$Count' WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							$temp_query = "SELECT total_user_deviations FROM Users WHERE username = '$Username'"
							$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
							$User_Deviations = $result[0].total_user_deviations
							$LockedCount = $User_Deviations - $Count
							$temp_query = "UPDATE Users SET locked_deviations = '$LockedCount' WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							$HasMoreFiles = $false
							break
						}
					} else {
						Write-Host "No items found in response. Skipping user $UserName..." -ForegroundColor Red
						$HasMoreFiles = $false
						break
					}
				} catch {
					if ($_.Exception.Response.StatusCode -in 429, 500) {
						$delay = Calculate-Delay -retryCount $retryCount
						$retryCount++
						Write-Host "error 429/500 encountered. Retrying in $delay milliseconds..." -ForegroundColor Red
						$TimeToWait = $TimeToWait + 100
						Start-Sleep -Milliseconds $delay
					} elseif ($Json.error_code -in 1,400,404 -or $Json.error_description -in @("Sorry, we have blocked access to this profile.", "Account is inactive.")) {
						Write-Host "User $Username not found, deleted or blocked. Marking user as deleted." -ForegroundColor Red
						$temp_query = "UPDATE Users SET deleted = 1 WHERE username = '$Username'"
						Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
						$ContinueFetching = $false
						return
					} else {
						Write-Host "(Download-Metadata-From-User 3) Error: $($Json.error) | Description: $($Json.error_description)" -ForegroundColor Red
						$HasMoreFiles = $false
						break
					}
				}
			}
		}
	}
}

function Process-Users {
	foreach ($User in $UserList) {
		$Username = $User[0]; $WordFilter = $User[1]; $WordFilterExclude = $User[2]
		Download-Metadata-From-User -Username $Username -WordFilter $WordFilter -WordFilterExclude $WordFilterExclude
	}
	Download-Files-From-Database -Type 1
}

function Process-Users-MetadataOnly {
	foreach ($User in $UserList) {
		$Username = $User[0]; $WordFilter = $User[1]; $WordFilterExclude = $User[2]
		Download-Metadata-From-User -Username $Username -WordFilter $WordFilter -WordFilterExclude $WordFilterExclude
	}
}

Create-Database-If-It-Doesnt-Exist -SiteName "DeviantArt" -DBFilePath $DBFilePath
Invoke-SqliteQuery -DataSource $DBFilePath -Query "PRAGMA default_cache_size = $PRAGMA_default_cache_size; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;"

function Show-Menu {
    param ([string]$Query = "")
	try {
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/DeviantArt_$($CurrentDate).log" -Append
		$exitScript = $false
		while (-not $exitScript) {
			Write-Host "`nDeviantArt Powershell Downloader" -ForegroundColor Green
			Write-Host "1. Download metadata and files`n2. Download only metadata`n3. Download all files in DB`n4. Download files from query`n5. Scan folder for favorites`n6. Exit" -ForegroundColor Green
			$choice = Read-Host "`nSelect (1-6)"
			if ($choice -eq 1) { Backup-Database; Process-Users }
			elseif ($choice -eq 2){ Backup-Database; Process-Users-MetadataOnly }
			elseif ($choice -eq 3){ Download-Files-From-Database -Type 1 }
			elseif ($choice -eq 4){ Download-Files-From-Database -Type 2 -Query $Query }
			elseif ($choice -eq 5){ Backup-Database; Scan-Folder-And-Add-Files-As-Favorites -Type 4 }
			elseif ($choice -eq 6){ $exitScript = $true }
		}
	} finally { Stop-Transcript }
}

if ($Function) {
	try {
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/DeviantArt_$($CurrentDate).log" -Append
		switch ($Function) {
			'DownloadAllMetadataAndFiles' { Backup-Database; Process-Users }
			'DownloadAllMetadata' { Backup-Database; Process-Users-MetadataOnly }
			'DownloadOnlyFiles' { Download-Files-From-Database -Type 1 }
			'DownloadFilesFromQuery' { Download-Files-From-Database -Type 2 -Query $Query }
			'ScanFolderForFavorites' { Backup-Database; Scan-Folder-And-Add-Files-As-Favorites -Type 4 }
			'DownloadMetadataForSingleUser' { Download-Metadata-From-User -Username $Username -WordFilter $WordFilter -WordFilterExclude $WordFilterExclude }
		}
	} finally { Stop-Transcript; [console]::beep() }
} else { Show-Menu; [console]::beep() }
