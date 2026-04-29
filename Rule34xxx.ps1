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
    Write-Host "Files Table Columns: id, url, hash, extension, width, height, createdAt, source, main_tag, tags_artist, tags_character, tags_general, tags_copyright, tags_meta, downloaded, favorite, deleted" -ForegroundColor Cyan
	$invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''
	if ($Type -eq 1) {
		Write-Host "`nStarting download..." -ForegroundColor Yellow
		$resQueries = Invoke-SQLiteQuery -DataSource $DBFilePath -Query "SELECT query, query_name, last_time_downloaded FROM Queries;"
		if ($resQueries.Count -gt 0) {
			Backup-Database
			foreach ($Q in $resQueries) {
				$Continue = $true
				if ($Q.last_time_downloaded) {
					$DateLast = [datetime]::ParseExact($Q.last_time_downloaded, "yyyy-MM-dd HH:mm:ss", $null)
					if (((Get-Date) - $DateLast).TotalSeconds -lt $TimeToCheckAgainDownload) {
						$Continue = $false; Write-Host "Query $($Q.query_name) downloaded recently. Skipping..." -ForegroundColor Yellow
					} else {
						Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Queries SET last_time_downloaded = NULL WHERE query = '$($Q.query)'"
					}
				}
				if ($Continue) {
					$files = Invoke-SQLiteQuery -DataSource $DBFilePath -Query "SELECT id, url, hash, extension, createdAt, tags_artist, tags_character FROM Files WHERE downloaded = 0 AND main_tag = '$($Q.query_name)' AND deleted = 0;"
					if ($files.Count -gt 0) { Start-Download -SiteName "Gelbooru_Based" -FileList $files }
				}
				Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Queries SET last_time_downloaded = '$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")' WHERE query = '$($Q.query)'"
			}
		}
	} elseif ($Type -eq 2) {
        $WhereQuery = if ([string]::IsNullOrEmpty($Query)) { Read-Host "`nEnter WHERE query:" } else { $Query }
		$result = Invoke-SQLiteQuery -DataSource $DBFilePath -Query "SELECT id, url, hash, extension, createdAt, tags_artist, tags_character FROM Files $WhereQuery;"
		if ($result.Count -gt 0) { Start-Download -SiteName "Gelbooru_Based" -FileList $result }
	}
}

