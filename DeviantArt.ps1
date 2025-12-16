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
	
		# Write-Host "temp_query: $temp_query" -ForegroundColor Yellow
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
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
################## Check and retrieve access token
		  $AccessCodeExpired = Check-if-Access-Token-Expired
		if ($AccessCodeExpired) {
			Write-Host "Access token expired. Requesting a new one..." -ForegroundColor Yellow
			# $Access_Token = Refresh-Access-Token
			$Access_Token = Refresh-Access-Token-Client-Credentials
		} else {
			$temp_query = "SELECT access_token FROM Auth"
			$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
			$Access_Token = $result[0].access_token
		}
########################################################
		$URL = "https://www.deviantart.com/api/v1/oauth2/user/profile/$($Username)?ext_collections=1&ext_galleries=1&access_token=$Access_Token"
		$URLConsole = "https://www.deviantart.com/api/v1/oauth2/user/profile/$($Username)?ext_collections=1&ext_galleries=1&access_token=access_token_here"
		Write-Host "`nURL: $URLConsole" -ForegroundColor Yellow
		
		Write-Host "Fetching username $username metadata..." -ForegroundColor Yellow
		$retryCount = 0
		while ($retryCount -lt $maxRetries) {
			try {
				# Make the API request and process the JSON response
				$Response = Invoke-RestMethod -Uri $URL -Method Get
				# $Response
########################################################
				if ($Response.StatusCode -in 400, 404) {
					Write-Output "User $username not found (400/404 error)" -ForegroundColor Red
					$ContinueFetching = $false
					break
################################## too many requests, try again
				} elseif ($Response.StatusCode -in 429, 500) {
					$delay = Calculate-Delay -retryCount $retryCount
					
					$retryCount++
					
					Write-Host "error 429/500 encountered. Retrying in $delay milliseconds..." -ForegroundColor Yellow
					Start-Sleep -Milliseconds $delay
########################################################
				} elseif ($Response -and $Response.user.username) {
					Write-Host "User found" -ForegroundColor Green
					
					$UserID = $Response.user.userid
					$Country = $Response.country
					#fix backtick issues
					$Country = $Country -replace "'", ""
					$User_Deviations = $Response.stats.user_deviations
					
					$username_url = "https://www.deviantart.com/$($Username)/gallery/all"
					
					$temp_query = "INSERT INTO Users (username, userID, url, country, total_user_deviations)
												VALUES ('$Username', '$UserID', '$username_url', '$Country', '$User_Deviations')"
					
					# Write-Host "`ntemp_query is $temp_query"
					Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
                    
					Write-Host "New user $Username added to database." -ForegroundColor Green
					break
				}
########################################################
			} catch {
				if ($Response.error_code -in 0, 1, 2) {
					Write-Host "User $username not found. Skipping..." -ForegroundColor Red
					$ContinueFetching = $false
					break
########################################################
				} elseif ($Response.error -eq "invalid_request") {
					Write-Host "Invalid request: $($Response.error_description)" -ForegroundColor Red
					$ContinueFetching = $false
					break
########################################################
				} else {
					Write-Host "(Download-Metadata-From-User 1) An unexpected error occurred: $($Response.error_description)" -ForegroundColor Red
					$ContinueFetching = $false
					break
				}
########################################################
			}
########################################################
		}
