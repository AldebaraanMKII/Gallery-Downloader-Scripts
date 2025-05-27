# Gallery Downloader Scripts

A collection of PowerShell scripts to download images/videos from various websites.

## Features

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

5. Refer to the configuration files' comments to understand each option

## Usage

1. Open a PowerShell terminal in the same folder as the scripts
2. Run:
   ```powershell
   . .\ScriptName.ps1; Execute-Function -function X
   ```
   
   Where `ScriptName` is the name of the website you want to download from (e.g., `CivitAI.ps1`), and `X` is one of the following options:

	   1. Download metadata from users/queries to database and then download files
	   2. Download only metadata from users/queries to database
	   3. Download all files in database not already downloaded (skip metadata download)
	   4. Download files in database from query
	   5. Scan folder for files and add them to database marked as favorites

You can also run a graphical interface:
```powershell
. .\ScriptName.ps1; Graphical-Options
```

### Using Custom Queries (Option 4)

Examples:
- `WHERE favorite = 1` - will download all favorites
- `WHERE username = 'username1' AND downloaded = 0` - will download all files not already downloaded from username "username1"

Use a tool like HeidiSQL to open the database and check the column names for constructing queries.
Note: when using the query to download the items will be downloaded by ID/Hash/GUID or whatever the unique column in the database for that site is.
