#######################################
# Folder where Files will be downloaded
$DownloadFolder = ""
$FavoriteScanFolder = ""
###############################
# API endpoint and other settings
# $BaseURL = "https://api.rule34.xxx/index.php?page=dapi&s=post&q=index&json=1"
$BaseURL = "https://api.rule34.xxx/index.php?page=dapi&s=post&q=index" 	#xml because json doesn`t return post creation date
$DownloadBaseURL = "https://api-cdn.rule34.xxx/images/"

$DBFilename = "Rule34xxx.sqlite3"
$DBFilePath = "./$DBFilename"

$TagDBFilename = "Tags_Rule34xxx.db"
$TagDBFilePath = "./$TagDBFilename"
###### http response error handling
$maxRetries = 5
$initialDelay = 5000  # Initial delay in milliseconds
$MaxDelay = 60000  # max delay in milliseconds
###############################
#max parallel downloads. Not recommended to set this above the default unless you like to be rate limited.
$MaxConcurrentDownloads = 3
###############################
# this is the amount of File skips that will abort the current query search. 
$MaxSkipsBeforeAborting = 50
# this is the number of Files that will be added at once to the database when processing metadata
# so if you have results_per_page set to 1000 in the queries array and this set to 50, it will add things 20 times
# otherwise all the 1000 items the metadata returned would need to be processed first before adding them to the database
$MetadataCountBeforeAdding = 50
#if set to true, skip ID checking. This will speed up metadata collection speed, but may produce errors if the same ID already exists in database
$SkipIDCheck = $false
###############################
# Here you can choose how the output file will be named
# available options are: %ID%, %TagsArtist%, %TagsCharacter%, %Width%, %Height%, %MD5%, %FileCreateDate% (format: yyyy-mm-dd), %FileCreateDateFull% (format: yyyy-mm-dd hh-mm-ss)
#e.g. 123456 (whatever123) (whoever123) asa54d5d1a5d45adda54ad (2024-10-11)"
$FilenameTemplate = "%ID% (%TagsArtist%) (%TagsCharacter%) %MD5% (%FileCreateDate%)"
###############################
#Backup database on metadata/download start, needs 7zip installed and in PATH
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
#Set this to false to prevent the type of tags you don't want from being added into the database. 
#general tags reduces database size significantly (20-1000 bytes per file) when turned off.
$AddArtistTags = $true
$AddCharacterTags = $true
$AddGeneralTags = $false
$AddCopyrightTags = $false
$AddMetaTags = $false
#if set to true, will add the file source link to the database. This increases the database size by 20-100 bytes per file.
$AddFileSourceMetadata = $false
###############################
$NegativeTagList = "-tag5 -tag6 -tag7"

# List of tags to download Files from
# format: query_name, MinID, MaxID, results_per_page, query
$QueryList = @(
	@("tag1", -1, -1, 1000, "tag1 -tag3 $NegativeTagList"),
	@("tag2", -1, -1, 1000, "tag2 -tag4 $NegativeTagList")
)
###############################
#if set to true, the script will load the tags from the $TagDBFilename database. Otherwise it will load from lists inside the script
$LoadTagsFromDatabase_General = $true
$LoadTagsFromDatabase_Artist = $true
$LoadTagsFromDatabase_Copyright = $true
$LoadTagsFromDatabase_Character = $true
$LoadTagsFromDatabase_Meta = $true

