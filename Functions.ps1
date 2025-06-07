function Backup-Database {
	if ($BackupDBOnStart) {
		# Get the current date to use in the backup archive name
		$BackupFolderPath = "./backups"
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
    $batchSize = 100
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
            
            # Process in batches of 50
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
    
    # First, check which files exist in the database
    $values = "'" + ($MatchedFiles.PatternMatch -join "','") + "'"
    $checkQuery = "SELECT $Column FROM Files WHERE $Column IN ($values)"
    $existingRecords = Invoke-SqliteQuery -DataSource $DBFilePath -Query $checkQuery
    
    if ($existingRecords.Count -gt 0) {
        # Create a hash set for faster lookups
        $existingSet = @{}
        foreach ($record in $existingRecords) {
            $existingSet[$record.$Column] = $true
        }
        
        # Build batch update query for files that exist
        $updateValues = ($MatchedFiles | Where-Object { $existingSet[$_.PatternMatch] } | ForEach-Object { $_.PatternMatch }) -join "','"
        if ($updateValues) {
            $batchUpdateQuery = "UPDATE Files SET favorite = 1, downloaded = 1 WHERE $Column IN ('$updateValues')"
            Invoke-SqliteQuery -DataSource $DBFilePath -Query $batchUpdateQuery
            
            $updateCount = ($MatchedFiles | Where-Object { $existingSet[$_.PatternMatch] }).Count
            Write-Host "Added $updateCount files as favorites to database." -ForegroundColor Green
            
            # Handle renaming if enabled
            if ($RenameFileFavorite) {
                # Get the data for files we need to rename
                $filesToRename = $MatchedFiles | Where-Object { $existingSet[$_.PatternMatch] }
                if ($filesToRename.Count -gt 0) {
                    Batch-Rename-Files -FilesToRename $filesToRename -Column $Column -DataQuery $DataQuery -Type $Type
                }
            }
        }
        
        # Report files not in database
        $notFoundFiles = $MatchedFiles | Where-Object { -not $existingSet[$_.PatternMatch] }
        if ($notFoundFiles.Count -gt 0) {
            Write-Host "$($notFoundFiles.Count) files were not found in database. Skipping..." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "None of the files in this batch were found in the database." -ForegroundColor Yellow
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
			$FileURL = "xG1nkqKTMzGDvpLrqFT7WA/"
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
		$FileCreatorID = $row.creatorID
		$FileCreatorName = $row.creatorName
		
		#shorten length due to windows 255 character limit
		if ($FileFilename.Length -gt 100) {
			$FileFilename = $FileFilename.Substring(0, 100)
		}
		
		#replace \ with /
		$FileURL = $FileURL.Replace("\","/")
		# Write-Host "Filename: $Filename"
		
		# Replace placeholders with actual values
		$Filename = $FilenameTemplate -replace '%CreatorID%', $FileCreatorID `
									-replace '%CreatorName%', $FileCreatorName `
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
		} elseif ($ErrorMessage -like "*Unable to read data from the transport connection*") {
			$delay = Calculate-Delay -retryCount $retryCount
		
			$retryCount++
			Write-Output "Error: Connection forcibly closed by the remote host." -ForegroundColor Red
	
			Start-Sleep -Milliseconds $delay
			
			$BreakLoop = $false
			return $retryCount, $BreakLoop
#####################################
		} elseif ($ErrorMessage -like "*The response ended prematurely*") {
			$delay = Calculate-Delay -retryCount $retryCount
		
			$retryCount++
			Write-Output "Error: The response ended prematurely." -ForegroundColor Red
	
			Start-Sleep -Milliseconds $delay
			
			$BreakLoop = $false
			return $retryCount, $BreakLoop
#####################################
		} elseif ($ErrorMessage -like "*The SSL connection could not be established*") {
			$delay = Calculate-Delay -retryCount $retryCount
		
			$retryCount++
			Write-Output "Error: The response ended prematurely." -ForegroundColor Red
	
			Start-Sleep -Milliseconds $delay
			
			$BreakLoop = $false
			return $retryCount, $BreakLoop
#####################################
		} else {
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
        [PSCustomObject[]]$FileList   #list of files to download
        # [int]$MaxConcurrentDownloads = 4  # Number of concurrent downloads
    )

    $FileListForConversion = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    $FilesRemaining = $FileList.Count
    $CompletedFiles = 0
    
    Write-Host "Found $FilesRemaining files." -ForegroundColor Green
    
    # Create runspace pool for concurrent downloads
    $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxConcurrentDownloads)
    $RunspacePool.Open()
    
    # Script block for each download task
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
            $PostTotalFiles
        )
        
        # Define functions in the runspace
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
                    $DownloadURL = "$($DownloadBaseURL)$($FileURL)$($FileFilename)/width=$FileWidth"
                    $DownloadSubfolderIdentifier = "$Username"
                    $SetFileDownloadedQuery = "UPDATE Files SET downloaded = 1 WHERE id = '$FileID'"
                    $FileIdentifier = $FileID
                }
                "Kemono" {
                    $FileHash, $FileExtension, $FileURL, $FileFilenameExtension, $CreatorName, $Filename = Create-Filename -row $File -Type 3
                    $DownloadURL = "$($DownloadBaseURL)$($FileURL)/$($FileHash).$($FileExtension)"
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
            
            # Clean filename
            $Filename = $Filename -replace "[$invalidChars]", ''
            
            # Define download path
            $DownloadSubFolder = Join-Path $DownloadFolder "$DownloadSubfolderIdentifier"
            $FilePath = Join-Path $DownloadSubFolder "$Filename.$FileExtension"
            
            # Ensure download folder exists
            if (-not (Test-Path $DownloadSubFolder)) {
                $null = New-Item -ItemType Directory -Path $DownloadSubFolder -Force
            }
            
            $result = @{
                Success = $false
                FilePath = $FilePath
                Filename = $Filename
                FileExtension = $FileExtension
                Message = ""
                FileIndex = $FileIndex
                AlreadyExists = $false
            }
            
            # Download logic
            if (-not (Test-Path $FilePath)) {
                $retryCount = 0
                $downloadSuccessful = $false
                
                while ($retryCount -lt $maxRetries -and -not $downloadSuccessful) {
                    try {
                        # Use WebClient for download
                        $webClient = [System.Net.WebClient]::new()
                        $webClient.DownloadFile($DownloadURL, $FilePath)
                        $webClient.Dispose()
                        
                        # Update database
                        Invoke-SqliteQuery -DataSource $DBFilePath -Query $SetFileDownloadedQuery
                        
                        $result.Success = $true
                        $result.Message = "Downloaded successfully"
                        $downloadSuccessful = $true
####################################################
                    } catch [System.IO.IOException] {
						$BreakLoop = $false
						Write-Host "Error message: $_.Exception.Message" -ForegroundColor Red
						$retryCount, $BreakLoop = Handle-Errors -retryCount $retryCount -ErrorMessage $_.Exception.Message -StatusCode 0 -Site $SiteName -Type 1 -FileIdentifier $FileIdentifier -Username $Username
						
						if ($BreakLoop) {
							break
						}
####################################################
					} catch {
						$BreakLoop = $false
						Write-Host "Error message: $_.Exception.Response.StatusCode" -ForegroundColor Red
						$retryCount, $BreakLoop = Handle-Errors -retryCount $retryCount -ErrorMessage "" -StatusCode $_.Exception.Response.StatusCode -Site $SiteName -Type 2 -FileIdentifier $FileIdentifier -Username $Username
						
						if ($BreakLoop) {
							break
						}
					}
####################################################
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
                Filename = $Filename
                FileExtension = $FileExtension
                Message = "Error processing file: $($_.Exception.Message)"
                FileIndex = $FileIndex
                AlreadyExists = $false
            }
        }
    }
    
    # Get function definitions as strings to pass to runspaces
    $CreateFilenameFunction = Get-Command Create-Filename | Select-Object -ExpandProperty Definition
    $HandleErrorsFunction = Get-Command Handle-Errors | Select-Object -ExpandProperty Definition  
    $InvokeSqliteQueryFunction = Get-Command Invoke-SqliteQuery | Select-Object -ExpandProperty Definition
    
    # Create jobs for each file
    $Jobs = @()
    $FileIndex = 0
    
    foreach ($File in $FileList) {
        $FileIndex++
        
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
        [void]$PowerShell.AddArgument($FileIndex)
        [void]$PowerShell.AddArgument($FilesRemaining)
        [void]$PowerShell.AddArgument($FilenameTemplate)
        [void]$PowerShell.AddArgument($PostID)
        [void]$PowerShell.AddArgument($PostTitle)
        [void]$PowerShell.AddArgument($PostDatePublishedFormatted)
        [void]$PowerShell.AddArgument($PostDatePublishedFormattedShort)
        [void]$PowerShell.AddArgument($PostTotalFiles)
        
        # Start the job
        $AsyncResult = $PowerShell.BeginInvoke()
        
        $Jobs += [PSCustomObject]@{
            PowerShell = $PowerShell
            AsyncResult = $AsyncResult
            FileIndex = $FileIndex
        }
    }
    
    # Wait for jobs to complete and collect results
    $CompletedJobs = 0
    $FilesForConversion = @()
    
    while ($CompletedJobs -lt $Jobs.Count) {
        foreach ($Job in $Jobs) {
            if ($Job.AsyncResult.IsCompleted -and $Job.PowerShell) {
                try {
                    $Result = $Job.PowerShell.EndInvoke($Job.AsyncResult)
                    
                    if ($Result.Success) {
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
                    # Clean up
                    $Job.PowerShell.Dispose()
                    $Job.PowerShell = $null
                    $CompletedJobs++
                }
            }
        }
        
        # Small delay to prevent busy waiting
        Start-Sleep -Milliseconds 100
    }
    
    # Clean up runspace pool
    $RunspacePool.Close()
    $RunspacePool.Dispose()
    
    # Handle file conversion if needed
    if ($ConvertFiles -and $FilesForConversion.Count -gt 0) {
        # Group files by subfolder for conversion
        $FileGroups = $FilesForConversion | Group-Object { Split-Path (Split-Path $_.FilePath -Parent) -Leaf }
        
        foreach ($group in $FileGroups) {
            $SubfolderPath = Join-Path $DownloadFolder $group.Name
            Convert-File -FileList $group.Group -Folder $SubfolderPath
        }
    }
    
    Write-Host "All downloads completed!" -ForegroundColor Green
}
###############################################