########################################################
	} else {
		Write-Host "`nFound user $Username in database." -ForegroundColor Green
################## Check and retrieve access token
		  $AccessCodeExpired = Check-if-Access-Token-Expired
		if ($AccessCodeExpired) {
			Write-Host "Access token expired. Requesting a new one..." -ForegroundColor Yellow
			# $Access_Token = Refresh-Access-Token
			$Access_Token = Refresh-Access-Token-Client-Credentials
		} else {
			$temp_query = "SELECT access_token FROM Auth"
			$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
			$Access_Token = $result[0].access_token
		}
########################################################
		#load last_time_fetched_metadata and start search from there
		$temp_query = "SELECT last_time_fetched_metadata FROM Users WHERE username = '$Username'"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
########################################################
		# Check the result
		if ($result.Count -gt 0) {
			if (-not [string]::IsNullOrWhiteSpace($result[0].last_time_fetched_metadata)) {
				$DateLastDownloaded = $result[0].last_time_fetched_metadata
########################################################
				# Ensure both dates are DateTime objects
				$CurrentDate = [datetime]::ParseExact((Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "yyyy-MM-dd HH:mm:ss", $null)
				$DateLastDownloaded = [datetime]::ParseExact($DateLastDownloaded, "yyyy-MM-dd HH:mm:ss", $null)

				$TimeDifference = $CurrentDate - $DateLastDownloaded
				$SecondsDifference = $TimeDifference.TotalSeconds
	
########################################################
				if ($SecondsDifference -lt $TimeToCheckAgainMetadata) {
					$ContinueFetching = $false
					Write-Host "This user was updated less than $TimeToCheckAgainMetadata seconds ago. Skipping..." -ForegroundColor Yellow
########################################################
				}	else {
					$URL = "https://www.deviantart.com/api/v1/oauth2/user/profile/$($Username)?ext_collections=1&ext_galleries=1&access_token=$Access_Token"
					# Make the API request and process the JSON response
					
					try {
						$Response = Invoke-RestMethod -Uri $URL -Method Get
						
						if ($Response.StatusCode -in 400, 404) {
							Write-Output "User $username not found (400/404 error)" -ForegroundColor Red
							$ContinueFetching = $false
							# break
######################################################## too many requests, try again
						} elseif ($Response.StatusCode -in 429, 500) {
							$delay = Calculate-Delay -retryCount $retryCount
							
							$retryCount++
							
							Write-Host "error 429/500 encountered. Retrying in $delay milliseconds..." -ForegroundColor Yellow
							Start-Sleep -Milliseconds $delay
						} else {
							Write-Host "Found user in DeviantArt`s database." -ForegroundColor Yellow
							$User_Deviations = $Response.stats.user_deviations
							#update total_user_deviations to current count
							$temp_query = "UPDATE Users SET total_user_deviations = '$User_Deviations' WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
########################################################
							#update the last_time_fetched_metadata column to NULL
							# $temp_query = "UPDATE Users SET last_time_fetched_metadata = NULL WHERE username = '$Username'"
							# Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
########################################################
						}
########################################################
					} catch {
						Write-Host "(Download-Metadata-From-User 2) An unexpected error occurred: $($_.Exception.Message)" -ForegroundColor Red
						$ContinueFetching = $false
					}
########################################################
				}
########################################################
			}
			#load cur_offset and start search from there, regardless of stats of last_time_fetched_metadata
			$temp_query = "SELECT cur_offset FROM Users WHERE username = '$Username'"
			$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
			
			# Write-Output "(Line 562) Raw result: $($result | Out-String)"
			# Check the result
			if ($result.Count -gt 0) {
				if ($result[0].cur_offset -gt 0) {
					$Cur_Offset = $result[0].cur_offset
					Write-Host "Starting from offset $Cur_Offset." -ForegroundColor Green
				} else {
					$Cur_Offset = 0
				}
			}
########################################################
		}
########################################################
	}
########################################################
	$CurrentSkips = 0
	if ($ContinueFetching) {
		$HasMoreFiles = $true
########################################################
		# Loop through pages of images for the user
		while ($HasMoreFiles) {
			$retryCount = 0
			while ($retryCount -lt $maxRetries) {
				if ($Cur_Offset -gt 0) {
					Write-Host "`nFetching metadata for offset $Cur_Offset for user $Username..." -ForegroundColor Yellow
				} else {
					Write-Host "`nFetching metadata for user $Username..." -ForegroundColor Yellow
				}
########################################################
				try {
					$AccessCodeExpired = Check-if-Access-Token-Expired
					if ($AccessCodeExpired) {
						Write-Host "Access token expired. Requesting a new one..." -ForegroundColor Red
						# $Access_Token = Refresh-Access-Token
						$Access_Token = Refresh-Access-Token-Client-Credentials
					}
					# $headers = @{
						# Authorization = "Bearer $Access_Token"
					# }
					# Write-Host "Access_Token: $Access_Token"
					# $Access_Token = "5c3ce678136a4fdb86afbff500771e8d2348e03bf53bfe3625"
					
					$URLConsole = "https://www.deviantart.com/api/v1/oauth2/gallery/all?username=$($Username)&offset=$($Cur_Offset)&limit=$($Limit)&mature_content=$($AllowMatureContent)&access_token=access_token_here"
					Write-Host "`nURL: $URLConsole" -ForegroundColor Yellow
					
					$URL = "https://www.deviantart.com/api/v1/oauth2/gallery/all?username=$($Username)&offset=$($Cur_Offset)&limit=$($Limit)&mature_content=$($AllowMatureContent)&access_token=$Access_Token"
					# $Response = Invoke-RestMethod -Uri $URL -Method Get -Headers $headers
					$Response = Invoke-RestMethod -Uri $URL -Method Get
					# $response
########################################################
					# Check if there are any files returned in the response
					if ($Response.results -and $Response.results.Count -gt 0) {
						Write-Host "Number of results found: $($Response.results.Count)" -ForegroundColor Green
########################################################
						#files
						$stopwatchCursor = [System.Diagnostics.Stopwatch]::StartNew()
						$sqlScript = "BEGIN TRANSACTION; " 
						foreach ($File in $Response.results) {
							$DeviationID = $File.deviationid
							$FileTitle = $File.title
######################################################## Skip locked content
							$Continue = $false
							#tiers
							#object exists in json response
							if ($File.PSObject.Properties['tier_access']) {
								$TierAcess = $File.tier_access
								#locked, skip
								if ($TierAcess = "locked") {
									$Continue = $false
									Write-Host "File $DeviationID ($FileTitle) belongs to a tier that is locked from your account. Skipping..." -ForegroundColor Yellow
								} else {
								#not locked
									$Continue = $true
								}
							} else {
								$Continue = $true
							}
########################################################
							if ($Continue) {
								#premium folders
								if ($File.PSObject.Properties['premium_folder_data']) {
									$PremiumAccess = $File.premium_folder_data.has_access
									#no access, skip
									if ($PremiumAccess = "false") {
										$Continue = $false
										Write-Host "File $DeviationID ($FileTitle) belongs to a premium folder that is locked from your account. Skipping..." -ForegroundColor Yellow
									} else {
									#not locked
										$Continue = $true
									}
								} else {
									$Continue = $true
								}
########################################################
								if ($Continue) {
######################################################## Filter
									$Continue = $false
									# check title
									$result = Check-WordFilter -Content $FileTitle -WordFilter $WordFilter -WordFilterExclude $WordFilterExclude
									# title passed the filter
									if ($result) {
										$Continue = $true
									} else {
										Write-Host "File $DeviationID ($FileTitle) failed the title word filter." -ForegroundColor Yellow
									}
########################################################
									if ($Continue) {
										$temp_query = "SELECT EXISTS(SELECT 1 from Files WHERE deviationid = '$DeviationID');"
										$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
										
										# Extract the value from the result object
										$exists = $result."EXISTS(SELECT 1 from Files WHERE deviationid = '$DeviationID')"
				
										if ($exists -eq 1) {
											Write-Host "File $DeviationID ($FileTitle) already exists in database, skipping..." -ForegroundColor Yellow
											$CurrentSkips++
											
											if ($MaxSkipsBeforeAborting -gt 0) {
												if ($CurrentSkips -gt $MaxSkipsBeforeAborting) {
													Write-Host "Reached maximum amount of skipped items. Skipping user $Username" -ForegroundColor Yellow
													$HasMoreFiles = $false
													# $CurrentSkips = 0
													break
												}
											}
########################################################
										} else {
											$FileUrlRaw = $File.url
											# "https://www.deviantart.com/$($Username)/art/$($URL)"
											$FileUrl = $FileUrlRaw -replace "https://www.deviantart.com/$($Username)/art/", ''
											
											$FileHeight = $File.content.height
											$FileWidth = $File.content.width
											$FileUsername = $File.author.username
											
											#fix backtick issues
											$FileTitle = $FileTitle -replace "'", "''"
											
											$FilePublishedTimeRaw = $File.published_time     #Unix time
											# Convert to DateTime
											$FilePublishedTime = [System.DateTime]::UnixEpoch.AddSeconds($FilePublishedTimeRaw).ToString("yyyy-MM-dd HH:mm:ss")
											
											# Write-Output "`nFileSrcURLRaw: $FileSrcURLRaw"
########################################################
											#process images and videos differently
											#images
											if ($File.PSObject.Properties['content']) {
												# Write-Output "Found image"
												$FileSrcURLRaw = $File.content.src
												#remove this to save some database space
												$FileSrcURL = $FileSrcURLRaw -replace "https://images-wixmp-", ""
												
######################################################## Things from this point foward improve image quality
												$FileSrcURL = $FileSrcURL -replace ",q_\d{1,3}", ",q_100"	#any number between 1 and 3 digits is replaced with q_100
												
												#This will replace lower quality jpg/jpeg with png if available
												# Extract first and last file types using regex
												$firstFileType = [regex]::Match($FileSrcURL, "\.(bmp|png|jpg|jpeg|webp|avif|gif)").Value
												$lastFileType = [regex]::Match($FileSrcURL, "\.(bmp|png|jpg|jpeg|webp|avif|gif)(?=\?|$)").Value
												
												$FileExtension = $firstFileType
												# Check if they are different
												if ($firstFileType -ne $lastFileType) {
													# Replace the last file type with the first
													$FileSrcURL = $FileSrcURL -replace [regex]::Escape($lastFileType), $firstFileType
													# Write-Host "Updated string: $FileSrcURL" -ForegroundColor Green
												}
######################################################## Image quality improvements end
												$temp_query = "INSERT INTO Files (deviationID, url, src_url, extension, height, width, title, username, published_time)
																			VALUES ('$DeviationID', '$FileUrl', '$FileSrcURL', '$FileExtension', '$FileHeight', '$FileWidth', '$FileTitle', '$FileUsername', '$FilePublishedTime');"
				
												# Write-Host "`n$temp_query"
												$sqlScript += $temp_query + " "
												
												Write-Host "Added File $DeviationID ($FileTitle) ($FileExtension) to database." -ForegroundColor Green
################################################################################
											#videos
											} elseif ($File.PSObject.Properties['videos']) {
												# Write-Output "Found video"
												#get the highest quality video
												$highestResolutionVideo = $File.videos | Sort-Object { [int]($_.quality -replace 'p', '') } -Descending | Select-Object -First 1
												
												if ($highestResolutionVideo) {
													$VideoSrcURL = $highestResolutionVideo.src
													switch ($highestResolutionVideo.quality) {
														"2160p" {
															$FileWidth = ""
															$FileHeight = "2160"
														}
														"1440p" {
															$FileWidth = ""
															$FileHeight = "1440"
														}
														"1080p" {
															$FileWidth = ""
															$FileHeight = "1080"
														}
														"720p" {
															$FileWidth = ""
															$FileHeight = "720"
														}
														"480p" {
															$FileWidth = ""
															$FileHeight = "480"
														}
														"360p" {
															$FileWidth = ""
															$FileHeight = "360"
														}
														"240p" {
															$FileWidth = ""
															$FileHeight = "240"
														}
														"144p" {
															$FileWidth = ""
															$FileHeight = "144"
														}
													}
												}
												
												# Output the highest resolution video information
												# Write-Output "Video URL: $VideoSrcURL"
												# Write-Output "Resolution: $FileWidth x $FileHeight"
												
												#remove this to save some database space
												$VideoSrcURL = $VideoSrcURL -replace "https://wixmp-", ""
												
												if ($VideoSrcURL -match "\.\w+$") {
													# $FileExtension = $matches[0].TrimStart('.') #this removes the dot
													$FileExtension = $matches[0]
													# Write-Output "File Extension: $FileExtension"
												} else {
													Write-Output "No file extension found in $VideoSrcURL"
													$FileExtension = ".mp4"
												}
												
												$temp_query = "INSERT INTO Files (deviationID, url, src_url, extension, height, width, title, username, published_time)
																			VALUES ('$DeviationID', '$FileUrl', '$VideoSrcURL', '$FileExtension', '$FileHeight', '$FileWidth', '$FileTitle', '$FileUsername', '$FilePublishedTime');"
				
												# Write-Host "`n$temp_query"
												$sqlScript += $temp_query + " "
												Write-Host "Added File $DeviationID ($FileTitle) ($FileExtension) to database." -ForegroundColor Green
											}
				
										}
########################################################
									}
########################################################
								}
							}
########################################################
						}
########################################################
						# End the transaction
						$sqlScript += "COMMIT;"  
						#execute all queries at once
						# Write-Host "`nExecuting queries..."
						# Write-Host "`n sqlScript query from line 443 is $sqlScript"
						Invoke-SqliteQuery -DataSource $DBFilePath -Query $sqlScript
########################################################
						$stopwatchCursor.Stop()
						if ($Cur_Offset -gt 0) {
							Write-Host "Fetched metadata for offset $Cur_Offset for user $Username in $($stopwatchCursor.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
						} else {
							Write-Host "Fetched metadata for user $Username in $($stopwatchCursor.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
						}
						
						#fixed fetching more pages when the skip limit is reached
						#this happened because the break only stopped the foreach loop
						if ($HasMoreFiles) {
							if ($Response.has_more -eq $true) {
								$Cur_Offset = $Response.next_offset
								
								#update the page_offset column so that next time the query is run it starts from the begginning
								$temp_query = "UPDATE Users SET Cur_Offset = '$Cur_Offset' WHERE username = '$Username'"
								Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								
								Start-Sleep -Milliseconds $TimeToWait  # Waits for X seconds
########################################################
							}	else {
								Write-Host "No more files found for user $UserName" -ForegroundColor Yellow
								
								#update the Cur_Offset column so that next time the script is run it starts from the beginning
								$temp_query = "UPDATE Users SET Cur_Offset = 0 WHERE username = '$Username'"
								# Write-Host "`ntemp_query for line 399: $temp_query"
								Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								
								$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
								#update the last_time_fetched_metadata column
								$temp_query = "UPDATE Users SET last_time_fetched_metadata = '$CurrentDate' WHERE username = '$Username'"
								Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								
								# deviations_in_database INTEGER DEFAULT 0,
								# locked_deviations INTEGER DEFAULT 0,
								# total_user_deviations INTEGER DEFAULT 0,
								#update the deviations_in_database based upon the amount of files
								$temp_query = "SELECT COUNT(*) FROM Files WHERE UPPER(username) = UPPER('$Username')"
								$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								
								# Write-Output "Raw result: $($result | Out-String)"
								$Count = [int]$result[0].'COUNT(*)'
								# Write-Host "Total files count: $Count" -ForegroundColor Yellow
								$temp_query = "UPDATE Users SET deviations_in_database = '$Count' WHERE username = '$Username'"
								Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								
								#set locked deviations
								$temp_query = "SELECT total_user_deviations FROM Users WHERE username = '$Username'"
								$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
								$User_Deviations = $result[0].total_user_deviations
								# Write-Host "User_Deviations: $User_Deviations" -ForegroundColor Yellow
								$LockedCount = $User_Deviations - $Count
								$temp_query = "UPDATE Users SET locked_deviations = '$LockedCount' WHERE username = '$Username'"
								Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								
								Start-Sleep -Milliseconds $TimeToWait  # Waits for X seconds
								
								$HasMoreFiles = $false
								break       #stop fetching more data
							}
########################################################
						#handle errors like skip limit reached
						} else {
							#update the Cur_Offset column so that next time the script is run it starts from the beginning
							$temp_query = "UPDATE Users SET Cur_Offset = 0 WHERE username = '$Username'"
							# Write-Host "`ntemp_query for line 399: $temp_query"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							
							$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
							#update the last_time_fetched_metadata column
							$temp_query = "UPDATE Users SET last_time_fetched_metadata = '$CurrentDate' WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							
							# deviations_in_database INTEGER DEFAULT 0,
							# locked_deviations INTEGER DEFAULT 0,
							# total_user_deviations INTEGER DEFAULT 0,
							#update the deviations_in_database based upon the amount of files
							$temp_query = "SELECT COUNT(*) FROM Files WHERE UPPER(username) = UPPER('$Username')"
							$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							
							# Write-Output "Raw result: $($result | Out-String)"
							$Count = [int]$result[0].'COUNT(*)'
							# Write-Host "Total files count: $Count" -ForegroundColor Yellow
							$temp_query = "UPDATE Users SET deviations_in_database = '$Count' WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							
							#set locked deviations
							$temp_query = "SELECT total_user_deviations FROM Users WHERE username = '$Username'"
							$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
							$User_Deviations = $result[0].total_user_deviations
							# Write-Host "User_Deviations: $User_Deviations" -ForegroundColor Yellow
							$LockedCount = $User_Deviations - $Count
							$temp_query = "UPDATE Users SET locked_deviations = '$LockedCount' WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							
							$HasMoreFiles = $false
							break       #stop fetching more data
						}
########################################################
					#this is to account for empty responses
					} else {
						Write-Host "No items found in response. Skipping user $UserName..." -ForegroundColor Red
						$HasMoreFiles = $false
						break
					}
########################################################
				} catch {
					if ($_.Exception.Response.StatusCode -in 429, 500) {
						$delay = Calculate-Delay -retryCount $retryCount
						
						$retryCount++
						
						Write-Host "error 429/500 encountered. Retrying in $delay milliseconds..." -ForegroundColor Red
						
						#increase this by X seconds each time
						$TimeToWait = $TimeToWait + 500
						Write-Host "Time to wait between requests increased to $TimeToWait." -ForegroundColor Yellow
						
						Start-Sleep -Milliseconds $delay
########################################################
					# 401 = Unauthorized
					} elseif ($_.Exception.Response.StatusCode -eq 401) {
						Write-Host "Access token invalid. Requesting a new one..." -ForegroundColor Yellow
						# $Access_Token = Refresh-Access-Token
						$Access_Token = Refresh-Access-Token-Client-Credentials
						Write-Host "Refreshed access token. Retrying..." -ForegroundColor Yellow
						Start-Sleep -Milliseconds $TimeToWait
						# $HasMoreFiles = $false
						# break
########################################################
					} else {
						Write-Host "An unexpected error occurred: $($_.Exception.Message)" -ForegroundColor Red
						$HasMoreFiles = $false
						break
					}
########################################################
				}
########################################################
			}
########################################################
		}
########################################################
	}
########################################################
}
########################################################


