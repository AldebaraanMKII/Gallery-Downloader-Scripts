Import-Module PSSQLite

###############################
# Import functions and configuration
. "$PSScriptRoot/(config) CivitAI.ps1"
. "$PSScriptRoot/Functions.ps1"
###############################
function Download-Files-From-Database {
    param (
        [int]$Type
    )

	# Define the invalid characters for Windows file names
	$invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''

	if ($Type -eq 1) {
		Write-Host "Starting download of files..." -ForegroundColor Yellow
			
		#same query for all
		$temp_query = "SELECT username FROM Users;"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
######################################
		if ($result.Count -gt 0) {
			Write-Host "Found $($result.Count) users." -ForegroundColor Green
			Backup-Database
######################################
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
						$HoursDifference = $TimeDifference.TotalHours
	
						if ($HoursDifference -lt $TimeToCheckAgainDownload) {
							$ContinueFetching = $false
							Write-Host "This user's gallery was downloaded less than $TimeToCheckAgainDownload hours ago. Skipping..." -ForegroundColor Yellow
						} else {
							#update the last_time_downloaded column to NULL
							$temp_query = "UPDATE Users SET last_time_downloaded = NULL WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
######################################
						}
######################################
					}
				}
######################################
				if ($ContinueFetching) {
					$temp_query = "SELECT id, filename, extension, width, height, url, createdAt, username FROM Files WHERE username = '$Username' AND downloaded = 0 AND deleted = 0;"

					$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
######################################
					if ($result.Count -gt 0) {
						
						Start-Download -SiteName "CivitAI" -FileList $result
						
######################################
					} else {
						Write-Host "Found 0 files that meet the query requirements for username $Username. Skipping..." -ForegroundColor Yellow
							
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
		$WhereQuery = $(Write-Host "`nEnter WHERE query:" -ForegroundColor cyan -NoNewLine; Read-Host)
		
		$temp_query = "SELECT username, id, filename, extension, width, height, url, createdAt FROM Files $WhereQuery;"

		# Write-Host "temp_query: $temp_query" -ForegroundColor Yellow
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
######################################
		if ($result.Count -gt 0) {
			Start-Download -SiteName "CivitAI" -FileList $result
######################################
		} else {
			Write-Host "Found 0 files that meet the query conditions." -ForegroundColor Red
		}
	}
######################################
}
######################################
# Function to download metadata
function Download-Metadata-From-User {
    param (
        [string]$Username
    )
	
	# Set initial parameters for paging
	$CursorString = ""
	
	# $HasMoreImages = $true         #this is set inside the rating loop
	$ContinueFetching = $true        
	$TotalFiles = 0
########################################
	
######### Add user if it doesn`t exist
	$temp_query = "SELECT EXISTS(SELECT 1 from Users WHERE username = '$Username');"
	$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
	$exists = $result."EXISTS(SELECT 1 from Users WHERE username = '$Username')"
	
	# Write-Host "exists is $exists."
	# Check the result
	if ($exists -eq 0) {
        $username_url = "https://civitai.com/user/$Username/images"
        
        $temp_query = "INSERT INTO Users (username, url, cur_cursor)
                                    VALUES ('$Username', '$username_url', NULL)"
        # Write-Host "`ntemp_query is $temp_query"
        Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
        
        Write-Host "`nNew user $Username added to database." -ForegroundColor Green
##########################################
	} else {
		Write-Host "`nfound user $Username in database." -ForegroundColor Green
##########################################
		#load last_time_fetched_metadata and start search from there
		$temp_query = "SELECT last_time_fetched_metadata FROM Users WHERE username = '$Username'"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
							
		# Check the result
		if ($result.Count -gt 0) {
			if (-not [string]::IsNullOrWhiteSpace($result[0].last_time_fetched_metadata)) {
				$DateLastDownloaded = $result[0].last_time_fetched_metadata
				
				# Ensure both dates are DateTime objects
				$CurrentDate = [datetime]::ParseExact((Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "yyyy-MM-dd HH:mm:ss", $null)
				$DateLastDownloaded = [datetime]::ParseExact($DateLastDownloaded, "yyyy-MM-dd HH:mm:ss", $null)

				$TimeDifference = $CurrentDate - $DateLastDownloaded
				$HoursDifference = $TimeDifference.TotalHours

				if ($HoursDifference -lt $TimeToCheckAgainMetadata) {
					$ContinueFetching = $false
					Write-Host "This user was updated less than $TimeToCheckAgainMetadata hours ago. Skipping..." -ForegroundColor Yellow
				} else {
					#update the last_time_fetched_metadata column to NULL
					$temp_query = "UPDATE Users SET last_time_fetched_metadata = NULL WHERE username = '$Username'"
					Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
					
##########################################
				}
##########################################
			}
            # Load cur_cursor and start search from there, regardless of stats of last_time_fetched_metadata
            $temp_query = "SELECT cur_cursor FROM Users WHERE username = '$Username'"
            $result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
            
            # Check the result
            if ($result.Count -gt 0) {
                # Ensure proper NULL checking
                if ($result[0].cur_cursor -ne $null) {
                    $Cursor = $result[0].cur_cursor
                    $CursorString = "&cursor=$Cursor"
                    Write-Host "Starting from cursor $Cursor." -ForegroundColor Green
                } else {
                    $CursorString = ""
                    # Write-Host "No valid cursor found, starting fresh." -ForegroundColor Yellow
                }
            } else {
                Write-Host "User not found or query returned no results." -ForegroundColor Red
            }
##########################################
		}
##########################################
	}
###########################
	# The API is currently bugged and only returns SFW files when no parameter is set, so this is needed
	if ($AllowSFWFiles -and $AllowNSFWFiles) {
		$RatingList = @(
			"X",
			"Mature",
			"Soft",
			"None"
		)
	} elseif ($AllowSFWFiles) {
		$RatingList = @(
			"Soft",
			"None"
		)
	} else {
		$RatingList = @(
			"X",
			"Mature"
		)
	}
############################################
	if ($ContinueFetching) {
		$CurrentSkips = 0
		foreach ($Rating in $RatingList) {
			$HasMoreFiles = $true
############################################
			# Loop through pages of files for the user
			while ($HasMoreFiles) {
				$retryCount = 0
				while ($retryCount -lt $maxRetries) {
					# ("sort","Newest"); // Weird undocumented behavior. It doesn't return all files if this parameter is not set.
					# ("nsfw","X"); // Another weird undocumented behavior. It marks highest possible level.
					# https://civitai.com/api/v1/images?username=Gemini3443&limit=200&token=token_here&nsfw=X&cursor=26380421
					# "On July 2, 2023 we switch from a paging system to a cursor based system due to the volume of data and requests for this endpoint."
					# so user cursor=cursornumber instead of page=pagenumber
					$URL = "$($BaseURL)?username=$Username&limit=$Limit&token=$API_Key&period=AllTime&sort=Newest&nsfw=$($Rating)$($CursorString)"
					$ConsoleURL = "$($BaseURL)?username=$Username&limit=$Limit&token=API_Key_Here&period=AllTime&sort=Newest&nsfw=$($Rating)$($CursorString)"
					# Write-Host "`nURL: $URL" -ForegroundColor Yellow
					Write-Host "`nURL: $ConsoleURL" -ForegroundColor Yellow	#users can share this in case of bugs
					
					if ($CursorString.Trim() -ne "") {
						Write-Host "`nFetching metadata for cursor $Cursor for user $Username (Rating: $Rating)..." -ForegroundColor Yellow
					} else {
						Write-Host "`nFetching metadata for user $Username (Rating: $Rating)..." -ForegroundColor Yellow
					}
############################################
					try {
						# Get the raw response
						$ResponseRaw = Invoke-WebRequest -Uri $URL -Method Get -ErrorAction Stop
						
						# Convert to UTF-8
						# $UTF8Response = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::Default.GetBytes($ResponseRaw.Content))
						
						# Now parse the JSON response
						$Response = $ResponseRaw | ConvertFrom-Json -AsHashTable

						# Make the API request and process the JSON response
						# $Response = Invoke-RestMethod -Uri $URL -Method Get
						# $Response = Invoke-RestMethod -Uri $URL -Method Get -ErrorAction Stop
############################################
						# Check if there are any files returned in the response
						if ($Response.items -and $Response.items.Count -gt 0) {
							Write-Host "Number of results found: $($Response.items.Count)" -ForegroundColor Green
############################################
							#files
							$stopwatchCursor = [System.Diagnostics.Stopwatch]::StartNew()
							$sqlScript = "BEGIN TRANSACTION; " 
							foreach ($File in $Response.items) {
								$FileID = $File.id
##########################################
								$temp_query = "SELECT EXISTS(SELECT 1 FROM Files WHERE id = '$FileID');"
								$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								
								# Extract the value from the result object
								$exists = $result."EXISTS(SELECT 1 FROM Files WHERE id = '$FileID')"
	
								if ($exists -eq 1) {
									Write-Host "FileID $FileID already exists in database, skipping..." -ForegroundColor Yellow
									$CurrentSkips++
									
									if ($MaxSkipsBeforeAborting -gt 0) {
										if ($CurrentSkips -gt $MaxSkipsBeforeAborting) {
											Write-Host "Reached maximum amount of skipped items. Skipping user $Username." -ForegroundColor Yellow
											$HasMoreFiles = $false
											# $CurrentSkips = 0
											break
										}
									}
##########################################
								} else {
									$FileUrlRaw = $File.url
									
									# $FileHash = $File.hash
									$FileWidth = $File.width
									$FileHeight = $File.height
									$FileCreateDate = $File.createdAt	# e.g. 06\21\2024 06:43:18
									$FilePostID = $File.postId	
									$FileUsername = $File.username
									
									# Convert to DateTime object
									$formattedDate = [datetime]::ParseExact($FileCreateDate, "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss")
									
									# Extract the filename with extension
									$filenameWithExtension = ([uri]$FileUrlRaw).Segments[-1]
									# # Split the filename and extension
									$filename, $extension = $filenameWithExtension -split '\.'
									
									#remove baseurl, filename + extension, filename again and file width
									$FileUrl = $FileUrlRaw -replace "$DownloadBaseURL", ''
									$FileUrl = $FileUrl -replace "$filenameWithExtension", ''
									$FileUrl = $FileUrl -replace "$filename", ''
									#sometimes whatever is inside /width=/ doesn`t match $FileWidth, so use a regular expression
									$FileUrl = $FileUrl -replace "/width=\d+/", ''
									#remove url to save database space
									$FileUrl = $FileUrl -replace "xG1nkqKTMzGDvpLrqFT7WA/", ''
									#New stuff 30-09-2025
									$FileUrl = $FileUrl -replace "/original=true/", ''
									$FileUrl = ""

									if ($DownloadPromptMetadata) {
										$FileMeta_Size = $File.meta.Size
										$FileMeta_Seed = $File.meta.seed
										$FileMeta_Model = $File.meta.Model
										$FileMeta_Steps = $File.meta.steps
										$FileMeta_Prompt = $File.meta.prompt
	
										$FileMeta_Sampler = $File.meta.sampler
										$FileMeta_CFGScale = $File.meta.cfgScale
										$FileMeta_ClipSkip = $File.meta.'Clip skip'
										$FileMeta_HiresUpscale = $File.meta.'Hires upscale'
										$FileMeta_HiresUpscaler = $File.meta.'Hires upscaler'
										$FileMeta_NegativePrompt = $File.meta.negativePrompt
										$FileMeta_DenoisingStrength = $File.meta.'Denoising strength'
										# $FileMeta_CreatedDate = $File.meta.'Created Date'
										# "2024-06-13T0517:26.3008551Z"
										# $FileMeta_CreatedDate_formatted = [datetime]::ParseExact($FileCreateDate, "MM/dd/yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH:mm:ss")
	
										$FileMeta_Model = $FileMeta_Model -replace "'", ""
										$FileMeta_Prompt = $FileMeta_Prompt -replace "'", ""
										$FileMeta_Sampler = $FileMeta_Sampler -replace "'", ""
										$FileMeta_NegativePrompt = $FileMeta_NegativePrompt -replace "'", ""
										
										$temp_query = "INSERT INTO Files (id, filename, extension, width, height, url, createdAt, postId, username, rating, meta_size, meta_seed, meta_model, meta_steps, meta_prompt, meta_sampler, meta_cfgScale, meta_clip_skip, meta_hires_upscale, meta_hires_upscaler, meta_negativePrompt, meta_denoising_strength, downloaded)
																VALUES ('$FileID', '$filename', '$extension', '$FileWidth', '$FileHeight', '$FileUrl', '$formattedDate', '$FilePostID', '$FileUsername', '$Rating', '$FileMeta_Size', '$FileMeta_Seed', '$FileMeta_Model', '$FileMeta_Steps', '$FileMeta_Prompt', '$FileMeta_Sampler', '$FileMeta_CFGScale', '$FileMeta_ClipSkip', '$FileMeta_HiresUpscale', '$FileMeta_HiresUpscaler', '$FileMeta_NegativePrompt', '$FileMeta_DenoisingStrength', 0);"
									} else {
										$temp_query = "INSERT INTO Files (id, filename, extension, width, height, url, createdAt, postId, username, rating, downloaded)
																VALUES ('$FileID', '$filename', '$extension', '$FileWidth', '$FileHeight', '$FileUrl', '$formattedDate', '$FilePostID', '$FileUsername', '$Rating', 0);"
									}
									
									# Write-Host "`n$temp_query"
									$sqlScript += $temp_query + " "
									
									# $TotalFiles++
									# Write-Host "TotalFiles is $TotalFiles."
									Write-Host "Added FileID $FileID to database." -ForegroundColor Green
								}
							}
##################################################
							# End the transaction
							$sqlScript += "COMMIT;"  
							#execute all queries at once
							# Write-Host "`nExecuting queries..."
							# Write-Host "`n sqlScript query from line 443 is $sqlScript"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $sqlScript
######################################
							$stopwatchCursor.Stop()
							if ($CursorString.Trim() -ne "") {
								Write-Host "Fetched metadata for cursor $Cursor (Rating: $Rating) for user $Username in $($stopwatchCursor.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
							} else {
								Write-Host "Fetched metadata (Rating: $Rating) for user $Username in $($stopwatchCursor.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
							}
######################################
							#update total files
							$query = "SELECT COUNT(*) AS FileCount FROM Files WHERE username = '$Username'"
							$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $query
							$TotalFiles = $result.FileCount
							$query = "UPDATE Users SET total_files = '$TotalFiles' WHERE username = '$Username'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $query
######################################
							# if ($Response.metadata.nextCursor) {
							#fixed fetching more pages when the skip limit is reached
							#this happened because the break only stopped the foreach loop
							if ($HasMoreFiles) {
								if ($Response.metadata.nextCursor) {
									$Cursor = $Response.metadata.nextCursor
									$CursorString = "&cursor=$Cursor"
									
									#update the page_offset column so that next time the query is run it starts from the begginning
									$temp_query = "UPDATE Users SET cur_cursor = '$Cursor' WHERE username = '$Username'"
									Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
									
									Start-Sleep -Milliseconds $TimeToWait  # Waits for X seconds
############################################
								}	else {
									Write-Host "No more files found for user $UserName" -ForegroundColor Yellow
									
									#update the cur_cursor column so that next time the script is run it starts from the beginning
									$temp_query = "UPDATE Users SET cur_cursor = NULL WHERE username = '$Username'"
									# Write-Host "`ntemp_query for line 399: $temp_query"
									Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
									
									Start-Sleep -Milliseconds $TimeToWait  # Waits for X seconds
									
									$HasMoreFiles = $false
									break
								}
							 } else {
								Start-Sleep -Milliseconds $TimeToWait  # Waits for X seconds
								$HasMoreFiles = $false
								break       #stop fetching more data
							 }
############################################
						#this is to account for empty responses
						} else {
							Write-Host "No items found in response. Skipping user $UserName..." -ForegroundColor Yellow
							Start-Sleep -Milliseconds $TimeToWait  # Waits for X seconds
							$HasMoreFiles = $false
							break
						}
############################################
					} catch {
						if ($_.Exception.Response.StatusCode -in 429, 502) {
							$delay = Calculate-Delay -retryCount $retryCount
							
							$retryCount++
							
							Write-Host "error 429/502 encountered. Retrying in $delay milliseconds..." -ForegroundColor Red
							Start-Sleep -Milliseconds $delay
############################################
						} elseif ($_.Exception.Response.StatusCode -eq 500) {
							Write-Host "Error 500 encountered. This probably means that the user ($Username) doesn't exist." -ForegroundColor Red
							Start-Sleep -Milliseconds $TimeToWait  # Waits for X seconds
							$HasMoreFiles = $false
							break
############################################
						} else {
							Write-Host "Failed to fetch posts for user $($Username): $($_.Exception.Message)" -ForegroundColor Red
							Start-Sleep -Milliseconds $TimeToWait  # Waits for X seconds
							$HasMoreFiles = $false
							break
						}
					}
############################################
				}
############################################
			}
############################################
			#update the cur_cursor column so that next time the query is run it starts from the beginning
			$temp_query = "UPDATE Users SET cur_cursor = NULL WHERE username = '$Username'"
			# Write-Host "`ntemp_query for line 399: $temp_query"
			Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
			$CursorString = ""
		}
		$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
		#update the last_time_fetched_metadata column
		$temp_query = "UPDATE Users SET last_time_fetched_metadata = '$CurrentDate' WHERE username = '$Username'"
		Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
############################################
	}
############################################
}
############################################
#create database file if it doesn`t exist
if (-not (Test-Path $DBFilePath)) {
	
	$createTableQuery = "CREATE TABLE Users (
		username TEXT PRIMARY KEY,
		url TEXT,
		total_files INTEGER DEFAULT 0,
		cur_cursor TEXT,
		last_time_fetched_metadata TEXT,
		last_time_downloaded TEXT
		);
		"
	
	Invoke-SQLiteQuery -Database $DBFilePath -Query $createTableQuery
	
	$createTableQuery = "CREATE TABLE Files (
		id INTEGER PRIMARY KEY,
		filename TEXT,
		extension TEXT,
		width INTEGER,
		height INTEGER,
		url TEXT,
		createdAt TEXT,
		postId INTEGER DEFAULT 0,
		username TEXT,
		rating TEXT,
		meta_size TEXT,
		meta_seed INTEGER DEFAULT 0,
		meta_model TEXT,
		meta_steps INTEGER DEFAULT 0,
		meta_prompt TEXT,
		meta_sampler TEXT,
		meta_cfgScale INTEGER DEFAULT 0,
		meta_clip_skip INTEGER DEFAULT 0,
		meta_hires_upscale INTEGER DEFAULT 0,
		meta_hires_upscaler TEXT,
		meta_negativePrompt TEXT,
		meta_denoising_strength FLOAT DEFAULT 0,
		downloaded INTEGER DEFAULT 0,
		favorite INTEGER DEFAULT 0,
		deleted INTEGER DEFAULT 0
		);
		"
		
	Invoke-SQLiteQuery -Database $DBFilePath -Query $createTableQuery
}