function Download-Metadata-From-Query {
    param ($QueryName, $MinID, $MaxID, $Results_per_Page, $Query)
	$Page = 1; $ContinueFetching = $true; $IDString = ""
	if ($MinID -ge 0 -and $MaxID -ge 0 -and $MaxID -gt $MinID) { $IDString = " id:>$MinID id:<$MaxID" }
	elseif ($MinID -ge 0) { $IDString = " id:>$MinID" }
	elseif ($MaxID -ge 0) { $IDString = " id:<$MaxID" }
	$res = Invoke-SQLiteQuery -DataSource $DBFilePath -Query "SELECT COUNT(*) as count FROM Queries WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID"
	if ($res[0].count -eq 0) {
		Invoke-SqliteQuery -DataSource $DBFilePath -Query "INSERT INTO Queries (query_name, query, minID, maxID, results_per_page) VALUES ('$QueryName', '$Query', $MinID, $MaxID, $Results_per_Page)"
		Write-Host "New query added." -ForegroundColor Green
	} else {
		Write-Host "Found query in DB." -ForegroundColor Green
		$res = Invoke-SQLiteQuery -DataSource $DBFilePath -Query "SELECT last_time_fetched_metadata, results_per_page, last_id FROM Queries WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID"
		if ($res[0].last_time_fetched_metadata) {
			$DateLast = [datetime]::ParseExact($res[0].last_time_fetched_metadata, "yyyy-MM-dd HH:mm:ss", $null)
			if (((Get-Date) - $DateLast).TotalSeconds -lt $TimeToCheckAgainMetadata) {
				$ContinueFetching = $false; Write-Host "Recently updated. Skipping metadata." -ForegroundColor Yellow
			} else {
				Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Queries SET last_time_fetched_metadata = NULL WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID"
				$Results_per_Page = $res[0].results_per_page; Write-Host "Fetching $Results_per_Page per page." -ForegroundColor Green
			}
		}
		if ($ContinueFetching -and $res[0].last_id -gt 0) { $IDString = " id:<$($res[0].last_id)"; Write-Host "Starting from ID $($res[0].last_id)." -ForegroundColor Green }
	}
	if ($ContinueFetching) {
		$HasMoreFiles = $true; $CurrentSkips = 0; Write-Host "`nFetching metadata for $QueryName..." -ForegroundColor Yellow
		while ($HasMoreFiles) {
			$URL = "$($BaseURL)&api_key=$API_Key&user_id=$UserID&limit=$Results_per_Page&pid=$Page&tags=$($Query)$($IDString)"
			Write-Host "Page $Page..." -ForegroundColor Yellow
			try {
				$Response = Invoke-Rule34xxxApi -Uri $URL
                if ($null -eq $Response) { $HasMoreFiles = $false; break }
				$xml = [xml]$Response.Content
				if ($xml.posts.post) {
					Write-Host "Found $($xml.posts.post.Count) items." -ForegroundColor Green
					$sqlScript = "BEGIN TRANSACTION; "; $i = 0; $HashList = New-Object System.Collections.Generic.List[System.Object]
					foreach ($File in $xml.posts.post) {
						$FileID = $File.id; $i++
						$resExists = Invoke-SqliteQuery -DataSource $DBFilePath -Query "SELECT EXISTS(SELECT 1 FROM Files WHERE id = '$FileID');"
						if ($resExists.'EXISTS(SELECT 1 FROM Files WHERE id = ''$FileID'')' -eq 1) {
							Write-Host "File ID $FileID exists, skipping..." -ForegroundColor Yellow
							if ($MaxSkipsBeforeAborting -gt 0 -and ++$CurrentSkips -gt $MaxSkipsBeforeAborting) { $HasMoreFiles = $false; break }
						} elseif ($HashList -notcontains $FileID) {
							$HashList.Add($FileID) | Out-Null
							$FileUrlRaw = $File.file_url; $fnWithExt = ([uri]$FileUrlRaw).Segments[-1]; $Fh, $Fe = $fnWithExt -split '\.'
							$FileDir = if ($FileUrlRaw -match '\/images\/(\d+)\/') { $matches[1] } else { "" }
							$parsedDate = [datetime]::ParseExact(($File.created_at -replace '^\w{3} ', '' -replace ' \+\d{4}', ''), "MMM dd HH:mm:ss yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
							$FDate = $parsedDate.ToString("dd-MM-yyyy HH:mm:ss")
							$TagsRaw = $File.tags -replace "'", "''"; $Tags = $TagsRaw -split " "
							$AList = @(); $CList = @(); $GList = @(); $CoList = @(); $MList = @()
							$Tags | ForEach-Object {
								if ($AddArtistTags -and $tagSetArtists.Contains($_)) { $AList += $_ }
								elseif ($AddCharacterTags -and $tagSetCharacters.Contains($_)) { $CList += $_ }
								elseif ($AddGeneralTags -and $tagSetGeneral.Contains($_)) { $GList += $_ }
								elseif ($AddCopyrightTags -and $tagSetCopyright.Contains($_)) { $CoList += $_ }
								elseif ($AddMetaTags -and $tagSetMeta.Contains($_)) { $MList += $_ }
							}
							$FileSource = if ($AddFileSourceMetadata) { $File.source } else { "" }
							$sqlScript += "INSERT INTO Files (id, url, hash, extension, width, height, createdAt, source, main_tag, tags_artist, tags_character, tags_general, tags_copyright, tags_meta, downloaded) VALUES ('$FileID', '$FileDir', '$Fh', '$Fe', '$($File.width)', '$($File.height)', '$FDate', '$FileSource', '$QueryName', '$($AList -join " + ")', '$($CList -join " + ")', '$($GList -join " ")', '$($CoList -join " ")', '$($MList -join " ")', 0); "
							Write-Host "Added $FileID." -ForegroundColor Green
						}
						if ($i -ge $MetadataCountBeforeAdding -or $i -eq $xml.posts.post.Count) {
							$sqlScript += "UPDATE Queries SET last_id = '$FileID' WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID; COMMIT;"
							Invoke-SqliteQuery -DataSource $DBFilePath -Query $sqlScript
							$sqlScript = "BEGIN TRANSACTION; "; $i = 0
						}
					}
					if ($HasMoreFiles) { if (++$Page -gt 200) { $IDString = " id:<$FileID"; $Page = 1 } }
				} else {
					Write-Host "No more files." -ForegroundColor Yellow
					Invoke-SqliteQuery -DataSource $DBFilePath -Query "UPDATE Queries SET last_id = 0, last_time_fetched_metadata = '$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")' WHERE query = '$Query' AND minID = $MinID AND maxID = $MaxID"
					$HasMoreFiles = $false; break
				}
			} catch { Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red; $HasMoreFiles = $false; break }
		}
	}
}

