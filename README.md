# Attention!
If are using a database made before commit 4b560e1e68db5deeba817404bc1195960fdbc355, then you need to update it by running these sql queries (i recommend HeidiSQL):

CivitAI/DeviantArt:
```
ALTER TABLE Users
ADD COLUMN deleted INTEGER DEFAULT 0 CHECK (deleted IN (0,1));
```

Kemono:
```
ALTER TABLE Creators
ADD COLUMN deleted INTEGER DEFAULT 0 CHECK (deleted IN (0,1));
```



# Gallery Downloader Scripts

A collection of PowerShell scripts to download images/videos from various websites.

## Features

- Concurrent downloads
- Download metadata from the API of supported sites
- Store metadata efficiently in a SQLite database to minimize size
- Download images/videos using the database without contacting the API again
- Create organized subfolders for each username/query
- Name downloaded files according to configurable patterns
- Handle errors (IO errors, 401/404 errors)
- Auto retry on unknown errors (configurable)
- Skip username/query when encountering items already in the database (configurable)
- Skip username/query if already fetched within a configurable time period
- Convert files after download using FFMPEG (configurable)
- (CivitAI/DeviantArt) Handle authentication procedures
- Add local files as favorites to the database, so that they can be downloaded quickly without needing to sort things again
- Log all activities in the logs subfolder
- Continue from where you left off when closing the script
- (DeviantArt/Kemono) Filter titles of posts, only add into database what you want
- (Kemono) Filter filetypes
- (Rule34xxx) Automatically deals with 200 page limit of the API

## Supported Sites

- Rule34xxx
- CivitAI
- Kemono
- DeviantArt

## Installation

1. Install the latest PowerShell 7
2. Install PSSQLite module:
   ```powershell
   Install-Module PSSQLite
   ```
3. **CivitAI Setup:**
   - Create an account and get an API key
   - Set it in "(config) CivitAI.ps1" `$API_Key` variable

4. **DeviantArt Setup:**
   - Create an account and [register a new application](https://www.deviantart.com/developers/apps) to get a client_id and client_secret
   - Set OAuth2 Redirect URI Whitelist to "https://mikf.github.io/gallery-dl/oauth-redirect.html" (Gallery-DL redirect)
   - Set the client_id and client_secret in "(config) DeviantArt.ps1" `$client_id` and `$client_secret` variables
   - Run the script once (see usage below) and copy the refresh token from your default browser, then paste it in the console

5. **Rule34xxx Setup:**
   - (02/08/2025) Rule34xxx now requires a account and API key to access its API
   - Create an account and generate an API key: [Link](https://rule34.xxx/index.php?page=account&s=options)
   - Get your user ID as well
   - Set it in "(config) Rule34xxx.ps1" `$API_Key` and `$UserID` variables
     
6. Refer to the configuration files' comments to understand each option

## Usage
You can just double click the script in question to show the graphical options. Or:

1. Open a PowerShell terminal in the same folder as the scripts
2. Run:
   ```powershell
   . "$PSScriptRoot\ScriptName.ps1"; Function -Function X
   ```
   
   Where `ScriptName` is the name of the website you want to download from (e.g., `CivitAI.ps1`), and `X` is one of the following options:
   
	   1. DownloadAllMetadataAndFiles (Download metadata from users/queries to database and then download files)
	   2. DownloadAllMetadata (Download only metadata from users/queries to database)
	   3. DownloadOnlyFiles (Download all files in database not already downloaded (skip metadata download))
	   4. DownloadFilesFromQuery -Query $SQLquery (Download files in database from query)
	   5. ScanFolderForFavorites (Scan folder for files and add them to database marked as favorites)
	   6. DownloadMetadataForSingleUser -Username $Username (Downloads metadata for a single user)


### Using Custom Queries (Option 4)

Examples:
- `WHERE favorite = 1` - will download all favorites
- `WHERE username = 'username1' AND downloaded = 0` - will download all files not already downloaded from username "username1"

Use a tool like HeidiSQL to open the database and check the column names for constructing queries.

Note: when using the query to download the items will be downloaded by ID/Hash/GUID or whatever the unique column in the database for that site is.


### Favorites (Option 5)
Set the directory in the $FavoriteScanFolder variable in the respective configuration script.

The script will scan for any files in that folder, and any subfolders.

The files will be added if they have a pattern in their filename: 

- Rule34xxx = MD5/SHA-1
- CivitAI/DeviantArt = UUID
- Kemono = SHA256



### TODO list
- Add CivitAI tag filter
