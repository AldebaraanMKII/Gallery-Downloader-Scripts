###############
# Folder where files will be downloaded
$DownloadFolder = ""
$FavoriteScanFolder = ""
###############
# API endpoint and other settings
$BaseURL = "https://kemono.cr/api/v1"
$DownloadBaseURL = "https://n1.kemono.cr/data"
###############
$DBFilename = "Kemono.sqlite3"
$DBFilePath = "./$DBFilename"
###############
# Here you can choose how the output file will be named
# available options are: %CreatorID%, %CreatorName%, %PostID%, %PostTitle%, %PostPublishDate% (format: yyyy-mm-dd hh-mm-ss), %PostPublishDateShort% (format: yyyy-mm-dd), %FileHash%, %Filename%, %FileIndex%, %PostTotalFiles%
#e.g. [Username1] [123456] (Commission 1) (1 of 3) 00479-123456 (dd83b728c14d0ea0c8cd3ebb986e3ab2ad6eb7a4c44e2942bb232eefb1d3e41b) (2024-06-24)
$FilenameTemplate = "[%CreatorName%] [%PostID%] (%PostTitle%) (%FileIndex% of %PostTotalFiles%) %FileHash% (%PostPublishDateShort%)"

###############################
###### http response error handling
$maxRetries = 5
$initialDelay = 5000  # Initial delay in milliseconds
$MaxDelay = 60000  # max delay in milliseconds
###############################
# this is the amount of post skips that will abort the current creator search. Set it to 0 to disable this.
$MaxSkipsBeforeAborting = 10
###############################
# if set to true, the word filter will also include/exclude posts that contain words in the content body
$FilterPostContent = $false
###############################
# if set to true, skip adding post content to the database. This can save space on database.
$PostContentSkip = $false
###############################
# if set to true, a subfolder will be created for each post ([postID] postTitle), otherwise all files will be under the service/creator [creatorID] folder
$CreateSubfolderForPosts = $false
###############################
#how many hours must pass after downloading a user's entire gallery before the script will try to download any new files from them in the database
#this is to speed things up when the script is closed for whatever reason
$TimeToCheckAgainDownload = 168
###############################
#time to wait between requests
$TimeToWait = 2000
###############################
#max parallel downloads. Not recommended to set this above the default unless you like to be rate limited.
$MaxConcurrentDownloads = 1
###############################
#Backup database on metadata/download start, 7zip needs to be installed and in PATH
$BackupDBOnStart = $false
###############################
#this will rename a file after adding it to favorites in the database using the pattern set in $FilenameTemplate. This is useful to rename old files you have around to a new pattern.
$RenameFileFavorite = $true
###############################
#convert files after downloading them. FFMPEG needs to be installed and in PATH
$ConvertFiles = $false
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
# List of creators to download files from
# format: creator name (can be anything), creator ID, service, word filter (include), word filter (exclude), file types to exclude
# service list: patreon, fanbox, discord, fantia, boosty, gumroad, subscribestar
# word filter: separate words by comma and a space e.g "laptop, desktop". Use "" if you don`t want to use the filter
# using the include word filter will exclude all results that don`t have the words in them!
$CreatorList = @(
	@("User1", 12345, "patreon", "", "teaser, preview, next characters, Next Characters", "zip, 7z, rar"),
	@("User2", 123456, "patreon", "", "Vote, Poll", "")
)
###########################################################