############################################
#create database file if it doesn`t exist
if (-not (Test-Path $DBFilePath)) {
	$createTableQuery = "CREATE TABLE Auth (
		access_token TEXT,
		access_token_creation_date TEXT,
		refresh_token TEXT,
		refresh_token_creation_date TEXT
		);"
	Invoke-SQLiteQuery -Database $DBFilePath -Query $createTableQuery
	
	$createTableQuery = "CREATE TABLE Users (
		username TEXT PRIMARY KEY,
		userID TEXT,
		url TEXT,
		country TEXT,
		deviations_in_database INTEGER DEFAULT 0,
		locked_deviations INTEGER DEFAULT 0,
		total_user_deviations INTEGER DEFAULT 0,
		last_time_fetched_metadata TEXT,
		last_time_downloaded TEXT,
		cur_offset INTEGER DEFAULT 0
		);"
	Invoke-SQLiteQuery -Database $DBFilePath -Query $createTableQuery
	
	$createTableQuery = "CREATE TABLE Files (
		deviationID TEXT PRIMARY KEY,
		url TEXT,
		src_url TEXT,
		extension TEXT,
		width INTEGER,
		height INTEGER,
		title TEXT,
		username TEXT,
		published_time TEXT,
		downloaded INTEGER DEFAULT 0 CHECK (downloaded IN (0,1)),
		favorite INTEGER DEFAULT 0 CHECK (downloaded IN (0,1)),
		deleted INTEGER DEFAULT 0 CHECK (downloaded IN (0,1))
		);"
	Invoke-SQLiteQuery -Database $DBFilePath -Query $createTableQuery
}
############################################


