
###############
# Folder where files will be downloaded
$DownloadFolder = ""
$FavoriteScanFolder = ""
###############
# API endpoint and other settings
$BaseURL = "https://civitai.com/api/v1/images"
$DownloadBaseURL = "https://image.civitai.com/"
###############
$DBFilename = "CivitAI.sqlite3"
$DBFilePath = "./$DBFilename"
###############
# API key for authentication
$API_Key = ""
###############
#metadata fetch per request, minimum 1 maximum 200
$Limit = 200
###############
# Here you can choose how the output file will be named
# available options are: %Username%, %FileID%, %Filename%, %FileWidth%, %FileHeight%, %FileCreatedAt% (format: yyyy-mm-dd)
#e.g. [Username1] [123456] 0001-0002-0003 (2024-08-24)
$FilenameTemplate = "[%Username%] (%FileID%) %Filename% (%FileCreatedAt%)"
###### http response error handling
$maxRetries = 5
$initialDelay = 5000  # Initial delay in milliseconds
$MaxDelay = 60000  # max delay in milliseconds
###############
# this is the amount of file skips that will abort the current user search. Set it to 0 to disable this.
$MaxSkipsBeforeAborting = 50
###############################
#if set to true, metadata such as model used and prompts will be saved to the database
#this will increase database size several times over
$DownloadPromptMetadata = $false
###############################
#time to wait between requests in milliseconds
$TimeToWait = 3000
###############################
#max parallel downloads. Not recommended to set this above the default unless you like to be rate limited.
$MaxConcurrentDownloads = 4
###############################
#how many hours must pass after fetching metadata for a user's entire gallery before the script will check it again
$TimeToCheckAgainMetadata = 336
#how many hours must pass after downloading a user's entire gallery before the script will try to download any new files from them in the database
#this is to speed things up when the script is closed for whatever reason
$TimeToCheckAgainDownload = 720
###############################
#if set to true, will add SFW files to the database
$AllowSFWFiles = $false
#if set to true, will add NSFW files to the database
$AllowNSFWFiles = $true
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
# format: username
$UserList = @(
	"Username1",
	"Username2"
)
###########