############################################
function Process-Users {
	# Loop through the user list and download files
	foreach ($User in $UserList) {
		$Username = $User
		
		Download-Metadata-From-User -Username $Username
		
		# Start-Sleep -Milliseconds $TimeToWait
	}
	
	Download-Files-From-Database -Type 1
}
############################################
function Graphical-Options {
	try {
		# Start logging
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/CivitAI_$($CurrentDate).log" -Append
		
		$exitScript = $false
		while (-not $exitScript) {
			Write-Host "`nCivitAI Powershell Downloader" -ForegroundColor Green
			Write-Host "`nSelect a option:" -ForegroundColor Green
			Write-Host "1. Download metadata from users to database and then download files." -ForegroundColor Green
			Write-Host "2. Download only metadata from users to database." -ForegroundColor Green
			Write-Host "3. Download all files in database not already downloaded (skip metadata download)." -ForegroundColor Green
			Write-Host "4. Download all files from query." -ForegroundColor Green
			Write-Host "5. Scan folder for files and add them to database marked as favorites." -ForegroundColor Green
			Write-Host "6. Exit script" -ForegroundColor Green
			
			$choice = $(Write-Host "`nType a number (1-6):" -ForegroundColor green -NoNewLine; Read-Host) 
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
############################################
			} elseif ($choice -eq 2){
				Backup-Database
				
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Process-Users
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all metadata from users in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
############################################
			} elseif ($choice -eq 3){
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -Type 1
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
############################################
			} elseif ($choice -eq 4){
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -Type 2
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all files from query in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
############################################
			} elseif ($choice -eq 5){
				Backup-Database
				Scan-Folder-And-Add-Files-As-Favorites -Type 2
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
        [int]$function
    )
	
	try {
		# Start logging
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/CivitAI_$($CurrentDate).log" -Append
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
############################################
		} elseif ($function -eq 2){
			Backup-Database
			
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Process-Users
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded all metadata from users in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
############################################
		} elseif ($function -eq 3){
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Download-Files-From-Database -Type 1
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
############################################
		} elseif ($function -eq 4){
			$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
			Download-Files-From-Database -Type 2
			$stopwatch_main.Stop()
			Write-Host "`nDownloaded all files from query in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
############################################
		} elseif ($function -eq 5){
			Backup-Database
			Scan-Folder-And-Add-Files-As-Favorites -Type 2
############################################
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