############################################
function Process-Users {
	# Loop through the user list and download files
	foreach ($User in $UserList) {
		$Username = $User[0]
		$WordFilter = $User[1]
		$WordFilterExclude = $User[2]
		
		Download-Metadata-From-User -Username $Username -WordFilter $WordFilter -WordFilterExclude $WordFilterExclude
		
		# Start-Sleep -Milliseconds $TimeToWait
	}
	
	Download-Files-From-Database -Type 1
	
}
############################################
####################################
####################################
$RefreshTokenExpired = Check-if-Refresh-Token-Expired
#expired
if ($RefreshTokenExpired) {
	$Access_Token = Get-Tokens-From-Authorization-Code
}

function Graphical-Options {
    param (
        [string]$Query = ""
    )
	try {
		# Start logging
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/DeviantArt_$($CurrentDate).log" -Append
		$exitScript = $false
############################################
		while (-not $exitScript) {
			Write-Host "`nDeviantArt Powershell Downloader" -ForegroundColor Green
			Write-Host "`nSelect a option:" -ForegroundColor Green
			Write-Host "1. Download metadata from creators to database and then download files." -ForegroundColor Green
			Write-Host "2. Download only metadata from creators to database." -ForegroundColor Green
			Write-Host "3. Download all files in database not already downloaded (skip metadata download)." -ForegroundColor Green
			Write-Host "4. Download files in database from query." -ForegroundColor Green
			Write-Host "5. Scan folder for files and add them to database marked as favorites." -ForegroundColor Green
			Write-Host "6. Exit script" -ForegroundColor Green
			
			$choice = $(Write-Host "`nType a number (1-7):" -ForegroundColor green -NoNewLine; Read-Host) 
############################################
			if ($choice -eq 1) {
				Backup-Database
				
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Process-Users
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all metadata from users in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -Type 1
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				[console]::beep()
############################################
			} elseif ($choice -eq 2){
				Backup-Database
				
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Process-Users
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all metadata from users in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				[console]::beep()
############################################
			} elseif ($choice -eq 3){
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -Type 1
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				[console]::beep()
##########################################
			} elseif ($choice -eq 4){
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -Type 2 -Query $Query
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded files from query in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				[console]::beep()
############################################
			} elseif ($choice -eq 5){
				Backup-Database
				Scan-Folder-And-Add-Files-As-Favorites -Type 4
				[console]::beep()
############################################
			} elseif ($choice -eq 6){
				$exitScript = $true
############################################
			} else {
				Write-Host "`nInvalid choice. Try again." -ForegroundColor Red
			}
############################################
		}
############################################
	} catch {
		Write-Error "An error occurred (line $($_.InvocationInfo.ScriptLineNumber)): $($_.Exception.Message)"
	} finally {
		Stop-Transcript
		# Write-Output "Transcript stopped"
	}
}
############################################
function Execute-Function {
    param (
        [int]$function,
        [string]$Query = ""
    )
	
	try {
		# Start logging
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/DeviantArt_$($CurrentDate).log" -Append
############################################
		if ($function -eq 1) {
			Backup-Database
			
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Process-Users
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded all metadata from users in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Download-Files-From-Database -Type 1
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			[console]::beep()
##########################################
		} elseif ($function -eq 2){
			Backup-Database
			
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Process-Users
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded all metadata from users in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			[console]::beep()
##########################################
		} elseif ($function -eq 3){
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Download-Files-From-Database -Type 1
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			[console]::beep()
##########################################
		} elseif ($function -eq 4){
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Download-Files-From-Database -Type 2 -Query $Query
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded files from query in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			[console]::beep()
##########################################
		} elseif ($function -eq 5){
			Backup-Database
			Scan-Folder-And-Add-Files-As-Favorites -Type 4
			[console]::beep()
##########################################
		} else {
			Write-Host "`nInvalid choice." -ForegroundColor Red
		}
##########################################
	} catch {
		Write-Error "An error occurred (line $($_.InvocationInfo.ScriptLineNumber)): $($_.Exception.Message)"
	} finally {
		Stop-Transcript
		# Write-Output "Transcript stopped"
	}
}
############################################