# tag list
# this is to avoid big database filesize
$tagListGeneral = (
	#character count
	("1boy"),("1girls"),("2girls"),("3girls"),("4girls"),("5girls"),("6girls"),("7girls"),("8girls"),("9girls"),("10girls"),
	("11girls"),("12girls"),("13girls"),("14girls"),("15girls"),("multiple_girls"),("solo"),("solo_female"),("female_only"),
	
################# BODY TAGS
	#breasts
	("giant_breasts"),("enormous_breasts"),("gigantic_breasts"),("large_breasts"),("huge_breasts"),("big_breasts"),("hyper_breasts"),("cleavage"),
	
	#nipples
	("areolae"),("huge_areolae"),("huge_nipples"),("big_nipples"),("erect_nipples"),("puffy_nipples"),
	
	#ass
	("ass"),("huge_ass"),("large_ass"),("big_ass"),("fat_ass"),("huge_butt"),("bottom_heavy"),("enormous_ass"),
	
	#thighs
	("thighs"),("huge_thighs"),("thick_thighs"),("muscular_thighs"),("thunder_thighs"),
	
	#hips
	("thick_hips"),("wide_hips"),
	
	#vagina
	("cameltoe"),("pubic_hair"),
	
	#fitness
	("muscles"),("muscular"),("muscular_female"),("athletic"),("athletic_female"),("fit"),("fit_female"),
	
	#waist
	("waist"),("slim_waist"),
	
	#belly
	("navel"),("abs"),("six_pack"),("eight_pack"),
	
	#penis
	("penis"),("big_penis"),("huge_penis"),("gigantic_penis"),("huge_cock"),("gigantic_cock"),("foreskin"),("veiny_penis"),
	
	#balls
	("huge_balls"),
	
	#lips
	("thick_lips"),
	
	#figure
	("curvaceous"),("curvy"),("hourglass_figure"),("thick"),("voluptuous"),("hyper"),
	
	#giantess
	("giantess"),("size_difference"),("height_difference"),("micro"),
	
	#legs
	("thick_legs"),
	
	#futa
	("futanari"),("futa_only"),
	
	#skin color
	("light_skin"),("brown_skin"),("dark_skin"),("grey_body"),("white_skin"),("blue_skin"),("green_skin"),("purple_skin"),
	("tan_skin"),("grey_skin"),("red_skin"),("pink_skin"),("black_skin"),("yellow_skin"),("orange_skin"),("olive_skin"),
	
	#skin
	("shiny_skin"),("wet_skin"),("oiled_skin"),
	
	#hair color
	("black_hair"),("blonde_hair"),("brown_hair"),("ginger"),("red_hair"),("blue_hair"),("green_hair"),("silver_hair"),
	("white_hair"),("pink_hair"),("orange_hair"),("redhead"),("yellow_hair"),
	
	#eye color
	("black_eyes"),("blonde_eyes"),("brown_eyes"),("red_eyes"),("blue_eyes"),("green_eyes"),("silver_eyes"),
	("white_eyes"),("pink_eyes"),("orange_eyes"),("yellow_eyes"),
	
	#hair type
	("bangs"),("very_long_hair"),("ponytail"),("long_hair"),("tied_hair"),("short_hair"),("braid"),
##################################
	
	#hair accessories
	("ribbon"),("bow"),
	
	#expression
	("blush"),("smile"),("smiling"),("closed_mouth"),("saliva"),("tongue_out"),("looking_away"),("smirk"),
	("ahe_gao"),
	
	#setting
	("cyberpunk"),
	
	#species
	("human"),("animal_ears"),("catgirl"),("orc"),
	
	#clothes
	("half_dressed"),("nude"),("naked"),("beret"),("gloves"),("school_uniform"),("apron"),("dress"),("legwear"),("latex"),("tight_clothing"),
	("bikini"),("swimsuit"),("thighhighs"),("lingerie"),("miniskirt"),("shirt"),
	
	#accessories
	("earrings"),("jewelry"),("choker"),("belt"),
	
	#makeup
	("lipstick"),("eyelashes"),
	
	#angle/camera
	("solo_focus"),("female_focus"),("looking_at_viewer"),("male_pov"),("pov"),("eyebrows_visible_through_hair"),
	("ass_focus"),("from_behind"),("rear_view"),("looking_down"),("pov_eye_contact"),
	
	#body position
	("asymmetrical_docking"),("sitting"),("breast_press"),("seductive"),("spread_legs"),("side_boob"),("hand_on_head"),
	("ass_grab"),("grabbing_from_behind"),("on_top"),("on_knees"),("dogeza"),("crossed_arms"),
	
	#sex
	("kissing"),("breast_squeeze"),("yuri"),("threesome"),("foursome"),("fivesome"),("orgy"),("paizuri"),
	("straight"),("anal"),("vaginal_penetration"),("futa_on_female"),("cum"),("cum_inside"),("cum_in_ass"),("deep_penetration"),
	("penetration"),("rape"),("fucked_from_behind"),
	
	#location
	("indoors"),("outdoors"),("kitchen"),("beach"),("bed"),("on_bed"),
	 
	#type
	("maid"),("heroine"),("superheroine"),("nurse"),("teacher"),("goth"),
	
	#age
	("mature_female"),("milf"),("younger_female"),
	
	#remember the lack of comma at the end!
	("whateverTag51454545")
	
)


$tagListMeta = (
	("2d"),("3d"),("realistic"),("3d_digital_media_(artwork)"),("digital_media_(artwork)"),("comic"), 
	#ai
	("ai_generated"),("nai_diffusion"),("stable_diffusion"),
	#background
	("simple_background"),("blue_background"),("gradient_background"),
	#censorship
	("uncensored"),("mosaic_censorship"),("censored"),
	
	("pinup"),
	("rule_63"),
	("high_resolution"),
	("english_text"),("speech_bubble"),
	("portrait"),
	("artist_name"),
	("watermark"),
	("animated"),
	("loop"),
	("official_art"),
	("monochrome"),
	#remember the lack of comma at the end!
	("virtual_youtuber")
)

$tagListArtists = (
	("tag_here")
)

$tagListCharacters = (
	("tag_here")
)

$tagListCopyright = (
	("tag_here")
)
#############################################


