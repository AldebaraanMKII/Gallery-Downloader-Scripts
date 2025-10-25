function Backup-Database {
	if ($BackupDBOnStart) {
		# Get the current date to use in the backup archive name
		$BackupFolderPath = "$PSScriptRoot/backups"
		$DateTime = Get-Date -Format "yyyyMMdd-HHmmss"
		$BackupFileName = "$DBFilename $DateTime.7z"
		$BackupFilePath = Join-Path -Path $BackupFolderPath -ChildPath $BackupFileName
		
		# Ensure folder exists
		if (-not (Test-Path $BackupFolderPath)) {
			New-Item -ItemType Directory -Path $BackupFolderPath | Out-Null
		}
		
		if (Test-Path $DBFilePath) {
			Write-Host "`nBacking up database..." -ForegroundColor Yellow
			7z a -t7z "$BackupFilePath" $DBFilePath > NUL
			Write-Host "Backed up database ($BackupFileName)." -ForegroundColor Green
		}
	}
}
###############################
function Check-WordFilter {
    param (
        [string]$Content,
        [string]$WordFilter,
        [string]$WordFilterExclude
    )

    # Debugging output
    # Write-Host "Content: $Content"
    # Write-Host "WordFilter: $WordFilter"
    # Write-Host "WordFilterExclude: $WordFilterExclude"

    if ($WordFilterExclude -ne "") {
        $ExcludeWords = $WordFilterExclude -split ', '
        foreach ($word in $ExcludeWords) {
            if ($Content -imatch $word) {   #imatch ignores case sensitivity
                # Write-Host "Excluded by word: $word"
                return $false
            }
        }
    }

    if ($WordFilter -ne "") {
        $IncludeWords = $WordFilter -split ', '
        foreach ($word in $IncludeWords) {
            if ($Content -imatch $word) {   #imatch ignores case sensitivity
                # Write-Host "Included by word: $word"
                return $true
            }
        }
	#if filter is empty, return true if passed the negative filter
    } else {
        return $true
    }

    return $false
}
###############################
function Convert-File {
    param (
        [PSCustomObject[]]$FileList,
        [string]$Folder
    )

    Write-Host "`nStarting file conversion..." -ForegroundColor Yellow
    $semaphore = [System.Threading.SemaphoreSlim]::new($MaxThreads, $MaxThreads)
    $stopwatchConvert = [System.Diagnostics.Stopwatch]::StartNew()
    
    # Write-Output $FileList
########################################################
	$FoundFilesToConvert = $false
    foreach ($file in $FileList) {
        $FilePath = $file.FilePath
        $FileName = $file.Filename
        $FileExtension = $file.FileExtension
        
        # Write-Host "Processing file $FilePath, $FileName, $FileExtension" -ForegroundColor Yellow
########################################################
		# $FileListToConvert | ForEach-Object { Write-Host "Item: $_" }
        foreach ($item in $FileListToConvert) {
            $extension = $item[0]
            $MinimumSize = $item[1]
            $ConvertFileType = $item[2]
            $ConvertFileCommands = $item[3]
			# Write-Host "FileListToConvert: $extension, $MinimumSize, $ConvertFileType, $ConvertFileCommands"
########################################################
            # if ($FileExtension.ToString() -like "*$extension*") {
            if ($FileExtension -like "*$extension*") {
				# Replace your file size check with this
				try {
					# Write-Host "Full file path: '$FilePath'" -ForegroundColor Cyan 
					# Write-Host "File exists: $(Test-Path -LiteralPath $FilePath)" -ForegroundColor Cyan
					
					# Try alternative method to get file size
					$fileSize = (Get-ChildItem -LiteralPath $FilePath -ErrorAction Stop).Length
					# Write-Host "File size using Get-ChildItem: $fileSize bytes" -ForegroundColor Cyan
########################################################
					if ($fileSize -eq 0) {
						# Try another alternative for file size
						$fileSize = [System.IO.FileInfo]::new($FilePath).Length
						Write-Host "File size using System.IO.FileInfo: $fileSize bytes" -ForegroundColor Cyan
					}
					
					$fileSizeInBytes = $fileSize
					$MinimumSizeInBytes = $MinimumSize * 1KB
					
					$fileSizeInKB = [math]::Round($fileSizeInBytes / 1KB)
					Write-Host "Filesize is $fileSizeInKB KB. Minimum size is $MinimumSize KB - $FileName" -ForegroundColor Cyan
########################################################
					if ($fileSizeInBytes -ge $MinimumSizeInBytes) {
						# Write-Host "Converting $FileExtension to $($ConvertFileType)..." -ForegroundColor Green
						$FoundFilesToConvert = $true
########################################################
						Start-Job -ScriptBlock {
							param (
								$FilePath,
								$FileName,
								$ConvertFileType,
								$ConvertFileCommands,
								$Folder,
								$SaveConvertedFileSubfolder,
								$RemoveOriginalFileAfterConversion
							)
########################################################
							try {
								if ($SaveConvertedFileSubfolder) {
									$ConvertedFolder = Join-Path $Folder "Converted"
									if (-not (Test-Path -LiteralPath $ConvertedFolder)) {
										New-Item -ItemType Directory -Path $ConvertedFolder | Out-Null
									}
									$outputPath = Join-Path $ConvertedFolder "$FileName.$ConvertFileType"
								} else {
									$outputPath = Join-Path $Folder "$FileName.$ConvertFileType"
								}

								$ffmpegCommand = "ffmpeg -i `"$FilePath`" $ConvertFileCommands `"$outputPath`" -loglevel quiet"
								# Write-Host "Executing command: $ffmpegCommand" -ForegroundColor Cyan
								Invoke-Expression $ffmpegCommand *> $null
								
								# $FoundFilesToConvert = $true
								if ($RemoveOriginalFileAfterConversion) {
									# Write-Host "Removing original file: $FileName" -ForegroundColor Magenta
									Remove-Item -LiteralPath $FilePath
								}
########################################################
									} catch {
										Write-Error "Error during conversion: $($_.Exception.Message)"
									}
								
														} -ArgumentList $FilePath, $FileName, $ConvertFileType, $ConvertFileCommands, $Folder, $SaveConvertedFileSubfolder, $RemoveOriginalFileAfterConversion *> $null
								break
					}
########################################################
				} catch {
					Write-Host "Error accessing file: $($_.Exception.Message)" -ForegroundColor Red
				}
########################################################
            }
########################################################
        }
########################################################
    }
    Get-Job | Wait-Job *> $null
    Get-Job | Receive-Job *> $null
    Get-Job | Remove-Job *> $null

    $stopwatchConvert.Stop()
	
	if ($FoundFilesToConvert) {
		Write-Host "Converted all files in $($stopwatchConvert.Elapsed.TotalSeconds) seconds." -ForegroundColor Green
		Write-Host "`n" -ForegroundColor Green
	} else {
		Write-Host "No files meet the conversion requirements." -ForegroundColor Yellow
	}
}
########################################################

