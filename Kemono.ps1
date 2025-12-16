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
	
	# Define the invalid characters for Windows file names
	$invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''
				
	if ($Type -eq 1) {
		Write-Host "`nStarting download of files..." -ForegroundColor Yellow
		
		#same query for all
		$temp_query = "SELECT creatorID, name, service FROM Creators;"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
#########################################
		if ($result.Count -gt 0) {
			Write-Host "`nFound $($result.Count) creators." -ForegroundColor Green
			Backup-Database
#########################################
			foreach ($Creator in $result) {
				$CreatorID = $Creator.creatorID
				$CreatorName = $Creator.creatorName
				$CreatorService = $Creator.service
				
				$ContinueFetching = $true
				#load last_time_downloaded and start search from there
				$temp_query = "SELECT last_time_downloaded FROM Creators WHERE creatorID = '$CreatorID'"
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
							$temp_query = "UPDATE Creators SET last_time_downloaded = NULL WHERE creatorID = '$CreatorID'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
#########################################
						}
#########################################
					}
				}
#########################################
				if ($ContinueFetching) {
					$temp_query = "SELECT postID, title, content, date_published, total_files FROM Posts WHERE creatorName = '$CreatorName' AND downloaded = 0 AND deleted = 0;"
					
					$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
#########################################
					if ($result.Count -gt 0) {
						$FileList = @()
						$FilesRemaining = $result.Count
						Write-Host "`nFound $($result.Count) posts for creator $CreatorName." -ForegroundColor Green
						foreach ($Post in $result) {
							$PostID = $Post.postID
							$PostTitle = $Post.title
							$PostContent = $Post.content
							# $PostDatePublished = $Post.date_published
							
######################################### Check if is null or empty
							if ($Post.date_published) 
							{ 
								$PostDatePublished = $Post.date_published 
								$PostDatePublishedFormatted = [datetime]::ParseExact($PostDatePublished, "yyyy-MM-dd HH:mm:ss", $null).ToString("yyyy-MM-dd HH-mm-ss")
								$PostDatePublishedFormattedShort = [datetime]::ParseExact($PostDatePublished, "yyyy-MM-dd HH:mm:ss", $null).ToString("yyyy-MM-dd")
							} else { 
								$PostDatePublishedFormatted = "Unknown" 
								$PostDatePublishedFormattedShort = "Unknown" 
							}
#########################################
							$PostTotalFiles = $Post.total_files
							
							# Replace invalid characters with an empty string
							$PostTitleFilename = $PostTitle -replace "[$invalidChars]", ''
							
							$temp_query = "SELECT postID, hash, hash_extension, filename, filename_extension, url, file_index, creatorID, creatorName FROM Files WHERE postID = '$PostID' AND downloaded = 0;"
					
							$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
#########################################
							if ($result.Count -gt 0) {
								Start-Download -SiteName "Kemono" -FileList $result -PostContent $PostContent -PostContent $PostContent
#########################################
							} else {
								Write-Host "Found 0 posts that meet the query requirements for creatorName $CreatorName. Skipping..." -ForegroundColor Red
								
								$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
								#update the last_time_downloaded column
								$temp_query = "UPDATE Creators SET last_time_downloaded = '$CurrentDate' WHERE creatorID = '$creatorID'"
								Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							}
#########################################
						}
						$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
						#update the last_time_downloaded column
						$temp_query = "UPDATE Creators SET last_time_downloaded = '$CurrentDate' WHERE creatorID = '$creatorID'"
						Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
#########################################
					}
#########################################
				}
#########################################
			}
#########################################
		} else {
			Write-Host "`nFound 0 users in database. Terminating..." -ForegroundColor Red
		}
