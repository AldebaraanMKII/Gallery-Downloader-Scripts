

[CmdletBinding()]
param (
    [string]$Function,
    [string]$Query,
    [string]$QueryName,
    [string]$MinID = "-1",
    [string]$MaxID = "-1",
    [string]$Results_per_Page = "1000"
)

Import-Module PSSQLite

############################################
# Import functions
. "$PSScriptRoot/(config) Rule34xxx.ps1"
. "$PSScriptRoot/Functions.ps1"
############################################
function Download-Files-From-Database {
    param (
        [int]$Type,
        [string]$Query = ""
    )
    Write-Host "Files Table Columns (for download operations): id[int], url[string], hash[string], extension[string], width[int], height[int], createdAt[string], source[string], main_tag[string], tags_artist[string], tags_character[string], tags_general[string], tags_copyright[string], tags_meta[string], downloaded[int/0-1], favorite[int/0-1], deleted[int/0-1]" -ForegroundColor Cyan
	
	# Define the invalid characters for Windows file names
	$invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''
	
	if ($Type -eq 1) {
		Write-Host "`nStarting download of files..." -ForegroundColor Yellow
		
		#same query for all
		$temp_query = "SELECT query, query_name, last_time_downloaded FROM Queries;"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
###################################
		if ($result.Count -gt 0) {
			Write-Host "Found $($result.Count) queries." -ForegroundColor Green
			Backup-Database
###################################
			foreach ($ResultQuery in $result) {
				$query = $ResultQuery.query
				$query_name = $ResultQuery.query_name
				$last_time_downloaded = $ResultQuery.last_time_downloaded
				Write-Host "`nProcessing query $query_name..." -ForegroundColor Yellow
				
				$ContinueFetching = $true
				#load last_time_downloaded and start search from there
				$temp_query = "SELECT last_time_downloaded FROM Queries WHERE query = '$query'"
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
							Write-Host "This query's files was downloaded less than $TimeToCheckAgainDownload seconds ago. Skipping..." -ForegroundColor Yellow
						} else {
							#update the last_time_downloaded column to NULL
							$temp_query = "UPDATE Queries SET last_time_downloaded = NULL WHERE query = '$query'"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
###################################
						}
###################################
					}
				}
###################################
				if ($ContinueFetching) {
					Write-Host "Starting download of files..." -ForegroundColor Yellow
					$temp_query = "SELECT id, url, hash, extension, createdAt, tags_artist, tags_character FROM Files WHERE downloaded = 0 AND main_tag = '$query_name' AND deleted = 0;"
	
					# get all rows where downloaded = 0
					# Write-Host "temp query: $temp_query"
					$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
###################################
					if ($result.Count -gt 0) {
						
						Start-Download -SiteName "Gelbooru_Based" -FileList $result
						
###################################
					} else {
						Write-Host "Found 0 Files not already downloaded in database. Terminating..." -ForegroundColor Red
						
						$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
						#update the last_time_downloaded column
						$temp_query = "UPDATE Queries SET last_time_downloaded = '$CurrentDate' WHERE query = '$query'"
						Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
					}
######################################
				}
######################################
			}
######################################
		}
######################################
	} elseif ($Type -eq 2) {
        if (-not [string]::IsNullOrEmpty($Query)) {
            $WhereQuery = $Query
            Write-Host "`nUsing provided query: '$WhereQuery'" -ForegroundColor Blue
        } else {
            $WhereQuery = $(Write-Host "`nEnter WHERE query:" -ForegroundColor cyan -NoNewLine; Read-Host)
        }
		
		$temp_query = "SELECT id, url, hash, extension, createdAt, tags_artist, tags_character FROM Files $WhereQuery;"

        $stopwatch_temp = [System.Diagnostics.Stopwatch]::StartNew()
		# Write-Host "temp_query: $temp_query" -ForegroundColor Yellow
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
        $stopwatch_temp.Stop()
        Write-Host "`nFetched results in $($stopwatch_temp.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
######################################
		if ($result.Count -gt 0) {
			Start-Download -SiteName "Gelbooru_Based" -FileList $result
######################################
		} else {
			Write-Host "Found 0 files that meet the query conditions." -ForegroundColor Red
		}
	}