###############################
function Calculate-Delay {
    param (
        [int]$retryCount
    )
		
		if ($retryCount -eq 0){
			$delay = $initialDelay
			return $delay
		} else {
			$delay = $initialDelay * [math]::Pow(2, $retryCount)
			return $delay
		}
		
		if ($delay -gt $MaxDelay){
			$delay = $MaxDelay
			return $delay
		}
}
###############################
# Function to scan a folder
function Scan-Folder-And-Add-Files-As-Favorites {
    param (
        [int]$Type
    )
    
    # Define the allowed file extensions
    $allowedExtensions = @("*.jpg", "*.jpeg", "*.png", "*.bmp", "*.gif", "*.webp", "*.avif", "*.mp4", "*.mkv", "*.webm")
    
    Write-Host "Processing directory: $FavoriteScanFolder" -ForegroundColor Yellow
    
    # Get files matching the extensions
    $files = Get-ChildItem -Path $FavoriteScanFolder -File -Recurse -Include $allowedExtensions
    
    # Set up type-specific patterns and queries
    switch ($Type) {
        1 { # Rule34xxx/Gelbooru - MD5/SHA-1
            $idPattern = "[0-9a-fA-F]{40}|[0-9a-fA-F]{32}"
            $FoundMessage = "Found MD5/SHA-1:"
            $Column = "hash"
            $DataQuery = "SELECT id, url, hash, extension, createdAt, tags_artist, tags_character FROM Files"
        }
        2 { # CivitAI - UUID
            $idPattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
            $FoundMessage = "Found UUID:"
            $Column = "filename"
            $DataQuery = "SELECT id, filename, extension, width, height, url, createdAt, username FROM Files"
        }
        3 { # Kemono - SHA256
            $idPattern = "[0-9a-fA-F]{64}"
            $FoundMessage = "Found SHA256:"
            $Column = "hash"
            $DataQuery = "SELECT hash, hash_extension, filename, filename_extension, url, file_index, creatorName FROM Files"
        }
        4 { # DeviantArt - DeviantionID/UUID
            $idPattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
            $FoundMessage = "Found DeviantionID:"
            $Column = "deviationID"
            $DataQuery = "SELECT deviationID, src_url, extension, height, width, title, published_time, username FROM Files"
        }
    }
    
    # Prepare batch processing
    $batchSize = 500
    $matchedFiles = @()
    $renameOperations = @()
    $processedCount = 0
    
    foreach ($file in $files) {
        $fileName = $file.Name
        
        # Match the pattern in the filename
        if ($fileName -match $idPattern) {
            $PatternMatch = $matches[0] # Get the matched value
            $matchedFiles += @{
                PatternMatch = $PatternMatch
                FilePath = $file.FullName
                FileName = $fileName
                Extension = $file.Extension
                Directory = $file.DirectoryName
            }
            
            # Process in batches
            if ($matchedFiles.Count -ge $batchSize) {
                Process-BatchFiles -MatchedFiles $matchedFiles -Column $Column -DataQuery $DataQuery -Type $Type
                $processedCount += $matchedFiles.Count
                Write-Host "Processed $processedCount files so far..." -ForegroundColor Cyan
                $matchedFiles = @()
            }
        }
    }
    
    # Process any remaining files
    if ($matchedFiles.Count -gt 0) {
        Process-BatchFiles -MatchedFiles $matchedFiles -Column $Column -DataQuery $DataQuery -Type $Type
        $processedCount += $matchedFiles.Count
        Write-Host "Finished processing $processedCount total files." -ForegroundColor Cyan
    }
}
####################################################
function Process-BatchFiles {
    param (
        [array]$MatchedFiles,
        [string]$Column,
        [string]$DataQuery,
        [int]$Type
    )
    
    # Build batch update query for all matched files
    $updateValues = ($MatchedFiles.PatternMatch -join "','")
    # $updateValues = ($MatchedFiles.PatternMatch -join "`',`'")
    if ($updateValues) {
        $batchUpdateQuery = "UPDATE Files SET favorite = 1, downloaded = 1 WHERE $Column IN ('$updateValues')"
        Invoke-SqliteQuery -DataSource $DBFilePath -Query $batchUpdateQuery
        
        Write-Host "Processed $($MatchedFiles.Count) files - added as favorites to database." -ForegroundColor Green
        
        # Handle renaming if enabled
        if ($RenameFileFavorite) {
            Batch-Rename-Files -FilesToRename $matchedFiles -Column $Column -DataQuery $DataQuery -Type $Type
        }
    }
}
####################################################
function Batch-Rename-Files {
    param (
        [array]$FilesToRename,
        [string]$Column,
        [string]$DataQuery,
        [int]$Type
    )
    
    # Get all the necessary data in one query
    # $values = "'`" + ($FilesToRename.PatternMatch -join "`',`'") + "'`"
	$values = "'" + ($FilesToRename.PatternMatch -join "','") + "'"
    $fullDataQuery = "$DataQuery WHERE $Column IN ($values)"
    $results = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $fullDataQuery
    
    # Create a lookup dictionary for the results
    $resultLookup = @{}
    foreach ($row in $results) {
        $resultLookup[$row.$Column] = $row
    }
    
    # Process all rename operations
    $renameOperations = @()
    foreach ($file in $FilesToRename) {
        $row = $resultLookup[$file.PatternMatch]
        if ($row) {
            switch ($Type) {
                1 { # Rule34xxx/Gelbooru
                    $FileID, $FileDirectory, $FileHash, $FileExtension, $Filename = Create-Filename -row $row -Type 1
                    $NewFilePath = [System.IO.Path]::Combine($file.Directory, "$Filename$($file.Extension)")
                }
                2 { # CivitAI
                    $FileID, $Filename, $FileExtension, $FileURL, $FileFilename, $FileWidth = Create-Filename -row $row -Type 2
                    $NewFilePath = [System.IO.Path]::Combine($file.Directory, "$Filename$($file.Extension)")
                }
                3 { # Kemono
                    $FileHash, $FileHashExtension, $FileURL, $FileFilenameExtension, $Filename = Create-Filename -row $row -Type 3
                    $NewFilePath = [System.IO.Path]::Combine($file.Directory, "$Filename$($file.Extension)")
                }
                4 { # DeviantArt
                    $FileDeviationID, $FileExtension, $FileSrcURL, $FileTitle, $FileUsername, $Filename = Create-Filename -row $row -Type 4
                    $NewFilePath = [System.IO.Path]::Combine($file.Directory, "$Filename$($file.Extension)")
                }
            }
            
            $renameOperations += @{
                OldPath = $file.FilePath
                NewPath = $NewFilePath
            }
        }
    }
    
    # Execute all rename operations at once
    foreach ($op in $renameOperations) {
        try {
            Rename-Item -Path $op.OldPath -NewName $op.NewPath -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "Failed to rename file: $($op.OldPath)" -ForegroundColor Red
        }
    }
    
    Write-Host "Renamed $($renameOperations.Count) files." -ForegroundColor Cyan
}
####################################################
# Function to scan a folder
function Create-Filename {
    param (
        [PSCustomObject]$row,
        [int]$Type
    )
	
	# Define the invalid characters for Windows file names
	$invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''

########################################
	#Rule34xxx/Gelbooru
	if ($Type -eq 1) {
		$FileID = $row.id
		$FileDirectory = $row.url
		$FileTagsArtist = $row.tags_artist
		$FileTagsCharacter = $row.tags_character
		$FileWidth = $row.width
		$FileHeight = $row.height
		
		$FileHash = $row.hash
		$FileExtension = $row.extension
		$FileMainTag = $row.main_tag
		
		# Replace invalid characters with an empty string
		$FileTagsArtist = $FileTagsArtist -replace "[$invalidChars]", ''
		$FileTagsCharacter = $FileTagsCharacter -replace "[$invalidChars]", ''
				
		$FileCreateDate = $row.createdAt
		$FileCreateDateFormatted = [datetime]::ParseExact($FileCreateDate, "dd-MM-yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd")
		$FileCreateDateFormattedFull = [datetime]::ParseExact($FileCreateDate, "dd-MM-yyyy HH:mm:ss", $null).ToString("yyyy-MM-dd HH-mm-ss")
		
		#shorten length due to windows 255 character limit
		if ($FileTagsArtist.Length -gt 100) {
			$FileTagsArtist = $FileTagsArtist.Substring(0, 100)
		}
		if ($FileTagsCharacter.Length -gt 100) {
			$FileTagsCharacter = $FileTagsCharacter.Substring(0, 100)
		}
		
		# Determine the values for tags 
		$TagsArtist = if ($FileTagsArtist -ne "") { $FileTagsArtist } else { "anonymous" } 
		$TagsCharacter = if ($FileTagsCharacter -ne "") { $FileTagsCharacter } else { "unknown" } 
		
		# Replace placeholders with actual values 
		$Filename = $FilenameTemplate 
		$Filename = $Filename -replace '%TagsArtist%', $TagsArtist 
		$Filename = $Filename -replace '%TagsCharacter%', $TagsCharacter 
		$Filename = $Filename -replace '%ID%', $FileID 
		$Filename = $Filename -replace '%FileCreateDate%', $FileCreateDateFormatted 
		$Filename = $Filename -replace '%FileCreateDateFull%', $FileCreateDateFormattedFull 
		$Filename = $Filename -replace '%Width%', $FileWidth 
		$Filename = $Filename -replace '%Height%', $FileHeight 
		$Filename = $Filename -replace '%MD5%', $FileHash
		
		return $FileID, $FileDirectory, $FileHash, $FileExtension, $FileMainTag, $Filename
########################################
	#CivitAI
	} elseif ($Type -eq 2) {
		$FileID = $row.id
		# Write-Host "FileID: $FileID"
		$FileFilename = $row.filename
		$FileExtension = $row.extension
		$FileWidth = $row.width
		$FileHeight = $row.height
		$FileURL = $row.url
		if ($FileURL = 'NULL') {
			$FileURL = "xG1nkqKTMzGDvpLrqFT7WA"
		}
		
		$FileCreatedAt = $row.createdAt
		$FileUsername = $row.username
		
		$FileCreatedAtFormatted = [datetime]::ParseExact($FileCreatedAt, "yyyy-MM-dd HH:mm:ss", $null).ToString("yyyy-MM-dd")
		
		# Replace placeholders with actual values
		$Filename = $FilenameTemplate -replace '%Username%', $FileUsername `
									-replace '%FileID%', $FileID `
									-replace '%Filename%', $FileFilename `
									-replace '%FileWidth%', $FileWidth `
									-replace '%FileHeight%', $FileHeight `
									-replace '%FileCreatedAt%', $FileCreatedAtFormatted
									
		return $FileID, $Filename, $FileExtension, $FileURL, $FileFilename, $FileWidth, $FileUsername
########################################
	#Kemono
	} elseif ($Type -eq 3) {
		$FileHash = $row.hash
		$FileHashExtension = $row.hash_extension
		$FileFilename = $row.filename
		$FileFilenameExtension = $row.filename_extension
		$FileURL = $row.url
		$FileIndex = $row.file_index
		$FileCreatorName = $row.creatorName
		$PostID = $row.postID
		
		#empty initially
		$PostTitle = "unknown"
		$PostDatePublished = "unknown"
		$PostDatePublishedFormatted = "unknown"
		$PostDatePublishedFormattedShort = "unknown"
		$PostTotalFiles = "unknown"
		
		$query = "SELECT title, date_published, total_files FROM Posts WHERE postID = '$PostID';"
		$results = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $query
			
		if ($results.Count -gt 0) {
			$PostTitle = $results[0].title
			$PostDatePublished = $results[0].date_published
			
			$PostDatePublishedFormatted = [datetime]::ParseExact($PostDatePublished, "yyyy-MM-dd HH:mm:ss", $null).ToString("yyyy-MM-dd HH-mm-ss")
			$PostDatePublishedFormattedShort = [datetime]::ParseExact($PostDatePublished, "yyyy-MM-dd HH:mm:ss", $null).ToString("yyyy-MM-dd")
			
			$PostTotalFiles = $results[0].total_files
		}
		
		#shorten length due to windows 255 character limit
		if ($FileFilename.Length -gt 100) {
			$FileFilename = $FileFilename.Substring(0, 100)
		}
		
		#replace \ with /
		$FileURL = $FileURL.Replace("\","/")
		# Write-Host "Filename: $Filename"
		
		# Replace placeholders with actual values
		$Filename = $FilenameTemplate -replace '%CreatorName%', $FileCreatorName `
									-replace '%PostID%', $PostID `
									-replace '%PostTitle%', $PostTitle `
									-replace '%PostPublishDate%', $PostDatePublishedFormatted `
									-replace '%PostPublishDateShort%', $PostDatePublishedFormattedShort `
									-replace '%FileHash%', $FileHash `
									-replace '%Filename%', $FileFilename `
									-replace '%FileIndex%', $FileIndex `
									-replace '%PostTotalFiles%', $PostTotalFiles
									
		return $FileHash, $FileHashExtension, $FileURL, $FileFilenameExtension, $FileCreatorName, $Filename
########################################
	#DeviantArt
	} elseif ($Type -eq 4) {
		$FileDeviationID = $row.deviationID
		$FileSrcURL = $row.src_url
		$FileHeight = $row.height
		$FileWidth = $row.width
		$FileTitle = $row.title
		$FilePublishedTime = $row.published_time
		$FilePublishedTimeFormatted = [datetime]::ParseExact($FilePublishedTime, "yyyy-MM-dd HH:mm:ss", $null).ToString("yyyy-MM-dd")
		$FilePublishedTimeFormattedAll = [datetime]::ParseExact($FilePublishedTime, "yyyy-MM-dd HH:mm:ss", $null).ToString("yyyy-MM-dd HH-mm-ss")
		
		$FileExtension = $row.extension
		$FileExtension = $FileExtension.TrimStart('.')	#remove dot
		$FileUsername = $row.username
		
		# Write-Host "  username: $FileUsername" -ForegroundColor Cyan
				
		#remove invalid characters
		$FileTitle = $FileTitle -replace "[$invalidChars]", ''
		$FileTitle = $FileTitle.Replace("\", "")  #remove \
		$FileTitle = $FileTitle.Replace("/", "")  #remove /
		
		
		#shorten length due to windows 255 character limit
		if ($FileTitle.Length -gt 100) {
			$FileTitle = $FileTitle.Substring(0, 100)
		}
		
		# Replace placeholders with actual values
		$Filename = $FilenameTemplate -replace '%Username%', $FileUsername `
									-replace '%DeviationID%', $FileDeviationID `
									-replace '%Height%', $FileHeight `
									-replace '%Width%', $FileWidth `
									-replace '%Title%', $FileTitle `
									-replace '%PublishedTime%', $FilePublishedTimeFormattedAll `
									-replace '%PublishedTimeFormatted%', $FilePublishedTimeFormatted
									
		return $FileDeviationID, $FileExtension, $FileSrcURL, $FileTitle, $FileUsername, $Filename
	}
########################################
}
####################################################
# Function to handle download errors
function Handle-Errors {
    param (
        [int]$retryCount,
        [String]$ErrorMessage,
        [int]$StatusCode,
        [string]$Site,
        [int]$Type,
        [string]$FileIdentifier,
        [string]$Username
    )
	
########################################
	#Rule34xxx/Gelbooru - ID
	if ($Site -eq "Gelbooru_Based") {
		$DataQuery = "id = '$FileIdentifier'"
########################################
	#CivitAI - ID
	} elseif ($Site -eq "CivitAI") {
		$DataQuery = "id = '$FileIdentifier'"
########################################
	#Kemono - SHA256
	} elseif ($Site -eq "Kemono") {
		$DataQuery = "hash = '$FileIdentifier'"
########################################
	#DeviantArt - DeviantionID
	} elseif ($Site -eq "DeviantArt") {
		$DataQuery = "deviationID = '$FileIdentifier'"
	}
########################################
	#I/O errors
	if ($Type -eq 1) {
		if ($ErrorMessage -like "*There is not enough space on the disk*") {
			Write-Output "Error: Out of disk space." -ForegroundColor Red
			Exit #end script
#####################################
		}
		elseif ($ErrorMessage -like "*Unable to read data from the transport connection*") {
			$delay = Calculate-Delay -retryCount $retryCount
		
			$retryCount++
			Write-Output "Error: Connection forcibly closed by the remote host." -ForegroundColor Red

			Start-Sleep -Milliseconds $delay
			
			$BreakLoop = $false
			return $retryCount, $BreakLoop
#####################################
		}
		elseif ($ErrorMessage -like "*The response ended prematurely*") {
			$delay = Calculate-Delay -retryCount $retryCount
		
			$retryCount++
			Write-Output "Error: The response ended prematurely." -ForegroundColor Red

			Start-Sleep -Milliseconds $delay
			
			$BreakLoop = $false
			return $retryCount, $BreakLoop
#####################################
		}
		elseif ($ErrorMessage -like "*The SSL connection could not be established*") {
			$delay = Calculate-Delay -retryCount $retryCount
		
			$retryCount++
			Write-Output "Error: The response ended prematurely." -ForegroundColor Red

			Start-Sleep -Milliseconds $delay
			
			$BreakLoop = $false
			return $retryCount, $BreakLoop
#####################################
		}
		else {
			Write-Output "An IO exception occurred: $($ErrorMessage)" -ForegroundColor Red
			Exit #end script
		}
##########################################################################
	#General errors
	} elseif ($Type -eq 2) {
		if ($StatusCode -in 429, 500, 520) {
			$delay = Calculate-Delay -retryCount $retryCount
		
			$retryCount++
			
			if ($StatusCode -eq 429) {
				Write-Host "Error 429: Too Many Requests. Retrying in $delay milliseconds..." -ForegroundColor Red
			} elseif ($StatusCode -eq 500) {
				Write-Host "Error 500: Internal Server Error. Retrying in $delay milliseconds..." -ForegroundColor Red
			} elseif ($StatusCode -eq 520) {
				Write-Host "Error 520: Internal Server Error. Retrying in $delay milliseconds..." -ForegroundColor Red
			}
		
			Start-Sleep -Milliseconds $delay
			
			$BreakLoop = $false
			return $retryCount, $BreakLoop
#####################################
		} elseif ($StatusCode -in 404, 401) {
			if ($StatusCode -eq 404) {
				Write-Host "(ID: $FileIdentifier) Error 404. This means the file was deleted. It will be set to deleted in the database so that it's not processed again." -ForegroundColor Red
				$temp_query = "UPDATE Files SET deleted = 1 WHERE $DataQuery"
				Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
#####################################
			} elseif ($StatusCode -eq 401) {
				Write-Host "(ID: $FileIdentifier) Error 401. This means the file was locked by its creator, and you do not have access to it. It will be set to downloaded in the database so that it's not processed again." -ForegroundColor Red
				$temp_query = "UPDATE Files SET downloaded = 1 WHERE $DataQuery"
				Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
			}
			
			$BreakLoop = $true
			return $retryCount, $BreakLoop
#####################################
		} elseif ($ErrorMessage -like "*Could not find a part of the path*") {
			$retryCount++
			
			Write-Host "$ErrorMessage. Retrying..." -ForegroundColor Red

			Start-Sleep -Milliseconds $delay
			
			$BreakLoop = $false
			return $retryCount, $BreakLoop
#####################################
		} else {
			Write-Host "Failed to fetch file (ID: $FileIdentifier) for user $($Username): $($ErrorMessage)" -ForegroundColor Red
			$BreakLoop = $true
			return $retryCount, $BreakLoop
		}
		
	}
########################################
}
####################################################
function Start-Download {
    param (
        [string]$SiteName,  # Site name (e.g., "Gelbooru", "CivitAI", etc.)
        [PSCustomObject[]]$FileList,   #list of files to download
        [string]$PostContent = $null
    )

    $FileListForConversion = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    $FilesRemaining = $FileList.Count
    $CompletedFiles = 0
    
    Write-Host "Found $FilesRemaining files." -ForegroundColor Green
    
    # Create cancellation token source for graceful shutdown
    $CancellationTokenSource = [System.Threading.CancellationTokenSource]::new()
    
    # Register CTRL+C handler
    $null = Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -Action {
        Write-Host "`nCancellation requested. Stopping downloads..." -ForegroundColor Yellow
        $Event.MessageData.CancellationTokenSource.Cancel()
        $Event.MessageData.ShouldStop = $true
    } -MessageData @{ CancellationTokenSource = $CancellationTokenSource; ShouldStop = $false }
    
    # Create runspace pool for concurrent downloads
    $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxConcurrentDownloads)
    $RunspacePool.Open()
    
    # Script block for each download task (simplified and optimized)
    $DownloadScriptBlock = {
        param(
            $File,
            $SiteName,
            $DownloadBaseURL,
            $DownloadFolder,
            $invalidChars,
            $maxRetries,
            $DBFilePath,
            $CreateFilenameFunction,
            $HandleErrorsFunction,
            $InvokeSqliteQueryFunction,
            $FileIndex,
            $TotalFiles,
            $FilenameTemplate,
            $PostID,
            $PostTitle,
            $PostDatePublishedFormatted,
            $PostDatePublishedFormattedShort,
            $PostTotalFiles,
            [string]$PostContent = $null,
            $CancellationToken
        )
        
        # Check for cancellation at the start
        if ($CancellationToken.IsCancellationRequested) {
            return @{
                Success = $false
                FilePath = ""
                Filename = "Cancelled"
                FileExtension = ""
                Message = "Download cancelled"
                FileIndex = $FileIndex
                AlreadyExists = $false
                Cancelled = $true
            }
        }
        
        # Define functions in the runspace (only the definitions, not the full function objects)
        $CreateFilenameScriptBlock = [ScriptBlock]::Create("function Create-Filename { $CreateFilenameFunction }")
        $HandleErrorsScriptBlock = [ScriptBlock]::Create("function Handle-Errors { $HandleErrorsFunction }")
        $InvokeSqliteQueryScriptBlock = [ScriptBlock]::Create("function Invoke-SqliteQuery { $InvokeSqliteQueryFunction }")
        
        # Execute the function definitions
        . $CreateFilenameScriptBlock
        . $HandleErrorsScriptBlock  
        . $InvokeSqliteQueryScriptBlock
        
        try {
            # Process file based on site type
            switch ($SiteName) {
                "Gelbooru_Based" {
                    $FileID, $FileDirectory, $FileHash, $FileExtension, $MainTag, $Filename = Create-Filename -row $File -Type 1
                    $DownloadURL = "$($DownloadBaseURL)$($FileDirectory)/$($FileHash).$($FileExtension)"
                    $DownloadSubfolderIdentifier = "$MainTag"
                    $SetFileDownloadedQuery = "UPDATE Files SET downloaded = 1 WHERE id = '$FileID'"
                    $FileIdentifier = $FileID
                    $Username = ""
                }
                "CivitAI" {
                    $FileID, $Filename, $FileExtension, $FileURL, $FileFilename, $FileWidth, $Username = Create-Filename -row $File -Type 2
                    # $DownloadURL = "$($DownloadBaseURL)$($FileURL)$($FileFilename)/width=$FileWidth"
                    $DownloadURL = "$($DownloadBaseURL)$($FileURL)/$($FileFilename)/original=true/$($FileFilename)" #New 30-09-2025
                    $DownloadSubfolderIdentifier = "$Username"
                    $SetFileDownloadedQuery = "UPDATE Files SET downloaded = 1 WHERE id = '$FileID'"
                    $FileIdentifier = $FileID
					# Write-Host "Download URL: $DownloadURL" -ForegroundColor Blue
                }
                "Kemono" {
                    $FileHash, $FileExtension, $FileURL, $FileFilenameExtension, $CreatorName, $Filename = Create-Filename -row $File -Type 3
                    # $DownloadURL = "$($DownloadBaseURL)$($FileURL)/$($FileHash).$($FileExtension)"
                    $DownloadURL = "$($DownloadBaseURL)$($FileURL)/$($FileHash).$($FileExtension)?f=file.$($FileFilenameExtension)"
					
                    $DownloadSubfolderIdentifier = "$CreatorName"
                    $SetFileDownloadedQuery = "UPDATE Files SET downloaded = 1 WHERE hash = '$FileHash'"
                    $FileIdentifier = $FileHash
                    $Username = $CreatorName
                }
                "DeviantArt" {
                    $FileDeviationID, $FileExtension, $FileSrcURL, $FileTitle, $Username, $Filename = Create-Filename -row $File -Type 4
                    
                    if ($FileExtension -in @(".mp4", ".mkv", ".webm", ".av1")) {
                        $DownloadURL = "https://wixmp-$($FileSrcURL)"
                    } else {
                        $DownloadURL = "https://images-wixmp-$($FileSrcURL)"
                    }
                    
                    $DownloadSubfolderIdentifier = "$Username"
                    $SetFileDownloadedQuery = "UPDATE Files SET downloaded = 1 WHERE deviationID = '$FileDeviationID'"
                    $FileIdentifier = $FileDeviationID
                }
            }
            
			# Write-Host "Download URL: $DownloadURL"
					
            # Clean filename
            $Filename = $Filename -replace "[$invalidChars]", ''
            
            # Define download path
            $DownloadSubFolder = Join-Path $DownloadFolder "$DownloadSubfolderIdentifier"
            $FilePath = Join-Path $DownloadSubFolder "$Filename.$FileExtension"
            
            # Ensure download folder exists
            if (-not (Test-Path $DownloadSubFolder)) {
                $null = New-Item -ItemType Directory -Path $DownloadSubFolder -Force
            }

            # Write post content to a text file
            if (-not [string]::IsNullOrEmpty($PostContent)) {
                $PostContentPath = Join-Path $DownloadSubFolder "post_content.txt"
                Set-Content -Path $PostContentPath -Value $PostContent -Encoding UTF8
            }
            
            $result = @{
                Success = $false
                FilePath = $FilePath
                Filename = $Filename
                FileExtension = $FileExtension
                Message = ""
                FileIndex = $FileIndex
                AlreadyExists = $false
                Cancelled = $false
            }
            
            # Check for cancellation before download
            if ($CancellationToken.IsCancellationRequested) {
                $result.Cancelled = $true
                $result.Message = "Download cancelled"
                return $result
            }
            
            # Download logic
            if (-not (Test-Path $FilePath)) {
                $retryCount = 0
                $downloadSuccessful = $false
                $handledError = $false
                $handledErrorMessage = ""
                
                # Output progress immediately using Write-Output instead of Write-Host
                Write-Output "($FileIndex of $TotalFiles) Starting download: $Filename"
                
                while ($retryCount -lt $maxRetries -and -not $downloadSuccessful -and -not $handledError) {
                    # Check for cancellation before each retry
                    if ($CancellationToken.IsCancellationRequested) {
                        $result.Cancelled = $true
                        $result.Message = "Download cancelled"
                        return $result
                    }
                    
                    try {
                        # Create HttpWebRequest for better error handling
                        $request = [System.Net.HttpWebRequest]::Create($DownloadURL)
                        $request.Method = "GET"
                        $request.Timeout = 30000  # 30 seconds timeout
                        $request.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                        
                        # Get response
                        $response = $request.GetResponse()
                        $httpResponse = $response -as [System.Net.HttpWebResponse]
                        
                        $responseStream = $response.GetResponseStream()
                        
                        # Create file stream
                        $fileStream = [System.IO.File]::Create($FilePath)
                        
                        # Copy data with cancellation support
                        $buffer = New-Object byte[] 8192
                        $totalBytesRead = 0
                        do {
                            if ($CancellationToken.IsCancellationRequested) {
                                $fileStream.Close()
                                $responseStream.Close()
                                $response.Close()
                                if (Test-Path $FilePath) { Remove-Item $FilePath -Force }
                                $result.Cancelled = $true
                                $result.Message = "Download cancelled"
                                return $result
                            }
                            
                            $bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)
                            if ($bytesRead -gt 0) {
                                $fileStream.Write($buffer, 0, $bytesRead)
                                $totalBytesRead += $bytesRead
                            }
                        } while ($bytesRead -gt 0)
                        
                        # Get actual file size
                        $fileSize = $fileStream.Length
                        
                        # Clean up streams
                        $fileStream.Close()
                        $responseStream.Close()
                        $response.Close()
                        
                        # Check if file is actually valid (not empty or error page)
                        if ($fileSize -eq 0) {
                            Remove-Item $FilePath -Force
                            throw [System.Exception]::new("Downloaded file is empty")
                        }
                        
                        # Update database
                        Invoke-SqliteQuery -DataSource $DBFilePath -Query $SetFileDownloadedQuery
                        
                        $result.Success = $true
                        $result.Message = "Downloaded successfully"
                        $downloadSuccessful = $true
                        
                    } catch [System.Net.WebException] {
                        $BreakLoop = $false
                        $ErrorMessage = $_.Exception.Message
                        $StatusCode = 0
                        
                        # Get HTTP status code from WebException
                        if ($_.Exception.Response) {
                            $httpResponse = $_.Exception.Response -as [System.Net.HttpWebResponse]
                            if ($httpResponse) {
                                $StatusCode = [int]$httpResponse.StatusCode
                                $StatusDescription = $httpResponse.StatusDescription
                                $httpResponse.Close()
                            }
                        }
                        
                        # Clean up any partial file
                        if (Test-Path $FilePath) {
                            try { Remove-Item $FilePath -Force } catch { }
                        }
                        
                        $retryCount, $BreakLoop = Handle-Errors -retryCount $retryCount -ErrorMessage $ErrorMessage -StatusCode $StatusCode -Site $SiteName -Type 2 -FileIdentifier $FileIdentifier -Username $Username
                        
                        if ($BreakLoop) {
                            $handledError = $true
                            if ($StatusCode -eq 404) {
                                $handledErrorMessage = "File was deleted (404 error) - marked as deleted in database"
                            } elseif ($StatusCode -eq 401) {
                                $handledErrorMessage = "File is locked/private (401 error) - marked as downloaded in database"
                            } else {
                                $handledErrorMessage = "HTTP Error $StatusCode`: $ErrorMessage"
                            }
                            break
                        }
                        
                    } catch [System.IO.IOException] {
                        $BreakLoop = $false
                        $ErrorMessage = $_.Exception.Message
                        
                        # Clean up any partial file
                        if (Test-Path $FilePath) {
                            try { Remove-Item $FilePath -Force } catch { }
                        }
                        
                        $retryCount, $BreakLoop = Handle-Errors -retryCount $retryCount -ErrorMessage $ErrorMessage -StatusCode 0 -Site $SiteName -Type 1 -FileIdentifier $FileIdentifier -Username $Username
                        
                        if ($BreakLoop) {
                            $handledError = $true
                            $handledErrorMessage = "IO Error: $ErrorMessage"
                            break
                        }
                        
                    } catch [System.UnauthorizedAccessException] {
                        $BreakLoop = $false
                        $ErrorMessage = $_.Exception.Message
                        
                        $retryCount, $BreakLoop = Handle-Errors -retryCount $retryCount -ErrorMessage $ErrorMessage -StatusCode 403 -Site $SiteName -Type 2 -FileIdentifier $FileIdentifier -Username $Username
                        
                        if ($BreakLoop) {
                            $handledError = $true
                            $handledErrorMessage = "Access Error: $ErrorMessage"
                            break
                        }
                        
                    } catch {
                        $BreakLoop = $false
                        $StatusCode = 0
                        $ErrorMessage = $_.Exception.Message
                        
                        # Clean up any partial file
                        if (Test-Path $FilePath) {
                            try { Remove-Item $FilePath -Force } catch { }
                        }
                        
                        # Check if this is actually a WebException that wasn't caught above
                        if ($_.Exception -is [System.Net.WebException]) {
                            $webEx = $_.Exception -as [System.Net.WebException]
                            if ($webEx.Response) {
                                $httpResponse = $webEx.Response -as [System.Net.HttpWebResponse]
                                if ($httpResponse) {
                                    $StatusCode = [int]$httpResponse.StatusCode
                                    $httpResponse.Close()
                                }
                            }
                        }
                        
                        # Try to extract status code from error message patterns
                        if ($StatusCode -eq 0) {
                            if ($ErrorMessage -match "404|Not Found") {
                                $StatusCode = 404
                            } elseif ($ErrorMessage -match "403|Forbidden|Unauthorized") {
                                $StatusCode = 403
                            } elseif ($ErrorMessage -match "500|Internal Server Error") {
                                $StatusCode = 500
                            } elseif ($ErrorMessage -match "429|Too Many Requests") {
                                $StatusCode = 429
                            } elseif ($ErrorMessage -match "502|Bad Gateway") {
                                $StatusCode = 502
                            } elseif ($ErrorMessage -match "503|Service Unavailable") {
                                $StatusCode = 503
                            }
                        }
                        
                        $retryCount, $BreakLoop = Handle-Errors -retryCount $retryCount -ErrorMessage $ErrorMessage -StatusCode $StatusCode -Site $SiteName -Type 2 -FileIdentifier $FileIdentifier -Username $Username
                        
                        if ($BreakLoop) {
                            $handledError = $true
                            if ($StatusCode -eq 404) {
                                $handledErrorMessage = "File was deleted (404 error) - marked as deleted in database"
                            } elseif ($StatusCode -eq 401) {
                                $handledErrorMessage = "File is locked/private (401 error) - marked as downloaded in database"
                            } else {
                                $handledErrorMessage = "General Error (Status: $StatusCode): $ErrorMessage"
                            }
                            break
                        }
                    }
                    
                    # Add delay between retries (with cancellation check)
                    if ($retryCount -lt $maxRetries -and -not $downloadSuccessful -and -not $handledError) {
                        $delaySeconds = [Math]::Min(2 * $retryCount, 10)
                        for ($i = 0; $i -lt $delaySeconds; $i++) {
                            if ($CancellationToken.IsCancellationRequested) {
                                $result.Cancelled = $true
                                $result.Message = "Download cancelled"
                                return $result
                            }
                            Start-Sleep -Seconds 1
                        }
                    }
                }
                
                # Set the appropriate result message
                if ($downloadSuccessful) {
                    # Already set above
                } elseif ($handledError) {
                    $result.Message = $handledErrorMessage
                } else {
                    $result.Message = "Failed after $maxRetries attempts"
                }
                
            } else {
                # File already exists
                Invoke-SqliteQuery -DataSource $DBFilePath -Query $SetFileDownloadedQuery
                $result.Success = $true
                $result.AlreadyExists = $true
                $result.Message = "File already exists"
            }
            
            return $result
            
        } catch {
            return @{
                Success = $false
                FilePath = ""
                Filename = if ($Filename) { $Filename } else { "Unknown" }
                FileExtension = if ($FileExtension) { $FileExtension } else { "" }
                Message = "Error processing file: $($_.Exception.Message)"
                FileIndex = $FileIndex
                AlreadyExists = $false
                Cancelled = $false
            }
        }
    }
    
    # Get function definitions as strings to pass to runspaces
    $CreateFilenameFunction = Get-Command Create-Filename | Select-Object -ExpandProperty Definition
    $HandleErrorsFunction = Get-Command Handle-Errors | Select-Object -ExpandProperty Definition  
    $InvokeSqliteQueryFunction = Get-Command Invoke-SqliteQuery | Select-Object -ExpandProperty Definition
    
    # Process files in batches to manage memory usage
    # $BatchSize = [Math]::Min(100, $MaxConcurrentDownloads * 200)  # Process in batches
    $BatchSize = $MaxConcurrentDownloads * 1000  # Process in batches
    $ProcessedFiles = 0
    $FilesForConversion = @()
    
    for ($BatchStart = 0; $BatchStart -lt $FileList.Count; $BatchStart += $BatchSize) {
        $BatchEnd = [Math]::Min($BatchStart + $BatchSize - 1, $FileList.Count - 1)
        $CurrentBatch = $FileList[$BatchStart..$BatchEnd]
        
        Write-Host "Processing batch: files $($BatchStart + 1) to $($BatchEnd + 1) of $($FileList.Count)" -ForegroundColor Cyan
        
        # Create jobs for current batch
        $Jobs = @()
        
        foreach ($File in $CurrentBatch) {
            # Check for cancellation
            if ($CancellationTokenSource.Token.IsCancellationRequested) {
                Write-Host "Cancellation requested. Stopping job creation..." -ForegroundColor Yellow
                break
            }
            
            $ProcessedFiles++
            
            # Create PowerShell instance
            $PowerShell = [powershell]::Create()
            $PowerShell.RunspacePool = $RunspacePool
            
            # Add script and parameters
            [void]$PowerShell.AddScript($DownloadScriptBlock)
            [void]$PowerShell.AddArgument($File)
            [void]$PowerShell.AddArgument($SiteName)
            [void]$PowerShell.AddArgument($DownloadBaseURL)
            [void]$PowerShell.AddArgument($DownloadFolder)
            [void]$PowerShell.AddArgument($invalidChars)
            [void]$PowerShell.AddArgument($maxRetries)
            [void]$PowerShell.AddArgument($DBFilePath)
            [void]$PowerShell.AddArgument($CreateFilenameFunction)
            [void]$PowerShell.AddArgument($HandleErrorsFunction)
            [void]$PowerShell.AddArgument($InvokeSqliteQueryFunction)
            [void]$PowerShell.AddArgument($ProcessedFiles)
            [void]$PowerShell.AddArgument($FilesRemaining)
            [void]$PowerShell.AddArgument($FilenameTemplate)
            [void]$PowerShell.AddArgument($PostID)
            [void]$PowerShell.AddArgument($PostTitle)
            [void]$PowerShell.AddArgument($PostDatePublishedFormatted)
            [void]$PowerShell.AddArgument($PostDatePublishedFormattedShort)
            [void]$PowerShell.AddArgument($PostTotalFiles)
            [void]$PowerShell.AddArgument($PostContent)
            [void]$PowerShell.AddArgument($CancellationTokenSource.Token)
            
            # Start the job
            $AsyncResult = $PowerShell.BeginInvoke()
            
            $Jobs += [PSCustomObject]@{ 
                PowerShell = $PowerShell
                AsyncResult = $AsyncResult
                FileIndex = $ProcessedFiles
            }
        }
        
        # Wait for current batch jobs to complete
        $CompletedJobs = 0
        
        while ($CompletedJobs -lt $Jobs.Count -and -not $CancellationTokenSource.Token.IsCancellationRequested) {
            foreach ($Job in $Jobs) {
                if ($Job.AsyncResult.IsCompleted -and $Job.PowerShell) {
                    try {
                        $Result = $Job.PowerShell.EndInvoke($Job.AsyncResult)
                        
                        if ($Result.Cancelled) {
                            Write-Host "($($Job.FileIndex) of $FilesRemaining) Download cancelled: $($Result.Filename)" -ForegroundColor Yellow
                        } elseif ($Result.Success) {
                            if ($Result.AlreadyExists) {
                                Write-Host "($($Job.FileIndex) of $FilesRemaining) File $($Result.Filename) already exists, skipping..." -ForegroundColor Yellow
                            } else {
                                Write-Host "($($Job.FileIndex) of $FilesRemaining) Downloaded file $($Result.Filename).$($Result.FileExtension)" -ForegroundColor Green
                                
                                # Add to conversion list
                                $fileObject = [PSCustomObject]@{ 
                                    FilePath      = $Result.FilePath
                                    Filename      = $Result.Filename
                                    FileExtension = $Result.FileExtension
                                }
                                $FilesForConversion += $fileObject
                            }
                        } else {
                            Write-Host "($($Job.FileIndex) of $FilesRemaining) Failed: $($Result.Filename) - $($Result.Message)" -ForegroundColor Red
                        }
                        
                    } catch {
                        Write-Host "Error retrieving job result: $($_.Exception.Message)" -ForegroundColor Red
                    } finally {
                        # Clean up immediately to free memory
                        $Job.PowerShell.Dispose()
                        $Job.PowerShell = $null
                        $CompletedJobs++
                    }
                }
            }
            
            # Small delay to prevent busy waiting
            Start-Sleep -Milliseconds 50
        }
        
        # Force garbage collection after each batch
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
        
        # Break if cancellation was requested
        if ($CancellationTokenSource.Token.IsCancellationRequested) {
            Write-Host "Cancellation requested. Stopping batch processing..." -ForegroundColor Yellow
            break
        }
    }
    
    # Clean up
    $RunspacePool.Close()
    $RunspacePool.Dispose()
    $CancellationTokenSource.Dispose()
    
    # Unregister the event handler
    Get-EventSubscriber | Where-Object { $_.SourceObject -eq [Console] } | Unregister-Event
    
    # Handle file conversion if needed
    if ($ConvertFiles -and $FilesForConversion.Count -gt 0 -and -not $CancellationTokenSource.Token.IsCancellationRequested) {
        # Group files by subfolder for conversion
        $FileGroups = $FilesForConversion | Group-Object { Split-Path (Split-Path $_.FilePath -Parent) -Leaf }
        
        foreach ($group in $FileGroups) {
            $SubfolderPath = Join-Path $DownloadFolder $group.Name
            Convert-File -FileList $group.Group -Folder $SubfolderPath
        }
    }
    
    if ($CancellationTokenSource.Token.IsCancellationRequested) {
        Write-Host "Downloads were cancelled by user." -ForegroundColor Yellow
    } else {
        Write-Host "All downloads completed!" -ForegroundColor Green
    }
}
######################################

