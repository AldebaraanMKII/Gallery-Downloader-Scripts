###############
# Folder where images will be downloaded
$DownloadFolder = ""
$FavoriteScanFolder = ""
###############
$DBFilename = "DeviantArt.sqlite3"
$DBFilePath = "./$DBFilename"
###############
#metadata fetch per request, minimum 1 maximum 24
$Limit = 24
###############
## Please read https://www.deviantart.com/developers/authentication on how to obtain the $client_id and $client_secret
## make sure to use gallery-dl URI in your OAuth2 Redirect URI Whitelist in your app settings
$client_id = ""
$client_secret = ""
$redirect_uri = "https://mikf.github.io/gallery-dl/oauth-redirect.html"	#using gallery-dl URI
$scope = "browse feed message note stash user user.manage comment.post collection"  # Or other scopes as required
$state = ""  # Optional
###############################
# Here you can choose how the output file will be named
# available options are: %Username%, %DeviationID%, %Height%, %Width%, %Title%, %PublishedTime% (format: yyyy-mm-dd HH-mm-ss), %PublishedTimeFormatted% (format: yyyy-mm-dd)
#e.g. [Username1] (AAAAA-BBBBB-CCCCC-DDDDD) whatever-0001 (2024-08-24)
$FilenameTemplate = "[%Username%] (%PublishedTimeFormatted%) %Title% (%DeviationID%)"
############################### http response error handling
$maxRetries = 20
$initialDelay = 30000  # Initial delay in milliseconds
$MaxDelay = 60000  # max delay in milliseconds
###############################
# this is the amount of file skips that will abort the current user search. Set it to 0 to disable this.
# $MaxSkipsBeforeAborting = $Limit * 2
$MaxSkipsBeforeAborting = 10
###############################
#time to wait between requests in milliseconds. Recommended is 12000+ due to Wix being pieces of shit.
$TimeToWait = 14000
###############################
#max parallel downloads. Not recommended to set this above the default unless you like to be rate limited.
$MaxConcurrentDownloads = 3
###############################
#how many hours must pass after downloading a user's entire gallery before the script will check it again
$TimeToCheckAgainMetadata = 336
#how many hours must pass after downloading a user's entire gallery before the script will try to download any new files from them in the database
#this is to speed things up when the script is closed for whatever reason
$TimeToCheckAgainDownload = 336
###############################
#if set to true, will add mature content to the database
$AllowMatureContent = $true
###############################
#Backup database on metadata/download start, needs 7zip installed and in PATH
$BackupDBOnStart = $false
###############################
#this will rename a file after adding it to favorites in the database using the pattern set in $FilenameTemplate. This is useful to rename old files you have around to a new pattern.
$RenameFileFavorite = $false
###############################
#convert files after downloading them. FFMPEG needs to be installed and in PATH
$ConvertFiles = $true
#Define the maximum number of parallel conversion jobs
$MaxThreads = 4
#Number of files to download before attempting conversion. Better to set it to $MaxThreads * 5
$ConvertFilesAmount = 50
#if set to true, will remove the original file after conversion
$RemoveOriginalFileAfterConversion = $true
#if set to true will save the converted file to directory named "Converted" inside the original folder
$SaveConvertedFileSubfolder = $false
#list of file types
#format is filetype, minimum filesize in KB, filetype to convert to, ffmpeg parameters
$FileListToConvert = @(
	@("png", 0, "webp", "-c:v libwebp -q:v 100 -map_metadata 0"),  #quality set to 100, keeps metadata
	@("jpg", 600, "webp", "-c:v libwebp -q:v 100 -map_metadata 0"),
	@("jpeg", 600, "webp", "-c:v libwebp -q:v 100 -map_metadata 0"),
	@("gif", 1000, "mp4", "-c:v libx265 -crf 28 -preset slow -pix_fmt yuv420p")        #convert gif to mp4 x265
)
###############################
###############################
# List of users to download files from
# format: username, filter, negative filter
# negative filter is processed first
# if filter is not empty, all results that pass the negative filter but do not have the words in the filter will be excluded as well
$UserList = @(
	@("username1", "", ""),
	@("username2", "", "")
)
###############################