#########################################
	} elseif ($Type -eq 2) {
        if (-not [string]::IsNullOrEmpty($Query)) {
            $WhereQuery = $Query
            Write-Host "`nUsing provided query: '$WhereQuery'" -ForegroundColor Blue
        } else {
            $WhereQuery = $(Write-Host "`nEnter WHERE query:" -ForegroundColor cyan -NoNewLine; Read-Host)
        }
		
		$temp_query = "SELECT postID, creatorName, hash, hash_extension, filename, filename_extension, url, file_index  FROM Files $WhereQuery;"

		# Write-Host "temp_query: $temp_query" -ForegroundColor Yellow
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
######################################
		if ($result.Count -gt 0) {
			Start-Download -SiteName "Kemono" -FileList $result
######################################
		} else {
			Write-Host "Found 0 files that meet the query conditions." -ForegroundColor Red
		}
	}
#########################################
}
########################################################



########################################################
# Function to download metadata
function Download-Metadata-From-Creator {
    param (
        [string]$CreatorName,
        [string]$CreatorID,
        [string]$Service,
        [string]$WordFilter,
        [string]$WordFilterExclude,
        [string]$Files_To_Exclude
    )
	
	# Set initial parameters for paging
	$Cur_Offset = 0
	
	$FormatList = $Files_To_Exclude -split ', '
	
	$HasMoreFiles = $true
	Write-Host "`n`nFetching metadata for creator $CreatorName..." -ForegroundColor Yellow
	
	#fix name
	$CreatorName = $CreatorName -replace "'", ""
######### Add creator if it doesn`t exist
	$temp_query = "SELECT EXISTS(SELECT 1 from Creators WHERE creatorID = '$CreatorID' AND service = '$Service');"
	$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
	
	# Extract the value from the result object
	$exists = $result."EXISTS(SELECT 1 from Creators WHERE creatorID = '$CreatorID' AND service = '$Service')"

	# Check the result
	if ($exists -eq 0) {
########################################################
		# "id": "IDHere",
		# "name": "NameHere",
		# "service": "patreon",
		# "indexed": "2023-06-23T06:09:18.245549",
		# "updated": "2024-08-27T17:32:11.991433",
		# "public_id": "NameHere",
		# "relation_id": nul		
		# {https://kemono.su/api/v1/service/user/usedID/profile
		$URL = "$($BaseURL)/$Service/user/$($CreatorID)/profile"
		# Write-Host "URL: $URL"
		
		# Write-Host "Fetching creator $CreatorName metadata..."
		# Make the API request and process the JSON response
		# $Response = Invoke-RestMethod -Uri $URL -Method Get
		$Response = Invoke-WebRequest -Uri $URL -Method Get -Headers @{"Accept" = "text/css"}
		$Response = $Response.Content | ConvertFrom-Json
########################################################
		# Check if there are any files returned in the response
		if ($Response -and $Response.Count -gt 0) {
			foreach ($Creator in $Response) {
				$DateIndexed = $Creator.indexed
				$DateUpdated = $Creator.updated
				
				$DateIndexed = $DateIndexed -replace 'T', ' ' -replace '\.\d+', ''
				$DateUpdated = $DateUpdated -replace 'T', ' ' -replace '\.\d+', ''
				
				# Write-Host "DateIndexed: $DateIndexed"
				# Write-Host "DateUpdated: $DateUpdated"
				
				$DateIndexedFormatted = [datetime]::ParseExact($DateIndexed, "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss")
				$DateUpdatedFormatted = [datetime]::ParseExact($DateUpdated, "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss")
			}
		}
########################################################
		# $CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
		$temp_query = "INSERT INTO Creators (creatorID, creatorName, service, date_indexed, date_updated)
									VALUES ('$CreatorID', '$CreatorName', '$Service', '$DateIndexedFormatted',  '$DateUpdatedFormatted')"
		Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
        
		Write-Host "New creator $CreatorName added to database." -ForegroundColor Green
########################################################
	} else {
		Write-Host "found creator $CreatorName in database." -ForegroundColor Green
		#load last_time_fetched_metadata
		$temp_query = "SELECT last_time_fetched_metadata FROM Creators WHERE creatorID = '$CreatorID' AND service = '$Service'"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
		
		# Check the result
		if ($result.Count -gt 0) {
			if (-not [string]::IsNullOrWhiteSpace($result[0].last_time_fetched_metadata)) {
				$DateMetadataFetchCompleted = $result[0].last_time_fetched_metadata
				$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
########################################################
				# Ensure both dates are DateTime objects
				$CurrentDate = [datetime]::ParseExact((Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "yyyy-MM-dd HH:mm:ss", $null)
				$DateMetadataFetchCompleted = [datetime]::ParseExact($DateMetadataFetchCompleted, "yyyy-MM-dd HH:mm:ss", $null)
		
				$TimeDifference = $CurrentDate - $DateMetadataFetchCompleted
				$SecondsDifference = $TimeDifference.TotalSeconds
########################################################
				if ($SecondsDifference -lt $TimeToCheckAgainMetadata) {
					$HasMoreFiles = $false
					Write-Host "This user was updated less than $TimeToCheckAgainMetadata seconds ago. Skipping..." -ForegroundColor Yellow
########################################################
				} else {
					$URL = "$($BaseURL)/$Service/user/$($CreatorID)/profile"
					
					$Response = Invoke-WebRequest -Uri $URL -Method Get -Headers @{"Accept" = "text/css"}
					$Response = $Response.Content | ConvertFrom-Json
########################################################
					# Check if there are any files returned in the response
					if ($Response -and $Response.Count -gt 0) {
						foreach ($Creator in $Response) {
							$DateIndexed = $Creator.indexed
							$DateUpdated = $Creator.updated
							
							$DateIndexed = $DateIndexed -replace 'T', ' ' -replace '\.\d+', ''
							$DateUpdated = $DateUpdated -replace 'T', ' ' -replace '\.\d+', ''
							
							# Write-Host "DateIndexed: $DateIndexed"
							# Write-Host "DateUpdated: $DateUpdated"
							
							$DateIndexedFormatted = [datetime]::ParseExact($DateIndexed, "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss")
							$DateUpdatedFormatted = [datetime]::ParseExact($DateUpdated, "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss")
						}
########################################################
						#if time that this user was last fetched is higher than the actual update time from kemono, skip it
						if ($DateMetadataFetchCompleted -gt $DateUpdatedFormatted) {
							$HasMoreFiles = $false
							Write-Host "This user didn't receive any updates since last fetched. Skipping..." -ForegroundColor Yellow
						}
					}
########################################################
				}
########################################################
			}
########################################################
			#load page_offset and start search from there, regardless of stats of last_time_fetched_metadata
			$temp_query = "SELECT page_offset FROM Creators WHERE creatorID = '$CreatorID' AND service = '$Service'"
			$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
			
			# Check the result
			if ($result.Count -gt 0) {
				if ($result[0].cur_offset -gt 0) {
					$Cur_Offset = $result[0].page_offset
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
########################################################
		$CurrentSkips = 0
########################################################
		# Loop through pages of files for the user
		while ($HasMoreFiles) {
			$retryCount = 0
			while ($retryCount -lt $maxRetries) {
				
				# https://kemono.su/api/v1/{service}/user/{creator_id}?o=int(in steps of 50)
				# $URL = "$($BaseURL)/$Service/user/$($CreatorID)?o=$Cur_Offset"
				$URL = "$($BaseURL)/$Service/user/$($CreatorID)/posts?o=$Cur_Offset"
				Write-Host "`nURL: $URL" -ForegroundColor Yellow
				
				if ($Cur_Offset -gt 0) {
					Write-Host "`nFetching metadata for offset $Cur_Offset for creator $CreatorName..." -ForegroundColor Green
				} else {
					Write-Host "`nFetching metadata for creator $CreatorName..." -ForegroundColor Green
				}
############################################
				try {
					# Make the API request and process the JSON response
					# $Response = Invoke-RestMethod -Uri $URL -Method Get -Headers @{"Accept" = "text/css"}
					$Response = Invoke-WebRequest -Uri $URL -Method Get -Headers @{"Accept" = "text/css"}
					$Response = $Response.Content | ConvertFrom-Json
############################################
					# Check if there are any files returned in the response
					if ($Response -and $Response.Count -gt 0) {
						Write-Host "Number of posts: $($Response.Count)" -ForegroundColor Green
						
############################################
						#posts
						foreach ($Post in $Response) {
							# id, filename_and_hash, extension, url, createdAt, artist_tag, downloaded favorite
							$PostID = $Post.id
							$PostTitle = $Post.title
							$PostContent = $Post.content
							
							$Continue = $false
							# check title
							$result = Check-WordFilter -Content $PostTitle -WordFilter $WordFilter -WordFilterExclude $WordFilterExclude
							# title passed the filter
							if ($result) {
								if ($FilterPostContent) {
									# check post content
									$result = Check-WordFilter -Content $PostContent -WordFilter $WordFilter -WordFilterExclude $WordFilterExclude
									if ($result) {
										$Continue = $true
										# Write-Host "post ID $PostID passed the content word filter."
									}
								} else {
									$Continue = $true
									# Write-Host "post ID $PostID passed the title word filter."
								}
							} else {
								Write-Host "`npost $PostTitle (ID $PostID) failed the title word filter." -ForegroundColor Yellow
							}

							if ($Continue) {
								$temp_query = "SELECT EXISTS(SELECT 1 from Posts WHERE postID = '$PostID');"
								$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								
								# Extract the value from the result object
								$exists = $result."EXISTS(SELECT 1 from Posts WHERE postID = '$PostID')"

								if ($exists -eq 1) {
									Write-Host "`n`nPost ID $PostID already exists in database, skipping..." -ForegroundColor Yellow
									$CurrentSkips++
									
									if ($MaxSkipsBeforeAborting -gt 0) {
										if ($CurrentSkips -gt $MaxSkipsBeforeAborting) {
											Write-Host "Reached maximum amount of skipped items. Skipping creator $CreatorName..." -ForegroundColor Yellow
											$HasMoreFiles = $false
											# $CurrentSkips = 0
											break
										}
									}
############################################
								} else {
									$stopwatchPost = [System.Diagnostics.Stopwatch]::StartNew() 
									Write-Host "`n`nAdding post $PostTitle ($PostID) to database..." -ForegroundColor Green
					 
									# $PostTitle = $PostTitle -replace "'", ""
									# $PostContent = $PostContent -replace "'", ""
									
									$PostTitle = $PostTitle -replace "'", "''"
									$PostContent = $PostContent -replace "'", "''"
									
									if ($PostContentSkip) 
									{
										$PostContent = ""
									}
									
									# $PostDateAdded = $Post.added
									# $PostDatePublished = $Post.published
									
									# Check if is null or empty
									if ($Post.added) 
									{ 
										$PostDateAdded = $Post.added 
										$PostDateAdded = $PostDateAdded -replace 'T', ' ' -replace '\.\d+', ''
										$PostDateAddedFormatted = [datetime]::ParseExact($PostDateAdded, "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss")
									} else { 
										$PostDateAddedFormatted = "" 
									}
									
									if ($Post.published) 
									{ 
										$PostDatePublished = $Post.published 
										$PostDatePublished = $PostDatePublished -replace 'T', ' ' -replace '\.\d+', ''
										$PostDatePublishedFormatted = [datetime]::ParseExact($PostDatePublished, "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss")
									} else { 
										$PostDatePublishedFormatted = "" 
									}

									# "added": "2024-08-27T17:26:54.105855",
									# "published": "2024-08-26T23:13:16",
									# "edited": "2024-08-26T23:13:16",
									
									#added below
									####$temp_query = "INSERT INTO Posts (postID, creatorName, title, content, date_published, date_added, downloaded) 
									####							VALUES ('$PostID', '$CreatorName', '$PostTitle', '$PostContent', '$PostDatePublishedFormatted', '$PostDateAddedFormatted', 0);"
									##### Write-Host "`n temp query from line 391 is $temp_query"
									####Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
########################################################################################
									#files
									$stopwatchFile = [System.Diagnostics.Stopwatch]::StartNew()
									$sqlScript = "BEGIN TRANSACTION; "
									$Cur_Index = 0 	#start index at 0
									#list to compare hashes to avoid duplicates
									$HashList = New-Object System.Collections.Generic.List[System.Object]
########################################################################################
									#process single file
									if ($Post.file -and $Post.file.name) {
										foreach ($File in $Post.file) {
											$Cur_Index++	#increment by 1 if file is unique
											Write-Host "Found header file."  -ForegroundColor Green
											# "file": {
												# "name": "namehere.png",
												# "path": "/c7/13/hashhere.png"
											# },
											$FilenameRaw = $File.name
											
											#this is for filenames that have dots before the extension
											$parts = [regex]::Match($FilenameRaw, "^(.*\S)\s*\.\s*([^.]+)$")
											$Filename = $parts.Groups[1].Value
											$FileExtension = $parts.Groups[2].Value

											#code to account for times where creator didn`t name the file correctly
											if ($FileExtension -eq "") {
												Write-Host "file extension for filename $Filename not found, using hash extension instead" -ForegroundColor Yellow
												$FileURLRaw = $File.path
												$HashWithExtension = Split-Path -Path $FileURLRaw -Leaf
												$FileHash, $FileExtension = $HashWithExtension -split '\.'
											}
########################################################################################
											# check file extension
											# Write-Host "Excluded file formats is $FormatList."
											# Write-Host "File extension is $FileExtension."
											if ($FormatList -notcontains $FileExtension) {
########################################################################################
												if ($HashList -notcontains $FileHash) {
													$HashList.Add($FileHash) | Out-Null
													#fix filename query errors
													$Filename = $Filename -replace "'", "''"
													
													$FileURLRaw = $File.path
													# filename can also be extracted with this
													$HashWithExtension = Split-Path -Path $FileURLRaw -Leaf
													# Split the filename and extension
													$FileHash, $HashExtension = $HashWithExtension -split '\.'
########################################################################################
													$temp_query = "SELECT exists(SELECT 1 FROM Files WHERE hash = '$FileHash');"
													$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
													
													# Extract the value from the result object
													$exists = $result."EXISTS(SELECT 1 from Files WHERE hash = '$FileHash')"
													
													if ($exists -eq 1) {
														Write-Host "File $Filename ($FileHash) already exists in database, skipping..." -ForegroundColor Yellow
													} else {
														# Write-Host "Adding file $Filename to database"
														
														$FileURL = Split-Path -Path $FileURLRaw -Parent
														# Write-Output $FileURL
										
														# hash	hash_extension	filename	url service postID	downloaded	favorite
														$temp_query = "INSERT INTO Files (hash, hash_extension, filename, filename_extension, url, file_index,  creatorName, postID, downloaded) 
																					VALUES ('$FileHash', '$HashExtension', '$Filename', '$FileExtension', '$FileURL', '$Cur_Index', '$CreatorName', '$PostID', 0);"
							
														Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
														# Write-Host "`n sqlScript query from line 429 is $sqlScript"
														Write-Host "Added file $Filename ($FileHash) to database."  -ForegroundColor Green
													}
########################################################################################
												}
########################################################################################
											} else {
												Write-Host "Skipped file $FilenameRaw." -ForegroundColor Yellow
											}
########################################################################################
										}
									}
########################################################################################
############################################ #process attachments
									if ($Post.attachments.Count -gt 0) {
										Write-Host "Number of files (attachments): $($Post.attachments.Count)" -ForegroundColor Green
										foreach ($File in $Post.attachments) {
											# {
												# "name": "Filename.rar",
												# "path": "/29/2d/hash.bin"
											# },
											$Cur_Index++		#increment by 1
											$FilenameRaw = $File.name
											
											#this is for filenames that have dots before the extension
											$parts = [regex]::Match($FilenameRaw, "^(.*\S)\s*\.\s*([^.]+)$")
											$Filename = $parts.Groups[1].Value
											$FileExtension = $parts.Groups[2].Value

											#code to account for times where creator didn`t name the file correctly
											if ($FileExtension -eq "") {
												Write-Host "file extension for filename $Filename not found, using hash extension instead" -ForegroundColor Yellow
												$FileURLRaw = $File.path
												$HashWithExtension = Split-Path -Path $FileURLRaw -Leaf
												$FileHash, $FileExtension = $HashWithExtension -split '\.'
											}
											
											# check file extension
											# Write-Host "Excluded file formats is $FormatList."
											# Write-Host "File extension is $FileExtension."
											if ($FormatList -notcontains $FileExtension) {
												#fix filename query errors
												$Filename = $Filename -replace "'", "''"
												
												$FileURLRaw = $File.path
												# filename can also be extracted with this
												$HashWithExtension = Split-Path -Path $FileURLRaw -Leaf
												# Split the filename and extension
												$FileHash, $HashExtension = $HashWithExtension -split '\.'
												
												if ($HashList -notcontains $FileHash) {
													$HashList.Add($FileHash)
													
													$temp_query = "SELECT exists(SELECT 1 FROM Files WHERE hash = '$FileHash');"
													$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
	
													# Extract the value from the result object
													$exists = $result."EXISTS(SELECT 1 from Files WHERE hash = '$FileHash')"
													
													if ($exists -eq 1) {
														Write-Host "File $Filename ($FileHash) already exists in database, skipping..." -ForegroundColor Yellow
													}	else {
														$FileURL = Split-Path -Path $FileURLRaw -Parent
														# Write-Output $FileURL
									
														# hash	hash_extension	filename	url service postID	downloaded	favorite
														$temp_query = "INSERT INTO Files (hash, hash_extension, filename, filename_extension, url, file_index, creatorName, postID, downloaded) 
																					VALUES ('$FileHash', '$HashExtension', '$Filename', '$FileExtension', '$FileURL', '$Cur_Index', '$CreatorName', '$PostID', 0);"
							
														$sqlScript += $temp_query + " "
														# Write-Host "`n sqlScript query from line 429 is $sqlScript"
														Write-Host "Added file $Filename ($FileHash) to database." -ForegroundColor Green
													}
########################################################################################
												} else {
													Write-Host "Skipped file $FilenameRaw because it has a duplicate hash ($FileHash)." -ForegroundColor Yellow
												}
########################################################################################
											} else {
												Write-Host "Skipped file $FilenameRaw." -ForegroundColor Yellow
											}
										}
									}
########################################################################################
									#this needs to go here to avoid a duplicate below
									# End the transaction
									$sqlScript += "COMMIT;"  
									#execute all queries at once
									# Write-Host "`nExecuting queries..."
									# Write-Host "`n sqlScript query from line 443 is $sqlScript"
									Invoke-SqliteQuery -DataSource $DBFilePath -Query $sqlScript
									
############################################ Now add the post itself. This is to prevent a post being skipped if for whatever reason the files for that post didn't get added fully
									$temp_query = "INSERT INTO Posts (postID, creatorName, title, content, date_published, date_added, downloaded) 
																VALUES ('$PostID', '$CreatorName', '$PostTitle', '$PostContent', '$PostDatePublishedFormatted', '$PostDateAddedFormatted', 0);"
									# Write-Host "`n temp query from line 391 is $temp_query"
									Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
############################################ update total_files for this post
									$temp_query = "UPDATE Posts SET total_files = '$Cur_Index' WHERE postID = '$PostID'"
									Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
####################################################
									$stopwatchFile.Stop()
									# Write-Host "Queries applied in $($stopwatchFile.Elapsed.TotalSeconds) seconds."
############################################
									$stopwatchPost.Stop()
									Write-Host "Fetched metadata for post $($PostID) in $($stopwatchPost.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
								}
							}
############################################
						}
############################################
						#fixed fetching more pages when the skip limit is reached
						#this happened because the break only stopped the foreach loop
						if ($HasMoreFiles) {
							$Cur_Offset += 50
							
							#update the page_offset column so that next time the query is run it starts from the begginning
							$temp_query = "UPDATE Creators SET page_offset = '$Cur_Offset' WHERE creatorID = '$CreatorID' AND service = '$Service'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							
							Start-Sleep -Milliseconds $TimeToWait  # Waits for X seconds
##########################################
						#handle errors like skip limit reached
						} else {
							#update the page_offset column so that next time the script is run it starts from the beginning
							$temp_query = "UPDATE Creators SET page_offset = 0 WHERE creatorID = '$CreatorID' AND service = '$Service'"
							# Write-Host "`ntemp_query for line 399: $temp_query"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							
							#update the last_time_fetched_metadata
							$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
							$temp_query = "UPDATE Creators SET last_time_fetched_metadata = '$CurrentDate' WHERE creatorID = '$CreatorID' AND service = '$Service'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							
							$HasMoreFiles = $false
							break       #stop fetching more data
						}
############################################
					} else {
						Write-Host "No more posts found for creator $CreatorName" -ForegroundColor Yellow
						
						#update the page_offset column so that next time the script is run it starts from the begginning
						$temp_query = "UPDATE Creators SET page_offset = 0 WHERE creatorID = '$CreatorID' AND service = '$Service'"
						Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
						
						#update the last_time_fetched_metadata
						$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
						$temp_query = "UPDATE Creators SET last_time_fetched_metadata = '$CurrentDate' WHERE creatorID = '$CreatorID' AND service = '$Service'"
						Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
						
						Start-Sleep -Milliseconds $TimeToWait  # Waits for X seconds
						
						$HasMoreFiles = $false
						break
					}
############################################
				} catch {
					if ($_.Exception.Response.StatusCode -in 429, 502) {
						$delay = Calculate-Delay -retryCount $retryCount
						
						$retryCount++
						
						Write-Host "429/502 error encountered. Retrying in $delay milliseconds..." -ForegroundColor Red
						Start-Sleep -Milliseconds $delay
					} else {
						Write-Host "Failed to fetch posts for creator $($CreatorName): $($_.Exception.Message)" -ForegroundColor Red
						$HasMoreFiles = $false
						break
					}
				}
############################################
			}
############################################
	}
############################################
}
############################################
#create database file if it doesn`t exist
if (-not (Test-Path $DBFilePath)) {
	$createTableQuery = "CREATE TABLE Creators (
		creatorID TEXT PRIMARY KEY,
		creatorName TEXT,
		service TEXT,
		date_indexed TEXT,
		date_updated TEXT,
		last_time_fetched_metadata TEXT,
		last_time_downloaded TEXT,
		page_offset INTEGER DEFAULT 0);
		"
	Invoke-SQLiteQuery -Database $DBFilePath -Query $createTableQuery
	
	
	$createTableQuery = "CREATE TABLE Posts (
		postID TEXT PRIMARY KEY,
		creatorName TEXT,
		title TEXT,
		content TEXT,
		total_files INTEGER DEFAULT 0,
		date_published TEXT,
		date_added TEXT,
		downloaded INTEGER DEFAULT 0 CHECK (downloaded IN (0,1))
		"
	Invoke-SQLiteQuery -Database $DBFilePath -Query $createTableQuery
	

	$createTableQuery = "CREATE TABLE Files (
		hash TEXT PRIMARY KEY,
		hash_extension TEXT,
		filename TEXT,
		filename_extension TEXT,
		url TEXT,
		file_index INTEGER DEFAULT 0,
		creatorName TEXT,
		postID TEXT,
		downloaded INTEGER DEFAULT 0 CHECK (downloaded IN (0,1)),
		favorite INTEGER DEFAULT 0 CHECK (downloaded IN (0,1)),
		deleted INTEGER DEFAULT 0 CHECK (downloaded IN (0,1))
		);
		"
	Invoke-SQLiteQuery -Database $DBFilePath -Query $createTableQuery
}

###############################


############################################
function Process-Creators {
	# Loop through the user list and download files
	foreach ($Creator in $CreatorList) {
		$CreatorName = $Creator[0]
		$CreatorID = $Creator[1]
		$Service = $Creator[2]
		$WordFilter = $Creator[3]
		$WordFilterExclude = $Creator[4]
		$Files_To_Exclude = $Creator[5]
		
		Download-Metadata-From-Creator -CreatorName $CreatorName -CreatorID $CreatorID -Service $Service -WordFilter $WordFilter -WordFilterExclude $WordFilterExclude -Files_To_Exclude $Files_To_Exclude
		
		# Start-Sleep -Milliseconds $TimeToWait
	}
}
############################################
function Graphical-Options {
    param (
        [string]$Query = ""
    )
	try {
		# Start logging
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/Kemono_$($CurrentDate).log" -Append
############################################
		$exitScript = $false
		while (-not $exitScript) {    
			Write-Host "`nKemono Powershell Downloader" -ForegroundColor Green
			Write-Host "`nSelect a option:" -ForegroundColor Green
			Write-Host "1. Download metadata from creators to database and then download files." -ForegroundColor Green
			Write-Host "2. Download only metadata from creators to database." -ForegroundColor Green
			Write-Host "3. Download all files in database not already downloaded (skip metadata download)." -ForegroundColor Green
			Write-Host "4. Download files in database from query." -ForegroundColor Green
			Write-Host "5. Scan folder for files and add them to database marked as favorites." -ForegroundColor Green
			Write-Host "6. Exit script" -ForegroundColor Green
			
			$choice = $(Write-Host "`nType a number (1-6):" -ForegroundColor green -NoNewLine; Read-Host) 
############################################
			if ($choice -eq 1) {
				Backup-Database
				
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Process-Creators
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all metadata from creators in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -FavoritesOnly $false -RedownloadEverything $false
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				[console]::beep()
############################################
			} elseif ($choice -eq 2){
				Backup-Database
				
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Process-Creators
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all metadata from creators in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				[console]::beep()
############################################
			} elseif ($choice -eq 3){
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -type 1
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				[console]::beep()
############################################
			} elseif ($choice -eq 4){
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -type 2 -Query $Query
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all files from query in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				[console]::beep()
############################################
			} elseif ($choice -eq 5){
				Backup-Database
				Scan-Folder-And-Add-Files-As-Favorites -Type 3
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
		Start-Transcript -Path "$PSScriptRoot/logs/Kemono_$($CurrentDate).log" -Append
###########################################
		if ($function -eq 1) {
			Backup-Database
			
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Process-Creators
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded all metadata from creators in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Download-Files-From-Database -Type 1
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			[console]::beep()
###########################################
		} elseif ($function -eq 2){
			Backup-Database
			
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Process-Creators
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded all metadata from creators in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			[console]::beep()
###########################################
		} elseif ($function -eq 3){
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Download-Files-From-Database -Type 1
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			[console]::beep()
###########################################
		} elseif ($function -eq 4){
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Download-Files-From-Database -Type 2 -Query $Query
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded all files from query in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			[console]::beep()
###########################################
		} elseif ($function -eq 5){
			Backup-Database
			Scan-Folder-And-Add-Files-As-Favorites -Type 3
			[console]::beep()
###########################################
		} else {
			Write-Host "`nInvalid choice. Try again." -ForegroundColor Red
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