############################################
function Check-if-Refresh-Token-Expired {
	$temp_query = "SELECT EXISTS(SELECT 1 from Auth WHERE refresh_token IS NOT NULL);"
	$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
	$exists = $result."EXISTS(SELECT 1 from Auth WHERE refresh_token IS NOT NULL)"
########################
	# Check the result
	if (!$exists) {
		#no refresh token found
		return $true
########################
	}	else {
		#refresh token found, check if it expired
		$temp_query = "SELECT refresh_token_creation_date FROM Auth"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
########################
		# Check the result
		if ($result.Count -gt 0) {
			if (-not [string]::IsNullOrWhiteSpace($result[0].refresh_token_creation_date)) {
				$DateCreated = $result[0].refresh_token_creation_date
				
				# Ensure both dates are DateTime objects
				$CurrentDate = [datetime]::ParseExact((Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "yyyy-MM-dd HH:mm:ss", $null)
				$DateCreated = [datetime]::ParseExact($DateCreated, "yyyy-MM-dd HH:mm:ss", $null)

				$DaysDifference = ($CurrentDate - $DateCreated).Days
				# Write-Host "DaysDifference: $DaysDifference"
				
				if ($DaysDifference -ge 89) {
					#expired
					return $true
				}	else {
					$TimeToExpire = 90 - $DaysDifference
					Write-Host "`nRefresh token will expire in $TimeToExpire days." -ForegroundColor Yellow
					return $false
				}
########################
			#refresh_token_creation_date = NULL
			} else {
				return $true
			}
########################
		}
########################
	}
########################
}
########################

############################################
function Check-if-Access-Token-Expired {
	$temp_query = "SELECT EXISTS(SELECT 1 from Auth WHERE access_token IS NOT NULL);"
	$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
	$exists = $result."EXISTS(SELECT 1 from Auth WHERE access_token IS NOT NULL)"
########################
	# Check the result
	if (!$exists) {
		#no access token found
		return $true
########################
	}	else {
		#access token found, check if it expired
		$temp_query = "SELECT access_token_creation_date FROM Auth"
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
########################
		# Check the result
		if ($result.Count -gt 0) {
			if (-not [string]::IsNullOrWhiteSpace($result[0].access_token_creation_date)) {
				$DateCreated = $result[0].access_token_creation_date
				
				# Ensure both dates are DateTime objects
				$CurrentDate = [datetime]::ParseExact((Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "yyyy-MM-dd HH:mm:ss", $null)
				$DateCreated = [datetime]::ParseExact($DateCreated, "yyyy-MM-dd HH:mm:ss", $null)

				# Write-Host "CurrentDate: $CurrentDate"
				# Write-Host "DateCreated: $DateCreated"
				
				$SecondsDifference = ($CurrentDate - $DateCreated).TotalSeconds
				# Write-Host "SecondsDifference: $SecondsDifference"
				
				if ($SecondsDifference -gt 3500) {
					#expired
					return $true
				}	else {
					$TimeToExpire = 3600 - $SecondsDifference
					Write-Host "`nAccess token will expire in $TimeToExpire seconds." -ForegroundColor Yellow
					return $false
				}
########################
			#access_token_creation_date = NULL
			} else {
				return $true
			}
########################
		}
########################
	}
########################
}
########################

########################
# All access_token's expire after 1 hour, after expiration you either need to re-authorize the app or refresh your access token using the refresh_token from the /token request.
# The refresh_token will expire after 3 months, after that time you must re-authorize the app. 
# returns the access token
function Get-Tokens-From-Authorization-Code {
	Write-Host "`nRefresh token expired or doesn't exist. Getting a new one..." -ForegroundColor Yellow
	
	$authUrl = "https://www.deviantart.com/oauth2/authorize?response_type=code&client_id=$client_id&redirect_uri=$redirect_uri&scope=$scope&state=$state"

	Write-Host "Opening default browser and redirecting to authorization URL..." -ForegroundColor Yellow
	Write-Host "After the authorization is complete, copy the code and paste it into the console." -ForegroundColor Yellow
	Start-Process $authUrl
	$ExitFunction = $false
####################################
	while (!$ExitFunction) {
		$AuthorizationCode = $(Write-Host "`nPlease type the authorization code you got from your browser: " -ForegroundColor green -NoNewLine; Read-Host) 
	
		$body = @{
			grant_type = "authorization_code"
			client_id = $client_id
			client_secret = $client_secret
			redirect_uri = $redirect_uri
			code = $AuthorizationCode
		}
####################################
		try {
			$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			$Response = Invoke-RestMethod -Uri "https://www.deviantart.com/oauth2/token" -Method Post -Body $body
			# $Response
			
			#this expires in one hour
			$Access_Token = $Response.access_token
			#this expires in 3 months
			$Refresh_Token = $Response.refresh_token
			# return $access_token, $refresh_token
			
			$temp_query = "SELECT EXISTS(SELECT 1 from Auth WHERE refresh_token IS NOT NULL);"
			$result = Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
			$exists = $result."EXISTS(SELECT 1 from Auth WHERE refresh_token IS NOT NULL)"
####################################
			# Check the result
			if ($exists -eq 0) {
				#no refresh token found, insert it into table
				$temp_query = "INSERT INTO Auth (access_token, access_token_creation_date, refresh_token, refresh_token_creation_date)
											VALUES ('$Access_Token', '$CurrentDate', '$Refresh_Token', '$CurrentDate')"
				Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
				Write-Host "`nAdded new access and refresh tokens to database." -ForegroundColor Green
				$ExitFunction = $true
				return $Access_Token
			} else {
				#refresh token found, update it
				$temp_query = "UPDATE Auth SET access_token = '$Access_Token', access_token_creation_date = '$CurrentDate', refresh_token = '$Refresh_Token', refresh_token_creation_date = '$CurrentDate'"
				Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
				Write-Host "`nAdded new access and refresh tokens to database." -ForegroundColor Green
				$ExitFunction = $true
				return $Access_Token
			}
####################################
		#errors
		} catch {
			if ($Response.error -eq "invalid_request") {
				Write-Host "Authorization code is invalid!" -ForegroundColor Yellow
			} else {
				Write-Host "(Get-Tokens-From-Authorization-Code) An unexpected error occurred: $($_.Exception.Message)" -ForegroundColor Red
			}
####################################
		}
####################################
	}
####################################
}
####################################

########################
# If the access_token expires after 1 hour, you can refresh it using the refresh_token.
function Refresh-Access-Token {
	$temp_query = "SELECT refresh_token FROM Auth"
	$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
	$Refresh_Token = $result[0].refresh_token
	
	# Write-Host "(Refresh-Access-Token) refresh token: $Refresh_Token" -ForegroundColor Yellow
	$body = @{
		grant_type = "refresh_token"
		client_id = $client_id
		client_secret = $client_secret
		refresh_token = $Refresh_Token
	}
	
	try {
		$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
		$refreshResponse = Invoke-RestMethod -Uri "https://www.deviantart.com/oauth2/token" -Method Post -Body $body
		# $refreshResponse
		
		$Access_Token = $refreshResponse.access_token
		$temp_query = "UPDATE Auth SET access_token = '$Access_Token', access_token_creation_date = '$CurrentDate'"
		Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
		return $Access_Token
########################
	} catch {
		if ($_.Exception.Response.StatusCode -eq 400) {
			Write-Host "(Refresh-Access-Token) Received error code 400. This propably means the refresh token is invalid." -ForegroundColor Red
			# Attempt to get a new token
			$Access_Token = Get-Tokens-From-Authorization-Code
			return $Access_Token
		} else {
			Write-Host "(Refresh-Access-Token) An unexpected error occurred: $($_.Exception.Message)" -ForegroundColor Red
		}
	}
####################################
}
####################################
# If the access_token expires after 1 hour, you can refresh it using the refresh_token.
function Refresh-Access-Token-Client-Credentials {
	# $temp_query = "SELECT refresh_token FROM Auth"
	# $result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query $temp_query
	# $Refresh_Token = $result[0].refresh_token
	
	# Write-Host "(Refresh-Access-Token) refresh token: $Refresh_Token" -ForegroundColor Yellow
	$body = @{
		grant_type = "client_credentials"
		client_id = $client_id
		client_secret = $client_secret
	}
	
	try {
		$CurrentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
		$refreshResponse = Invoke-RestMethod -Uri "https://www.deviantart.com/oauth2/token" -Method Post -Body $body
		# $refreshResponse
		
		$Access_Token = $refreshResponse.access_token
		$temp_query = "UPDATE Auth SET access_token = '$Access_Token', access_token_creation_date = '$CurrentDate'"
		Invoke-SqliteQuery -DataSource $DBFilePath -Query $temp_query
		return $Access_Token
########################
	} catch {
		if ($_.Exception.Response.StatusCode -eq 400) {
			Write-Host "(Refresh-Access-Token) Received error code 400. This propably means the refresh token is invalid." -ForegroundColor Red
			# Attempt to get a new token
			$Access_Token = Get-Tokens-From-Authorization-Code
			return $Access_Token
		} else {
			Write-Host "(Refresh-Access-Token) An unexpected error occurred: $($_.Exception.Message)" -ForegroundColor Red
		}
	}
####################################
}
####################################