######################################
}
############################################
# Function to download metadata
function Download-Metadata-From-Query {
    param (
        [string]$QueryName,
        [string]$MinID,
        [string]$MaxID,
        [string]$Results_per_Page,
        [string]$Query
    )
	
	# Set initial parameters for paging
	$Page = 1
	$ContinueFetching = $true
	
	$IDString = ""
	# id:>$MinID id:<$MaxID
	if ($MinID -ge 0 -and $MaxID -ge 0 -and $MaxID -gt $MinID){
		#remember the white space between $Query and $IDString
		$IDString = " id:>$MinID id:<$MaxID"
		
	}	elseif ($MaxID -gt 0 -and $MaxID -le $MinID) {
		Write-Host "MinID must be lower than MaxID and MaxID higher than MinID. Removing id search from query $QueryName." -ForegroundColor Yellow
	
	} elseif ($MinID -ge 0) {
		$IDString = " id:>$MinID"
		
	}	elseif ($MaxID -ge 0) {
		$IDString = " id:<$MaxID"
	}
		
		
######### Add query if it doesn`t exist
	# Define the query
	$temp_query = "SELECT COUNT(*) FROM Queries WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID"
	
	# Write-Host "`n$temp_query" -ForegroundColor Yellow
	# Execute the query
	$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
	
	$count = $result[0]."COUNT(*)"
	
	# Check the result
	if ($count -eq 0) {
		$temp_query = "INSERT INTO Queries (query_name, query, minID, maxID, results_per_page)
									VALUES ('$QueryName', '$Query', $MinID, $MaxID, $Results_per_Page)"
		Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
		
		Write-Host "New query added to database." -ForegroundColor Green
	} else {
		Write-Host "found query in database." -ForegroundColor Green
############################################
		#load last_time_fetched_metadata and start search from there
		$temp_query = "SELECT last_time_fetched_metadata FROM Queries WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
							
		# Check the result
		if ($result.Count -gt 0) {
			if (-not [string]::IsNullOrWhiteSpace($result[0].last_time_fetched_metadata)) {
				$DateLastDownloaded = $result[0].last_time_fetched_metadata
				
				# Ensure both dates are DateTime objects
				$CurrentDate = [datetime]::ParseExact((Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "yyyy-MM-dd HH:mm:ss", $null)
				$DateLastDownloaded = [datetime]::ParseExact($DateLastDownloaded, "yyyy-MM-dd HH:mm:ss", $null)

				$TimeDifference = $CurrentDate - $DateLastDownloaded
				$SecondsDifference = $TimeDifference.TotalSeconds

				if ($SecondsDifference -lt $TimeToCheckAgainMetadata) {
					$ContinueFetching = $false
					Write-Host "This query was updated less than $TimeToCheckAgainMetadata seconds ago. Skipping..." -ForegroundColor Yellow
				} else {
					#update the last_time_fetched_metadata column to NULL
					$temp_query = "UPDATE Queries SET last_time_fetched_metadata = NULL WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID"
					Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
############################################
					#load results_per_page
					$temp_query = "SELECT results_per_page FROM Queries WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID"
					$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
					
					# Check the result
					if ($result.Count -gt 0) {
						$Results_per_Page = $result[0].results_per_page
						Write-Host "Fetching $Results_per_Page results per page." -ForegroundColor Green
					}
############################################
				}
############################################
			}
############################################
		}
        
		#load last_id and start search from there, regardless of stats from last_time_fetched_metadata
		$temp_query = "SELECT last_id FROM Queries WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
		
		# Check the result
		if ($result.Count -gt 0) {
			$LastID = $result[0].last_id
			#if 0, skip id query
			if ($LastID -eq 0) {
				$IDString = ""
			#if any number other than 0, start search from there
			} else {
				$IDString = " id:<$LastID"
				Write-Host "Starting from ID $LastID." -ForegroundColor Green
			}
		}
############################################
	}
############################################
	if ($ContinueFetching) {
		$HasMoreFiles = $true
		Write-Host "`nFetching metadata for query $QueryName..." -ForegroundColor Yellow
############################################
		# Loop through pages of Files for the user
		
		$CurrentSkips = 0
		while ($HasMoreFiles) {
			$retryCount = 0
			while ($retryCount -lt $maxRetries) {
				
				# https://api.rule34.xxx/index.php?page=dapi&s=post&q=index&json=1&limit=1000&pid=200&tags=*huge_breasts%20-anthro*
				# $URL = "$($BaseURL)&limit=$Results_per_Page&pid=$Page&tags=$($Query)$($IDString)"
                $URL = "$($BaseURL)&api_key=$API_Key&user_id=$UserID&limit=$Results_per_Page&pid=$Page&tags=$($Query)$($IDString)"
				$ConsoleURL = "$($BaseURL)&api_key=API_Key_Here&user_id=UserID_Here&limit=$Results_per_Page&pid=$Page&tags=$($Query)$($IDString)"
                
				Write-Host "`nURL: $ConsoleURL" -ForegroundColor Yellow
				
				Write-Host "Fetching metadata for page $Page..." -ForegroundColor Yellow
############################################
				try {
					
					$sqlScript = "BEGIN TRANSACTION; "  # Using transactions reduced query apply time by 14-16 times
					
					if (-not $stopwatchBatch.IsRunning) {
						$stopwatchBatch = [System.Diagnostics.Stopwatch]::StartNew() 
					}
					
					# Make the API request and process the JSON response
					$Response = Invoke-RestMethod -Uri $URL -Method Get
					
					# Parse the XML response 
					$xml = [xml]$Response
					
############################################
					# Check if there are any Files returned in the response
					# if ($Response -and $Response.Count -gt 0) {
					if ($xml.posts.post -ne $null) {
						# Write-Host "Number of items: $($Response.Count)" -ForegroundColor Green
						Write-Host "Number of items: $($xml.posts.post.Count)" -ForegroundColor Green
						$CurItemCount = $xml.posts.post.Count
						$i = 0
						# this is to account for those times that the returned items are less than $MetadataCountBeforeAdding
						# if ($Response.Count -lt $MetadataCountBeforeAdding) {
							# $MetadataCountBeforeAdding = $Response.Count
							# Write-Host "Set MetadataCountBeforeAdding to $($Response.Count)."
						# }
############################################
						# $i = 0
						#list to compare IDs to avoid duplicates
						$HashList = New-Object System.Collections.Generic.List[System.Object]
						# foreach ($File in $Response) {
						foreach ($File in $xml.posts.post) {
							$CurItemCount--
							$i++
							# Write-Host "CurItemCount is $CurItemCount"
							# Write-Host "i is $i"
							# id, filename_and_hash, extension, url, createdAt, artist_tag, downloaded favorite
							$FileID = $File.id
							
							$Continue = $false
							if ($SkipIDCheck -eq $false) {
############################################
								$temp_query = "SELECT EXISTS(SELECT 1 FROM Files WHERE id = '$FileID');"
								$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
								
								# Extract the value from the result object
								$exists = $result."EXISTS(SELECT 1 FROM Files WHERE id = '$FileID')"

								if ($exists -eq 1) {
									Write-Host "File ID $FileID already exists in database, skipping..." -ForegroundColor Yellow
									$CurrentSkips++
									# Write-Host "CurrentSkips: $CurrentSkips" -ForegroundColor Yellow
############################################
									if ($CurItemCount -le 0 -or $i -ge $MetadataCountBeforeAdding) {
										$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
										#update last_id to the current $FileID
										$temp_query = "UPDATE Queries SET last_id = '$FileID' WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID;"
										$sqlScript += $temp_query + " "
										# End the transaction
										$sqlScript += "COMMIT;"  
										#execute all queries at once
										# Write-Host "$sqlScript"
										Write-Host "Executing queries..." -ForegroundColor Yellow
										Invoke-SqliteQuery -DataSource $DBFilePath -Query $sqlScript
										
										$stopwatch.Stop()
										Write-Host "Queries applied in $($stopwatch.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
										Write-Host "`n"
										
										$sqlScript = "BEGIN TRANSACTION; "  # Using transactions reduced query apply time by 14-16 times
										$i = 0 		#reset it
										
									}
############################################
									if ($CurrentSkips -gt $MaxSkipsBeforeAborting) {
										Write-Host "Reached maximum amount of skipped items. Skipping query..." -ForegroundColor Yellow
										$HasMoreFiles = $false
										# $CurrentSkips = 0
										break
									}
############################################
								} else {
									$Continue = $true
								}
############################################
							} else {
								$Continue = $true
							}
							
############################################ code to avoid duplicates
							if ($HashList -notcontains $FileID) {
								$HashList.Add($FileID)
							} else {
								$Continue = $false
								Write-Host "Duplicate found in json (ID: $FileID) (this shoudn't happen)! Skipping..." -ForegroundColor Yellow
							}
############################################
							if ($Continue) {
								# filename with extension 	e.g. b834b1f7efff2d04e3188b122aa3a3d4.png
								
								# $filenameWithExtension = $File.image
								# Split the filename and extension
								# $FileHash, $FileExtension = $filenameWithExtension -split '\.'
								$FileUrlRaw = $File.file_url	   #e.g.	https://api-cdn.rule34.xxx/images/1856/b834b1f7efff2d04e3188b122aa3a3d4.png

								# filename can be extracted with this
								$filenameWithExtension = ([uri]$FileUrlRaw).Segments[-1]
								# Split the filename and extension
								$FileHash, $FileExtension = $filenameWithExtension -split '\.'
								
								# #remove base url to reduce database space
								# $FileUrl = $FileUrlRaw -replace $DownloadBaseURL, ''
								# $FileUrl = $FileUrl -replace $FileHash, ''
								# $FileUrl = $FileUrl -replace $FileExtension, ''
								# $FileUrl = $FileUrl -replace '/', ''
								# $FileUrl = $FileUrl -replace '.', ''
								# Extract the directory part using regex 
								if ($FileUrlRaw -match '\/images\/(\d+)\/') { 
									$FileUrl = $matches[1] 
								} else {
									$FileUrl = ""
								}
								
								$FileWidth = $File.width
								$FileHeight = $File.height
								$TagListRaw = $File.tags
								
								
								$dateString = $File.created_at  # e.g., Thu Oct 31 04:53:49 +0100 2024
								# Write-Output "dateString: $dateString"
								# Remove the day of the week and timezone
								$intermediateDateString = $dateString -replace '^\w{3} ', '' -replace ' \+\d{4}', ''
								# Write-Output "Intermediate date string: $intermediateDateString"
								# Parse the intermediate date string
								try {
									$parsedDate = [datetime]::ParseExact($intermediateDateString, "MMM dd HH:mm:ss yyyy", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None)
									# Convert to the desired format
									$FileCreateDate = $parsedDate.ToString("dd-MM-yyyy HH:mm:ss")
									# Write-Output "Output date string: $FileCreateDate"
								} catch {
									$FileCreateDate = ""
									Write-Host "Failed to parse the date string: $($intermediateDateString)"
								}


								$TagListRaw = $TagListRaw -replace "'", "''"
								
								# Split the string into a list
								$TagList = $TagListRaw -split " "
								
								# Print the list to the console
								# $TagList | ForEach-Object { Write-Host $_ }
								
								$CharacterList = @()
								$ArtistList = @()
								$GeneralList = @()
								$CopyrightList = @()
								$MetaList = @()
								
								# Iterate through each tag in $TagList
								# $stopwatch2 = [System.Diagnostics.Stopwatch]::StartNew()
								$TagList | ForEach-Object {
									if ($AddGeneralTags -and $tagSetGeneral -contains $_) {
										# Write-Host "Tag $_ is an general tag."
										$GeneralList += $_
										
									} elseif ($AddMetaTags -and $tagSetMeta -contains $_) {
										# Write-Host "Tag $_ is an meta tag."
										$MetaList += $_
										
									} elseif ($AddCopyrightTags -and $tagSetCopyright -contains $_) {
										# Write-Host "Tag $_ is an copyright tag."
										$CopyrightList += $_
										
									} elseif ($AddCharacterTags -and $tagSetCharacters -contains $_) {
										# Write-Host "Tag $_ is a character tag."
										$CharacterList += $_
										
									} elseif ($AddArtistTags -and $tagSetArtists -contains $_) {
										# Write-Host "Tag $_ is an artist tag."
										$ArtistList += $_
									}
								}
								
								$CharacterListString = ""
								$ArtistListString = ""
								$GeneralListString = ""
								$CopyrightListString = ""
								$MetaListString = ""
								
								# Join the lists with spaces
								if ($AddArtistTags) {
									$ArtistListString = $ArtistList -join " + "
								} 
								if ($AddCharacterTags) {
									$CharacterListString = $CharacterList -join " + "
								} 
								if ($AddGeneralTags) {
									$GeneralListString = $GeneralList -join " "
								} 
								if ($AddCopyrightTags) {
									$CopyrightListString = $CopyrightList -join " "
								} 
								if ($AddMetaTags) {
									$MetaListString = $MetaList -join " "
								}
##########################################################
								if ($AddFileSourceMetadata) {
									$FileSource = $File.source	
								} else {
									$FileSource = ''
								}
								
								$temp_query = "INSERT INTO Files (id, url, hash, extension, width, height, createdAt, source, main_tag, tags_artist, tags_character, tags_general, tags_copyright, tags_meta, downloaded) 
															VALUES ('$FileID', '$FileUrl', '$FileHash', '$FileExtension', '$FileWidth', '$FileHeight', '$FileCreateDate', '$FileSource', '$QueryName', '$ArtistListString', '$CharacterListString', '$GeneralListString', '$CopyrightListString', '$MetaListString', 0);"
								$sqlScript += $temp_query + " "
								Write-Host "Added file $FileID to database." -ForegroundColor Green
								
								if ($CurItemCount -le 0 -or $i -ge $MetadataCountBeforeAdding) {
									$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
									#update last_id to the current $FileID
									$temp_query = "UPDATE Queries SET last_id = '$FileID' WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID;"
									$sqlScript += $temp_query + " "
									# End the transaction
									$sqlScript += "COMMIT;"  
									#execute all queries at once
									# Write-Host "$sqlScript"
									Write-Host "Executing queries..." -ForegroundColor Yellow
									Invoke-SqliteQuery -DataSource $DBFilePath -Query $sqlScript
									
									$stopwatch.Stop()
									Write-Host "Queries applied in $($stopwatch.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
									Write-Host "`n"
									
									$sqlScript = "BEGIN TRANSACTION; "  # Using transactions reduced query apply time by 14-16 times
									$i = 0 		#reset it
									
								}
								
								
							}
########################################################################################
						}
						
						#fixed fetching more pages when the skip limit is reached
						#this happened because the break only stopped the foreach loop
						if ($HasMoreFiles) {
							$Page++
							
							#max pages that the API can return for a query is 200, so do some logic here to keep going
							if ($Page -gt 200) {
								$IDString = " id:<$FileID"
								$Page = 1
							}
								
							$stopwatchBatch.Stop()
							Write-Host "Fetched metadata in $($stopwatchBatch.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
##########################################
						#handle errors like skip limit reached
						} else {
							Write-Host "No more files found for query $QueryName." -ForegroundColor Yellow
							
							#update the last_id column so that next time the query is run it starts from the begginning
							$temp_query = "UPDATE Queries SET last_id = 0 WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
							
							$HasMoreFiles = $false
							break       #stop fetching more data
						}
############################################
					} else {
						Write-Host "No more files found for query $QueryName." -ForegroundColor Yellow
						
						#update the last_id column so that next time the query is run it starts from the begginning
						$temp_query = "UPDATE Queries SET last_id = 0 WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID"
						Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
						
						$HasMoreFiles = $false
						break
					}
############################################
				} catch {
					if ($_.Exception.Response.StatusCode -eq 429 -or $_.Exception.Response.StatusCode -eq 502) {
						$delay = Calculate-Delay -retryCount $retryCount
						
						$retryCount++
						
						Write-Host "429/502 error encountered. Retrying in $delay milliseconds..." -ForegroundColor Red
						Start-Sleep -Milliseconds $delay
					} else {
						Write-Host "Failed to fetch files for query $($QueryName): $($_.Exception.Message)" -ForegroundColor Red
						$HasMoreFiles = $false
						break
					}
				}
############################################
			}
############################################
		}
		$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
		#update the last_time_fetched_metadata column
		$temp_query = "UPDATE Queries SET last_time_fetched_metadata = '$CurrentDate' WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID"
		Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
############################################
	}
}
############################################
#create database file if it doesn`t exist
Create-Database-If-It-Doesnt-Exist -SiteName "Rule34xxx" -DBFilePath $DBFilePath
############################################

###############################
## have to load tags from database and make a list from them
$tagSetGeneral = New-Object 'System.Collections.Generic.HashSet[String]'
$tagSetArtists = New-Object 'System.Collections.Generic.HashSet[String]'
$tagSetCharacters = New-Object 'System.Collections.Generic.HashSet[String]'
$tagSetCopyright = New-Object 'System.Collections.Generic.HashSet[String]'
$tagSetMeta = New-Object 'System.Collections.Generic.HashSet[String]'
###############################
# general tags
if ($LoadTagsFromDatabase_General) {
	$temp_query = "SELECT tag FROM tags_general"
	$tags = Invoke-SQLiteQuery -DataSource $TagDBFilePath -Query $temp_query
	# Convert the result to a hashset
    $tags | ForEach-Object { [void]$tagSetGeneral.Add($_.tag) }
} else {
	$tagListGeneral | ForEach-Object { [void]$tagSetGeneral.Add($_) }
}
$TempCount = $tagSetGeneral.Count
Write-Host "Loaded $TempCount general tags." -ForegroundColor Green
###############################
# artist tags
if ($LoadTagsFromDatabase_Artist) {
	$temp_query = "SELECT tag FROM tags_artist"
	$tags = Invoke-SQLiteQuery -DataSource $TagDBFilePath -Query $temp_query
	# Convert the result to a hashset
    $tags | ForEach-Object { [void]$tagSetArtists.Add($_.tag) }
} else {
	$tagListArtists | ForEach-Object { [void]$tagSetArtists.Add($_) }
}
$TempCount = $tagSetArtists.Count
Write-Host "Loaded $TempCount artist tags." -ForegroundColor Green
###############################
# character tags
if ($LoadTagsFromDatabase_Character) {
	$temp_query = "SELECT tag FROM tags_character"
	$tags = Invoke-SQLiteQuery -DataSource $TagDBFilePath -Query $temp_query
	# Convert the result to a hashset
    $tags | ForEach-Object { [void]$tagSetCharacters.Add($_.tag) }
} else {
	$tagListCharacters | ForEach-Object { [void]$tagSetCharacters.Add($_) }
}
$TempCount = $tagSetCharacters.Count
Write-Host "Loaded $TempCount character tags." -ForegroundColor Green
###############################
# copyright tags
if ($LoadTagsFromDatabase_Copyright) {
	$temp_query = "SELECT tag FROM tags_copyright"
	$tags = Invoke-SQLiteQuery -DataSource $TagDBFilePath -Query $temp_query
	# Convert the result to a hashset
    $tags | ForEach-Object { [void]$tagSetCopyright.Add($_.tag) }
} else {
	$tagListCopyright | ForEach-Object { [void]$tagSetCopyright.Add($_) }
}
$TempCount = $tagSetCopyright.Count
Write-Host "Loaded $TempCount copyright tags." -ForegroundColor Green
###############################
# meta tags
if ($LoadTagsFromDatabase_Meta) {
	$temp_query = "SELECT tag FROM tags_meta"
	$tags = Invoke-SQLiteQuery -DataSource $TagDBFilePath -Query $temp_query
	# Convert the result to a hashset
    $tags | ForEach-Object { [void]$tagSetMeta.Add($_.tag) }
} else {
	$tagListMeta | ForEach-Object { [void]$tagSetMeta.Add($_) }
}
$TempCount = $tagSetMeta.Count
Write-Host "Loaded $TempCount meta tags." -ForegroundColor Green
###############################
###############################



############################################
function Process-Queries {
	# Loop through the user list and download Files
	foreach ($Query in $QueryList) {
		$QueryName = $Query[0]
		$MinID = $Query[1]
		$MaxID = $Query[2]
		$Results_per_Page = $Query[3]
		$Query = $Query[4]
	
		Download-Metadata-From-Query -QueryName $QueryName -MinID $MinID -MaxID $MaxID -Results_per_Page $Results_per_Page -Query $Query
	}
}
############################################
function Show-Menu {
    param (
        [string]$Query = ""
    )
	try {
		# Start logging
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/Rule34xxx_$($CurrentDate).log" -Append
		$exitScript = $false
		while (-not $exitScript) {
			Write-Host "`nRule34xxx Powershell Downloader" -ForegroundColor Green
			Write-Host "`nSelect a option:" -ForegroundColor Green
			Write-Host "1. Download metadata from queries to database and then download Files." -ForegroundColor Green
			Write-Host "2. Download only metadata from queries to database." -ForegroundColor Green
			Write-Host "3. Download all files in database not already downloaded (skip metadata download)." -ForegroundColor Green
			Write-Host "4. Download files in database from query." -ForegroundColor Green
			Write-Host "5. Scan folder for files and add them to database marked as favorites." -ForegroundColor Green
			Write-Host "6. Exit script" -ForegroundColor Green
			
			$choice = $(Write-Host "`nType a number (1-6):" -ForegroundColor green -NoNewLine; Read-Host) 
#################################
			if ($choice -eq 1) {
				Backup-Database
				
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Process-Queries
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all metadata from queries in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -Type 1
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				[console]::beep()
#################################
			} elseif ($choice -eq 2){
				Backup-Database
				
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Process-Queries
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all metadata from queries in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				[console]::beep()
#################################
			} elseif ($choice -eq 3){
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -Type 1
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				[console]::beep()
#################################
			} elseif ($choice -eq 4){
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -Type 2 -Query $Query
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all files from query in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				[console]::beep()
#################################
			} elseif ($choice -eq 5){
				Backup-Database
				Scan-Folder-And-Add-Files-As-Favorites -Type 1
				[console]::beep()
#################################
			} elseif ($choice -eq 6){
				$exitScript = $true
#################################
			} else {
				Write-Host "`nInvalid choice. Try again." -ForegroundColor Red
			}
		}
#################################
	} catch {
		Write-Error "An error occurred (line $($_.InvocationInfo.ScriptLineNumber)): $($_.Exception.Message)"
	} finally {
		Stop-Transcript
		# Write-Output "Transcript stopped"
	}
}
##########################################################################
if ($Function) {
	try {
		# Start logging
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/Rule34xxx_$($CurrentDate).log" -Append
		switch ($Function) {
			'DownloadAllMetadataAndFiles' { 
				Backup-Database
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Process-Queries
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all metadata from queries in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -Type 1
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			}
			'DownloadAllMetadata' { 
				Backup-Database
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Process-Queries
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all metadata from queries in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			}
			'DownloadOnlyFiles' { 
				$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
				Download-Files-From-Database -Type 1
				$stopwatch_main.Stop()
				Write-Host "`nDownloaded all files from database in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
			}
			'DownloadFilesFromQuery' {
				if ([string]::IsNullOrWhiteSpace($Query)) {
					Write-Host "The -Query parameter is required for the DownloadFilesFromQuery function." -ForegroundColor Red
				} else {
					$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
					Download-Files-From-Database -Type 2 -Query $Query
					$stopwatch_main.Stop()
					Write-Host "`nDownloaded all files from query in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				}
			}
			'ScanFolderForFavorites' { 
				Backup-Database
				Scan-Folder-And-Add-Files-As-Favorites -Type 1
			}
			'DownloadMetadataForSingleQuery' {
				if ([string]::IsNullOrWhiteSpace($QueryName) -or [string]::IsNullOrWhiteSpace($Query)) {
					Write-Host "The -QueryName and -Query parameters are required for the DownloadMetadataForSingleQuery function." -ForegroundColor Red
				} else {
					Backup-Database
					$stopwatch_main = [System.Diagnostics.Stopwatch]::StartNew()
					Download-Metadata-From-Query -QueryName $QueryName -MinID $MinID -MaxID $MaxID -Results_per_Page $Results_per_Page -Query $Query
					$stopwatch_main.Stop()
					Write-Host "`nDownloaded metadata for query '$QueryName' in $($stopwatch_main.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
				}
			}
			default { Write-Host "Invalid function name: $Function" -ForegroundColor Red }
		}
##########################################################################
	} catch {
		Write-Error "An error occurred (line $($_.InvocationInfo.ScriptLineNumber)): $($_.Exception.Message)"
	} finally {
		Stop-Transcript
		[console]::beep()
		Pause
	}
##########################################################################
} else {
    Show-Menu
    [console]::beep()
    Pause
}