function Process-Queries { foreach ($Q in $QueryList) { Download-Metadata-From-Query -QueryName $Q[0] -MinID $Q[1] -MaxID $Q[2] -Results_per_Page $Q[3] -Query $Q[4] } }

Create-Database-If-It-Doesnt-Exist -SiteName "Rule34xxx" -DBFilePath $DBFilePath
Invoke-SqliteQuery -DataSource $DBFilePath -Query "PRAGMA default_cache_size = $PRAGMA_default_cache_size; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;"

$tagSetGeneral = [System.Collections.Generic.HashSet[string]]::new(); $tagSetArtists = [System.Collections.Generic.HashSet[string]]::new(); $tagSetCharacters = [System.Collections.Generic.HashSet[string]]::new(); $tagSetCopyright = [System.Collections.Generic.HashSet[string]]::new(); $tagSetMeta = [System.Collections.Generic.HashSet[string]]::new()
function LoadTags($useDB, $dbTable, $localList, $set) {
	if ($useDB) { (Invoke-SQLiteQuery -DataSource $TagDBFilePath -Query "SELECT tag FROM $dbTable").tag | ForEach-Object { [void]$set.Add($_) } }
	else { $localList | ForEach-Object { [void]$set.Add($_) } }
	Write-Host "Loaded $($set.Count) tags for $dbTable." -ForegroundColor Green
}
LoadTags $LoadTagsFromDatabase_General "tags_general" $tagListGeneral $tagSetGeneral
LoadTags $LoadTagsFromDatabase_Artist "tags_artist" $tagListArtists $tagSetArtists
LoadTags $LoadTagsFromDatabase_Character "tags_character" $tagListCharacters $tagSetCharacters
LoadTags $LoadTagsFromDatabase_Copyright "tags_copyright" $tagListCopyright $tagSetCopyright
LoadTags $LoadTagsFromDatabase_Meta "tags_meta" $tagListMeta $tagSetMeta

function Show-Menu {
    param ([string]$Query = "")
	try {
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/Rule34xxx_$($CurrentDate).log" -Append
		$exitScript = $false
		while (-not $exitScript) {
			Write-Host "`nRule34xxx Downloader`n1. Metadata and Files`n2. Metadata only`n3. All files in DB`n4. Files from query`n5. Scan favorites`n6. Exit" -ForegroundColor Green
			$choice = Read-Host "`nSelect (1-6)"
			if ($choice -eq 1) { Backup-Database; Process-Queries; Download-Files-From-Database -Type 1 }
			elseif ($choice -eq 2){ Backup-Database; Process-Queries }
			elseif ($choice -eq 3){ Download-Files-From-Database -Type 1 }
			elseif ($choice -eq 4){ Download-Files-From-Database -Type 2 -Query $Query }
			elseif ($choice -eq 5){ Backup-Database; Scan-Folder-And-Add-Files-As-Favorites -Type 1 }
			elseif ($choice -eq 6){ $exitScript = $true }
		}
	} finally { Stop-Transcript }
}

if ($Function) {
	try {
		$CurrentDate = Get-Date -Format "yyyyMMdd_HHmmss"
		Start-Transcript -Path "$PSScriptRoot/logs/Rule34xxx_$($CurrentDate).log" -Append
		switch ($Function) {
			'DownloadAllMetadataAndFiles' { Backup-Database; Process-Queries; Download-Files-From-Database -Type 1 }
			'DownloadAllMetadata' { Backup-Database; Process-Queries }
			'DownloadOnlyFiles' { Download-Files-From-Database -Type 1 }
			'DownloadFilesFromQuery' { Download-Files-From-Database -Type 2 -Query $Query }
			'ScanFolderForFavorites' { Backup-Database; Scan-Folder-And-Add-Files-As-Favorites -Type 1 }
			'DownloadMetadataForSingleQuery' { Backup-Database; Download-Metadata-From-Query -QueryName $QueryName -MinID $MinID -MaxID $MaxID -Results_per_Page $Results_per_Page -Query $Query }
		}
	} finally { Stop-Transcript; [console]::beep() }
} else { Show-Menu; [console]::beep() }
