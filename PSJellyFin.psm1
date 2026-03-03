#Requires -Version 5.1

<#
.SYNOPSIS
    Complete PowerShell module for Jellyfin API (v10.11.0)

.DESCRIPTION
    This module provides a comprehensive wrapper around the entire Jellyfin REST API.
    All endpoints from the OpenAPI specification are included.

.NOTES
    Author: PowerShell Module Generator
    Version: 2.0.0
    Jellyfin API Version: 10.11.0
    OpenAPI Spec: https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json
#>

# Module variables
$script:JellyfinConfig = @{
    ServerUrl = $null
    ApiKey = $null
    AccessToken = $null
    Headers = @{
        'Content-Type' = 'application/json'
        'Accept' = 'application/json'
    }
    OpenApiSpec = $null
}

#region Core Helper Functions

function convertto-delimited([string[]]$array, $delimiter = ',')
{
     $outstring = ""
	 foreach($item in $array)
	 {
			$outstring += "$item$delimiter"
	 }
	 return $outstring.TrimEnd($delimiter)
}


function Get-JellyfinOpenApiSpec {
    <#
    .SYNOPSIS
        Fetches and caches the Jellyfin OpenAPI specification
    #>
    [CmdletBinding()]
    param(
        [string]$SpecUrl = 'https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json'
    )
    
    if (-not $script:JellyfinConfig.OpenApiSpec) {
        try {
            Write-Verbose "Fetching OpenAPI specification from $SpecUrl"
            $script:JellyfinConfig.OpenApiSpec = Invoke-RestMethod -Uri $SpecUrl -Method Get
            Write-Verbose "OpenAPI specification cached successfully"
        }
        catch {
            throw "Failed to fetch OpenAPI specification: $_"
        }
    }
    return $script:JellyfinConfig.OpenApiSpec
}

function ConvertTo-QueryString {
    <#
    .SYNOPSIS
        Converts a hashtable to URL query string
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Parameters
    )
    
    if ($null -eq $Parameters -or $Parameters.Count -eq 0) {
        return ''
    }
    
    $queryParts = foreach ($key in $Parameters.Keys) {
        $value = $Parameters[$key]
        if ($null -ne $value) {
            if ($value -is [array]) {
                "$key=$([System.Uri]::EscapeDataString((convertto-delimited $value ',')))"
            }
            elseif ($value -is [bool]) {
                "$key=$($value.ToString().ToLower())"
            }
            else {
                "$key=$([System.Uri]::EscapeDataString($value.ToString()))"
            }
        }
    }
    
    if ($queryParts) {
        return '?' + ($queryParts -join '&')
    }
    return ''
}

function Invoke-JellyfinRequest {
    <#
    .SYNOPSIS
        Core function to make HTTP requests to Jellyfin API
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter()]
        [string]$Method = 'GET',
        
        [Parameter()]
        [hashtable]$QueryParameters,
        
        [Parameter()]
        [object]$Body,
        
        [Parameter()]
        [hashtable]$Headers = @{},
        
        [Parameter()]
        [string]$ContentType,
        
        [Parameter()]
        [switch]$OutFile,
        
        [Parameter()]
        [string]$OutFilePath
    )
    
    if (-not $script:JellyfinConfig.ServerUrl) {
        throw "Jellyfin server URL not configured. Use Connect-JellyfinServer first."
    }
    
    # Build URL
    $uri = "$($script:JellyfinConfig.ServerUrl)$Path"
    if ($QueryParameters) {
        $uri += ConvertTo-QueryString -Parameters $QueryParameters
    }
    
    # Merge headers
    $requestHeaders = $script:JellyfinConfig.Headers.Clone()
    foreach ($key in $Headers.Keys) {
        $requestHeaders[$key] = $Headers[$key]
    }
    
    # Add authentication
    if ($script:JellyfinConfig.ApiKey) {
        $requestHeaders['X-Emby-Authorization'] = "MediaBrowser Token=`"$($script:JellyfinConfig.ApiKey)`""
    }
    elseif ($script:JellyfinConfig.AccessToken) {
        $requestHeaders['X-Emby-Token'] = $script:JellyfinConfig.AccessToken
    }
    
    # Prepare request parameters
    $requestParams = @{
        Uri = $uri
        Method = $Method
        Headers = $requestHeaders
        ErrorAction = 'Stop'
    }
    
    if ($ContentType) {
        $requestParams.ContentType = $ContentType
    }
    
    if ($Body) {
        if ($Body -is [string]) {
            $requestParams.Body = $Body
        }
        else {
            $requestParams.Body = $Body | ConvertTo-Json -Depth 10 -Compress
        }
    }
    
    if ($OutFile -and $OutFilePath) {
        $requestParams.OutFile = $OutFilePath
    }
    
    try {
        Write-Verbose "$Method $uri"
        if ($OutFile) {
            Invoke-RestMethod @requestParams
            return @{ FilePath = $OutFilePath }
        }
        else {
            $response = Invoke-RestMethod @requestParams
            return $response
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $statusDescription = $_.Exception.Response.StatusDescription
        Write-Error "Jellyfin API Error [$statusCode - $statusDescription]: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Configuration and Authentication

function Connect-JellyfinServer {
    <#
    .SYNOPSIS
        Connects to a Jellyfin server
    
    .DESCRIPTION
        Configures the module to connect to a Jellyfin server using either API Key or username/password authentication
    
    .PARAMETER ServerUrl
        The base URL of the Jellyfin server (e.g., http://localhost:8096)
    
    .PARAMETER ApiKey
        API key for authentication
    
    .PARAMETER Username
        Username for authentication (requires Password)
    
    .PARAMETER Password
        Password for authentication (requires Username)
    
    .PARAMETER Credential
        PSCredential object for authentication
    
    .EXAMPLE
        Connect-JellyfinServer -ServerUrl 'http://localhost:8096' -ApiKey 'your-api-key'
    
    .EXAMPLE
        Connect-JellyfinServer -ServerUrl 'http://localhost:8096' -Username 'admin' -Password 'password'
    
    .EXAMPLE
        $cred = Get-Credential
        Connect-JellyfinServer -ServerUrl 'http://localhost:8096' -Credential $cred
    #>
    [CmdletBinding(DefaultParameterSetName = 'ApiKey')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ServerUrl,
        
        [Parameter(ParameterSetName = 'ApiKey')]
        [string]$ApiKey,
        
        [Parameter(ParameterSetName = 'Credential')]
        [string]$Username,
        
        [Parameter(ParameterSetName = 'Credential')]
        [string]$Password,
        
        [Parameter(ParameterSetName = 'PSCredential')]
        [PSCredential]$Credential
    )
    
    # Normalize server URL
    $script:JellyfinConfig.ServerUrl = $ServerUrl.TrimEnd('/')

	if ($PSVersionTable.PSVersion.Major -lt 6) {
    	$UserAgent = [Microsoft.PowerShell.Commands.PSUserAgent]::InternetExplorer
	}
	else {
	    $UserAgent = [Microsoft.PowerShell.Commands.PSUserAgent]::PowerShell
	}
    # Generate a Jellyfin-like numeric suffix (13–17 digit monotonic ID)
    # Using current time in microseconds for Jellyfin-style uniqueness - a random ID is as good as anything
    $MicroSeconds = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000 + (Get-Random -Minimum 0 -Maximum 1000))
    # Combine to produce a Jellyfin-style DeviceId string
    $DeviceIdString = "$UserAgent|$MicroSeconds"
    # Base64 encode it, as Jellyfin sends it in the Authorization header
    $DeviceIdBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($DeviceIdString))
    $JellyFinVersion = Get-JellyfinVersion -ServerUrl $ServerUrl
    $headers = @{}
    $headers["Authorization"] = "MediaBrowser Client=`"Jellyfin Web`", Device=`"Chrome`", DeviceId=`"$DeviceIdBase64`", Version=`"$JellyFinVersion`""
    $headers["Origin"]= $ServerUrl
    $headers["accept"]="application/json"
    $headers["Accept-Encoding"] = "deflate"
    $headers["User-Agent"] = $UserAgent
    $headers["Accept-Language"]="en-US,en;q=0.9"
    
    if ($PSCmdlet.ParameterSetName -eq 'ApiKey') {
        $script:JellyfinConfig.ApiKey = $ApiKey
        $script:JellyfinConfig.AccessToken = $null
        Write-Verbose "Connected to Jellyfin server at $ServerUrl with API Key"
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'PSCredential') {
        $Username = $Credential.UserName
        $Password = $Credential.GetNetworkCredential().Password
        
        $authBody = @{
            Username = $Username
            Pw = $Password
        } | ConvertTo-Json
        
        try {
            $response = Invoke-RestMethod -Uri "$ServerUrl/Users/AuthenticateByName" `
                -Method Post `
                -Body $authBody `
                -ContentType 'application/json' `
                -Headers $headers
            
            $script:JellyfinConfig.AccessToken = $response.AccessToken
            $script:JellyfinConfig.ApiKey = $null
            Write-Verbose "Connected to Jellyfin server at $ServerUrl as $Username"
        }
        catch {
            throw "Authentication failed: $_"
        }
    }
    else {
        $authBody = @{
            Username = $Username
            Pw = $Password
        } | ConvertTo-Json

        try {
            $response = Invoke-RestMethod -Uri "$ServerUrl/Users/AuthenticateByName" `
                -Method Post `
                -Body $authBody `
                -ContentType 'application/json' `
                -Headers $headers
            
            $script:JellyfinConfig.AccessToken = $response.AccessToken
            $script:JellyfinConfig.ApiKey = $null
            Write-Verbose "Connected to Jellyfin server at $ServerUrl as $Username"
        }
        catch {
            throw "Authentication failed: $_"
        }
    }
}

function Get-JellyfinVersion {
    [CmdletBinding()]
    param(
        # Base URL of the Jellyfin server (no trailing slash)
        [Parameter(Mandatory=$true)]
        [string]$ServerUrl
    )

    # Normalize the server URL (remove trailing slash)
    $ServerUrl = $ServerUrl.TrimEnd('/')

    $endpoint = "$ServerUrl/System/Info/Public"

    try {
        $response = Invoke-RestMethod -Uri $endpoint -Method GET -ErrorAction Stop

        if ($response.Version) {
            return $response.Version
        }
        else {
            Write-Warning "Server responded, but no Version field was found."
            return $null
        }
    }
    catch {
        Write-Error "Failed to query Jellyfin server version: $($_.Exception.Message)"
        return $null
    }
}


function Disconnect-JellyfinServer {
    <#
    .SYNOPSIS
        Disconnects from the Jellyfin server and clears stored credentials
    #>
    [CmdletBinding()]
    param()
    
    $script:JellyfinConfig.ServerUrl = $null
    $script:JellyfinConfig.ApiKey = $null
    $script:JellyfinConfig.AccessToken = $null
    Write-Verbose "Disconnected from Jellyfin server"
}

function Test-JellyfinConnection {
    <#
    .SYNOPSIS
        Tests the connection to the Jellyfin server
    #>
    [CmdletBinding()]
    param()
    
    try {
        $info = Get-JellyfinSystemInfo
        Write-Output "Connected to Jellyfin $($info.Version) - Server Name: $($info.ServerName)"
        return $true
    }
    catch {
        Write-Warning "Connection test failed: $_"
        return $false
    }
}

#endregion

#region ActivityLog Functions (1 functions)

function Get-JellyfinLogEntries {
    <#
    .SYNOPSIS
            Gets activity log entries.

    .DESCRIPTION
        API Endpoint: GET /System/ActivityLog/Entries
        Operation ID: GetLogEntries
        Tags: ActivityLog
    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Mindate
        Optional. The minimum date. Format = ISO.

    .PARAMETER Hasuserid
        Optional. Filter log entries if it has user id, or not.
    
    .EXAMPLE
        Get-JellyfinLogEntries
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [string]$Mindate,

        [Parameter()]
        [nullable[bool]]$Hasuserid
    )


    $path = '/System/ActivityLog/Entries'
    $queryParameters = @{}
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Mindate) { $queryParameters['minDate'] = $Mindate }
    if ($PSBoundParameters.ContainsKey('Hasuserid')) { $queryParameters['hasUserId'] = $Hasuserid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region ApiKey Functions (3 functions)

function Get-JellyfinKeys {
    <#
    .SYNOPSIS
            Get all keys.

    .DESCRIPTION
        API Endpoint: GET /Auth/Keys
        Operation ID: GetKeys
        Tags: ApiKey
    .EXAMPLE
        Get-JellyfinKeys
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Auth/Keys' -Method GET
}
function New-JellyfinKey {
    <#
    .SYNOPSIS
            Create a new api key.

    .DESCRIPTION
        API Endpoint: POST /Auth/Keys
        Operation ID: CreateKey
        Tags: ApiKey
    .PARAMETER App
        Name of the app using the authentication key.
    
    .EXAMPLE
        New-JellyfinKey
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$App
    )


    $path = '/Auth/Keys'
    $queryParameters = @{}
    if ($App) { $queryParameters['app'] = $App }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinKey {
    <#
    .SYNOPSIS
            Remove an api key.

    .DESCRIPTION
        API Endpoint: DELETE /Auth/Keys/{key}
        Operation ID: RevokeKey
        Tags: ApiKey
    .PARAMETER Key
        Path parameter: key
    
    .EXAMPLE
        Remove-JellyfinRevokeKey
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Key
    )


    $path = '/Auth/Keys/{key}'
    $path = $path -replace '\{key\}', $Key

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Artists Functions (3 functions)

function Get-JellyfinArtists {
    <#
    .SYNOPSIS
            Gets all artists from a given item, folder, or the entire library.

    .DESCRIPTION
        API Endpoint: GET /Artists
        Operation ID: GetArtists
        Tags: Artists
    .PARAMETER Mincommunityrating
        Optional filter by minimum community rating.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Searchterm
        Optional. Search term.

    .PARAMETER Parentid
        Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Excludeitemtypes
        Optional. If specified, results will be filtered out based on item type. This allows multiple, comma delimited.

    .PARAMETER Includeitemtypes
        Optional. If specified, results will be filtered based on item type. This allows multiple, comma delimited.

    .PARAMETER Filters
        Optional. Specify additional filters to apply.

    .PARAMETER Isfavorite
        Optional filter by items that are marked as favorite, or not.

    .PARAMETER Mediatypes
        Optional filter by MediaType. Allows multiple, comma delimited.

    .PARAMETER Genres
        Optional. If specified, results will be filtered based on genre. This allows multiple, pipe delimited.

    .PARAMETER Genreids
        Optional. If specified, results will be filtered based on genre id. This allows multiple, pipe delimited.

    .PARAMETER Officialratings
        Optional. If specified, results will be filtered based on OfficialRating. This allows multiple, pipe delimited.

    .PARAMETER Tags
        Optional. If specified, results will be filtered based on tag. This allows multiple, pipe delimited.

    .PARAMETER Years
        Optional. If specified, results will be filtered based on production year. This allows multiple, comma delimited.

    .PARAMETER Enableuserdata
        Optional, include user data.

    .PARAMETER Imagetypelimit
        Optional, the max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Person
        Optional. If specified, results will be filtered to include only those containing the specified person.

    .PARAMETER Personids
        Optional. If specified, results will be filtered to include only those containing the specified person ids.

    .PARAMETER Persontypes
        Optional. If specified, along with Person, results will be filtered to include only those containing the specified person and PersonType. Allows multiple, comma-delimited.

    .PARAMETER Studios
        Optional. If specified, results will be filtered based on studio. This allows multiple, pipe delimited.

    .PARAMETER Studioids
        Optional. If specified, results will be filtered based on studio id. This allows multiple, pipe delimited.

    .PARAMETER Userid
        User id.

    .PARAMETER Namestartswithorgreater
        Optional filter by items whose name is sorted equally or greater than a given input string.

    .PARAMETER Namestartswith
        Optional filter by items whose name is sorted equally than a given input string.

    .PARAMETER Namelessthan
        Optional filter by items whose name is equally or lesser than a given input string.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited.

    .PARAMETER Sortorder
        Sort Order - Ascending,Descending.

    .PARAMETER Enableimages
        Optional, include image information in output.

    .PARAMETER Enabletotalrecordcount
        Total record count.
    
    .EXAMPLE
        Get-JellyfinArtists
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [double]$Mincommunityrating,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [string]$Searchterm,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Excludeitemtypes,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Includeitemtypes,

        [Parameter()]
        [ValidateSet('IsFolder','IsNotFolder','IsUnplayed','IsPlayed','IsFavorite','IsResumable','Likes','Dislikes','IsFavoriteOrLikes')]
        [string[]]$Filters,

        [Parameter()]
        [nullable[bool]]$Isfavorite,

        [Parameter()]
        [ValidateSet('Unknown','Video','Audio','Photo','Book')]
        [string[]]$Mediatypes,

        [Parameter()]
        [string[]]$Genres,

        [Parameter()]
        [string[]]$Genreids,

        [Parameter()]
        [string[]]$Officialratings,

        [Parameter()]
        [string[]]$Tags,

        [Parameter()]
        [string[]]$Years,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [string]$Person,

        [Parameter()]
        [string[]]$Personids,

        [Parameter()]
        [string[]]$Persontypes,

        [Parameter()]
        [string[]]$Studios,

        [Parameter()]
        [string[]]$Studioids,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Namestartswithorgreater,

        [Parameter()]
        [string]$Namestartswith,

        [Parameter()]
        [string]$Namelessthan,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [ValidateSet('Ascending','Descending')]
        [string[]]$Sortorder,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount
    )


    $path = '/Artists'
    $queryParameters = @{}
    if ($Mincommunityrating) { $queryParameters['minCommunityRating'] = $Mincommunityrating }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Searchterm) { $queryParameters['searchTerm'] = $Searchterm }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Excludeitemtypes) { $queryParameters['excludeItemTypes'] = convertto-delimited $Excludeitemtypes ',' }
    if ($Includeitemtypes) { $queryParameters['includeItemTypes'] = convertto-delimited $Includeitemtypes ',' }
    if ($Filters) { $queryParameters['filters'] = convertto-delimited $Filters ',' }
    if ($PSBoundParameters.ContainsKey('Isfavorite')) { $queryParameters['isFavorite'] = $Isfavorite }
    if ($Mediatypes) { $queryParameters['mediaTypes'] = convertto-delimited $Mediatypes ',' }
    if ($Genres) { $queryParameters['genres'] = convertto-delimited $Genres ',' }
    if ($Genreids) { $queryParameters['genreIds'] = convertto-delimited $Genreids ',' }
    if ($Officialratings) { $queryParameters['officialRatings'] = convertto-delimited $Officialratings ',' }
    if ($Tags) { $queryParameters['tags'] = convertto-delimited $Tags ',' }
    if ($Years) { $queryParameters['years'] = convertto-delimited $Years ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Person) { $queryParameters['person'] = $Person }
    if ($Personids) { $queryParameters['personIds'] = convertto-delimited $Personids ',' }
    if ($Persontypes) { $queryParameters['personTypes'] = convertto-delimited $Persontypes ',' }
    if ($Studios) { $queryParameters['studios'] = convertto-delimited $Studios ',' }
    if ($Studioids) { $queryParameters['studioIds'] = convertto-delimited $Studioids ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Namestartswithorgreater) { $queryParameters['nameStartsWithOrGreater'] = $Namestartswithorgreater }
    if ($Namestartswith) { $queryParameters['nameStartsWith'] = $Namestartswith }
    if ($Namelessthan) { $queryParameters['nameLessThan'] = $Namelessthan }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinArtistByName {
    <#
    .SYNOPSIS
            Gets an artist by name.

    .DESCRIPTION
        API Endpoint: GET /Artists/{name}
        Operation ID: GetArtistByName
        Tags: Artists
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.
    
    .EXAMPLE
        Get-JellyfinArtistByName
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Artists/{name}'
    $path = $path -replace '\{name\}', $Name
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinAlbumArtists {
    <#
    .SYNOPSIS
            Gets all album artists from a given item, folder, or the entire library.

    .DESCRIPTION
        API Endpoint: GET /Artists/AlbumArtists
        Operation ID: GetAlbumArtists
        Tags: Artists
    .PARAMETER Mincommunityrating
        Optional filter by minimum community rating.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Searchterm
        Optional. Search term.

    .PARAMETER Parentid
        Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Excludeitemtypes
        Optional. If specified, results will be filtered out based on item type. This allows multiple, comma delimited.

    .PARAMETER Includeitemtypes
        Optional. If specified, results will be filtered based on item type. This allows multiple, comma delimited.

    .PARAMETER Filters
        Optional. Specify additional filters to apply.

    .PARAMETER Isfavorite
        Optional filter by items that are marked as favorite, or not.

    .PARAMETER Mediatypes
        Optional filter by MediaType. Allows multiple, comma delimited.

    .PARAMETER Genres
        Optional. If specified, results will be filtered based on genre. This allows multiple, pipe delimited.

    .PARAMETER Genreids
        Optional. If specified, results will be filtered based on genre id. This allows multiple, pipe delimited.

    .PARAMETER Officialratings
        Optional. If specified, results will be filtered based on OfficialRating. This allows multiple, pipe delimited.

    .PARAMETER Tags
        Optional. If specified, results will be filtered based on tag. This allows multiple, pipe delimited.

    .PARAMETER Years
        Optional. If specified, results will be filtered based on production year. This allows multiple, comma delimited.

    .PARAMETER Enableuserdata
        Optional, include user data.

    .PARAMETER Imagetypelimit
        Optional, the max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Person
        Optional. If specified, results will be filtered to include only those containing the specified person.

    .PARAMETER Personids
        Optional. If specified, results will be filtered to include only those containing the specified person ids.

    .PARAMETER Persontypes
        Optional. If specified, along with Person, results will be filtered to include only those containing the specified person and PersonType. Allows multiple, comma-delimited.

    .PARAMETER Studios
        Optional. If specified, results will be filtered based on studio. This allows multiple, pipe delimited.

    .PARAMETER Studioids
        Optional. If specified, results will be filtered based on studio id. This allows multiple, pipe delimited.

    .PARAMETER Userid
        User id.

    .PARAMETER Namestartswithorgreater
        Optional filter by items whose name is sorted equally or greater than a given input string.

    .PARAMETER Namestartswith
        Optional filter by items whose name is sorted equally than a given input string.

    .PARAMETER Namelessthan
        Optional filter by items whose name is equally or lesser than a given input string.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited.

    .PARAMETER Sortorder
        Sort Order - Ascending,Descending.

    .PARAMETER Enableimages
        Optional, include image information in output.

    .PARAMETER Enabletotalrecordcount
        Total record count.
    
    .EXAMPLE
        Get-JellyfinAlbumArtists
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [double]$Mincommunityrating,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [string]$Searchterm,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Excludeitemtypes,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Includeitemtypes,

        [Parameter()]
        [ValidateSet('IsFolder','IsNotFolder','IsUnplayed','IsPlayed','IsFavorite','IsResumable','Likes','Dislikes','IsFavoriteOrLikes')]
        [string[]]$Filters,

        [Parameter()]
        [nullable[bool]]$Isfavorite,

        [Parameter()]
        [ValidateSet('Unknown','Video','Audio','Photo','Book')]
        [string[]]$Mediatypes,

        [Parameter()]
        [string[]]$Genres,

        [Parameter()]
        [string[]]$Genreids,

        [Parameter()]
        [string[]]$Officialratings,

        [Parameter()]
        [string[]]$Tags,

        [Parameter()]
        [string[]]$Years,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [string]$Person,

        [Parameter()]
        [string[]]$Personids,

        [Parameter()]
        [string[]]$Persontypes,

        [Parameter()]
        [string[]]$Studios,

        [Parameter()]
        [string[]]$Studioids,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Namestartswithorgreater,

        [Parameter()]
        [string]$Namestartswith,

        [Parameter()]
        [string]$Namelessthan,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [ValidateSet('Ascending','Descending')]
        [string[]]$Sortorder,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount
    )


    $path = '/Artists/AlbumArtists'
    $queryParameters = @{}
    if ($Mincommunityrating) { $queryParameters['minCommunityRating'] = $Mincommunityrating }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Searchterm) { $queryParameters['searchTerm'] = $Searchterm }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Excludeitemtypes) { $queryParameters['excludeItemTypes'] = convertto-delimited $Excludeitemtypes ',' }
    if ($Includeitemtypes) { $queryParameters['includeItemTypes'] = convertto-delimited $Includeitemtypes ',' }
    if ($Filters) { $queryParameters['filters'] = convertto-delimited $Filters ',' }
    if ($PSBoundParameters.ContainsKey('Isfavorite')) { $queryParameters['isFavorite'] = $Isfavorite }
    if ($Mediatypes) { $queryParameters['mediaTypes'] = convertto-delimited $Mediatypes ',' }
    if ($Genres) { $queryParameters['genres'] = convertto-delimited $Genres ',' }
    if ($Genreids) { $queryParameters['genreIds'] = convertto-delimited $Genreids ',' }
    if ($Officialratings) { $queryParameters['officialRatings'] = convertto-delimited $Officialratings ',' }
    if ($Tags) { $queryParameters['tags'] = convertto-delimited $Tags ',' }
    if ($Years) { $queryParameters['years'] = convertto-delimited $Years ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Person) { $queryParameters['person'] = $Person }
    if ($Personids) { $queryParameters['personIds'] = convertto-delimited $Personids ',' }
    if ($Persontypes) { $queryParameters['personTypes'] = convertto-delimited $Persontypes ',' }
    if ($Studios) { $queryParameters['studios'] = convertto-delimited $Studios ',' }
    if ($Studioids) { $queryParameters['studioIds'] = convertto-delimited $Studioids ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Namestartswithorgreater) { $queryParameters['nameStartsWithOrGreater'] = $Namestartswithorgreater }
    if ($Namestartswith) { $queryParameters['nameStartsWith'] = $Namestartswith }
    if ($Namelessthan) { $queryParameters['nameLessThan'] = $Namelessthan }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Audio Functions (4 functions)

function Get-JellyfinAudioStream {
    <#
    .SYNOPSIS
            Gets an audio stream.

    .DESCRIPTION
        API Endpoint: GET /Audio/{itemId}/stream
        Operation ID: GetAudioStream
        Tags: Audio
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Container
        The audio container.

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3. If omitted the server will auto-select using the url's extension.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264. If omitted the server will auto-select using the url's extension.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.
    
    .EXAMPLE
        Get-JellyfinAudioStream
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Container,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding
    )


    $path = '/Audio/{itemId}/stream'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Container) { $queryParameters['container'] = convertto-delimited $Container ',' }
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinAudioStream {
    <#
    .SYNOPSIS
            Gets an audio stream.

    .DESCRIPTION
        API Endpoint: HEAD /Audio/{itemId}/stream
        Operation ID: HeadAudioStream
        Tags: Audio
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Container
        The audio container.

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3. If omitted the server will auto-select using the url's extension.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264. If omitted the server will auto-select using the url's extension.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.
    
    .EXAMPLE
        Test-JellyfinAudioStream
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Container,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding
    )


    $path = '/Audio/{itemId}/stream'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Container) { $queryParameters['container'] = convertto-delimited $Container ',' }
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinAudioStreamByContainer {
    <#
    .SYNOPSIS
            Gets an audio stream.

    .DESCRIPTION
        API Endpoint: GET /Audio/{itemId}/stream.{container}
        Operation ID: GetAudioStreamByContainer
        Tags: Audio
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Container
        Path parameter: container

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3. If omitted the server will auto-select using the url's extension.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264. If omitted the server will auto-select using the url's extension.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.
    
    .EXAMPLE
        Get-JellyfinAudioStreamByContainer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Container,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding
    )


    $path = '/Audio/{itemId}/stream.{container}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{container\}', $Container
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinAudioStreamByContainer {
    <#
    .SYNOPSIS
            Gets an audio stream.

    .DESCRIPTION
        API Endpoint: HEAD /Audio/{itemId}/stream.{container}
        Operation ID: HeadAudioStreamByContainer
        Tags: Audio
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Container
        Path parameter: container

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3. If omitted the server will auto-select using the url's extension.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264. If omitted the server will auto-select using the url's extension.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.
    
    .EXAMPLE
        Test-JellyfinAudioStreamByContainer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Container,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding
    )


    $path = '/Audio/{itemId}/stream.{container}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{container\}', $Container
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Backup Functions (4 functions)

function Get-JellyfinListBackups {
    <#
    .SYNOPSIS
            Gets a list of all currently present backups in the backup directory.

    .DESCRIPTION
        API Endpoint: GET /Backup
        Operation ID: ListBackups
        Tags: Backup
    .EXAMPLE
        Get-JellyfinListBackups
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Backup' -Method GET
}
function New-JellyfinBackup {
    <#
    .SYNOPSIS
            Creates a new Backup.

    .DESCRIPTION
        API Endpoint: POST /Backup/Create
        Operation ID: CreateBackup
        Tags: Backup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        New-JellyfinBackup
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Backup/Create'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinBackup {
    <#
    .SYNOPSIS
            Gets the descriptor from an existing archive is present.

    .DESCRIPTION
        API Endpoint: GET /Backup/Manifest
        Operation ID: GetBackup
        Tags: Backup
    .PARAMETER Path
        The data to start a restore process.
    
    .EXAMPLE
        Get-JellyfinBackup
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )


    $path = '/Backup/Manifest'
    $queryParameters = @{}
    if ($Path) { $queryParameters['path'] = $Path }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Start-JellyfinRestoreBackup {
    <#
    .SYNOPSIS
            Restores to a backup by restarting the server and applying the backup.

    .DESCRIPTION
        API Endpoint: POST /Backup/Restore
        Operation ID: StartRestoreBackup
        Tags: Backup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Start-JellyfinRestoreBackup
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Backup/Restore'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Branding Functions (3 functions)

function Get-JellyfinBrandingOptions {
    <#
    .SYNOPSIS
            Gets branding configuration.

    .DESCRIPTION
        API Endpoint: GET /Branding/Configuration
        Operation ID: GetBrandingOptions
        Tags: Branding
    .EXAMPLE
        Get-JellyfinBrandingOptions
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Branding/Configuration' -Method GET
}
function Get-JellyfinBrandingCss {
    <#
    .SYNOPSIS
            Gets branding css.

    .DESCRIPTION
        API Endpoint: GET /Branding/Css
        Operation ID: GetBrandingCss
        Tags: Branding
    .EXAMPLE
        Get-JellyfinBrandingCss
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Branding/Css' -Method GET
}
function Get-JellyfinBrandingCss_2 {
    <#
    .SYNOPSIS
            Gets branding css.

    .DESCRIPTION
        API Endpoint: GET /Branding/Css.css
        Operation ID: GetBrandingCss_2
        Tags: Branding
    .EXAMPLE
        Get-JellyfinBrandingCss_2
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Branding/Css.css' -Method GET
}
#endregion

#region Channels Functions (5 functions)

function Get-JellyfinChannels {
    <#
    .SYNOPSIS
            Gets available channels.

    .DESCRIPTION
        API Endpoint: GET /Channels
        Operation ID: GetChannels
        Tags: Channels
    .PARAMETER Userid
        User Id to filter by. Use System.Guid.Empty to not filter by user.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Supportslatestitems
        Optional. Filter by channels that support getting latest items.

    .PARAMETER Supportsmediadeletion
        Optional. Filter by channels that support media deletion.

    .PARAMETER Isfavorite
        Optional. Filter by channels that are favorite.
    
    .EXAMPLE
        Get-JellyfinChannels
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [nullable[bool]]$Supportslatestitems,

        [Parameter()]
        [nullable[bool]]$Supportsmediadeletion,

        [Parameter()]
        [nullable[bool]]$Isfavorite
    )


    $path = '/Channels'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($PSBoundParameters.ContainsKey('Supportslatestitems')) { $queryParameters['supportsLatestItems'] = $Supportslatestitems }
    if ($PSBoundParameters.ContainsKey('Supportsmediadeletion')) { $queryParameters['supportsMediaDeletion'] = $Supportsmediadeletion }
    if ($PSBoundParameters.ContainsKey('Isfavorite')) { $queryParameters['isFavorite'] = $Isfavorite }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinChannelFeatures {
    <#
    .SYNOPSIS
            Get channel features.

    .DESCRIPTION
        API Endpoint: GET /Channels/{channelId}/Features
        Operation ID: GetChannelFeatures
        Tags: Channels
    .PARAMETER Channelid
        Path parameter: channelId
    
    .EXAMPLE
        Get-JellyfinChannelFeatures
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Channelid
    )


    $path = '/Channels/{channelId}/Features'
    $path = $path -replace '\{channelId\}', $Channelid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinChannelItems {
    <#
    .SYNOPSIS
            Get channel items.

    .DESCRIPTION
        API Endpoint: GET /Channels/{channelId}/Items
        Operation ID: GetChannelItems
        Tags: Channels
    .PARAMETER Channelid
        Path parameter: channelId

    .PARAMETER Folderid
        Optional. Folder Id.

    .PARAMETER Userid
        Optional. User Id.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Sortorder
        Optional. Sort Order - Ascending,Descending.

    .PARAMETER Filters
        Optional. Specify additional filters to apply.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited. Options: Album, AlbumArtist, Artist, Budget, CommunityRating, CriticRating, DateCreated, DatePlayed, PlayCount, PremiereDate, ProductionYear, SortName, Random, Revenue, Runtime.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.
    
    .EXAMPLE
        Get-JellyfinChannelItems
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Channelid,

        [Parameter()]
        [string]$Folderid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('Ascending','Descending')]
        [string[]]$Sortorder,

        [Parameter()]
        [ValidateSet('IsFolder','IsNotFolder','IsUnplayed','IsPlayed','IsFavorite','IsResumable','Likes','Dislikes','IsFavoriteOrLikes')]
        [string[]]$Filters,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields
    )


    $path = '/Channels/{channelId}/Items'
    $path = $path -replace '\{channelId\}', $Channelid
    $queryParameters = @{}
    if ($Folderid) { $queryParameters['folderId'] = $Folderid }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }
    if ($Filters) { $queryParameters['filters'] = convertto-delimited $Filters ',' }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinAllChannelFeatures {
    <#
    .SYNOPSIS
            Get all channel features.

    .DESCRIPTION
        API Endpoint: GET /Channels/Features
        Operation ID: GetAllChannelFeatures
        Tags: Channels
    .EXAMPLE
        Get-JellyfinAllChannelFeatures
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Channels/Features' -Method GET
}
function Get-JellyfinLatestChannelItems {
    <#
    .SYNOPSIS
            Gets latest channel items.

    .DESCRIPTION
        API Endpoint: GET /Channels/Items/Latest
        Operation ID: GetLatestChannelItems
        Tags: Channels
    .PARAMETER Userid
        Optional. User Id.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Filters
        Optional. Specify additional filters to apply.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Channelids
        Optional. Specify one or more channel id's, comma delimited.
    
    .EXAMPLE
        Get-JellyfinLatestChannelItems
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('IsFolder','IsNotFolder','IsUnplayed','IsPlayed','IsFavorite','IsResumable','Likes','Dislikes','IsFavoriteOrLikes')]
        [string[]]$Filters,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [string[]]$Channelids
    )


    $path = '/Channels/Items/Latest'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Filters) { $queryParameters['filters'] = convertto-delimited $Filters ',' }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Channelids) { $queryParameters['channelIds'] = convertto-delimited $Channelids ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region ClientLog Functions (1 functions)

function Invoke-JellyfinLogFile {
    <#
    .SYNOPSIS
            Upload a document.

    .DESCRIPTION
        API Endpoint: POST /ClientLog/Document
        Operation ID: LogFile
        Tags: ClientLog
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinLogFile
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/ClientLog/Document'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Collection Functions (3 functions)

function New-JellyfinCollection {
    <#
    .SYNOPSIS
            Creates a new collection.

    .DESCRIPTION
        API Endpoint: POST /Collections
        Operation ID: CreateCollection
        Tags: Collection
    .PARAMETER Name
        The name of the collection.

    .PARAMETER Ids
        Item Ids to add to the collection.

    .PARAMETER Parentid
        Optional. Create the collection within a specific folder.

    .PARAMETER Islocked
        Whether or not to lock the new collection.
    
    .EXAMPLE
        New-JellyfinCollection
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string[]]$Ids,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [nullable[bool]]$Islocked
    )


    $path = '/Collections'
    $queryParameters = @{}
    if ($Name) { $queryParameters['name'] = $Name }
    if ($Ids) { $queryParameters['ids'] = convertto-delimited $Ids ',' }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($PSBoundParameters.ContainsKey('Islocked')) { $queryParameters['isLocked'] = $Islocked }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}

function Add-JellyfinItemsToCollection {
	    <#
    .SYNOPSIS
            Creates a new collection.

    .DESCRIPTION
        API Endpoint: POST /Collections
        Operation ID: CreateCollection
        Tags: Collection
    .PARAMETER Name
        The name of the collection.

    .PARAMETER Ids
        Item Id to add to the collection.

    
    .EXAMPLE
        Add-JellyfinItemsToCollection
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CollectionId,

        [Parameter(Mandatory)]
        [string[]]$Ids
    )


    $path = "/Collections/$CollectionId/Items"
    $queryParameters = @{}
    if ($Ids) { $queryParameters['ids'] = convertto-delimited $Ids ',' }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}

function Remove-JellyfinFromCollection {
    <#
    .SYNOPSIS
            Removes items from a collection.

    .DESCRIPTION
        API Endpoint: DELETE /Collections/{collectionId}/Items
        Operation ID: RemoveFromCollection
        Tags: Collection
    .PARAMETER Collectionid
        Path parameter: collectionId

    .PARAMETER Ids
        Item ids, comma delimited.
    
    .EXAMPLE
        Remove-JellyfinFromCollection
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Collectionid,

        [Parameter(Mandatory)]
        [string[]]$Ids
    )


    $path = '/Collections/{collectionId}/Items'
    $path = $path -replace '\{collectionId\}', $Collectionid
    $queryParameters = @{}
    if ($Ids) { $queryParameters['ids'] = convertto-delimited $Ids ',' }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Configuration Functions (6 functions)

function Get-JellyfinConfiguration {
    <#
    .SYNOPSIS
            Gets application configuration.

    .DESCRIPTION
        API Endpoint: GET /System/Configuration
        Operation ID: GetConfiguration
        Tags: Configuration
    .EXAMPLE
        Get-JellyfinConfiguration
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/System/Configuration' -Method GET
}
function Set-JellyfinConfiguration {
    <#
    .SYNOPSIS
            Updates application configuration.

    .DESCRIPTION
        API Endpoint: POST /System/Configuration
        Operation ID: UpdateConfiguration
        Tags: Configuration
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinConfiguration
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/System/Configuration'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinNamedConfiguration {
    <#
    .SYNOPSIS
            Gets a named configuration.

    .DESCRIPTION
        API Endpoint: GET /System/Configuration/{key}
        Operation ID: GetNamedConfiguration
        Tags: Configuration
    .PARAMETER Key
        Path parameter: key
    
    .EXAMPLE
        Get-JellyfinNamedConfiguration
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Key
    )


    $path = '/System/Configuration/{key}'
    $path = $path -replace '\{key\}', $Key

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinNamedConfiguration {
    <#
    .SYNOPSIS
            Updates named configuration.

    .DESCRIPTION
        API Endpoint: POST /System/Configuration/{key}
        Operation ID: UpdateNamedConfiguration
        Tags: Configuration
    .PARAMETER Key
        Path parameter: key

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinNamedConfiguration
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Key,

        [Parameter()]
        [object]$Body
    )


    $path = '/System/Configuration/{key}'
    $path = $path -replace '\{key\}', $Key

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinBrandingConfiguration {
    <#
    .SYNOPSIS
            Updates branding configuration.

    .DESCRIPTION
        API Endpoint: POST /System/Configuration/Branding
        Operation ID: UpdateBrandingConfiguration
        Tags: Configuration
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinBrandingConfiguration
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/System/Configuration/Branding'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinDefaultMetadataOptions {
    <#
    .SYNOPSIS
            Gets a default MetadataOptions object.

    .DESCRIPTION
        API Endpoint: GET /System/Configuration/MetadataOptions/Default
        Operation ID: GetDefaultMetadataOptions
        Tags: Configuration
    .EXAMPLE
        Get-JellyfinDefaultMetadataOptions
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/System/Configuration/MetadataOptions/Default' -Method GET
}
#endregion

#region Dashboard Functions (2 functions)

function Get-JellyfinDashboardConfigurationPage {
    <#
    .SYNOPSIS
            Gets a dashboard configuration page.

    .DESCRIPTION
        API Endpoint: GET /web/ConfigurationPage
        Operation ID: GetDashboardConfigurationPage
        Tags: Dashboard
    .PARAMETER Name
        The name of the page.
    
    .EXAMPLE
        Get-JellyfinDashboardConfigurationPage
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name
    )


    $path = '/web/ConfigurationPage'
    $queryParameters = @{}
    if ($Name) { $queryParameters['name'] = $Name }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinConfigurationPages {
    <#
    .SYNOPSIS
            Gets the configuration pages.

    .DESCRIPTION
        API Endpoint: GET /web/ConfigurationPages
        Operation ID: GetConfigurationPages
        Tags: Dashboard
    .PARAMETER Enableinmainmenu
        Whether to enable in the main menu.
    
    .EXAMPLE
        Get-JellyfinConfigurationPages
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [nullable[bool]]$Enableinmainmenu
    )


    $path = '/web/ConfigurationPages'
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Enableinmainmenu')) { $queryParameters['enableInMainMenu'] = $Enableinmainmenu }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Devices Functions (5 functions)

function Get-JellyfinDevices {
    <#
    .SYNOPSIS
            Get Devices.

    .DESCRIPTION
        API Endpoint: GET /Devices
        Operation ID: GetDevices
        Tags: Devices
    .PARAMETER Userid
        Gets or sets the user identifier.
    
    .EXAMPLE
        Get-JellyfinDevices
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid
    )


    $path = '/Devices'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinDevice {
    <#
    .SYNOPSIS
            Deletes a device.

    .DESCRIPTION
        API Endpoint: DELETE /Devices
        Operation ID: DeleteDevice
        Tags: Devices
    .PARAMETER Id
        Device Id.
    
    .EXAMPLE
        Remove-JellyfinDevice
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )


    $path = '/Devices'
    $queryParameters = @{}
    if ($Id) { $queryParameters['id'] = $Id }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinDeviceInfo {
    <#
    .SYNOPSIS
            Get info for a device.

    .DESCRIPTION
        API Endpoint: GET /Devices/Info
        Operation ID: GetDeviceInfo
        Tags: Devices
    .PARAMETER Id
        Device Id.
    
    .EXAMPLE
        Get-JellyfinDeviceInfo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )


    $path = '/Devices/Info'
    $queryParameters = @{}
    if ($Id) { $queryParameters['id'] = $Id }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinDeviceOptions {
    <#
    .SYNOPSIS
            Get options for a device.

    .DESCRIPTION
        API Endpoint: GET /Devices/Options
        Operation ID: GetDeviceOptions
        Tags: Devices
    .PARAMETER Id
        Device Id.
    
    .EXAMPLE
        Get-JellyfinDeviceOptions
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )


    $path = '/Devices/Options'
    $queryParameters = @{}
    if ($Id) { $queryParameters['id'] = $Id }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinDeviceOptions {
    <#
    .SYNOPSIS
            Update device options.

    .DESCRIPTION
        API Endpoint: POST /Devices/Options
        Operation ID: UpdateDeviceOptions
        Tags: Devices
    .PARAMETER Id
        Device Id.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinDeviceOptions
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter()]
        [object]$Body
    )


    $path = '/Devices/Options'
    $queryParameters = @{}
    if ($Id) { $queryParameters['id'] = $Id }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region DisplayPreferences Functions (2 functions)

function Get-JellyfinDisplayPreferences {
    <#
    .SYNOPSIS
            Get Display Preferences.

    .DESCRIPTION
        API Endpoint: GET /DisplayPreferences/{displayPreferencesId}
        Operation ID: GetDisplayPreferences
        Tags: DisplayPreferences
    .PARAMETER Displaypreferencesid
        Path parameter: displayPreferencesId

    .PARAMETER Userid
        User id.

    .PARAMETER Client
        Client.
    
    .EXAMPLE
        Get-JellyfinDisplayPreferences
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Displaypreferencesid,

        [Parameter()]
        [string]$Userid,

        [Parameter(Mandatory)]
        [string]$Client
    )


    $path = '/DisplayPreferences/{displayPreferencesId}'
    $path = $path -replace '\{displayPreferencesId\}', $Displaypreferencesid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Client) { $queryParameters['client'] = $Client }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinDisplayPreferences {
    <#
    .SYNOPSIS
            Update Display Preferences.

    .DESCRIPTION
        API Endpoint: POST /DisplayPreferences/{displayPreferencesId}
        Operation ID: UpdateDisplayPreferences
        Tags: DisplayPreferences
    .PARAMETER Displaypreferencesid
        Path parameter: displayPreferencesId

    .PARAMETER Userid
        User Id.

    .PARAMETER Client
        Client.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinDisplayPreferences
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Displaypreferencesid,

        [Parameter()]
        [string]$Userid,

        [Parameter(Mandatory)]
        [string]$Client,

        [Parameter()]
        [object]$Body
    )


    $path = '/DisplayPreferences/{displayPreferencesId}'
    $path = $path -replace '\{displayPreferencesId\}', $Displaypreferencesid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Client) { $queryParameters['client'] = $Client }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region DynamicHls Functions (9 functions)

function Get-JellyfinHlsAudioSegment {
    <#
    .SYNOPSIS
            Gets a video stream using HTTP live streaming.

    .DESCRIPTION
        API Endpoint: GET /Audio/{itemId}/hls1/{playlistId}/{segmentId}.{container}
        Operation ID: GetHlsAudioSegment
        Tags: DynamicHls
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Playlistid
        Path parameter: playlistId

    .PARAMETER Segmentid
        Path parameter: segmentId

    .PARAMETER Container
        Path parameter: container

    .PARAMETER Runtimeticks
        The position of the requested segment in ticks.

    .PARAMETER Actualsegmentlengthticks
        The length of the requested segment in ticks.

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Maxstreamingbitrate
        Optional. The maximum streaming bitrate.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.
    
    .EXAMPLE
        Get-JellyfinHlsAudioSegment
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Segmentid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Container,

        [Parameter(Mandatory)]
        [int]$Runtimeticks,

        [Parameter(Mandatory)]
        [int]$Actualsegmentlengthticks,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Maxstreamingbitrate,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding
    )


    $path = '/Audio/{itemId}/hls1/{playlistId}/{segmentId}.{container}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{playlistId\}', $Playlistid
    $path = $path -replace '\{segmentId\}', $Segmentid
    $path = $path -replace '\{container\}', $Container
    $queryParameters = @{}
    if ($Runtimeticks) { $queryParameters['runtimeTicks'] = $Runtimeticks }
    if ($Actualsegmentlengthticks) { $queryParameters['actualSegmentLengthTicks'] = $Actualsegmentlengthticks }
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Maxstreamingbitrate) { $queryParameters['maxStreamingBitrate'] = $Maxstreamingbitrate }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinVariantHlsAudioPlaylist {
    <#
    .SYNOPSIS
            Gets an audio stream using HTTP live streaming.

    .DESCRIPTION
        API Endpoint: GET /Audio/{itemId}/main.m3u8
        Operation ID: GetVariantHlsAudioPlaylist
        Tags: DynamicHls
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Maxstreamingbitrate
        Optional. The maximum streaming bitrate.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.
    
    .EXAMPLE
        Get-JellyfinVariantHlsAudioPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Maxstreamingbitrate,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding
    )


    $path = '/Audio/{itemId}/main.m3u8'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Maxstreamingbitrate) { $queryParameters['maxStreamingBitrate'] = $Maxstreamingbitrate }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinMasterHlsAudioPlaylist {
    <#
    .SYNOPSIS
            Gets an audio hls playlist stream.

    .DESCRIPTION
        API Endpoint: GET /Audio/{itemId}/master.m3u8
        Operation ID: GetMasterHlsAudioPlaylist
        Tags: DynamicHls
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Maxstreamingbitrate
        Optional. The maximum streaming bitrate.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableadaptivebitratestreaming
        Enable adaptive bitrate streaming.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.
    
    .EXAMPLE
        Get-JellyfinMasterHlsAudioPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter(Mandatory)]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Maxstreamingbitrate,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableadaptivebitratestreaming,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding
    )


    $path = '/Audio/{itemId}/master.m3u8'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Maxstreamingbitrate) { $queryParameters['maxStreamingBitrate'] = $Maxstreamingbitrate }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableadaptivebitratestreaming')) { $queryParameters['enableAdaptiveBitrateStreaming'] = $Enableadaptivebitratestreaming }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinMasterHlsAudioPlaylist {
    <#
    .SYNOPSIS
            Gets an audio hls playlist stream.

    .DESCRIPTION
        API Endpoint: HEAD /Audio/{itemId}/master.m3u8
        Operation ID: HeadMasterHlsAudioPlaylist
        Tags: DynamicHls
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Maxstreamingbitrate
        Optional. The maximum streaming bitrate.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableadaptivebitratestreaming
        Enable adaptive bitrate streaming.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.
    
    .EXAMPLE
        Test-JellyfinMasterHlsAudioPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter(Mandatory)]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Maxstreamingbitrate,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableadaptivebitratestreaming,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding
    )


    $path = '/Audio/{itemId}/master.m3u8'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Maxstreamingbitrate) { $queryParameters['maxStreamingBitrate'] = $Maxstreamingbitrate }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableadaptivebitratestreaming')) { $queryParameters['enableAdaptiveBitrateStreaming'] = $Enableadaptivebitratestreaming }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinHlsVideoSegment {
    <#
    .SYNOPSIS
            Gets a video stream using HTTP live streaming.

    .DESCRIPTION
        API Endpoint: GET /Videos/{itemId}/hls1/{playlistId}/{segmentId}.{container}
        Operation ID: GetHlsVideoSegment
        Tags: DynamicHls
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Playlistid
        Path parameter: playlistId

    .PARAMETER Segmentid
        Path parameter: segmentId

    .PARAMETER Container
        Path parameter: container

    .PARAMETER Runtimeticks
        The position of the requested segment in ticks.

    .PARAMETER Actualsegmentlengthticks
        The length of the requested segment in ticks.

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The desired segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Maxwidth
        Optional. The maximum horizontal resolution of the encoded video.

    .PARAMETER Maxheight
        Optional. The maximum vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.

    .PARAMETER Alwaysburninsubtitlewhentranscoding
        Whether to always burn in subtitles when transcoding.
    
    .EXAMPLE
        Get-JellyfinHlsVideoSegment
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Segmentid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Container,

        [Parameter(Mandatory)]
        [int]$Runtimeticks,

        [Parameter(Mandatory)]
        [int]$Actualsegmentlengthticks,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding,

        [Parameter()]
        [nullable[bool]]$Alwaysburninsubtitlewhentranscoding
    )


    $path = '/Videos/{itemId}/hls1/{playlistId}/{segmentId}.{container}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{playlistId\}', $Playlistid
    $path = $path -replace '\{segmentId\}', $Segmentid
    $path = $path -replace '\{container\}', $Container
    $queryParameters = @{}
    if ($Runtimeticks) { $queryParameters['runtimeTicks'] = $Runtimeticks }
    if ($Actualsegmentlengthticks) { $queryParameters['actualSegmentLengthTicks'] = $Actualsegmentlengthticks }
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }
    if ($PSBoundParameters.ContainsKey('Alwaysburninsubtitlewhentranscoding')) { $queryParameters['alwaysBurnInSubtitleWhenTranscoding'] = $Alwaysburninsubtitlewhentranscoding }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinLiveHlsStream {
    <#
    .SYNOPSIS
            Gets a hls live stream.

    .DESCRIPTION
        API Endpoint: GET /Videos/{itemId}/live.m3u8
        Operation ID: GetLiveHlsStream
        Tags: DynamicHls
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Container
        The audio container.

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Maxwidth
        Optional. The max width.

    .PARAMETER Maxheight
        Optional. The max height.

    .PARAMETER Enablesubtitlesinmanifest
        Optional. Whether to enable subtitles in the manifest.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.

    .PARAMETER Alwaysburninsubtitlewhentranscoding
        Whether to always burn in subtitles when transcoding.
    
    .EXAMPLE
        Get-JellyfinLiveHlsStream
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Container,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [nullable[bool]]$Enablesubtitlesinmanifest,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding,

        [Parameter()]
        [nullable[bool]]$Alwaysburninsubtitlewhentranscoding
    )


    $path = '/Videos/{itemId}/live.m3u8'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Container) { $queryParameters['container'] = convertto-delimited $Container ',' }
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($PSBoundParameters.ContainsKey('Enablesubtitlesinmanifest')) { $queryParameters['enableSubtitlesInManifest'] = $Enablesubtitlesinmanifest }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }
    if ($PSBoundParameters.ContainsKey('Alwaysburninsubtitlewhentranscoding')) { $queryParameters['alwaysBurnInSubtitleWhenTranscoding'] = $Alwaysburninsubtitlewhentranscoding }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinVariantHlsVideoPlaylist {
    <#
    .SYNOPSIS
            Gets a video stream using HTTP live streaming.

    .DESCRIPTION
        API Endpoint: GET /Videos/{itemId}/main.m3u8
        Operation ID: GetVariantHlsVideoPlaylist
        Tags: DynamicHls
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Maxwidth
        Optional. The maximum horizontal resolution of the encoded video.

    .PARAMETER Maxheight
        Optional. The maximum vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.

    .PARAMETER Alwaysburninsubtitlewhentranscoding
        Whether to always burn in subtitles when transcoding.
    
    .EXAMPLE
        Get-JellyfinVariantHlsVideoPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding,

        [Parameter()]
        [nullable[bool]]$Alwaysburninsubtitlewhentranscoding
    )


    $path = '/Videos/{itemId}/main.m3u8'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }
    if ($PSBoundParameters.ContainsKey('Alwaysburninsubtitlewhentranscoding')) { $queryParameters['alwaysBurnInSubtitleWhenTranscoding'] = $Alwaysburninsubtitlewhentranscoding }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinMasterHlsVideoPlaylist {
    <#
    .SYNOPSIS
            Gets a video hls playlist stream.

    .DESCRIPTION
        API Endpoint: GET /Videos/{itemId}/master.m3u8
        Operation ID: GetMasterHlsVideoPlaylist
        Tags: DynamicHls
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Maxwidth
        Optional. The maximum horizontal resolution of the encoded video.

    .PARAMETER Maxheight
        Optional. The maximum vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableadaptivebitratestreaming
        Enable adaptive bitrate streaming.

    .PARAMETER Enabletrickplay
        Enable trickplay image playlists being added to master playlist.

    .PARAMETER Enableaudiovbrencoding
        Whether to enable Audio Encoding.

    .PARAMETER Alwaysburninsubtitlewhentranscoding
        Whether to always burn in subtitles when transcoding.
    
    .EXAMPLE
        Get-JellyfinMasterHlsVideoPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter(Mandatory)]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableadaptivebitratestreaming,

        [Parameter()]
        [nullable[bool]]$Enabletrickplay,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding,

        [Parameter()]
        [nullable[bool]]$Alwaysburninsubtitlewhentranscoding
    )


    $path = '/Videos/{itemId}/master.m3u8'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableadaptivebitratestreaming')) { $queryParameters['enableAdaptiveBitrateStreaming'] = $Enableadaptivebitratestreaming }
    if ($PSBoundParameters.ContainsKey('Enabletrickplay')) { $queryParameters['enableTrickplay'] = $Enabletrickplay }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }
    if ($PSBoundParameters.ContainsKey('Alwaysburninsubtitlewhentranscoding')) { $queryParameters['alwaysBurnInSubtitleWhenTranscoding'] = $Alwaysburninsubtitlewhentranscoding }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinMasterHlsVideoPlaylist {
    <#
    .SYNOPSIS
            Gets a video hls playlist stream.

    .DESCRIPTION
        API Endpoint: HEAD /Videos/{itemId}/master.m3u8
        Operation ID: HeadMasterHlsVideoPlaylist
        Tags: DynamicHls
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Maxwidth
        Optional. The maximum horizontal resolution of the encoded video.

    .PARAMETER Maxheight
        Optional. The maximum vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableadaptivebitratestreaming
        Enable adaptive bitrate streaming.

    .PARAMETER Enabletrickplay
        Enable trickplay image playlists being added to master playlist.

    .PARAMETER Enableaudiovbrencoding
        Whether to enable Audio Encoding.

    .PARAMETER Alwaysburninsubtitlewhentranscoding
        Whether to always burn in subtitles when transcoding.
    
    .EXAMPLE
        Test-JellyfinMasterHlsVideoPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter(Mandatory)]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableadaptivebitratestreaming,

        [Parameter()]
        [nullable[bool]]$Enabletrickplay,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding,

        [Parameter()]
        [nullable[bool]]$Alwaysburninsubtitlewhentranscoding
    )


    $path = '/Videos/{itemId}/master.m3u8'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableadaptivebitratestreaming')) { $queryParameters['enableAdaptiveBitrateStreaming'] = $Enableadaptivebitratestreaming }
    if ($PSBoundParameters.ContainsKey('Enabletrickplay')) { $queryParameters['enableTrickplay'] = $Enabletrickplay }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }
    if ($PSBoundParameters.ContainsKey('Alwaysburninsubtitlewhentranscoding')) { $queryParameters['alwaysBurnInSubtitleWhenTranscoding'] = $Alwaysburninsubtitlewhentranscoding }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Environment Functions (6 functions)

function Get-JellyfinDefaultDirectoryBrowser {
    <#
    .SYNOPSIS
            Get Default directory browser.

    .DESCRIPTION
        API Endpoint: GET /Environment/DefaultDirectoryBrowser
        Operation ID: GetDefaultDirectoryBrowser
        Tags: Environment
    .EXAMPLE
        Get-JellyfinDefaultDirectoryBrowser
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Environment/DefaultDirectoryBrowser' -Method GET
}
function Get-JellyfinDirectoryContents {
    <#
    .SYNOPSIS
            Gets the contents of a given directory in the file system.

    .DESCRIPTION
        API Endpoint: GET /Environment/DirectoryContents
        Operation ID: GetDirectoryContents
        Tags: Environment
    .PARAMETER Path
        The path.

    .PARAMETER Includefiles
        An optional filter to include or exclude files from the results. true/false.

    .PARAMETER Includedirectories
        An optional filter to include or exclude folders from the results. true/false.
    
    .EXAMPLE
        Get-JellyfinDirectoryContents
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [nullable[bool]]$Includefiles,

        [Parameter()]
        [nullable[bool]]$Includedirectories
    )


    $path = '/Environment/DirectoryContents'
    $queryParameters = @{}
    if ($Path) { $queryParameters['path'] = $Path }
    if ($PSBoundParameters.ContainsKey('Includefiles')) { $queryParameters['includeFiles'] = $Includefiles }
    if ($PSBoundParameters.ContainsKey('Includedirectories')) { $queryParameters['includeDirectories'] = $Includedirectories }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinDrives {
    <#
    .SYNOPSIS
            Gets available drives from the server's file system.

    .DESCRIPTION
        API Endpoint: GET /Environment/Drives
        Operation ID: GetDrives
        Tags: Environment
    .EXAMPLE
        Get-JellyfinDrives
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Environment/Drives' -Method GET
}
function Get-JellyfinNetworkShares {
    <#
    .SYNOPSIS
            Gets network paths.

    .DESCRIPTION
        API Endpoint: GET /Environment/NetworkShares
        Operation ID: GetNetworkShares
        Tags: Environment
    .EXAMPLE
        Get-JellyfinNetworkShares
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Environment/NetworkShares' -Method GET
}
function Get-JellyfinParentPath {
    <#
    .SYNOPSIS
            Gets the parent path of a given path.

    .DESCRIPTION
        API Endpoint: GET /Environment/ParentPath
        Operation ID: GetParentPath
        Tags: Environment
    .PARAMETER Path
        The path.
    
    .EXAMPLE
        Get-JellyfinParentPath
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )


    $path = '/Environment/ParentPath'
    $queryParameters = @{}
    if ($Path) { $queryParameters['path'] = $Path }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinValidatePath {
    <#
    .SYNOPSIS
            Validates path.

    .DESCRIPTION
        API Endpoint: POST /Environment/ValidatePath
        Operation ID: ValidatePath
        Tags: Environment
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinValidatePath
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Environment/ValidatePath'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Filter Functions (2 functions)

function Get-JellyfinQueryFiltersLegacy {
    <#
    .SYNOPSIS
            Gets legacy query filters.

    .DESCRIPTION
        API Endpoint: GET /Items/Filters
        Operation ID: GetQueryFiltersLegacy
        Tags: Filter
    .PARAMETER Userid
        Optional. User id.

    .PARAMETER Parentid
        Optional. Parent id.

    .PARAMETER Includeitemtypes
        Optional. If specified, results will be filtered based on item type. This allows multiple, comma delimited.

    .PARAMETER Mediatypes
        Optional. Filter by MediaType. Allows multiple, comma delimited.
    
    .EXAMPLE
        Get-JellyfinQueryFiltersLegacy
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Includeitemtypes,

        [Parameter()]
        [ValidateSet('Unknown','Video','Audio','Photo','Book')]
        [string[]]$Mediatypes
    )


    $path = '/Items/Filters'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Includeitemtypes) { $queryParameters['includeItemTypes'] = convertto-delimited $Includeitemtypes ',' }
    if ($Mediatypes) { $queryParameters['mediaTypes'] = convertto-delimited $Mediatypes ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinQueryFilters {
    <#
    .SYNOPSIS
            Gets query filters.

    .DESCRIPTION
        API Endpoint: GET /Items/Filters2
        Operation ID: GetQueryFilters
        Tags: Filter
    .PARAMETER Userid
        Optional. User id.

    .PARAMETER Parentid
        Optional. Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Includeitemtypes
        Optional. If specified, results will be filtered based on item type. This allows multiple, comma delimited.

    .PARAMETER Isairing
        Optional. Is item airing.

    .PARAMETER Ismovie
        Optional. Is item movie.

    .PARAMETER Issports
        Optional. Is item sports.

    .PARAMETER Iskids
        Optional. Is item kids.

    .PARAMETER Isnews
        Optional. Is item news.

    .PARAMETER Isseries
        Optional. Is item series.

    .PARAMETER Recursive
        Optional. Search recursive.
    
    .EXAMPLE
        Get-JellyfinQueryFilters
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Includeitemtypes,

        [Parameter()]
        [nullable[bool]]$Isairing,

        [Parameter()]
        [nullable[bool]]$Ismovie,

        [Parameter()]
        [nullable[bool]]$Issports,

        [Parameter()]
        [nullable[bool]]$Iskids,

        [Parameter()]
        [nullable[bool]]$Isnews,

        [Parameter()]
        [nullable[bool]]$Isseries,

        [Parameter()]
        [nullable[bool]]$Recursive
    )


    $path = '/Items/Filters2'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Includeitemtypes) { $queryParameters['includeItemTypes'] = convertto-delimited $Includeitemtypes ',' }
    if ($PSBoundParameters.ContainsKey('Isairing')) { $queryParameters['isAiring'] = $Isairing }
    if ($PSBoundParameters.ContainsKey('Ismovie')) { $queryParameters['isMovie'] = $Ismovie }
    if ($PSBoundParameters.ContainsKey('Issports')) { $queryParameters['isSports'] = $Issports }
    if ($PSBoundParameters.ContainsKey('Iskids')) { $queryParameters['isKids'] = $Iskids }
    if ($PSBoundParameters.ContainsKey('Isnews')) { $queryParameters['isNews'] = $Isnews }
    if ($PSBoundParameters.ContainsKey('Isseries')) { $queryParameters['isSeries'] = $Isseries }
    if ($PSBoundParameters.ContainsKey('Recursive')) { $queryParameters['recursive'] = $Recursive }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Genres Functions (2 functions)

function Get-JellyfinGenres {
    <#
    .SYNOPSIS
            Gets all genres from a given item, folder, or the entire library.

    .DESCRIPTION
        API Endpoint: GET /Genres
        Operation ID: GetGenres
        Tags: Genres
    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Searchterm
        The search term.

    .PARAMETER Parentid
        Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Excludeitemtypes
        Optional. If specified, results will be filtered out based on item type. This allows multiple, comma delimited.

    .PARAMETER Includeitemtypes
        Optional. If specified, results will be filtered in based on item type. This allows multiple, comma delimited.

    .PARAMETER Isfavorite
        Optional filter by items that are marked as favorite, or not.

    .PARAMETER Imagetypelimit
        Optional, the max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Userid
        User id.

    .PARAMETER Namestartswithorgreater
        Optional filter by items whose name is sorted equally or greater than a given input string.

    .PARAMETER Namestartswith
        Optional filter by items whose name is sorted equally than a given input string.

    .PARAMETER Namelessthan
        Optional filter by items whose name is equally or lesser than a given input string.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited.

    .PARAMETER Sortorder
        Sort Order - Ascending,Descending.

    .PARAMETER Enableimages
        Optional, include image information in output.

    .PARAMETER Enabletotalrecordcount
        Optional. Include total record count.
    
    .EXAMPLE
        Get-JellyfinGenres
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [string]$Searchterm,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Excludeitemtypes,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Includeitemtypes,

        [Parameter()]
        [nullable[bool]]$Isfavorite,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Namestartswithorgreater,

        [Parameter()]
        [string]$Namestartswith,

        [Parameter()]
        [string]$Namelessthan,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [ValidateSet('Ascending','Descending')]
        [string[]]$Sortorder,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount
    )


    $path = '/Genres'
    $queryParameters = @{}
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Searchterm) { $queryParameters['searchTerm'] = $Searchterm }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Excludeitemtypes) { $queryParameters['excludeItemTypes'] = convertto-delimited $Excludeitemtypes ',' }
    if ($Includeitemtypes) { $queryParameters['includeItemTypes'] = convertto-delimited $Includeitemtypes ',' }
    if ($PSBoundParameters.ContainsKey('Isfavorite')) { $queryParameters['isFavorite'] = $Isfavorite }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Namestartswithorgreater) { $queryParameters['nameStartsWithOrGreater'] = $Namestartswithorgreater }
    if ($Namestartswith) { $queryParameters['nameStartsWith'] = $Namestartswith }
    if ($Namelessthan) { $queryParameters['nameLessThan'] = $Namelessthan }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinGenre {
    <#
    .SYNOPSIS
            Gets a genre, by name.

    .DESCRIPTION
        API Endpoint: GET /Genres/{genreName}
        Operation ID: GetGenre
        Tags: Genres
    .PARAMETER Genrename
        Path parameter: genreName

    .PARAMETER Userid
        The user id.
    
    .EXAMPLE
        Get-JellyfinGenre
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Genrename,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Genres/{genreName}'
    $path = $path -replace '\{genreName\}', $Genrename
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region HlsSegment Functions (5 functions)

function Get-JellyfinHlsAudioSegmentLegacyAac {
    <#
    .SYNOPSIS
            Gets the specified audio segment for an audio item.

    .DESCRIPTION
        API Endpoint: GET /Audio/{itemId}/hls/{segmentId}/stream.aac
        Operation ID: GetHlsAudioSegmentLegacyAac
        Tags: HlsSegment
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Segmentid
        Path parameter: segmentId
    
    .EXAMPLE
        Get-JellyfinHlsAudioSegmentLegacyAac
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Segmentid
    )


    $path = '/Audio/{itemId}/hls/{segmentId}/stream.aac'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{segmentId\}', $Segmentid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinHlsAudioSegmentLegacyMp3 {
    <#
    .SYNOPSIS
            Gets the specified audio segment for an audio item.

    .DESCRIPTION
        API Endpoint: GET /Audio/{itemId}/hls/{segmentId}/stream.mp3
        Operation ID: GetHlsAudioSegmentLegacyMp3
        Tags: HlsSegment
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Segmentid
        Path parameter: segmentId
    
    .EXAMPLE
        Get-JellyfinHlsAudioSegmentLegacyMp3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Segmentid
    )


    $path = '/Audio/{itemId}/hls/{segmentId}/stream.mp3'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{segmentId\}', $Segmentid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinHlsVideoSegmentLegacy {
    <#
    .SYNOPSIS
            Gets a hls video segment.

    .DESCRIPTION
        API Endpoint: GET /Videos/{itemId}/hls/{playlistId}/{segmentId}.{segmentContainer}
        Operation ID: GetHlsVideoSegmentLegacy
        Tags: HlsSegment
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Playlistid
        Path parameter: playlistId

    .PARAMETER Segmentid
        Path parameter: segmentId

    .PARAMETER Segmentcontainer
        Path parameter: segmentContainer
    
    .EXAMPLE
        Get-JellyfinHlsVideoSegmentLegacy
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Segmentid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Segmentcontainer
    )


    $path = '/Videos/{itemId}/hls/{playlistId}/{segmentId}.{segmentContainer}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{playlistId\}', $Playlistid
    $path = $path -replace '\{segmentId\}', $Segmentid
    $path = $path -replace '\{segmentContainer\}', $Segmentcontainer

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinHlsPlaylistLegacy {
    <#
    .SYNOPSIS
            Gets a hls video playlist.

    .DESCRIPTION
        API Endpoint: GET /Videos/{itemId}/hls/{playlistId}/stream.m3u8
        Operation ID: GetHlsPlaylistLegacy
        Tags: HlsSegment
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Playlistid
        Path parameter: playlistId
    
    .EXAMPLE
        Get-JellyfinHlsPlaylistLegacy
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid
    )


    $path = '/Videos/{itemId}/hls/{playlistId}/stream.m3u8'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{playlistId\}', $Playlistid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Stop-JellyfinEncodingProcess {
    <#
    .SYNOPSIS
            Stops an active encoding.

    .DESCRIPTION
        API Endpoint: DELETE /Videos/ActiveEncodings
        Operation ID: StopEncodingProcess
        Tags: HlsSegment
    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Playsessionid
        The play session id.
    
    .EXAMPLE
        Stop-JellyfinEncodingProcess
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Deviceid,

        [Parameter(Mandatory)]
        [string]$Playsessionid
    )


    $path = '/Videos/ActiveEncodings'
    $queryParameters = @{}
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Image Functions (37 functions)

function Get-JellyfinArtistImage {
    <#
    .SYNOPSIS
            Get artist image by name.

    .DESCRIPTION
        API Endpoint: GET /Artists/{name}/Images/{imageType}/{imageIndex}
        Operation ID: GetArtistImage
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Get-JellyfinArtistImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/Artists/{name}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinArtistImage {
    <#
    .SYNOPSIS
            Get artist image by name.

    .DESCRIPTION
        API Endpoint: HEAD /Artists/{name}/Images/{imageType}/{imageIndex}
        Operation ID: HeadArtistImage
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Test-JellyfinArtistImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/Artists/{name}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSplashscreen {
    <#
    .SYNOPSIS
            Generates or gets the splashscreen.

    .DESCRIPTION
        API Endpoint: GET /Branding/Splashscreen
        Operation ID: GetSplashscreen
        Tags: Image
    .PARAMETER Tag
        Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.
    
    .EXAMPLE
        Get-JellyfinSplashscreen
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format
    )


    $path = '/Branding/Splashscreen'
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinUploadCustomSplashscreen {
    <#
    .SYNOPSIS
            Uploads a custom splashscreen.
The body is expected to the image contents base64 encoded.
The body is expected to the image contents base64 encoded.

    .DESCRIPTION
        API Endpoint: POST /Branding/Splashscreen
        Operation ID: UploadCustomSplashscreen
        Tags: Image
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinUploadCustomSplashscreen
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Branding/Splashscreen'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinCustomSplashscreen {
    <#
    .SYNOPSIS
            Delete a custom splashscreen.

    .DESCRIPTION
        API Endpoint: DELETE /Branding/Splashscreen
        Operation ID: DeleteCustomSplashscreen
        Tags: Image
    .EXAMPLE
        Remove-JellyfinCustomSplashscreen
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Branding/Splashscreen' -Method DELETE
}
function Get-JellyfinGenreImage {
    <#
    .SYNOPSIS
            Get genre image by name.

    .DESCRIPTION
        API Endpoint: GET /Genres/{name}/Images/{imageType}
        Operation ID: GetGenreImage
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.

    .PARAMETER Imageindex
        Image index.
    
    .EXAMPLE
        Get-JellyfinGenreImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer,

        [Parameter()]
        [int]$Imageindex
    )


    $path = '/Genres/{name}/Images/{imageType}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }
    if ($Imageindex) { $queryParameters['imageIndex'] = $Imageindex }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinGenreImage {
    <#
    .SYNOPSIS
            Get genre image by name.

    .DESCRIPTION
        API Endpoint: HEAD /Genres/{name}/Images/{imageType}
        Operation ID: HeadGenreImage
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.

    .PARAMETER Imageindex
        Image index.
    
    .EXAMPLE
        Test-JellyfinGenreImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer,

        [Parameter()]
        [int]$Imageindex
    )


    $path = '/Genres/{name}/Images/{imageType}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }
    if ($Imageindex) { $queryParameters['imageIndex'] = $Imageindex }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinGenreImageByIndex {
    <#
    .SYNOPSIS
            Get genre image by name.

    .DESCRIPTION
        API Endpoint: GET /Genres/{name}/Images/{imageType}/{imageIndex}
        Operation ID: GetGenreImageByIndex
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Get-JellyfinGenreImageByIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/Genres/{name}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinGenreImageByIndex {
    <#
    .SYNOPSIS
            Get genre image by name.

    .DESCRIPTION
        API Endpoint: HEAD /Genres/{name}/Images/{imageType}/{imageIndex}
        Operation ID: HeadGenreImageByIndex
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Test-JellyfinGenreImageByIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/Genres/{name}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinItemImageInfos {
    <#
    .SYNOPSIS
            Get item image infos.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/Images
        Operation ID: GetItemImageInfos
        Tags: Image
    .PARAMETER Itemid
        Path parameter: itemId
    
    .EXAMPLE
        Get-JellyfinItemImageInfos
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid
    )


    $path = '/Items/{itemId}/Images'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinItemImage {
    <#
    .SYNOPSIS
            Delete an item's image.

    .DESCRIPTION
        API Endpoint: DELETE /Items/{itemId}/Images/{imageType}
        Operation ID: DeleteItemImage
        Tags: Image
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        The image index.
    
    .EXAMPLE
        Remove-JellyfinItemImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter()]
        [int]$Imageindex
    )


    $path = '/Items/{itemId}/Images/{imageType}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{imageType\}', $Imagetype
    $queryParameters = @{}
    if ($Imageindex) { $queryParameters['imageIndex'] = $Imageindex }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinItemImage {
    <#
    .SYNOPSIS
            Set item image.

    .DESCRIPTION
        API Endpoint: POST /Items/{itemId}/Images/{imageType}
        Operation ID: SetItemImage
        Tags: Image
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinItemImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter()]
        [object]$Body
    )


    $path = '/Items/{itemId}/Images/{imageType}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{imageType\}', $Imagetype

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinItemImage {
    <#
    .SYNOPSIS
            Gets the item's image.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/Images/{imageType}
        Operation ID: GetItemImage
        Tags: Image
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Optional. The MediaBrowser.Model.Drawing.ImageFormat of the returned image.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.

    .PARAMETER Imageindex
        Image index.
    
    .EXAMPLE
        Get-JellyfinItemImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer,

        [Parameter()]
        [int]$Imageindex
    )


    $path = '/Items/{itemId}/Images/{imageType}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{imageType\}', $Imagetype
    $queryParameters = @{}
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }
    if ($Imageindex) { $queryParameters['imageIndex'] = $Imageindex }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinItemImage {
    <#
    .SYNOPSIS
            Gets the item's image.

    .DESCRIPTION
        API Endpoint: HEAD /Items/{itemId}/Images/{imageType}
        Operation ID: HeadItemImage
        Tags: Image
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Optional. The MediaBrowser.Model.Drawing.ImageFormat of the returned image.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.

    .PARAMETER Imageindex
        Image index.
    
    .EXAMPLE
        Test-JellyfinItemImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer,

        [Parameter()]
        [int]$Imageindex
    )


    $path = '/Items/{itemId}/Images/{imageType}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{imageType\}', $Imagetype
    $queryParameters = @{}
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }
    if ($Imageindex) { $queryParameters['imageIndex'] = $Imageindex }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinItemImageByIndex {
    <#
    .SYNOPSIS
            Delete an item's image.

    .DESCRIPTION
        API Endpoint: DELETE /Items/{itemId}/Images/{imageType}/{imageIndex}
        Operation ID: DeleteItemImageByIndex
        Tags: Image
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex
    
    .EXAMPLE
        Remove-JellyfinItemImageByIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex
    )


    $path = '/Items/{itemId}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinItemImageByIndex {
    <#
    .SYNOPSIS
            Set item image.

    .DESCRIPTION
        API Endpoint: POST /Items/{itemId}/Images/{imageType}/{imageIndex}
        Operation ID: SetItemImageByIndex
        Tags: Image
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinItemImageByIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [object]$Body
    )


    $path = '/Items/{itemId}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinItemImageByIndex {
    <#
    .SYNOPSIS
            Gets the item's image.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/Images/{imageType}/{imageIndex}
        Operation ID: GetItemImageByIndex
        Tags: Image
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Optional. The MediaBrowser.Model.Drawing.ImageFormat of the returned image.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Get-JellyfinItemImageByIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/Items/{itemId}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinItemImageByIndex {
    <#
    .SYNOPSIS
            Gets the item's image.

    .DESCRIPTION
        API Endpoint: HEAD /Items/{itemId}/Images/{imageType}/{imageIndex}
        Operation ID: HeadItemImageByIndex
        Tags: Image
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Optional. The MediaBrowser.Model.Drawing.ImageFormat of the returned image.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Test-JellyfinItemImageByIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/Items/{itemId}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinItemImage2 {
    <#
    .SYNOPSIS
            Gets the item's image.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/Images/{imageType}/{imageIndex}/{tag}/{format}/{maxWidth}/{maxHeight}/{percentPlayed}/{unplayedCount}
        Operation ID: GetItemImage2
        Tags: Image
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Maxwidth
        Path parameter: maxWidth

    .PARAMETER Maxheight
        Path parameter: maxHeight

    .PARAMETER Tag
        Path parameter: tag

    .PARAMETER Format
        Path parameter: format

    .PARAMETER Percentplayed
        Path parameter: percentPlayed

    .PARAMETER Unplayedcount
        Path parameter: unplayedCount

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Get-JellyfinItemImage2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Maxwidth,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Maxheight,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Tag,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Format,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [double]$Percentplayed,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Unplayedcount,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/Items/{itemId}/Images/{imageType}/{imageIndex}/{tag}/{format}/{maxWidth}/{maxHeight}/{percentPlayed}/{unplayedCount}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{maxWidth\}', $Maxwidth
    $path = $path -replace '\{maxHeight\}', $Maxheight
    $path = $path -replace '\{tag\}', $Tag
    $path = $path -replace '\{format\}', $Format
    $path = $path -replace '\{percentPlayed\}', $Percentplayed
    $path = $path -replace '\{unplayedCount\}', $Unplayedcount
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinItemImage2 {
    <#
    .SYNOPSIS
            Gets the item's image.

    .DESCRIPTION
        API Endpoint: HEAD /Items/{itemId}/Images/{imageType}/{imageIndex}/{tag}/{format}/{maxWidth}/{maxHeight}/{percentPlayed}/{unplayedCount}
        Operation ID: HeadItemImage2
        Tags: Image
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Maxwidth
        Path parameter: maxWidth

    .PARAMETER Maxheight
        Path parameter: maxHeight

    .PARAMETER Tag
        Path parameter: tag

    .PARAMETER Format
        Path parameter: format

    .PARAMETER Percentplayed
        Path parameter: percentPlayed

    .PARAMETER Unplayedcount
        Path parameter: unplayedCount

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Test-JellyfinItemImage2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Maxwidth,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Maxheight,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Tag,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Format,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [double]$Percentplayed,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Unplayedcount,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/Items/{itemId}/Images/{imageType}/{imageIndex}/{tag}/{format}/{maxWidth}/{maxHeight}/{percentPlayed}/{unplayedCount}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{maxWidth\}', $Maxwidth
    $path = $path -replace '\{maxHeight\}', $Maxheight
    $path = $path -replace '\{tag\}', $Tag
    $path = $path -replace '\{format\}', $Format
    $path = $path -replace '\{percentPlayed\}', $Percentplayed
    $path = $path -replace '\{unplayedCount\}', $Unplayedcount
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinItemImageIndex {
    <#
    .SYNOPSIS
            Updates the index for an item image.

    .DESCRIPTION
        API Endpoint: POST /Items/{itemId}/Images/{imageType}/{imageIndex}/Index
        Operation ID: UpdateItemImageIndex
        Tags: Image
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Newindex
        New image index.
    
    .EXAMPLE
        Set-JellyfinItemImageIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter(Mandatory)]
        [int]$Newindex
    )


    $path = '/Items/{itemId}/Images/{imageType}/{imageIndex}/Index'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Newindex) { $queryParameters['newIndex'] = $Newindex }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinMusicGenreImage {
    <#
    .SYNOPSIS
            Get music genre image by name.

    .DESCRIPTION
        API Endpoint: GET /MusicGenres/{name}/Images/{imageType}
        Operation ID: GetMusicGenreImage
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.

    .PARAMETER Imageindex
        Image index.
    
    .EXAMPLE
        Get-JellyfinMusicGenreImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer,

        [Parameter()]
        [int]$Imageindex
    )


    $path = '/MusicGenres/{name}/Images/{imageType}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }
    if ($Imageindex) { $queryParameters['imageIndex'] = $Imageindex }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinMusicGenreImage {
    <#
    .SYNOPSIS
            Get music genre image by name.

    .DESCRIPTION
        API Endpoint: HEAD /MusicGenres/{name}/Images/{imageType}
        Operation ID: HeadMusicGenreImage
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.

    .PARAMETER Imageindex
        Image index.
    
    .EXAMPLE
        Test-JellyfinMusicGenreImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer,

        [Parameter()]
        [int]$Imageindex
    )


    $path = '/MusicGenres/{name}/Images/{imageType}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }
    if ($Imageindex) { $queryParameters['imageIndex'] = $Imageindex }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinMusicGenreImageByIndex {
    <#
    .SYNOPSIS
            Get music genre image by name.

    .DESCRIPTION
        API Endpoint: GET /MusicGenres/{name}/Images/{imageType}/{imageIndex}
        Operation ID: GetMusicGenreImageByIndex
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Get-JellyfinMusicGenreImageByIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/MusicGenres/{name}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinMusicGenreImageByIndex {
    <#
    .SYNOPSIS
            Get music genre image by name.

    .DESCRIPTION
        API Endpoint: HEAD /MusicGenres/{name}/Images/{imageType}/{imageIndex}
        Operation ID: HeadMusicGenreImageByIndex
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Test-JellyfinMusicGenreImageByIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/MusicGenres/{name}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPersonImage {
    <#
    .SYNOPSIS
            Get person image by name.

    .DESCRIPTION
        API Endpoint: GET /Persons/{name}/Images/{imageType}
        Operation ID: GetPersonImage
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.

    .PARAMETER Imageindex
        Image index.
    
    .EXAMPLE
        Get-JellyfinPersonImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer,

        [Parameter()]
        [int]$Imageindex
    )


    $path = '/Persons/{name}/Images/{imageType}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }
    if ($Imageindex) { $queryParameters['imageIndex'] = $Imageindex }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinPersonImage {
    <#
    .SYNOPSIS
            Get person image by name.

    .DESCRIPTION
        API Endpoint: HEAD /Persons/{name}/Images/{imageType}
        Operation ID: HeadPersonImage
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.

    .PARAMETER Imageindex
        Image index.
    
    .EXAMPLE
        Test-JellyfinPersonImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer,

        [Parameter()]
        [int]$Imageindex
    )


    $path = '/Persons/{name}/Images/{imageType}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }
    if ($Imageindex) { $queryParameters['imageIndex'] = $Imageindex }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPersonImageByIndex {
    <#
    .SYNOPSIS
            Get person image by name.

    .DESCRIPTION
        API Endpoint: GET /Persons/{name}/Images/{imageType}/{imageIndex}
        Operation ID: GetPersonImageByIndex
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Get-JellyfinPersonImageByIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/Persons/{name}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinPersonImageByIndex {
    <#
    .SYNOPSIS
            Get person image by name.

    .DESCRIPTION
        API Endpoint: HEAD /Persons/{name}/Images/{imageType}/{imageIndex}
        Operation ID: HeadPersonImageByIndex
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Test-JellyfinPersonImageByIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/Persons/{name}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinStudioImage {
    <#
    .SYNOPSIS
            Get studio image by name.

    .DESCRIPTION
        API Endpoint: GET /Studios/{name}/Images/{imageType}
        Operation ID: GetStudioImage
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.

    .PARAMETER Imageindex
        Image index.
    
    .EXAMPLE
        Get-JellyfinStudioImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer,

        [Parameter()]
        [int]$Imageindex
    )


    $path = '/Studios/{name}/Images/{imageType}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }
    if ($Imageindex) { $queryParameters['imageIndex'] = $Imageindex }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinStudioImage {
    <#
    .SYNOPSIS
            Get studio image by name.

    .DESCRIPTION
        API Endpoint: HEAD /Studios/{name}/Images/{imageType}
        Operation ID: HeadStudioImage
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.

    .PARAMETER Imageindex
        Image index.
    
    .EXAMPLE
        Test-JellyfinStudioImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer,

        [Parameter()]
        [int]$Imageindex
    )


    $path = '/Studios/{name}/Images/{imageType}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }
    if ($Imageindex) { $queryParameters['imageIndex'] = $Imageindex }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinStudioImageByIndex {
    <#
    .SYNOPSIS
            Get studio image by name.

    .DESCRIPTION
        API Endpoint: GET /Studios/{name}/Images/{imageType}/{imageIndex}
        Operation ID: GetStudioImageByIndex
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Get-JellyfinStudioImageByIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/Studios/{name}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinStudioImageByIndex {
    <#
    .SYNOPSIS
            Get studio image by name.

    .DESCRIPTION
        API Endpoint: HEAD /Studios/{name}/Images/{imageType}/{imageIndex}
        Operation ID: HeadStudioImageByIndex
        Tags: Image
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Imagetype
        Path parameter: imageType

    .PARAMETER Imageindex
        Path parameter: imageIndex

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.

    .PARAMETER Maxwidth
        The maximum image width to return.

    .PARAMETER Maxheight
        The maximum image height to return.

    .PARAMETER Percentplayed
        Optional. Percent to render for the percent played overlay.

    .PARAMETER Unplayedcount
        Optional. Unplayed count overlay to render.

    .PARAMETER Width
        The fixed image width to return.

    .PARAMETER Height
        The fixed image height to return.

    .PARAMETER Quality
        Optional. Quality setting, from 0-100. Defaults to 90 and should suffice in most cases.

    .PARAMETER Fillwidth
        Width of box to fill.

    .PARAMETER Fillheight
        Height of box to fill.

    .PARAMETER Blur
        Optional. Blur image.

    .PARAMETER Backgroundcolor
        Optional. Apply a background color for transparent images.

    .PARAMETER Foregroundlayer
        Optional. Apply a foreground layer on top of the image.
    
    .EXAMPLE
        Test-JellyfinStudioImageByIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Imagetype,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Imageindex,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [double]$Percentplayed,

        [Parameter()]
        [int]$Unplayedcount,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Quality,

        [Parameter()]
        [int]$Fillwidth,

        [Parameter()]
        [int]$Fillheight,

        [Parameter()]
        [int]$Blur,

        [Parameter()]
        [string]$Backgroundcolor,

        [Parameter()]
        [string]$Foregroundlayer
    )


    $path = '/Studios/{name}/Images/{imageType}/{imageIndex}'
    $path = $path -replace '\{name\}', $Name
    $path = $path -replace '\{imageType\}', $Imagetype
    $path = $path -replace '\{imageIndex\}', $Imageindex
    $queryParameters = @{}
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Percentplayed) { $queryParameters['percentPlayed'] = $Percentplayed }
    if ($Unplayedcount) { $queryParameters['unplayedCount'] = $Unplayedcount }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Quality) { $queryParameters['quality'] = $Quality }
    if ($Fillwidth) { $queryParameters['fillWidth'] = $Fillwidth }
    if ($Fillheight) { $queryParameters['fillHeight'] = $Fillheight }
    if ($Blur) { $queryParameters['blur'] = $Blur }
    if ($Backgroundcolor) { $queryParameters['backgroundColor'] = $Backgroundcolor }
    if ($Foregroundlayer) { $queryParameters['foregroundLayer'] = $Foregroundlayer }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinUserImage {
    <#
    .SYNOPSIS
            Sets the user image.

    .DESCRIPTION
        API Endpoint: POST /UserImage
        Operation ID: PostUserImage
        Tags: Image
    .PARAMETER Userid
        User Id.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinUserImage
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [object]$Body
    )


    $path = '/UserImage'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinUserImage {
    <#
    .SYNOPSIS
            Delete the user's image.

    .DESCRIPTION
        API Endpoint: DELETE /UserImage
        Operation ID: DeleteUserImage
        Tags: Image
    .PARAMETER Userid
        User Id.
    
    .EXAMPLE
        Remove-JellyfinUserImage
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid
    )


    $path = '/UserImage'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinUserImage {
    <#
    .SYNOPSIS
            Get user profile image.

    .DESCRIPTION
        API Endpoint: GET /UserImage
        Operation ID: GetUserImage
        Tags: Image
    .PARAMETER Userid
        User id.

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.
    
    .EXAMPLE
        Get-JellyfinUserImage
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format
    )


    $path = '/UserImage'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinUserImage {
    <#
    .SYNOPSIS
            Get user profile image.

    .DESCRIPTION
        API Endpoint: HEAD /UserImage
        Operation ID: HeadUserImage
        Tags: Image
    .PARAMETER Userid
        User id.

    .PARAMETER Tag
        Optional. Supply the cache tag from the item object to receive strong caching headers.

    .PARAMETER Format
        Determines the output format of the image - original,gif,jpg,png.
    
    .EXAMPLE
        Test-JellyfinUserImage
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Format
    )


    $path = '/UserImage'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Format) { $queryParameters['format'] = $Format }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region InstantMix Functions (8 functions)

function Get-JellyfinInstantMixFromAlbum {
    <#
    .SYNOPSIS
            Creates an instant playlist based on a given album.

    .DESCRIPTION
        API Endpoint: GET /Albums/{itemId}/InstantMix
        Operation ID: GetInstantMixFromAlbum
        Tags: InstantMix
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.
    
    .EXAMPLE
        Get-JellyfinInstantMixFromAlbum
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes
    )


    $path = '/Albums/{itemId}/InstantMix'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinInstantMixFromArtists {
    <#
    .SYNOPSIS
            Creates an instant playlist based on a given artist.

    .DESCRIPTION
        API Endpoint: GET /Artists/{itemId}/InstantMix
        Operation ID: GetInstantMixFromArtists
        Tags: InstantMix
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.
    
    .EXAMPLE
        Get-JellyfinInstantMixFromArtists
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes
    )


    $path = '/Artists/{itemId}/InstantMix'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinInstantMixFromArtists2 {
    <#
    .SYNOPSIS
            Creates an instant playlist based on a given artist.

    .DESCRIPTION
        API Endpoint: GET /Artists/InstantMix
        Operation ID: GetInstantMixFromArtists2
        Tags: InstantMix
    .PARAMETER Id
        The item id.

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.
    
    .EXAMPLE
        Get-JellyfinInstantMixFromArtists2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes
    )


    $path = '/Artists/InstantMix'
    $queryParameters = @{}
    if ($Id) { $queryParameters['id'] = $Id }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinInstantMixFromItem {
    <#
    .SYNOPSIS
            Creates an instant playlist based on a given item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/InstantMix
        Operation ID: GetInstantMixFromItem
        Tags: InstantMix
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.
    
    .EXAMPLE
        Get-JellyfinInstantMixFromItem
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes
    )


    $path = '/Items/{itemId}/InstantMix'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinInstantMixFromMusicGenreByName {
    <#
    .SYNOPSIS
            Creates an instant playlist based on a given genre.

    .DESCRIPTION
        API Endpoint: GET /MusicGenres/{name}/InstantMix
        Operation ID: GetInstantMixFromMusicGenreByName
        Tags: InstantMix
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.
    
    .EXAMPLE
        Get-JellyfinInstantMixFromMusicGenreByName
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes
    )


    $path = '/MusicGenres/{name}/InstantMix'
    $path = $path -replace '\{name\}', $Name
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinInstantMixFromMusicGenreById {
    <#
    .SYNOPSIS
            Creates an instant playlist based on a given genre.

    .DESCRIPTION
        API Endpoint: GET /MusicGenres/InstantMix
        Operation ID: GetInstantMixFromMusicGenreById
        Tags: InstantMix
    .PARAMETER Id
        The item id.

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.
    
    .EXAMPLE
        Get-JellyfinInstantMixFromMusicGenreById
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes
    )


    $path = '/MusicGenres/InstantMix'
    $queryParameters = @{}
    if ($Id) { $queryParameters['id'] = $Id }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinInstantMixFromPlaylist {
    <#
    .SYNOPSIS
            Creates an instant playlist based on a given playlist.

    .DESCRIPTION
        API Endpoint: GET /Playlists/{itemId}/InstantMix
        Operation ID: GetInstantMixFromPlaylist
        Tags: InstantMix
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.
    
    .EXAMPLE
        Get-JellyfinInstantMixFromPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes
    )


    $path = '/Playlists/{itemId}/InstantMix'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinInstantMixFromSong {
    <#
    .SYNOPSIS
            Creates an instant playlist based on a given song.

    .DESCRIPTION
        API Endpoint: GET /Songs/{itemId}/InstantMix
        Operation ID: GetInstantMixFromSong
        Tags: InstantMix
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.
    
    .EXAMPLE
        Get-JellyfinInstantMixFromSong
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes
    )


    $path = '/Songs/{itemId}/InstantMix'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region ItemLookup Functions (11 functions)

function Get-JellyfinExternalIdInfos {
    <#
    .SYNOPSIS
            Get the item's external id info.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/ExternalIdInfos
        Operation ID: GetExternalIdInfos
        Tags: ItemLookup
    .PARAMETER Itemid
        Path parameter: itemId
    
    .EXAMPLE
        Get-JellyfinExternalIdInfos
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid
    )


    $path = '/Items/{itemId}/ExternalIdInfos'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinApplySearchCriteria {
    <#
    .SYNOPSIS
            Applies search criteria to an item and refreshes metadata.

    .DESCRIPTION
        API Endpoint: POST /Items/RemoteSearch/Apply/{itemId}
        Operation ID: ApplySearchCriteria
        Tags: ItemLookup
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Replaceallimages
        Optional. Whether or not to replace all images. Default: True.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinApplySearchCriteria
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [nullable[bool]]$Replaceallimages,

        [Parameter()]
        [object]$Body
    )


    $path = '/Items/RemoteSearch/Apply/{itemId}'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Replaceallimages')) { $queryParameters['replaceAllImages'] = $Replaceallimages }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinBookRemoteSearchResults {
    <#
    .SYNOPSIS
            Get book remote search.

    .DESCRIPTION
        API Endpoint: POST /Items/RemoteSearch/Book
        Operation ID: GetBookRemoteSearchResults
        Tags: ItemLookup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Get-JellyfinBookRemoteSearchResults
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Items/RemoteSearch/Book'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinBoxSetRemoteSearchResults {
    <#
    .SYNOPSIS
            Get box set remote search.

    .DESCRIPTION
        API Endpoint: POST /Items/RemoteSearch/BoxSet
        Operation ID: GetBoxSetRemoteSearchResults
        Tags: ItemLookup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Get-JellyfinBoxSetRemoteSearchResults
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Items/RemoteSearch/BoxSet'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinMovieRemoteSearchResults {
    <#
    .SYNOPSIS
            Get movie remote search.

    .DESCRIPTION
        API Endpoint: POST /Items/RemoteSearch/Movie
        Operation ID: GetMovieRemoteSearchResults
        Tags: ItemLookup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Get-JellyfinMovieRemoteSearchResults
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Items/RemoteSearch/Movie'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinMusicAlbumRemoteSearchResults {
    <#
    .SYNOPSIS
            Get music album remote search.

    .DESCRIPTION
        API Endpoint: POST /Items/RemoteSearch/MusicAlbum
        Operation ID: GetMusicAlbumRemoteSearchResults
        Tags: ItemLookup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Get-JellyfinMusicAlbumRemoteSearchResults
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Items/RemoteSearch/MusicAlbum'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinMusicArtistRemoteSearchResults {
    <#
    .SYNOPSIS
            Get music artist remote search.

    .DESCRIPTION
        API Endpoint: POST /Items/RemoteSearch/MusicArtist
        Operation ID: GetMusicArtistRemoteSearchResults
        Tags: ItemLookup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Get-JellyfinMusicArtistRemoteSearchResults
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Items/RemoteSearch/MusicArtist'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinMusicVideoRemoteSearchResults {
    <#
    .SYNOPSIS
            Get music video remote search.

    .DESCRIPTION
        API Endpoint: POST /Items/RemoteSearch/MusicVideo
        Operation ID: GetMusicVideoRemoteSearchResults
        Tags: ItemLookup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Get-JellyfinMusicVideoRemoteSearchResults
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Items/RemoteSearch/MusicVideo'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPersonRemoteSearchResults {
    <#
    .SYNOPSIS
            Get person remote search.

    .DESCRIPTION
        API Endpoint: POST /Items/RemoteSearch/Person
        Operation ID: GetPersonRemoteSearchResults
        Tags: ItemLookup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Get-JellyfinPersonRemoteSearchResults
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Items/RemoteSearch/Person'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSeriesRemoteSearchResults {
    <#
    .SYNOPSIS
            Get series remote search.

    .DESCRIPTION
        API Endpoint: POST /Items/RemoteSearch/Series
        Operation ID: GetSeriesRemoteSearchResults
        Tags: ItemLookup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Get-JellyfinSeriesRemoteSearchResults
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Items/RemoteSearch/Series'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinTrailerRemoteSearchResults {
    <#
    .SYNOPSIS
            Get trailer remote search.

    .DESCRIPTION
        API Endpoint: POST /Items/RemoteSearch/Trailer
        Operation ID: GetTrailerRemoteSearchResults
        Tags: ItemLookup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Get-JellyfinTrailerRemoteSearchResults
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Items/RemoteSearch/Trailer'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region ItemRefresh Functions (1 functions)

function Invoke-JellyfinRefreshItem {
    <#
    .SYNOPSIS
            Refreshes metadata for an item.

    .DESCRIPTION
        API Endpoint: POST /Items/{itemId}/Refresh
        Operation ID: RefreshItem
        Tags: ItemRefresh
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Metadatarefreshmode
        (Optional) Specifies the metadata refresh mode.

    .PARAMETER Imagerefreshmode
        (Optional) Specifies the image refresh mode.

    .PARAMETER Replaceallmetadata
        (Optional) Determines if metadata should be replaced. Only applicable if mode is FullRefresh.

    .PARAMETER Replaceallimages
        (Optional) Determines if images should be replaced. Only applicable if mode is FullRefresh.

    .PARAMETER Regeneratetrickplay
        (Optional) Determines if trickplay images should be replaced. Only applicable if mode is FullRefresh.
    
    .EXAMPLE
        Invoke-JellyfinRefreshItem
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Metadatarefreshmode,

        [Parameter()]
        [string]$Imagerefreshmode,

        [Parameter()]
        [nullable[bool]]$Replaceallmetadata,

        [Parameter()]
        [nullable[bool]]$Replaceallimages,

        [Parameter()]
        [nullable[bool]]$Regeneratetrickplay
    )


    $path = '/Items/{itemId}/Refresh'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Metadatarefreshmode) { $queryParameters['metadataRefreshMode'] = $Metadatarefreshmode }
    if ($Imagerefreshmode) { $queryParameters['imageRefreshMode'] = $Imagerefreshmode }
    if ($PSBoundParameters.ContainsKey('Replaceallmetadata')) { $queryParameters['replaceAllMetadata'] = $Replaceallmetadata }
    if ($PSBoundParameters.ContainsKey('Replaceallimages')) { $queryParameters['replaceAllImages'] = $Replaceallimages }
    if ($PSBoundParameters.ContainsKey('Regeneratetrickplay')) { $queryParameters['regenerateTrickplay'] = $Regeneratetrickplay }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Items Functions (4 functions)

function Get-JellyfinItems {
    <#
    .SYNOPSIS
            Gets items based on a query.

    .DESCRIPTION
        API Endpoint: GET /Items
        Operation ID: GetItems
        Tags: Items
    .PARAMETER Userid
        The user id supplied as query parameter; this is required when not using an API key.

    .PARAMETER Maxofficialrating
        Optional filter by maximum official rating (PG, PG-13, TV-MA, etc).

    .PARAMETER Hasthemesong
        Optional filter by items with theme songs.

    .PARAMETER Hasthemevideo
        Optional filter by items with theme videos.

    .PARAMETER Hassubtitles
        Optional filter by items with subtitles.

    .PARAMETER Hasspecialfeature
        Optional filter by items with special features.

    .PARAMETER Hastrailer
        Optional filter by items with trailers.

    .PARAMETER Adjacentto
        Optional. Return items that are siblings of a supplied item.

    .PARAMETER Indexnumber
        Optional filter by index number.

    .PARAMETER Parentindexnumber
        Optional filter by parent index number.

    .PARAMETER Hasparentalrating
        Optional filter by items that have or do not have a parental rating.

    .PARAMETER Ishd
        Optional filter by items that are HD or not.

    .PARAMETER Is4k
        Optional filter by items that are 4K or not.

    .PARAMETER Locationtypes
        Optional. If specified, results will be filtered based on LocationType. This allows multiple, comma delimited.

    .PARAMETER Excludelocationtypes
        Optional. If specified, results will be filtered based on the LocationType. This allows multiple, comma delimited.

    .PARAMETER Ismissing
        Optional filter by items that are missing episodes or not.

    .PARAMETER Isunaired
        Optional filter by items that are unaired episodes or not.

    .PARAMETER Mincommunityrating
        Optional filter by minimum community rating.

    .PARAMETER Mincriticrating
        Optional filter by minimum critic rating.

    .PARAMETER Minpremieredate
        Optional. The minimum premiere date. Format = ISO.

    .PARAMETER Mindatelastsaved
        Optional. The minimum last saved date. Format = ISO.

    .PARAMETER Mindatelastsavedforuser
        Optional. The minimum last saved date for the current user. Format = ISO.

    .PARAMETER Maxpremieredate
        Optional. The maximum premiere date. Format = ISO.

    .PARAMETER Hasoverview
        Optional filter by items that have an overview or not.

    .PARAMETER Hasimdbid
        Optional filter by items that have an IMDb id or not.

    .PARAMETER Hastmdbid
        Optional filter by items that have a TMDb id or not.

    .PARAMETER Hastvdbid
        Optional filter by items that have a TVDb id or not.

    .PARAMETER Ismovie
        Optional filter for live tv movies.

    .PARAMETER Isseries
        Optional filter for live tv series.

    .PARAMETER Isnews
        Optional filter for live tv news.

    .PARAMETER Iskids
        Optional filter for live tv kids.

    .PARAMETER Issports
        Optional filter for live tv sports.

    .PARAMETER Excludeitemids
        Optional. If specified, results will be filtered by excluding item ids. This allows multiple, comma delimited.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Recursive
        When searching within folders, this determines whether or not the search will be recursive. true/false.

    .PARAMETER Searchterm
        Optional. Filter based on a search term.

    .PARAMETER Sortorder
        Sort Order - Ascending, Descending.

    .PARAMETER Parentid
        Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output. This allows multiple, comma delimited. Options: Budget, Chapters, DateCreated, Genres, HomePageUrl, IndexOptions, MediaStreams, Overview, ParentId, Path, People, ProviderIds, PrimaryImageAspectRatio, Revenue, SortName, Studios, Taglines.

    .PARAMETER Excludeitemtypes
        Optional. If specified, results will be filtered based on item type. This allows multiple, comma delimited.

    .PARAMETER Includeitemtypes
        Optional. If specified, results will be filtered based on the item type. This allows multiple, comma delimited.

    .PARAMETER Filters
        Optional. Specify additional filters to apply. This allows multiple, comma delimited. Options: IsFolder, IsNotFolder, IsUnplayed, IsPlayed, IsFavorite, IsResumable, Likes, Dislikes.

    .PARAMETER Isfavorite
        Optional filter by items that are marked as favorite, or not.

    .PARAMETER Mediatypes
        Optional filter by MediaType. Allows multiple, comma delimited.
		Possible values: "Unknown" "Video" "Audio" "Photo" "Book"
		Comma delimited

    .PARAMETER Imagetypes
        Optional. If specified, results will be filtered based on those containing image types. This allows multiple, comma delimited.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited. Options: Album, AlbumArtist, Artist, Budget, CommunityRating, CriticRating, DateCreated, DatePlayed, PlayCount, PremiereDate, ProductionYear, SortName, Random, Revenue, Runtime.

    .PARAMETER Isplayed
        Optional filter by items that are played, or not.

    .PARAMETER Genres
        Optional. If specified, results will be filtered based on genre. This allows multiple, pipe delimited.

    .PARAMETER Officialratings
        Optional. If specified, results will be filtered based on OfficialRating. This allows multiple, pipe delimited.

    .PARAMETER Tags
        Optional. If specified, results will be filtered based on tag. This allows multiple, pipe delimited.

    .PARAMETER Years
        Optional. If specified, results will be filtered based on production year. This allows multiple, comma delimited.

    .PARAMETER Enableuserdata
        Optional, include user data.

    .PARAMETER Imagetypelimit
        Optional, the max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Person
        Optional. If specified, results will be filtered to include only those containing the specified person.

    .PARAMETER Personids
        Optional. If specified, results will be filtered to include only those containing the specified person id.

    .PARAMETER Persontypes
        Optional. If specified, along with Person, results will be filtered to include only those containing the specified person and PersonType. Allows multiple, comma-delimited.

    .PARAMETER Studios
        Optional. If specified, results will be filtered based on studio. This allows multiple, pipe delimited.

    .PARAMETER Artists
        Optional. If specified, results will be filtered based on artists. This allows multiple, pipe delimited.

    .PARAMETER Excludeartistids
        Optional. If specified, results will be filtered based on artist id. This allows multiple, pipe delimited.

    .PARAMETER Artistids
        Optional. If specified, results will be filtered to include only those containing the specified artist id.

    .PARAMETER Albumartistids
        Optional. If specified, results will be filtered to include only those containing the specified album artist id.

    .PARAMETER Contributingartistids
        Optional. If specified, results will be filtered to include only those containing the specified contributing artist id.

    .PARAMETER Albums
        Optional. If specified, results will be filtered based on album. This allows multiple, pipe delimited.

    .PARAMETER Albumids
        Optional. If specified, results will be filtered based on album id. This allows multiple, pipe delimited.

    .PARAMETER Ids
        Optional. If specific items are needed, specify a list of item id's to retrieve. This allows multiple, comma delimited.

    .PARAMETER Videotypes
        Optional filter by VideoType (videofile, dvd, bluray, iso). Allows multiple, comma delimited.

    .PARAMETER Minofficialrating
        Optional filter by minimum official rating (PG, PG-13, TV-MA, etc).

    .PARAMETER Islocked
        Optional filter by items that are locked.

    .PARAMETER Isplaceholder
        Optional filter by items that are placeholders.

    .PARAMETER Hasofficialrating
        Optional filter by items that have official ratings.

    .PARAMETER Collapseboxsetitems
        Whether or not to hide items behind their boxsets.

    .PARAMETER Minwidth
        Optional. Filter by the minimum width of the item.

    .PARAMETER Minheight
        Optional. Filter by the minimum height of the item.

    .PARAMETER Maxwidth
        Optional. Filter by the maximum width of the item.

    .PARAMETER Maxheight
        Optional. Filter by the maximum height of the item.

    .PARAMETER Is3d
        Optional filter by items that are 3D, or not.

    .PARAMETER Seriesstatus
        Optional filter by Series Status. Allows multiple, comma delimited.

    .PARAMETER Namestartswithorgreater
        Optional filter by items whose name is sorted equally or greater than a given input string.

    .PARAMETER Namestartswith
        Optional filter by items whose name is sorted equally than a given input string.

    .PARAMETER Namelessthan
        Optional filter by items whose name is equally or lesser than a given input string.

    .PARAMETER Studioids
        Optional. If specified, results will be filtered based on studio id. This allows multiple, pipe delimited.

    .PARAMETER Genreids
        Optional. If specified, results will be filtered based on genre id. This allows multiple, pipe delimited.

    .PARAMETER Enabletotalrecordcount
        Optional. Enable the total record count.

    .PARAMETER Enableimages
        Optional, include image information in output.
    
    .EXAMPLE
        Get-JellyfinItems
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Maxofficialrating,

        [Parameter()]
        [nullable[bool]]$Hasthemesong,

        [Parameter()]
        [nullable[bool]]$Hasthemevideo,

        [Parameter()]
        [nullable[bool]]$Hassubtitles,

        [Parameter()]
        [nullable[bool]]$Hasspecialfeature,

        [Parameter()]
        [nullable[bool]]$Hastrailer,

        [Parameter()]
        [string]$Adjacentto,

        [Parameter()]
        [int]$Indexnumber,

        [Parameter()]
        [int]$Parentindexnumber,

        [Parameter()]
        [nullable[bool]]$Hasparentalrating,

        [Parameter()]
        [nullable[bool]]$Ishd,

        [Parameter()]
        [nullable[bool]]$Is4k,

        [Parameter()]
        [string[]]$Locationtypes,

        [Parameter()]
        [string[]]$Excludelocationtypes,

        [Parameter()]
        [nullable[bool]]$Ismissing,

        [Parameter()]
        [nullable[bool]]$Isunaired,

        [Parameter()]
        [double]$Mincommunityrating,

        [Parameter()]
        [double]$Mincriticrating,

        [Parameter()]
        [string]$Minpremieredate,

        [Parameter()]
        [string]$Mindatelastsaved,

        [Parameter()]
        [string]$Mindatelastsavedforuser,

        [Parameter()]
        [string]$Maxpremieredate,

        [Parameter()]
        [nullable[bool]]$Hasoverview,

        [Parameter()]
        [nullable[bool]]$Hasimdbid,

        [Parameter()]
        [nullable[bool]]$Hastmdbid,

        [Parameter()]
        [nullable[bool]]$Hastvdbid,

        [Parameter()]
        [nullable[bool]]$Ismovie,

        [Parameter()]
        [nullable[bool]]$Isseries,

        [Parameter()]
        [nullable[bool]]$Isnews,

        [Parameter()]
        [nullable[bool]]$Iskids,

        [Parameter()]
        [nullable[bool]]$Issports,

        [Parameter()]
        [string[]]$Excludeitemids,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [nullable[bool]]$Recursive,

        [Parameter()]
        [string]$Searchterm,

        [Parameter()]
        [ValidateSet('Ascending','Descending')]
        [string[]]$Sortorder,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Excludeitemtypes,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Includeitemtypes,

        [Parameter()]
        [ValidateSet('IsFolder','IsNotFolder','IsUnplayed','IsPlayed','IsFavorite','IsResumable','Likes','Dislikes','IsFavoriteOrLikes')]
        [string[]]$Filters,

        [Parameter()]
        [nullable[bool]]$Isfavorite,

        [Parameter()]
        [ValidateSet('Unknown','Video','Audio','Photo','Book')]
        [string[]]$Mediatypes,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Imagetypes,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [nullable[bool]]$Isplayed,

        [Parameter()]
        [string[]]$Genres,

        [Parameter()]
        [string[]]$Officialratings,

        [Parameter()]
        [string[]]$Tags,

        [Parameter()]
        [string[]]$Years,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [string]$Person,

        [Parameter()]
        [string[]]$Personids,

        [Parameter()]
        [string[]]$Persontypes,

        [Parameter()]
        [string[]]$Studios,

        [Parameter()]
        [string[]]$Artists,

        [Parameter()]
        [string[]]$Excludeartistids,

        [Parameter()]
        [string[]]$Artistids,

        [Parameter()]
        [string[]]$Albumartistids,

        [Parameter()]
        [string[]]$Contributingartistids,

        [Parameter()]
        [string[]]$Albums,

        [Parameter()]
        [string[]]$Albumids,

        [Parameter()]
        [string[]]$Ids,

        [Parameter()]
        [string[]]$Videotypes,

        [Parameter()]
        [string]$Minofficialrating,

        [Parameter()]
        [nullable[bool]]$Islocked,

        [Parameter()]
        [nullable[bool]]$Isplaceholder,

        [Parameter()]
        [nullable[bool]]$Hasofficialrating,

        [Parameter()]
        [nullable[bool]]$Collapseboxsetitems,

        [Parameter()]
        [int]$Minwidth,

        [Parameter()]
        [int]$Minheight,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [nullable[bool]]$Is3d,

        [Parameter()]
        [string[]]$Seriesstatus,

        [Parameter()]
        [string]$Namestartswithorgreater,

        [Parameter()]
        [string]$Namestartswith,

        [Parameter()]
        [string]$Namelessthan,

        [Parameter()]
        [string[]]$Studioids,

        [Parameter()]
        [string[]]$Genreids,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount,

        [Parameter()]
        [nullable[bool]]$Enableimages
    )


    $path = '/Items'
    $queryParameters = @{}
	# always include path - this is useful.
	$queryParameters['fields'] = 'Path'
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Maxofficialrating) { $queryParameters['maxOfficialRating'] = $Maxofficialrating }
    if ($PSBoundParameters.ContainsKey('Hasthemesong')) { $queryParameters['hasThemeSong'] = $Hasthemesong }
    if ($PSBoundParameters.ContainsKey('Hasthemevideo')) { $queryParameters['hasThemeVideo'] = $Hasthemevideo }
    if ($PSBoundParameters.ContainsKey('Hassubtitles')) { $queryParameters['hasSubtitles'] = $Hassubtitles }
    if ($PSBoundParameters.ContainsKey('Hasspecialfeature')) { $queryParameters['hasSpecialFeature'] = $Hasspecialfeature }
    if ($PSBoundParameters.ContainsKey('Hastrailer')) { $queryParameters['hasTrailer'] = $Hastrailer }
    if ($Adjacentto) { $queryParameters['adjacentTo'] = $Adjacentto }
    if ($Indexnumber) { $queryParameters['indexNumber'] = $Indexnumber }
    if ($Parentindexnumber) { $queryParameters['parentIndexNumber'] = $Parentindexnumber }
    if ($PSBoundParameters.ContainsKey('Hasparentalrating')) { $queryParameters['hasParentalRating'] = $Hasparentalrating }
    if ($PSBoundParameters.ContainsKey('Ishd')) { $queryParameters['isHd'] = $Ishd }
    if ($PSBoundParameters.ContainsKey('Is4k')) { $queryParameters['is4K'] = $Is4k }
    if ($Locationtypes) { $queryParameters['locationTypes'] = convertto-delimited $Locationtypes ',' }
    if ($Excludelocationtypes) { $queryParameters['excludeLocationTypes'] = convertto-delimited $Excludelocationtypes ',' }
    if ($PSBoundParameters.ContainsKey('Ismissing')) { $queryParameters['isMissing'] = $Ismissing }
    if ($PSBoundParameters.ContainsKey('Isunaired')) { $queryParameters['isUnaired'] = $Isunaired }
    if ($Mincommunityrating) { $queryParameters['minCommunityRating'] = $Mincommunityrating }
    if ($Mincriticrating) { $queryParameters['minCriticRating'] = $Mincriticrating }
    if ($Minpremieredate) { $queryParameters['minPremiereDate'] = $Minpremieredate }
    if ($Mindatelastsaved) { $queryParameters['minDateLastSaved'] = $Mindatelastsaved }
    if ($Mindatelastsavedforuser) { $queryParameters['minDateLastSavedForUser'] = $Mindatelastsavedforuser }
    if ($Maxpremieredate) { $queryParameters['maxPremiereDate'] = $Maxpremieredate }
    if ($PSBoundParameters.ContainsKey('Hasoverview')) { $queryParameters['hasOverview'] = $Hasoverview }
    if ($PSBoundParameters.ContainsKey('Hasimdbid')) { $queryParameters['hasImdbId'] = $Hasimdbid }
    if ($PSBoundParameters.ContainsKey('Hastmdbid')) { $queryParameters['hasTmdbId'] = $Hastmdbid }
    if ($PSBoundParameters.ContainsKey('Hastvdbid')) { $queryParameters['hasTvdbId'] = $Hastvdbid }
    if ($PSBoundParameters.ContainsKey('Ismovie')) { $queryParameters['isMovie'] = $Ismovie }
    if ($PSBoundParameters.ContainsKey('Isseries')) { $queryParameters['isSeries'] = $Isseries }
    if ($PSBoundParameters.ContainsKey('Isnews')) { $queryParameters['isNews'] = $Isnews }
    if ($PSBoundParameters.ContainsKey('Iskids')) { $queryParameters['isKids'] = $Iskids }
    if ($PSBoundParameters.ContainsKey('Issports')) { $queryParameters['isSports'] = $Issports }
    if ($Excludeitemids) { $queryParameters['excludeItemIds'] = convertto-delimited $Excludeitemids ',' }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($PSBoundParameters.ContainsKey('Recursive')) { $queryParameters['recursive'] = $Recursive }
    if ($Searchterm) { $queryParameters['searchTerm'] = $Searchterm }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Excludeitemtypes) { $queryParameters['excludeItemTypes'] = convertto-delimited $Excludeitemtypes ',' }
    if ($Includeitemtypes) { $queryParameters['includeItemTypes'] = convertto-delimited $Includeitemtypes ',' }
    if ($Filters) { $queryParameters['filters'] = convertto-delimited $Filters ',' }
    if ($PSBoundParameters.ContainsKey('Isfavorite')) { $queryParameters['isFavorite'] = $Isfavorite }
    if ($Mediatypes) { $queryParameters['mediaTypes'] = convertto-delimited $Mediatypes ',' }
    if ($Imagetypes) { $queryParameters['imageTypes'] = convertto-delimited $Imagetypes ',' }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($PSBoundParameters.ContainsKey('Isplayed')) { $queryParameters['isPlayed'] = $Isplayed }
    if ($Genres) { $queryParameters['genres'] = convertto-delimited $Genres ',' }
    if ($Officialratings) { $queryParameters['officialRatings'] = convertto-delimited $Officialratings ',' }
    if ($Tags) { $queryParameters['tags'] = convertto-delimited $Tags ',' }
    if ($Years) { $queryParameters['years'] = convertto-delimited $Years ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Person) { $queryParameters['person'] = $Person }
    if ($Personids) { $queryParameters['personIds'] = convertto-delimited $Personids ',' }
    if ($Persontypes) { $queryParameters['personTypes'] = convertto-delimited $Persontypes ',' }
    if ($Studios) { $queryParameters['studios'] = convertto-delimited $Studios ',' }
    if ($Artists) { $queryParameters['artists'] = convertto-delimited $Artists ',' }
    if ($Excludeartistids) { $queryParameters['excludeArtistIds'] = convertto-delimited $Excludeartistids ',' }
    if ($Artistids) { $queryParameters['artistIds'] = convertto-delimited $Artistids ',' }
    if ($Albumartistids) { $queryParameters['albumArtistIds'] = convertto-delimited $Albumartistids ',' }
    if ($Contributingartistids) { $queryParameters['contributingArtistIds'] = convertto-delimited $Contributingartistids ',' }
    if ($Albums) { $queryParameters['albums'] = convertto-delimited $Albums ',' }
    if ($Albumids) { $queryParameters['albumIds'] = convertto-delimited $Albumids ',' }
    if ($Ids) { $queryParameters['ids'] = convertto-delimited $Ids ',' }
    if ($Videotypes) { $queryParameters['videoTypes'] = convertto-delimited $Videotypes ',' }
    if ($Minofficialrating) { $queryParameters['minOfficialRating'] = $Minofficialrating }
    if ($PSBoundParameters.ContainsKey('Islocked')) { $queryParameters['isLocked'] = $Islocked }
    if ($PSBoundParameters.ContainsKey('Isplaceholder')) { $queryParameters['isPlaceHolder'] = $Isplaceholder }
    if ($PSBoundParameters.ContainsKey('Hasofficialrating')) { $queryParameters['hasOfficialRating'] = $Hasofficialrating }
    if ($PSBoundParameters.ContainsKey('Collapseboxsetitems')) { $queryParameters['collapseBoxSetItems'] = $Collapseboxsetitems }
    if ($Minwidth) { $queryParameters['minWidth'] = $Minwidth }
    if ($Minheight) { $queryParameters['minHeight'] = $Minheight }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($PSBoundParameters.ContainsKey('Is3d')) { $queryParameters['is3D'] = $Is3d }
    if ($Seriesstatus) { $queryParameters['seriesStatus'] = convertto-delimited $Seriesstatus ',' }
    if ($Namestartswithorgreater) { $queryParameters['nameStartsWithOrGreater'] = $Namestartswithorgreater }
    if ($Namestartswith) { $queryParameters['nameStartsWith'] = $Namestartswith }
    if ($Namelessthan) { $queryParameters['nameLessThan'] = $Namelessthan }
    if ($Studioids) { $queryParameters['studioIds'] = convertto-delimited $Studioids ',' }
    if ($Genreids) { $queryParameters['genreIds'] = convertto-delimited $Genreids ',' }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    return (Invoke-JellyfinRequest @invokeParams).Items
}
function Get-JellyfinItemUserData {
    <#
    .SYNOPSIS
            Get Item User Data.

    .DESCRIPTION
        API Endpoint: GET /UserItems/{itemId}/UserData
        Operation ID: GetItemUserData
        Tags: Items
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        The user id.
    
    .EXAMPLE
        Get-JellyfinItemUserData
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/UserItems/{itemId}/UserData'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinItemUserData {
    <#
    .SYNOPSIS
            Update Item User Data.

    .DESCRIPTION
        API Endpoint: POST /UserItems/{itemId}/UserData
        Operation ID: UpdateItemUserData
        Tags: Items
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        The user id.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinItemUserData
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [object]$Body
    )


    $path = '/UserItems/{itemId}/UserData'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinResumeItems {
    <#
    .SYNOPSIS
            Gets items based on a query.

    .DESCRIPTION
        API Endpoint: GET /UserItems/Resume
        Operation ID: GetResumeItems
        Tags: Items
    .PARAMETER Userid
        The user id.

    .PARAMETER Startindex
        The start index.

    .PARAMETER Limit
        The item limit.

    .PARAMETER Searchterm
        The search term.

    .PARAMETER Parentid
        Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output. This allows multiple, comma delimited. Options: Budget, Chapters, DateCreated, Genres, HomePageUrl, IndexOptions, MediaStreams, Overview, ParentId, Path, People, ProviderIds, PrimaryImageAspectRatio, Revenue, SortName, Studios, Taglines.

    .PARAMETER Mediatypes
        Optional. Filter by MediaType. Allows multiple, comma delimited.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Excludeitemtypes
        Optional. If specified, results will be filtered based on item type. This allows multiple, comma delimited.
        Possible Values: "AggregateFolder" "Audio" "AudioBook" "BasePluginFolder" "Book" "BoxSet" "Channel" "ChannelFolderItem" "CollectionFolder" "Episode" "Folder" "Genre" "ManualPlaylistsFolder" "Movie" "LiveTvChannel" "LiveTvProgram" "MusicAlbum" "MusicArtist" "MusicGenre" "MusicVideo" "Person" "Photo" "PhotoAlbum" "Playlist" "PlaylistsFolder" "Program" "Recording" "Season" "Series" "Studio" "Trailer" "TvChannel" "TvProgram" "UserRootFolder" "UserView" "Video" "Year"
        Comma Delimited


    .PARAMETER Includeitemtypes
        Optional. If specified, results will be filtered based on the item type. This allows multiple, comma delimited.
        Possible Values: "AggregateFolder" "Audio" "AudioBook" "BasePluginFolder" "Book" "BoxSet" "Channel" "ChannelFolderItem" "CollectionFolder" "Episode" "Folder" "Genre" "ManualPlaylistsFolder" "Movie" "LiveTvChannel" "LiveTvProgram" "MusicAlbum" "MusicArtist" "MusicGenre" "MusicVideo" "Person" "Photo" "PhotoAlbum" "Playlist" "PlaylistsFolder" "Program" "Recording" "Season" "Series" "Studio" "Trailer" "TvChannel" "TvProgram" "UserRootFolder" "UserView" "Video" "Year"
        Comma Delimited

    .PARAMETER Enabletotalrecordcount
        Optional. Enable the total record count.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Excludeactivesessions
        Optional. Whether to exclude the currently active sessions.
    
    .EXAMPLE
        Get-JellyfinResumeItems
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [string]$Searchterm,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [ValidateSet('Unknown','Video','Audio','Photo','Book')]
        [string[]]$Mediatypes,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Excludeitemtypes,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Includeitemtypes,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Excludeactivesessions
    )


    $path = '/UserItems/Resume'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Searchterm) { $queryParameters['searchTerm'] = $Searchterm }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Mediatypes) { $queryParameters['mediaTypes'] = convertto-delimited $Mediatypes ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Excludeitemtypes) { $queryParameters['excludeItemTypes'] = convertto-delimited $Excludeitemtypes ',' }
    if ($Includeitemtypes) { $queryParameters['includeItemTypes'] = convertto-delimited $Includeitemtypes ',' }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Excludeactivesessions')) { $queryParameters['excludeActiveSessions'] = $Excludeactivesessions }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region ItemUpdate Functions (3 functions)

function Set-JellyfinItem {
    <#
    .SYNOPSIS
            Updates an item.

    .DESCRIPTION
        API Endpoint: POST /Items/{itemId}
        Operation ID: UpdateItem
        Tags: ItemUpdate
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinItem
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [object]$Body
    )


    $path = '/Items/{itemId}'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinItemContentType {
    <#
    .SYNOPSIS
            Updates an item's content type.

    .DESCRIPTION
        API Endpoint: POST /Items/{itemId}/ContentType
        Operation ID: UpdateItemContentType
        Tags: ItemUpdate
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Contenttype
        The content type of the item.
    
    .EXAMPLE
        Set-JellyfinItemContentType
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Contenttype
    )


    $path = '/Items/{itemId}/ContentType'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Contenttype) { $queryParameters['contentType'] = $Contenttype }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinMetadataEditorInfo {
    <#
    .SYNOPSIS
            Gets metadata editor info for an item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/MetadataEditor
        Operation ID: GetMetadataEditorInfo
        Tags: ItemUpdate
    .PARAMETER Itemid
        Path parameter: itemId
    
    .EXAMPLE
        Get-JellyfinMetadataEditorInfo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid
    )


    $path = '/Items/{itemId}/MetadataEditor'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Library Functions (25 functions)

function Remove-JellyfinItems {
    <#
    .SYNOPSIS
            Deletes items from the library and filesystem.

    .DESCRIPTION
        API Endpoint: DELETE /Items
        Operation ID: DeleteItems
        Tags: Library
    .PARAMETER Ids
        The item ids.
    
    .EXAMPLE
        Remove-JellyfinItems
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$Ids
    )


    $path = '/Items'
    $queryParameters = @{}
    if ($Ids) { $queryParameters['ids'] = convertto-delimited $Ids ',' }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinItem {
    <#
    .SYNOPSIS
            Deletes an item from the library and filesystem.

    .DESCRIPTION
        API Endpoint: DELETE /Items/{itemId}
        Operation ID: DeleteItem
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId
    
    .EXAMPLE
        Remove-JellyfinItem
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid
    )


    $path = '/Items/{itemId}'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSimilarAlbums {
    <#
    .SYNOPSIS
            Gets similar items.

    .DESCRIPTION
        API Endpoint: GET /Albums/{itemId}/Similar
        Operation ID: GetSimilarAlbums
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Excludeartistids
        Exclude artist ids.

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output. This allows multiple, comma delimited. Options: Budget, Chapters, DateCreated, Genres, HomePageUrl, IndexOptions, MediaStreams, Overview, ParentId, Path, People, ProviderIds, PrimaryImageAspectRatio, Revenue, SortName, Studios, Taglines, TrailerUrls.
    
    .EXAMPLE
        Get-JellyfinSimilarAlbums
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string[]]$Excludeartistids,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields
    )


    $path = '/Albums/{itemId}/Similar'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Excludeartistids) { $queryParameters['excludeArtistIds'] = convertto-delimited $Excludeartistids ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSimilarArtists {
    <#
    .SYNOPSIS
            Gets similar items.

    .DESCRIPTION
        API Endpoint: GET /Artists/{itemId}/Similar
        Operation ID: GetSimilarArtists
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Excludeartistids
        Exclude artist ids.

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output. This allows multiple, comma delimited. Options: Budget, Chapters, DateCreated, Genres, HomePageUrl, IndexOptions, MediaStreams, Overview, ParentId, Path, People, ProviderIds, PrimaryImageAspectRatio, Revenue, SortName, Studios, Taglines, TrailerUrls.
    
    .EXAMPLE
        Get-JellyfinSimilarArtists
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string[]]$Excludeartistids,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields
    )


    $path = '/Artists/{itemId}/Similar'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Excludeartistids) { $queryParameters['excludeArtistIds'] = convertto-delimited $Excludeartistids ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinAncestors {
    <#
    .SYNOPSIS
            Gets all parents of an item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/Ancestors
        Operation ID: GetAncestors
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.
    
    .EXAMPLE
        Get-JellyfinAncestors
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Items/{itemId}/Ancestors'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinCriticReviews {
    <#
    .SYNOPSIS
            Gets critic review for an item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/CriticReviews
        Operation ID: GetCriticReviews
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId
    
    .EXAMPLE
        Get-JellyfinCriticReviews
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid
    )


    $path = '/Items/{itemId}/CriticReviews'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinDownload {
    <#
    .SYNOPSIS
            Downloads item media.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/Download
        Operation ID: GetDownload
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId
    
    .EXAMPLE
        Get-JellyfinDownload
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid
    )


    $path = '/Items/{itemId}/Download'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinFile {
    <#
    .SYNOPSIS
            Get the original file of an item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/File
        Operation ID: GetFile
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId
    
    .EXAMPLE
        Get-JellyfinFile
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid
    )


    $path = '/Items/{itemId}/File'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSimilarItems {
    <#
    .SYNOPSIS
            Gets similar items.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/Similar
        Operation ID: GetSimilarItems
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Excludeartistids
        Exclude artist ids.

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output. This allows multiple, comma delimited. Options: Budget, Chapters, DateCreated, Genres, HomePageUrl, IndexOptions, MediaStreams, Overview, ParentId, Path, People, ProviderIds, PrimaryImageAspectRatio, Revenue, SortName, Studios, Taglines, TrailerUrls.
    
    .EXAMPLE
        Get-JellyfinSimilarItems
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string[]]$Excludeartistids,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields
    )


    $path = '/Items/{itemId}/Similar'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Excludeartistids) { $queryParameters['excludeArtistIds'] = convertto-delimited $Excludeartistids ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinThemeMedia {
    <#
    .SYNOPSIS
            Get theme songs and videos for an item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/ThemeMedia
        Operation ID: GetThemeMedia
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Inheritfromparent
        Optional. Determines whether or not parent items should be searched for theme media.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited. Options: Album, AlbumArtist, Artist, Budget, CommunityRating, CriticRating, DateCreated, DatePlayed, PlayCount, PremiereDate, ProductionYear, SortName, Random, Revenue, Runtime.

    .PARAMETER Sortorder
        Optional. Sort Order - Ascending, Descending.
    
    .EXAMPLE
        Get-JellyfinThemeMedia
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [nullable[bool]]$Inheritfromparent,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [ValidateSet('Ascending','Descending')]
        [string[]]$Sortorder
    )


    $path = '/Items/{itemId}/ThemeMedia'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($PSBoundParameters.ContainsKey('Inheritfromparent')) { $queryParameters['inheritFromParent'] = $Inheritfromparent }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinThemeSongs {
    <#
    .SYNOPSIS
            Get theme songs for an item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/ThemeSongs
        Operation ID: GetThemeSongs
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Inheritfromparent
        Optional. Determines whether or not parent items should be searched for theme media.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited. Options: Album, AlbumArtist, Artist, Budget, CommunityRating, CriticRating, DateCreated, DatePlayed, PlayCount, PremiereDate, ProductionYear, SortName, Random, Revenue, Runtime.

    .PARAMETER Sortorder
        Optional. Sort Order - Ascending, Descending.
    
    .EXAMPLE
        Get-JellyfinThemeSongs
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [nullable[bool]]$Inheritfromparent,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [ValidateSet('Ascending','Descending')]
        [string[]]$Sortorder
    )


    $path = '/Items/{itemId}/ThemeSongs'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($PSBoundParameters.ContainsKey('Inheritfromparent')) { $queryParameters['inheritFromParent'] = $Inheritfromparent }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinThemeVideos {
    <#
    .SYNOPSIS
            Get theme videos for an item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/ThemeVideos
        Operation ID: GetThemeVideos
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Inheritfromparent
        Optional. Determines whether or not parent items should be searched for theme media.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited. Options: Album, AlbumArtist, Artist, Budget, CommunityRating, CriticRating, DateCreated, DatePlayed, PlayCount, PremiereDate, ProductionYear, SortName, Random, Revenue, Runtime.

    .PARAMETER Sortorder
        Optional. Sort Order - Ascending, Descending.
    
    .EXAMPLE
        Get-JellyfinThemeVideos
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [nullable[bool]]$Inheritfromparent,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [ValidateSet('Ascending','Descending')]
        [string[]]$Sortorder
    )


    $path = '/Items/{itemId}/ThemeVideos'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($PSBoundParameters.ContainsKey('Inheritfromparent')) { $queryParameters['inheritFromParent'] = $Inheritfromparent }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinItemCounts {
    <#
    .SYNOPSIS
            Get item counts.

    .DESCRIPTION
        API Endpoint: GET /Items/Counts
        Operation ID: GetItemCounts
        Tags: Library
    .PARAMETER Userid
        Optional. Get counts from a specific user's library.

    .PARAMETER Isfavorite
        Optional. Get counts of favorite items.
    
    .EXAMPLE
        Get-JellyfinItemCounts
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [nullable[bool]]$Isfavorite
    )


    $path = '/Items/Counts'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($PSBoundParameters.ContainsKey('Isfavorite')) { $queryParameters['isFavorite'] = $Isfavorite }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinLibraryOptionsInfo {
    <#
    .SYNOPSIS
            Gets the library options info.

    .DESCRIPTION
        API Endpoint: GET /Libraries/AvailableOptions
        Operation ID: GetLibraryOptionsInfo
        Tags: Library
    .PARAMETER Librarycontenttype
        Library content type.

    .PARAMETER Isnewlibrary
        Whether this is a new library.
    
    .EXAMPLE
        Get-JellyfinLibraryOptionsInfo
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Librarycontenttype,

        [Parameter()]
        [nullable[bool]]$Isnewlibrary
    )


    $path = '/Libraries/AvailableOptions'
    $queryParameters = @{}
    if ($Librarycontenttype) { $queryParameters['libraryContentType'] = $Librarycontenttype }
    if ($PSBoundParameters.ContainsKey('Isnewlibrary')) { $queryParameters['isNewLibrary'] = $Isnewlibrary }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinUpdatedMedia {
    <#
    .SYNOPSIS
            Reports that new movies have been added by an external source.

    .DESCRIPTION
        API Endpoint: POST /Library/Media/Updated
        Operation ID: PostUpdatedMedia
        Tags: Library
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinUpdatedMedia
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Library/Media/Updated'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinMediaFolders {
    <#
    .SYNOPSIS
            Gets all user media folders.

    .DESCRIPTION
        API Endpoint: GET /Library/MediaFolders
        Operation ID: GetMediaFolders
        Tags: Library
    .PARAMETER Ishidden
        Optional. Filter by folders that are marked hidden, or not.
    
    .EXAMPLE
        Get-JellyfinMediaFolders
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [nullable[bool]]$Ishidden
    )


    $path = '/Library/MediaFolders'
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Ishidden')) { $queryParameters['isHidden'] = $Ishidden }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinAddedMovies {
    <#
    .SYNOPSIS
            Reports that new movies have been added by an external source.

    .DESCRIPTION
        API Endpoint: POST /Library/Movies/Added
        Operation ID: PostAddedMovies
        Tags: Library
    .PARAMETER Tmdbid
        The tmdbId.

    .PARAMETER Imdbid
        The imdbId.
    
    .EXAMPLE
        Invoke-JellyfinAddedMovies
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Tmdbid,

        [Parameter()]
        [string]$Imdbid
    )


    $path = '/Library/Movies/Added'
    $queryParameters = @{}
    if ($Tmdbid) { $queryParameters['tmdbId'] = $Tmdbid }
    if ($Imdbid) { $queryParameters['imdbId'] = $Imdbid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinUpdatedMovies {
    <#
    .SYNOPSIS
            Reports that new movies have been added by an external source.

    .DESCRIPTION
        API Endpoint: POST /Library/Movies/Updated
        Operation ID: PostUpdatedMovies
        Tags: Library
    .PARAMETER Tmdbid
        The tmdbId.

    .PARAMETER Imdbid
        The imdbId.
    
    .EXAMPLE
        Invoke-JellyfinUpdatedMovies
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Tmdbid,

        [Parameter()]
        [string]$Imdbid
    )


    $path = '/Library/Movies/Updated'
    $queryParameters = @{}
    if ($Tmdbid) { $queryParameters['tmdbId'] = $Tmdbid }
    if ($Imdbid) { $queryParameters['imdbId'] = $Imdbid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPhysicalPaths {
    <#
    .SYNOPSIS
            Gets a list of physical paths from virtual folders.

    .DESCRIPTION
        API Endpoint: GET /Library/PhysicalPaths
        Operation ID: GetPhysicalPaths
        Tags: Library
    .EXAMPLE
        Get-JellyfinPhysicalPaths
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Library/PhysicalPaths' -Method GET
}
function Invoke-JellyfinRefreshLibrary {
    <#
    .SYNOPSIS
            Starts a library scan.

    .DESCRIPTION
        API Endpoint: POST /Library/Refresh
        Operation ID: RefreshLibrary
        Tags: Library
    .EXAMPLE
        Invoke-JellyfinRefreshLibrary
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Library/Refresh' -Method POST
}
function Invoke-JellyfinAddedSeries {
    <#
    .SYNOPSIS
            Reports that new episodes of a series have been added by an external source.

    .DESCRIPTION
        API Endpoint: POST /Library/Series/Added
        Operation ID: PostAddedSeries
        Tags: Library
    .PARAMETER Tvdbid
        The tvdbId.
    
    .EXAMPLE
        Invoke-JellyfinAddedSeries
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Tvdbid
    )


    $path = '/Library/Series/Added'
    $queryParameters = @{}
    if ($Tvdbid) { $queryParameters['tvdbId'] = $Tvdbid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinUpdatedSeries {
    <#
    .SYNOPSIS
            Reports that new episodes of a series have been added by an external source.

    .DESCRIPTION
        API Endpoint: POST /Library/Series/Updated
        Operation ID: PostUpdatedSeries
        Tags: Library
    .PARAMETER Tvdbid
        The tvdbId.
    
    .EXAMPLE
        Invoke-JellyfinUpdatedSeries
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Tvdbid
    )


    $path = '/Library/Series/Updated'
    $queryParameters = @{}
    if ($Tvdbid) { $queryParameters['tvdbId'] = $Tvdbid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSimilarMovies {
    <#
    .SYNOPSIS
            Gets similar items.

    .DESCRIPTION
        API Endpoint: GET /Movies/{itemId}/Similar
        Operation ID: GetSimilarMovies
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Excludeartistids
        Exclude artist ids.

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output. This allows multiple, comma delimited. Options: Budget, Chapters, DateCreated, Genres, HomePageUrl, IndexOptions, MediaStreams, Overview, ParentId, Path, People, ProviderIds, PrimaryImageAspectRatio, Revenue, SortName, Studios, Taglines, TrailerUrls.
    
    .EXAMPLE
        Get-JellyfinSimilarMovies
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string[]]$Excludeartistids,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields
    )


    $path = '/Movies/{itemId}/Similar'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Excludeartistids) { $queryParameters['excludeArtistIds'] = convertto-delimited $Excludeartistids ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSimilarShows {
    <#
    .SYNOPSIS
            Gets similar items.

    .DESCRIPTION
        API Endpoint: GET /Shows/{itemId}/Similar
        Operation ID: GetSimilarShows
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Excludeartistids
        Exclude artist ids.

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output. This allows multiple, comma delimited. Options: Budget, Chapters, DateCreated, Genres, HomePageUrl, IndexOptions, MediaStreams, Overview, ParentId, Path, People, ProviderIds, PrimaryImageAspectRatio, Revenue, SortName, Studios, Taglines, TrailerUrls.
    
    .EXAMPLE
        Get-JellyfinSimilarShows
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string[]]$Excludeartistids,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields
    )


    $path = '/Shows/{itemId}/Similar'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Excludeartistids) { $queryParameters['excludeArtistIds'] = convertto-delimited $Excludeartistids ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSimilarTrailers {
    <#
    .SYNOPSIS
            Gets similar items.

    .DESCRIPTION
        API Endpoint: GET /Trailers/{itemId}/Similar
        Operation ID: GetSimilarTrailers
        Tags: Library
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Excludeartistids
        Exclude artist ids.

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output. This allows multiple, comma delimited. Options: Budget, Chapters, DateCreated, Genres, HomePageUrl, IndexOptions, MediaStreams, Overview, ParentId, Path, People, ProviderIds, PrimaryImageAspectRatio, Revenue, SortName, Studios, Taglines, TrailerUrls.
    
    .EXAMPLE
        Get-JellyfinSimilarTrailers
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string[]]$Excludeartistids,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields
    )


    $path = '/Trailers/{itemId}/Similar'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Excludeartistids) { $queryParameters['excludeArtistIds'] = convertto-delimited $Excludeartistids ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region LibraryStructure Functions (8 functions)

function Get-JellyfinVirtualFolders {
    <#
    .SYNOPSIS
            Gets all virtual folders.

    .DESCRIPTION
        API Endpoint: GET /Library/VirtualFolders
        Operation ID: GetVirtualFolders
        Tags: LibraryStructure
    .EXAMPLE
        Get-JellyfinVirtualFolders
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Library/VirtualFolders' -Method GET
}
function New-JellyfinVirtualFolder {
    <#
    .SYNOPSIS
            Adds a virtual folder.

    .DESCRIPTION
        API Endpoint: POST /Library/VirtualFolders
        Operation ID: AddVirtualFolder
        Tags: LibraryStructure
    .PARAMETER Name
        The name of the virtual folder.

    .PARAMETER Collectiontype
        The type of the collection.

    .PARAMETER Paths
        The paths of the virtual folder.

    .PARAMETER Refreshlibrary
        Whether to refresh the library.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        New-JellyfinVirtualFolder
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$Collectiontype,

        [Parameter()]
        [string[]]$Paths,

        [Parameter()]
        [nullable[bool]]$Refreshlibrary,

        [Parameter()]
        [object]$Body
    )


    $path = '/Library/VirtualFolders'
    $queryParameters = @{}
    if ($Name) { $queryParameters['name'] = $Name }
    if ($Collectiontype) { $queryParameters['collectionType'] = $Collectiontype }
    if ($Paths) { $queryParameters['paths'] = convertto-delimited $Paths ',' }
    if ($PSBoundParameters.ContainsKey('Refreshlibrary')) { $queryParameters['refreshLibrary'] = $Refreshlibrary }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinVirtualFolder {
    <#
    .SYNOPSIS
            Removes a virtual folder.

    .DESCRIPTION
        API Endpoint: DELETE /Library/VirtualFolders
        Operation ID: RemoveVirtualFolder
        Tags: LibraryStructure
    .PARAMETER Name
        The name of the folder.

    .PARAMETER Refreshlibrary
        Whether to refresh the library.
    
    .EXAMPLE
        Remove-JellyfinVirtualFolder
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [nullable[bool]]$Refreshlibrary
    )


    $path = '/Library/VirtualFolders'
    $queryParameters = @{}
    if ($Name) { $queryParameters['name'] = $Name }
    if ($PSBoundParameters.ContainsKey('Refreshlibrary')) { $queryParameters['refreshLibrary'] = $Refreshlibrary }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinLibraryOptions {
    <#
    .SYNOPSIS
            Update library options.

    .DESCRIPTION
        API Endpoint: POST /Library/VirtualFolders/LibraryOptions
        Operation ID: UpdateLibraryOptions
        Tags: LibraryStructure
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinLibraryOptions
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Library/VirtualFolders/LibraryOptions'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinRenameVirtualFolder {
    <#
    .SYNOPSIS
            Renames a virtual folder.

    .DESCRIPTION
        API Endpoint: POST /Library/VirtualFolders/Name
        Operation ID: RenameVirtualFolder
        Tags: LibraryStructure
    .PARAMETER Name
        The name of the virtual folder.

    .PARAMETER Newname
        The new name.

    .PARAMETER Refreshlibrary
        Whether to refresh the library.
    
    .EXAMPLE
        Invoke-JellyfinRenameVirtualFolder
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$Newname,

        [Parameter()]
        [nullable[bool]]$Refreshlibrary
    )


    $path = '/Library/VirtualFolders/Name'
    $queryParameters = @{}
    if ($Name) { $queryParameters['name'] = $Name }
    if ($Newname) { $queryParameters['newName'] = $Newname }
    if ($PSBoundParameters.ContainsKey('Refreshlibrary')) { $queryParameters['refreshLibrary'] = $Refreshlibrary }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function New-JellyfinMediaPath {
    <#
    .SYNOPSIS
            Add a media path to a library.

    .DESCRIPTION
        API Endpoint: POST /Library/VirtualFolders/Paths
        Operation ID: AddMediaPath
        Tags: LibraryStructure
    .PARAMETER Refreshlibrary
        Whether to refresh the library.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        New-JellyfinMediaPath
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [nullable[bool]]$Refreshlibrary,

        [Parameter()]
        [object]$Body
    )


    $path = '/Library/VirtualFolders/Paths'
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Refreshlibrary')) { $queryParameters['refreshLibrary'] = $Refreshlibrary }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinMediaPath {
    <#
    .SYNOPSIS
            Remove a media path.

    .DESCRIPTION
        API Endpoint: DELETE /Library/VirtualFolders/Paths
        Operation ID: RemoveMediaPath
        Tags: LibraryStructure
    .PARAMETER Name
        The name of the library.

    .PARAMETER Path
        The path to remove.

    .PARAMETER Refreshlibrary
        Whether to refresh the library.
    
    .EXAMPLE
        Remove-JellyfinMediaPath
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [nullable[bool]]$Refreshlibrary
    )


    $path = '/Library/VirtualFolders/Paths'
    $queryParameters = @{}
    if ($Name) { $queryParameters['name'] = $Name }
    if ($Path) { $queryParameters['path'] = $Path }
    if ($PSBoundParameters.ContainsKey('Refreshlibrary')) { $queryParameters['refreshLibrary'] = $Refreshlibrary }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinMediaPath {
    <#
    .SYNOPSIS
            Updates a media path.

    .DESCRIPTION
        API Endpoint: POST /Library/VirtualFolders/Paths/Update
        Operation ID: UpdateMediaPath
        Tags: LibraryStructure
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinMediaPath
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Library/VirtualFolders/Paths/Update'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region LiveTv Functions (41 functions)

function Get-JellyfinChannelMappingOptions {
    <#
    .SYNOPSIS
            Get channel mapping options.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/ChannelMappingOptions
        Operation ID: GetChannelMappingOptions
        Tags: LiveTv
    .PARAMETER Providerid
        Provider id.
    
    .EXAMPLE
        Get-JellyfinChannelMappingOptions
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Providerid
    )


    $path = '/LiveTv/ChannelMappingOptions'
    $queryParameters = @{}
    if ($Providerid) { $queryParameters['providerId'] = $Providerid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinChannelMapping {
    <#
    .SYNOPSIS
            Set channel mappings.

    .DESCRIPTION
        API Endpoint: POST /LiveTv/ChannelMappings
        Operation ID: SetChannelMapping
        Tags: LiveTv
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinChannelMapping
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/LiveTv/ChannelMappings'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinLiveTvChannels {
    <#
    .SYNOPSIS
            Gets available live tv channels.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Channels
        Operation ID: GetLiveTvChannels
        Tags: LiveTv
    .PARAMETER Type
        Optional. Filter by channel type.

    .PARAMETER Userid
        Optional. Filter by user and attach user data.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Ismovie
        Optional. Filter for movies.

    .PARAMETER Isseries
        Optional. Filter for series.

    .PARAMETER Isnews
        Optional. Filter for news.

    .PARAMETER Iskids
        Optional. Filter for kids.

    .PARAMETER Issports
        Optional. Filter for sports.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Isfavorite
        Optional. Filter by channels that are favorites, or not.

    .PARAMETER Isliked
        Optional. Filter by channels that are liked, or not.

    .PARAMETER Isdisliked
        Optional. Filter by channels that are disliked, or not.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        "Optional. The image types to include in the output.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Sortby
        Optional. Key to sort by.

    .PARAMETER Sortorder
        Optional. Sort order.

    .PARAMETER Enablefavoritesorting
        Optional. Incorporate favorite and like status into channel sorting.

    .PARAMETER Addcurrentprogram
        Optional. Adds current program info to each channel.
    
    .EXAMPLE
        Get-JellyfinLiveTvChannels
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Type,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [nullable[bool]]$Ismovie,

        [Parameter()]
        [nullable[bool]]$Isseries,

        [Parameter()]
        [nullable[bool]]$Isnews,

        [Parameter()]
        [nullable[bool]]$Iskids,

        [Parameter()]
        [nullable[bool]]$Issports,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [nullable[bool]]$Isfavorite,

        [Parameter()]
        [nullable[bool]]$Isliked,

        [Parameter()]
        [nullable[bool]]$Isdisliked,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [string]$Sortorder,

        [Parameter()]
        [nullable[bool]]$Enablefavoritesorting,

        [Parameter()]
        [nullable[bool]]$Addcurrentprogram
    )


    $path = '/LiveTv/Channels'
    $queryParameters = @{}
    if ($Type) { $queryParameters['type'] = convertto-delimited $Type ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($PSBoundParameters.ContainsKey('Ismovie')) { $queryParameters['isMovie'] = $Ismovie }
    if ($PSBoundParameters.ContainsKey('Isseries')) { $queryParameters['isSeries'] = $Isseries }
    if ($PSBoundParameters.ContainsKey('Isnews')) { $queryParameters['isNews'] = $Isnews }
    if ($PSBoundParameters.ContainsKey('Iskids')) { $queryParameters['isKids'] = $Iskids }
    if ($PSBoundParameters.ContainsKey('Issports')) { $queryParameters['isSports'] = $Issports }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($PSBoundParameters.ContainsKey('Isfavorite')) { $queryParameters['isFavorite'] = $Isfavorite }
    if ($PSBoundParameters.ContainsKey('Isliked')) { $queryParameters['isLiked'] = $Isliked }
    if ($PSBoundParameters.ContainsKey('Isdisliked')) { $queryParameters['isDisliked'] = $Isdisliked }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }
    if ($PSBoundParameters.ContainsKey('Enablefavoritesorting')) { $queryParameters['enableFavoriteSorting'] = $Enablefavoritesorting }
    if ($PSBoundParameters.ContainsKey('Addcurrentprogram')) { $queryParameters['addCurrentProgram'] = $Addcurrentprogram }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinChannel {
    <#
    .SYNOPSIS
            Gets a live tv channel.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Channels/{channelId}
        Operation ID: GetChannel
        Tags: LiveTv
    .PARAMETER Channelid
        Path parameter: channelId

    .PARAMETER Userid
        Optional. Attach user data.
    
    .EXAMPLE
        Get-JellyfinChannel
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Channelid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/LiveTv/Channels/{channelId}'
    $path = $path -replace '\{channelId\}', $Channelid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinGuideInfo {
    <#
    .SYNOPSIS
            Get guide info.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/GuideInfo
        Operation ID: GetGuideInfo
        Tags: LiveTv
    .EXAMPLE
        Get-JellyfinGuideInfo
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/LiveTv/GuideInfo' -Method GET
}
function Get-JellyfinLiveTvInfo {
    <#
    .SYNOPSIS
            Gets available live tv services.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Info
        Operation ID: GetLiveTvInfo
        Tags: LiveTv
    .EXAMPLE
        Get-JellyfinLiveTvInfo
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/LiveTv/Info' -Method GET
}
function New-JellyfinListingProvider {
    <#
    .SYNOPSIS
            Adds a listings provider.

    .DESCRIPTION
        API Endpoint: POST /LiveTv/ListingProviders
        Operation ID: AddListingProvider
        Tags: LiveTv
    .PARAMETER Pw
        Password.

    .PARAMETER Validatelistings
        Validate listings.

    .PARAMETER Validatelogin
        Validate login.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        New-JellyfinListingProvider
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Pw,

        [Parameter()]
        [nullable[bool]]$Validatelistings,

        [Parameter()]
        [nullable[bool]]$Validatelogin,

        [Parameter()]
        [object]$Body
    )


    $path = '/LiveTv/ListingProviders'
    $queryParameters = @{}
    if ($Pw) { $queryParameters['pw'] = $Pw }
    if ($PSBoundParameters.ContainsKey('Validatelistings')) { $queryParameters['validateListings'] = $Validatelistings }
    if ($PSBoundParameters.ContainsKey('Validatelogin')) { $queryParameters['validateLogin'] = $Validatelogin }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinListingProvider {
    <#
    .SYNOPSIS
            Delete listing provider.

    .DESCRIPTION
        API Endpoint: DELETE /LiveTv/ListingProviders
        Operation ID: DeleteListingProvider
        Tags: LiveTv
    .PARAMETER Id
        Listing provider id.
    
    .EXAMPLE
        Remove-JellyfinListingProvider
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Id
    )


    $path = '/LiveTv/ListingProviders'
    $queryParameters = @{}
    if ($Id) { $queryParameters['id'] = $Id }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinDefaultListingProvider {
    <#
    .SYNOPSIS
            Gets default listings provider info.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/ListingProviders/Default
        Operation ID: GetDefaultListingProvider
        Tags: LiveTv
    .EXAMPLE
        Get-JellyfinDefaultListingProvider
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/LiveTv/ListingProviders/Default' -Method GET
}
function Get-JellyfinLineups {
    <#
    .SYNOPSIS
            Gets available lineups.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/ListingProviders/Lineups
        Operation ID: GetLineups
        Tags: LiveTv
    .PARAMETER Id
        Provider id.

    .PARAMETER Type
        Provider type.

    .PARAMETER Location
        Location.

    .PARAMETER Country
        Country.
    
    .EXAMPLE
        Get-JellyfinLineups
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Id,

        [Parameter()]
        [string]$Type,

        [Parameter()]
        [string]$Location,

        [Parameter()]
        [string]$Country
    )


    $path = '/LiveTv/ListingProviders/Lineups'
    $queryParameters = @{}
    if ($Id) { $queryParameters['id'] = $Id }
    if ($Type) { $queryParameters['type'] = convertto-delimited $Type ',' }
    if ($Location) { $queryParameters['location'] = $Location }
    if ($Country) { $queryParameters['country'] = $Country }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSchedulesDirectCountries {
    <#
    .SYNOPSIS
            Gets available countries.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/ListingProviders/SchedulesDirect/Countries
        Operation ID: GetSchedulesDirectCountries
        Tags: LiveTv
    .EXAMPLE
        Get-JellyfinSchedulesDirectCountries
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/LiveTv/ListingProviders/SchedulesDirect/Countries' -Method GET
}
function Get-JellyfinLiveRecordingFile {
    <#
    .SYNOPSIS
            Gets a live tv recording stream.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/LiveRecordings/{recordingId}/stream
        Operation ID: GetLiveRecordingFile
        Tags: LiveTv
    .PARAMETER Recordingid
        Path parameter: recordingId
    
    .EXAMPLE
        Get-JellyfinLiveRecordingFile
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Recordingid
    )


    $path = '/LiveTv/LiveRecordings/{recordingId}/stream'
    $path = $path -replace '\{recordingId\}', $Recordingid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinLiveStreamFile {
    <#
    .SYNOPSIS
            Gets a live tv channel stream.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/LiveStreamFiles/{streamId}/stream.{container}
        Operation ID: GetLiveStreamFile
        Tags: LiveTv
    .PARAMETER Streamid
        Path parameter: streamId

    .PARAMETER Container
        Path parameter: container
    
    .EXAMPLE
        Get-JellyfinLiveStreamFile
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Streamid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Container
    )


    $path = '/LiveTv/LiveStreamFiles/{streamId}/stream.{container}'
    $path = $path -replace '\{streamId\}', $Streamid
    $path = $path -replace '\{container\}', $Container

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinLiveTvPrograms {
    <#
    .SYNOPSIS
            Gets available live tv epgs.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Programs
        Operation ID: GetLiveTvPrograms
        Tags: LiveTv
    .PARAMETER Channelids
        The channels to return guide information for.

    .PARAMETER Userid
        Optional. Filter by user id.

    .PARAMETER Minstartdate
        Optional. The minimum premiere start date.

    .PARAMETER Hasaired
        Optional. Filter by programs that have completed airing, or not.

    .PARAMETER Isairing
        Optional. Filter by programs that are currently airing, or not.

    .PARAMETER Maxstartdate
        Optional. The maximum premiere start date.

    .PARAMETER Minenddate
        Optional. The minimum premiere end date.

    .PARAMETER Maxenddate
        Optional. The maximum premiere end date.

    .PARAMETER Ismovie
        Optional. Filter for movies.

    .PARAMETER Isseries
        Optional. Filter for series.

    .PARAMETER Isnews
        Optional. Filter for news.

    .PARAMETER Iskids
        Optional. Filter for kids.

    .PARAMETER Issports
        Optional. Filter for sports.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited. Options: Name, StartDate.

    .PARAMETER Sortorder
        Sort Order - Ascending,Descending.

    .PARAMETER Genres
        The genres to return guide information for.

    .PARAMETER Genreids
        The genre ids to return guide information for.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Seriestimerid
        Optional. Filter by series timer id.

    .PARAMETER Libraryseriesid
        Optional. Filter by library series id.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enabletotalrecordcount
        Retrieve total record count.
    
    .EXAMPLE
        Get-JellyfinLiveTvPrograms
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$Channelids,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Minstartdate,

        [Parameter()]
        [nullable[bool]]$Hasaired,

        [Parameter()]
        [nullable[bool]]$Isairing,

        [Parameter()]
        [string]$Maxstartdate,

        [Parameter()]
        [string]$Minenddate,

        [Parameter()]
        [string]$Maxenddate,

        [Parameter()]
        [nullable[bool]]$Ismovie,

        [Parameter()]
        [nullable[bool]]$Isseries,

        [Parameter()]
        [nullable[bool]]$Isnews,

        [Parameter()]
        [nullable[bool]]$Iskids,

        [Parameter()]
        [nullable[bool]]$Issports,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [ValidateSet('Ascending','Descending')]
        [string[]]$Sortorder,

        [Parameter()]
        [string[]]$Genres,

        [Parameter()]
        [string[]]$Genreids,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [string]$Seriestimerid,

        [Parameter()]
        [string]$Libraryseriesid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount
    )


    $path = '/LiveTv/Programs'
    $queryParameters = @{}
    if ($Channelids) { $queryParameters['channelIds'] = convertto-delimited $Channelids ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Minstartdate) { $queryParameters['minStartDate'] = $Minstartdate }
    if ($PSBoundParameters.ContainsKey('Hasaired')) { $queryParameters['hasAired'] = $Hasaired }
    if ($PSBoundParameters.ContainsKey('Isairing')) { $queryParameters['isAiring'] = $Isairing }
    if ($Maxstartdate) { $queryParameters['maxStartDate'] = $Maxstartdate }
    if ($Minenddate) { $queryParameters['minEndDate'] = $Minenddate }
    if ($Maxenddate) { $queryParameters['maxEndDate'] = $Maxenddate }
    if ($PSBoundParameters.ContainsKey('Ismovie')) { $queryParameters['isMovie'] = $Ismovie }
    if ($PSBoundParameters.ContainsKey('Isseries')) { $queryParameters['isSeries'] = $Isseries }
    if ($PSBoundParameters.ContainsKey('Isnews')) { $queryParameters['isNews'] = $Isnews }
    if ($PSBoundParameters.ContainsKey('Iskids')) { $queryParameters['isKids'] = $Iskids }
    if ($PSBoundParameters.ContainsKey('Issports')) { $queryParameters['isSports'] = $Issports }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }
    if ($Genres) { $queryParameters['genres'] = convertto-delimited $Genres ',' }
    if ($Genreids) { $queryParameters['genreIds'] = convertto-delimited $Genreids ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Seriestimerid) { $queryParameters['seriesTimerId'] = $Seriestimerid }
    if ($Libraryseriesid) { $queryParameters['librarySeriesId'] = $Libraryseriesid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPrograms {
    <#
    .SYNOPSIS
            Gets available live tv epgs.

    .DESCRIPTION
        API Endpoint: POST /LiveTv/Programs
        Operation ID: GetPrograms
        Tags: LiveTv
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Get-JellyfinPrograms
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/LiveTv/Programs'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinProgram {
    <#
    .SYNOPSIS
            Gets a live tv program.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Programs/{programId}
        Operation ID: GetProgram
        Tags: LiveTv
    .PARAMETER Programid
        Path parameter: programId

    .PARAMETER Userid
        Optional. Attach user data.
    
    .EXAMPLE
        Get-JellyfinProgram
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Programid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/LiveTv/Programs/{programId}'
    $path = $path -replace '\{programId\}', $Programid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinRecommendedPrograms {
    <#
    .SYNOPSIS
            Gets recommended live tv epgs.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Programs/Recommended
        Operation ID: GetRecommendedPrograms
        Tags: LiveTv
    .PARAMETER Userid
        Optional. filter by user id.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Isairing
        Optional. Filter by programs that are currently airing, or not.

    .PARAMETER Hasaired
        Optional. Filter by programs that have completed airing, or not.

    .PARAMETER Isseries
        Optional. Filter for series.

    .PARAMETER Ismovie
        Optional. Filter for movies.

    .PARAMETER Isnews
        Optional. Filter for news.

    .PARAMETER Iskids
        Optional. Filter for kids.

    .PARAMETER Issports
        Optional. Filter for sports.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Genreids
        The genres to return guide information for.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableuserdata
        Optional. include user data.

    .PARAMETER Enabletotalrecordcount
        Retrieve total record count.
    
    .EXAMPLE
        Get-JellyfinRecommendedPrograms
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [nullable[bool]]$Isairing,

        [Parameter()]
        [nullable[bool]]$Hasaired,

        [Parameter()]
        [nullable[bool]]$Isseries,

        [Parameter()]
        [nullable[bool]]$Ismovie,

        [Parameter()]
        [nullable[bool]]$Isnews,

        [Parameter()]
        [nullable[bool]]$Iskids,

        [Parameter()]
        [nullable[bool]]$Issports,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [string[]]$Genreids,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount
    )


    $path = '/LiveTv/Programs/Recommended'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($PSBoundParameters.ContainsKey('Isairing')) { $queryParameters['isAiring'] = $Isairing }
    if ($PSBoundParameters.ContainsKey('Hasaired')) { $queryParameters['hasAired'] = $Hasaired }
    if ($PSBoundParameters.ContainsKey('Isseries')) { $queryParameters['isSeries'] = $Isseries }
    if ($PSBoundParameters.ContainsKey('Ismovie')) { $queryParameters['isMovie'] = $Ismovie }
    if ($PSBoundParameters.ContainsKey('Isnews')) { $queryParameters['isNews'] = $Isnews }
    if ($PSBoundParameters.ContainsKey('Iskids')) { $queryParameters['isKids'] = $Iskids }
    if ($PSBoundParameters.ContainsKey('Issports')) { $queryParameters['isSports'] = $Issports }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Genreids) { $queryParameters['genreIds'] = convertto-delimited $Genreids ',' }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinRecordings {
    <#
    .SYNOPSIS
            Gets live tv recordings.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Recordings
        Operation ID: GetRecordings
        Tags: LiveTv
    .PARAMETER Channelid
        Optional. Filter by channel id.

    .PARAMETER Userid
        Optional. Filter by user and attach user data.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Status
        Optional. Filter by recording status.

    .PARAMETER Isinprogress
        Optional. Filter by recordings that are in progress, or not.

    .PARAMETER Seriestimerid
        Optional. Filter by recordings belonging to a series timer.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Ismovie
        Optional. Filter for movies.

    .PARAMETER Isseries
        Optional. Filter for series.

    .PARAMETER Iskids
        Optional. Filter for kids.

    .PARAMETER Issports
        Optional. Filter for sports.

    .PARAMETER Isnews
        Optional. Filter for news.

    .PARAMETER Islibraryitem
        Optional. Filter for is library item.

    .PARAMETER Enabletotalrecordcount
        Optional. Return total record count.
    
    .EXAMPLE
        Get-JellyfinRecordings
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Channelid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [string]$Status,

        [Parameter()]
        [nullable[bool]]$Isinprogress,

        [Parameter()]
        [string]$Seriestimerid,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [nullable[bool]]$Ismovie,

        [Parameter()]
        [nullable[bool]]$Isseries,

        [Parameter()]
        [nullable[bool]]$Iskids,

        [Parameter()]
        [nullable[bool]]$Issports,

        [Parameter()]
        [nullable[bool]]$Isnews,

        [Parameter()]
        [nullable[bool]]$Islibraryitem,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount
    )


    $path = '/LiveTv/Recordings'
    $queryParameters = @{}
    if ($Channelid) { $queryParameters['channelId'] = $Channelid }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Status) { $queryParameters['status'] = $Status }
    if ($PSBoundParameters.ContainsKey('Isinprogress')) { $queryParameters['isInProgress'] = $Isinprogress }
    if ($Seriestimerid) { $queryParameters['seriesTimerId'] = $Seriestimerid }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($PSBoundParameters.ContainsKey('Ismovie')) { $queryParameters['isMovie'] = $Ismovie }
    if ($PSBoundParameters.ContainsKey('Isseries')) { $queryParameters['isSeries'] = $Isseries }
    if ($PSBoundParameters.ContainsKey('Iskids')) { $queryParameters['isKids'] = $Iskids }
    if ($PSBoundParameters.ContainsKey('Issports')) { $queryParameters['isSports'] = $Issports }
    if ($PSBoundParameters.ContainsKey('Isnews')) { $queryParameters['isNews'] = $Isnews }
    if ($PSBoundParameters.ContainsKey('Islibraryitem')) { $queryParameters['isLibraryItem'] = $Islibraryitem }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinRecording {
    <#
    .SYNOPSIS
            Gets a live tv recording.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Recordings/{recordingId}
        Operation ID: GetRecording
        Tags: LiveTv
    .PARAMETER Recordingid
        Path parameter: recordingId

    .PARAMETER Userid
        Optional. Attach user data.
    
    .EXAMPLE
        Get-JellyfinRecording
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Recordingid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/LiveTv/Recordings/{recordingId}'
    $path = $path -replace '\{recordingId\}', $Recordingid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinRecording {
    <#
    .SYNOPSIS
            Deletes a live tv recording.

    .DESCRIPTION
        API Endpoint: DELETE /LiveTv/Recordings/{recordingId}
        Operation ID: DeleteRecording
        Tags: LiveTv
    .PARAMETER Recordingid
        Path parameter: recordingId
    
    .EXAMPLE
        Remove-JellyfinRecording
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Recordingid
    )


    $path = '/LiveTv/Recordings/{recordingId}'
    $path = $path -replace '\{recordingId\}', $Recordingid

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinRecordingFolders {
    <#
    .SYNOPSIS
            Gets recording folders.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Recordings/Folders
        Operation ID: GetRecordingFolders
        Tags: LiveTv
    .PARAMETER Userid
        Optional. Filter by user and attach user data.
    
    .EXAMPLE
        Get-JellyfinRecordingFolders
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid
    )


    $path = '/LiveTv/Recordings/Folders'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinRecordingGroups {
    <#
    .SYNOPSIS
            Gets live tv recording groups.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Recordings/Groups
        Operation ID: GetRecordingGroups
        Tags: LiveTv
    .PARAMETER Userid
        Optional. Filter by user and attach user data.
    
    .EXAMPLE
        Get-JellyfinRecordingGroups
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid
    )


    $path = '/LiveTv/Recordings/Groups'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinRecordingGroup {
    <#
    .SYNOPSIS
            Get recording group.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Recordings/Groups/{groupId}
        Operation ID: GetRecordingGroup
        Tags: LiveTv
    .PARAMETER Groupid
        Path parameter: groupId
    
    .EXAMPLE
        Get-JellyfinRecordingGroup
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Groupid
    )


    $path = '/LiveTv/Recordings/Groups/{groupId}'
    $path = $path -replace '\{groupId\}', $Groupid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinRecordingsSeries {
    <#
    .SYNOPSIS
            Gets live tv recording series.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Recordings/Series
        Operation ID: GetRecordingsSeries
        Tags: LiveTv
    .PARAMETER Channelid
        Optional. Filter by channel id.

    .PARAMETER Userid
        Optional. Filter by user and attach user data.

    .PARAMETER Groupid
        Optional. Filter by recording group.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Status
        Optional. Filter by recording status.

    .PARAMETER Isinprogress
        Optional. Filter by recordings that are in progress, or not.

    .PARAMETER Seriestimerid
        Optional. Filter by recordings belonging to a series timer.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Enabletotalrecordcount
        Optional. Return total record count.
    
    .EXAMPLE
        Get-JellyfinRecordingsSeries
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Channelid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Groupid,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [string]$Status,

        [Parameter()]
        [nullable[bool]]$Isinprogress,

        [Parameter()]
        [string]$Seriestimerid,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount
    )


    $path = '/LiveTv/Recordings/Series'
    $queryParameters = @{}
    if ($Channelid) { $queryParameters['channelId'] = $Channelid }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Groupid) { $queryParameters['groupId'] = $Groupid }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Status) { $queryParameters['status'] = $Status }
    if ($PSBoundParameters.ContainsKey('Isinprogress')) { $queryParameters['isInProgress'] = $Isinprogress }
    if ($Seriestimerid) { $queryParameters['seriesTimerId'] = $Seriestimerid }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSeriesTimers {
    <#
    .SYNOPSIS
            Gets live tv series timers.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/SeriesTimers
        Operation ID: GetSeriesTimers
        Tags: LiveTv
    .PARAMETER Sortby
        Optional. Sort by SortName or Priority.

    .PARAMETER Sortorder
        Optional. Sort in Ascending or Descending order.
    
    .EXAMPLE
        Get-JellyfinSeriesTimers
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Sortby,

        [Parameter()]
        [string]$Sortorder
    )


    $path = '/LiveTv/SeriesTimers'
    $queryParameters = @{}
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function New-JellyfinSeriesTimer {
    <#
    .SYNOPSIS
            Creates a live tv series timer.

    .DESCRIPTION
        API Endpoint: POST /LiveTv/SeriesTimers
        Operation ID: CreateSeriesTimer
        Tags: LiveTv
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        New-JellyfinSeriesTimer
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/LiveTv/SeriesTimers'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSeriesTimer {
    <#
    .SYNOPSIS
            Gets a live tv series timer.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/SeriesTimers/{timerId}
        Operation ID: GetSeriesTimer
        Tags: LiveTv
    .PARAMETER Timerid
        Path parameter: timerId
    
    .EXAMPLE
        Get-JellyfinSeriesTimer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Timerid
    )


    $path = '/LiveTv/SeriesTimers/{timerId}'
    $path = $path -replace '\{timerId\}', $Timerid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinCancelSeriesTimer {
    <#
    .SYNOPSIS
            Cancels a live tv series timer.

    .DESCRIPTION
        API Endpoint: DELETE /LiveTv/SeriesTimers/{timerId}
        Operation ID: CancelSeriesTimer
        Tags: LiveTv
    .PARAMETER Timerid
        Path parameter: timerId
    
    .EXAMPLE
        Remove-JellyfinCancelSeriesTimer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Timerid
    )


    $path = '/LiveTv/SeriesTimers/{timerId}'
    $path = $path -replace '\{timerId\}', $Timerid

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinSeriesTimer {
    <#
    .SYNOPSIS
            Updates a live tv series timer.

    .DESCRIPTION
        API Endpoint: POST /LiveTv/SeriesTimers/{timerId}
        Operation ID: UpdateSeriesTimer
        Tags: LiveTv
    .PARAMETER Timerid
        Path parameter: timerId

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinSeriesTimer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Timerid,

        [Parameter()]
        [object]$Body
    )


    $path = '/LiveTv/SeriesTimers/{timerId}'
    $path = $path -replace '\{timerId\}', $Timerid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinTimers {
    <#
    .SYNOPSIS
            Gets the live tv timers.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Timers
        Operation ID: GetTimers
        Tags: LiveTv
    .PARAMETER Channelid
        Optional. Filter by channel id.

    .PARAMETER Seriestimerid
        Optional. Filter by timers belonging to a series timer.

    .PARAMETER Isactive
        Optional. Filter by timers that are active.

    .PARAMETER Isscheduled
        Optional. Filter by timers that are scheduled.
    
    .EXAMPLE
        Get-JellyfinTimers
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Channelid,

        [Parameter()]
        [string]$Seriestimerid,

        [Parameter()]
        [nullable[bool]]$Isactive,

        [Parameter()]
        [nullable[bool]]$Isscheduled
    )


    $path = '/LiveTv/Timers'
    $queryParameters = @{}
    if ($Channelid) { $queryParameters['channelId'] = $Channelid }
    if ($Seriestimerid) { $queryParameters['seriesTimerId'] = $Seriestimerid }
    if ($PSBoundParameters.ContainsKey('Isactive')) { $queryParameters['isActive'] = $Isactive }
    if ($PSBoundParameters.ContainsKey('Isscheduled')) { $queryParameters['isScheduled'] = $Isscheduled }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function New-JellyfinTimer {
    <#
    .SYNOPSIS
            Creates a live tv timer.

    .DESCRIPTION
        API Endpoint: POST /LiveTv/Timers
        Operation ID: CreateTimer
        Tags: LiveTv
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        New-JellyfinTimer
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/LiveTv/Timers'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinTimer {
    <#
    .SYNOPSIS
            Gets a timer.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Timers/{timerId}
        Operation ID: GetTimer
        Tags: LiveTv
    .PARAMETER Timerid
        Path parameter: timerId
    
    .EXAMPLE
        Get-JellyfinTimer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Timerid
    )


    $path = '/LiveTv/Timers/{timerId}'
    $path = $path -replace '\{timerId\}', $Timerid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinCancelTimer {
    <#
    .SYNOPSIS
            Cancels a live tv timer.

    .DESCRIPTION
        API Endpoint: DELETE /LiveTv/Timers/{timerId}
        Operation ID: CancelTimer
        Tags: LiveTv
    .PARAMETER Timerid
        Path parameter: timerId
    
    .EXAMPLE
        Remove-JellyfinCancelTimer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Timerid
    )


    $path = '/LiveTv/Timers/{timerId}'
    $path = $path -replace '\{timerId\}', $Timerid

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinTimer {
    <#
    .SYNOPSIS
            Updates a live tv timer.

    .DESCRIPTION
        API Endpoint: POST /LiveTv/Timers/{timerId}
        Operation ID: UpdateTimer
        Tags: LiveTv
    .PARAMETER Timerid
        Path parameter: timerId

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinTimer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Timerid,

        [Parameter()]
        [object]$Body
    )


    $path = '/LiveTv/Timers/{timerId}'
    $path = $path -replace '\{timerId\}', $Timerid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinDefaultTimer {
    <#
    .SYNOPSIS
            Gets the default values for a new timer.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Timers/Defaults
        Operation ID: GetDefaultTimer
        Tags: LiveTv
    .PARAMETER Programid
        Optional. To attach default values based on a program.
    
    .EXAMPLE
        Get-JellyfinDefaultTimer
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Programid
    )


    $path = '/LiveTv/Timers/Defaults'
    $queryParameters = @{}
    if ($Programid) { $queryParameters['programId'] = $Programid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function New-JellyfinTunerHost {
    <#
    .SYNOPSIS
            Adds a tuner host.

    .DESCRIPTION
        API Endpoint: POST /LiveTv/TunerHosts
        Operation ID: AddTunerHost
        Tags: LiveTv
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        New-JellyfinTunerHost
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/LiveTv/TunerHosts'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinTunerHost {
    <#
    .SYNOPSIS
            Deletes a tuner host.

    .DESCRIPTION
        API Endpoint: DELETE /LiveTv/TunerHosts
        Operation ID: DeleteTunerHost
        Tags: LiveTv
    .PARAMETER Id
        Tuner host id.
    
    .EXAMPLE
        Remove-JellyfinTunerHost
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Id
    )


    $path = '/LiveTv/TunerHosts'
    $queryParameters = @{}
    if ($Id) { $queryParameters['id'] = $Id }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinTunerHostTypes {
    <#
    .SYNOPSIS
            Get tuner host types.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/TunerHosts/Types
        Operation ID: GetTunerHostTypes
        Tags: LiveTv
    .EXAMPLE
        Get-JellyfinTunerHostTypes
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/LiveTv/TunerHosts/Types' -Method GET
}
function Invoke-JellyfinResetTuner {
    <#
    .SYNOPSIS
            Resets a tv tuner.

    .DESCRIPTION
        API Endpoint: POST /LiveTv/Tuners/{tunerId}/Reset
        Operation ID: ResetTuner
        Tags: LiveTv
    .PARAMETER Tunerid
        Path parameter: tunerId
    
    .EXAMPLE
        Invoke-JellyfinResetTuner
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Tunerid
    )


    $path = '/LiveTv/Tuners/{tunerId}/Reset'
    $path = $path -replace '\{tunerId\}', $Tunerid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinDiscoverTuners {
    <#
    .SYNOPSIS
            Discover tuners.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Tuners/Discover
        Operation ID: DiscoverTuners
        Tags: LiveTv
    .PARAMETER Newdevicesonly
        Only discover new tuners.
    
    .EXAMPLE
        Get-JellyfinDiscoverTuners
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [nullable[bool]]$Newdevicesonly
    )


    $path = '/LiveTv/Tuners/Discover'
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Newdevicesonly')) { $queryParameters['newDevicesOnly'] = $Newdevicesonly }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinDiscvoverTuners {
    <#
    .SYNOPSIS
            Discover tuners.

    .DESCRIPTION
        API Endpoint: GET /LiveTv/Tuners/Discvover
        Operation ID: DiscvoverTuners
        Tags: LiveTv
    .PARAMETER Newdevicesonly
        Only discover new tuners.
    
    .EXAMPLE
        Get-JellyfinDiscvoverTuners
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [nullable[bool]]$Newdevicesonly
    )


    $path = '/LiveTv/Tuners/Discvover'
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Newdevicesonly')) { $queryParameters['newDevicesOnly'] = $Newdevicesonly }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Localization Functions (4 functions)

function Get-JellyfinCountries {
    <#
    .SYNOPSIS
            Gets known countries.

    .DESCRIPTION
        API Endpoint: GET /Localization/Countries
        Operation ID: GetCountries
        Tags: Localization
    .EXAMPLE
        Get-JellyfinCountries
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Localization/Countries' -Method GET
}
function Get-JellyfinCultures {
    <#
    .SYNOPSIS
            Gets known cultures.

    .DESCRIPTION
        API Endpoint: GET /Localization/Cultures
        Operation ID: GetCultures
        Tags: Localization
    .EXAMPLE
        Get-JellyfinCultures
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Localization/Cultures' -Method GET
}
function Get-JellyfinLocalizationOptions {
    <#
    .SYNOPSIS
            Gets localization options.

    .DESCRIPTION
        API Endpoint: GET /Localization/Options
        Operation ID: GetLocalizationOptions
        Tags: Localization
    .EXAMPLE
        Get-JellyfinLocalizationOptions
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Localization/Options' -Method GET
}
function Get-JellyfinParentalRatings {
    <#
    .SYNOPSIS
            Gets known parental ratings.

    .DESCRIPTION
        API Endpoint: GET /Localization/ParentalRatings
        Operation ID: GetParentalRatings
        Tags: Localization
    .EXAMPLE
        Get-JellyfinParentalRatings
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Localization/ParentalRatings' -Method GET
}
#endregion

#region Lyrics Functions (6 functions)

function Get-JellyfinLyrics {
    <#
    .SYNOPSIS
            Gets an item's lyrics.

    .DESCRIPTION
        API Endpoint: GET /Audio/{itemId}/Lyrics
        Operation ID: GetLyrics
        Tags: Lyrics
    .PARAMETER Itemid
        Path parameter: itemId
    
    .EXAMPLE
        Get-JellyfinLyrics
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid
    )


    $path = '/Audio/{itemId}/Lyrics'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinUploadLyrics {
    <#
    .SYNOPSIS
            Upload an external lyric file.

    .DESCRIPTION
        API Endpoint: POST /Audio/{itemId}/Lyrics
        Operation ID: UploadLyrics
        Tags: Lyrics
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Filename
        Name of the file being uploaded.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinUploadLyrics
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory)]
        [string]$Filename,

        [Parameter()]
        [object]$Body
    )


    $path = '/Audio/{itemId}/Lyrics'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Filename) { $queryParameters['fileName'] = $Filename }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinLyrics {
    <#
    .SYNOPSIS
            Deletes an external lyric file.

    .DESCRIPTION
        API Endpoint: DELETE /Audio/{itemId}/Lyrics
        Operation ID: DeleteLyrics
        Tags: Lyrics
    .PARAMETER Itemid
        Path parameter: itemId
    
    .EXAMPLE
        Remove-JellyfinLyrics
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid
    )


    $path = '/Audio/{itemId}/Lyrics'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSearchRemoteLyrics {
    <#
    .SYNOPSIS
            Search remote lyrics.

    .DESCRIPTION
        API Endpoint: GET /Audio/{itemId}/RemoteSearch/Lyrics
        Operation ID: SearchRemoteLyrics
        Tags: Lyrics
    .PARAMETER Itemid
        Path parameter: itemId
    
    .EXAMPLE
        Get-JellyfinSearchRemoteLyrics
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid
    )


    $path = '/Audio/{itemId}/RemoteSearch/Lyrics'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinDownloadRemoteLyrics {
    <#
    .SYNOPSIS
            Downloads a remote lyric.

    .DESCRIPTION
        API Endpoint: POST /Audio/{itemId}/RemoteSearch/Lyrics/{lyricId}
        Operation ID: DownloadRemoteLyrics
        Tags: Lyrics
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Lyricid
        Path parameter: lyricId
    
    .EXAMPLE
        Invoke-JellyfinDownloadRemoteLyrics
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Lyricid
    )


    $path = '/Audio/{itemId}/RemoteSearch/Lyrics/{lyricId}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{lyricId\}', $Lyricid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinRemoteLyrics {
    <#
    .SYNOPSIS
            Gets the remote lyrics.

    .DESCRIPTION
        API Endpoint: GET /Providers/Lyrics/{lyricId}
        Operation ID: GetRemoteLyrics
        Tags: Lyrics
    .PARAMETER Lyricid
        Path parameter: lyricId
    
    .EXAMPLE
        Get-JellyfinRemoteLyrics
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Lyricid
    )


    $path = '/Providers/Lyrics/{lyricId}'
    $path = $path -replace '\{lyricId\}', $Lyricid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region MediaInfo Functions (5 functions)

function Get-JellyfinPlaybackInfo {
    <#
    .SYNOPSIS
            Gets live playback media info for an item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/PlaybackInfo
        Operation ID: GetPlaybackInfo
        Tags: MediaInfo
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        The user id.
    
    .EXAMPLE
        Get-JellyfinPlaybackInfo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Items/{itemId}/PlaybackInfo'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPostedPlaybackInfo {
    <#
    .SYNOPSIS
            Gets live playback media info for an item.

    .DESCRIPTION
        API Endpoint: POST /Items/{itemId}/PlaybackInfo
        Operation ID: GetPostedPlaybackInfo
        Tags: MediaInfo
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        The user id.

    .PARAMETER Maxstreamingbitrate
        The maximum streaming bitrate.

    .PARAMETER Starttimeticks
        The start time in ticks.

    .PARAMETER Audiostreamindex
        The audio stream index.

    .PARAMETER Subtitlestreamindex
        The subtitle stream index.

    .PARAMETER Maxaudiochannels
        The maximum number of audio channels.

    .PARAMETER Mediasourceid
        The media source id.

    .PARAMETER Livestreamid
        The livestream id.

    .PARAMETER Autoopenlivestream
        Whether to auto open the livestream.

    .PARAMETER Enabledirectplay
        Whether to enable direct play. Default: true.

    .PARAMETER Enabledirectstream
        Whether to enable direct stream. Default: true.

    .PARAMETER Enabletranscoding
        Whether to enable transcoding. Default: true.

    .PARAMETER Allowvideostreamcopy
        Whether to allow to copy the video stream. Default: true.

    .PARAMETER Allowaudiostreamcopy
        Whether to allow to copy the audio stream. Default: true.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Get-JellyfinPostedPlaybackInfo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Maxstreamingbitrate,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Autoopenlivestream,

        [Parameter()]
        [nullable[bool]]$Enabledirectplay,

        [Parameter()]
        [nullable[bool]]$Enabledirectstream,

        [Parameter()]
        [nullable[bool]]$Enabletranscoding,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [object]$Body
    )


    $path = '/Items/{itemId}/PlaybackInfo'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Maxstreamingbitrate) { $queryParameters['maxStreamingBitrate'] = $Maxstreamingbitrate }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Autoopenlivestream')) { $queryParameters['autoOpenLiveStream'] = $Autoopenlivestream }
    if ($PSBoundParameters.ContainsKey('Enabledirectplay')) { $queryParameters['enableDirectPlay'] = $Enabledirectplay }
    if ($PSBoundParameters.ContainsKey('Enabledirectstream')) { $queryParameters['enableDirectStream'] = $Enabledirectstream }
    if ($PSBoundParameters.ContainsKey('Enabletranscoding')) { $queryParameters['enableTranscoding'] = $Enabletranscoding }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinCloseLiveStream {
    <#
    .SYNOPSIS
            Closes a media source.

    .DESCRIPTION
        API Endpoint: POST /LiveStreams/Close
        Operation ID: CloseLiveStream
        Tags: MediaInfo
    .PARAMETER Livestreamid
        The livestream id.
    
    .EXAMPLE
        Invoke-JellyfinCloseLiveStream
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Livestreamid
    )


    $path = '/LiveStreams/Close'
    $queryParameters = @{}
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinOpenLiveStream {
    <#
    .SYNOPSIS
            Opens a media source.

    .DESCRIPTION
        API Endpoint: POST /LiveStreams/Open
        Operation ID: OpenLiveStream
        Tags: MediaInfo
    .PARAMETER Opentoken
        The open token.

    .PARAMETER Userid
        The user id.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Maxstreamingbitrate
        The maximum streaming bitrate.

    .PARAMETER Starttimeticks
        The start time in ticks.

    .PARAMETER Audiostreamindex
        The audio stream index.

    .PARAMETER Subtitlestreamindex
        The subtitle stream index.

    .PARAMETER Maxaudiochannels
        The maximum number of audio channels.

    .PARAMETER Itemid
        The item id.

    .PARAMETER Enabledirectplay
        Whether to enable direct play. Default: true.

    .PARAMETER Enabledirectstream
        Whether to enable direct stream. Default: true.

    .PARAMETER Alwaysburninsubtitlewhentranscoding
        Always burn-in subtitle when transcoding.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinOpenLiveStream
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Opentoken,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [int]$Maxstreamingbitrate,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Itemid,

        [Parameter()]
        [nullable[bool]]$Enabledirectplay,

        [Parameter()]
        [nullable[bool]]$Enabledirectstream,

        [Parameter()]
        [nullable[bool]]$Alwaysburninsubtitlewhentranscoding,

        [Parameter()]
        [object]$Body
    )


    $path = '/LiveStreams/Open'
    $queryParameters = @{}
    if ($Opentoken) { $queryParameters['openToken'] = $Opentoken }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Maxstreamingbitrate) { $queryParameters['maxStreamingBitrate'] = $Maxstreamingbitrate }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Itemid) { $queryParameters['itemId'] = $Itemid }
    if ($PSBoundParameters.ContainsKey('Enabledirectplay')) { $queryParameters['enableDirectPlay'] = $Enabledirectplay }
    if ($PSBoundParameters.ContainsKey('Enabledirectstream')) { $queryParameters['enableDirectStream'] = $Enabledirectstream }
    if ($PSBoundParameters.ContainsKey('Alwaysburninsubtitlewhentranscoding')) { $queryParameters['alwaysBurnInSubtitleWhenTranscoding'] = $Alwaysburninsubtitlewhentranscoding }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinBitrateTestBytes {
    <#
    .SYNOPSIS
            Tests the network with a request with the size of the bitrate.

    .DESCRIPTION
        API Endpoint: GET /Playback/BitrateTest
        Operation ID: GetBitrateTestBytes
        Tags: MediaInfo
    .PARAMETER Size
        The bitrate. Defaults to 102400.
    
    .EXAMPLE
        Get-JellyfinBitrateTestBytes
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Size
    )


    $path = '/Playback/BitrateTest'
    $queryParameters = @{}
    if ($Size) { $queryParameters['size'] = $Size }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region MediaSegments Functions (1 functions)

function Get-JellyfinItemSegments {
    <#
    .SYNOPSIS
            Gets all media segments based on an itemId.

    .DESCRIPTION
        API Endpoint: GET /MediaSegments/{itemId}
        Operation ID: GetItemSegments
        Tags: MediaSegments
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Includesegmenttypes
        Optional filter of requested segment types.
    
    .EXAMPLE
        Get-JellyfinItemSegments
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string[]]$Includesegmenttypes
    )


    $path = '/MediaSegments/{itemId}'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Includesegmenttypes) { $queryParameters['includeSegmentTypes'] = convertto-delimited $Includesegmenttypes ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Movies Functions (1 functions)

function Get-JellyfinMovieRecommendations {
    <#
    .SYNOPSIS
            Gets movie recommendations.

    .DESCRIPTION
        API Endpoint: GET /Movies/Recommendations
        Operation ID: GetMovieRecommendations
        Tags: Movies
    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.

    .PARAMETER Parentid
        Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Fields
        Optional. The fields to return.

    .PARAMETER Categorylimit
        The max number of categories to return.

    .PARAMETER Itemlimit
        The max number of items to return per category.
    
    .EXAMPLE
        Get-JellyfinMovieRecommendations
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [int]$Categorylimit,

        [Parameter()]
        [int]$Itemlimit
    )


    $path = '/Movies/Recommendations'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Categorylimit) { $queryParameters['categoryLimit'] = $Categorylimit }
    if ($Itemlimit) { $queryParameters['itemLimit'] = $Itemlimit }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region MusicGenres Functions (2 functions)

function Get-JellyfinMusicGenres {
    <#
    .SYNOPSIS
            Gets all music genres from a given item, folder, or the entire library.

    .DESCRIPTION
        API Endpoint: GET /MusicGenres
        Operation ID: GetMusicGenres
        Tags: MusicGenres
    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Searchterm
        The search term.

    .PARAMETER Parentid
        Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Excludeitemtypes
        Optional. If specified, results will be filtered out based on item type. This allows multiple, comma delimited.
        Possible Values: "AggregateFolder" "Audio" "AudioBook" "BasePluginFolder" "Book" "BoxSet" "Channel" "ChannelFolderItem" "CollectionFolder" "Episode" "Folder" "Genre" "ManualPlaylistsFolder" "Movie" "LiveTvChannel" "LiveTvProgram" "MusicAlbum" "MusicArtist" "MusicGenre" "MusicVideo" "Person" "Photo" "PhotoAlbum" "Playlist" "PlaylistsFolder" "Program" "Recording" "Season" "Series" "Studio" "Trailer" "TvChannel" "TvProgram" "UserRootFolder" "UserView" "Video" "Year"
        Comma Delimited


    .PARAMETER Includeitemtypes
        Optional. If specified, results will be filtered in based on item type. This allows multiple, comma delimited.
        Possible Values: "AggregateFolder" "Audio" "AudioBook" "BasePluginFolder" "Book" "BoxSet" "Channel" "ChannelFolderItem" "CollectionFolder" "Episode" "Folder" "Genre" "ManualPlaylistsFolder" "Movie" "LiveTvChannel" "LiveTvProgram" "MusicAlbum" "MusicArtist" "MusicGenre" "MusicVideo" "Person" "Photo" "PhotoAlbum" "Playlist" "PlaylistsFolder" "Program" "Recording" "Season" "Series" "Studio" "Trailer" "TvChannel" "TvProgram" "UserRootFolder" "UserView" "Video" "Year"
        Comma Delimited

    .PARAMETER Isfavorite
        Optional filter by items that are marked as favorite, or not.

    .PARAMETER Imagetypelimit
        Optional, the max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Userid
        User id.

    .PARAMETER Namestartswithorgreater
        Optional filter by items whose name is sorted equally or greater than a given input string.

    .PARAMETER Namestartswith
        Optional filter by items whose name is sorted equally than a given input string.

    .PARAMETER Namelessthan
        Optional filter by items whose name is equally or lesser than a given input string.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited.

    .PARAMETER Sortorder
        Sort Order - Ascending,Descending.

    .PARAMETER Enableimages
        Optional, include image information in output.

    .PARAMETER Enabletotalrecordcount
        Optional. Include total record count.
    
    .EXAMPLE
        Get-JellyfinMusicGenres
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [string]$Searchterm,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Excludeitemtypes,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Includeitemtypes,

        [Parameter()]
        [nullable[bool]]$Isfavorite,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Namestartswithorgreater,

        [Parameter()]
        [string]$Namestartswith,

        [Parameter()]
        [string]$Namelessthan,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [ValidateSet('Ascending','Descending')]
        [string[]]$Sortorder,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount
    )


    $path = '/MusicGenres'
    $queryParameters = @{}
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Searchterm) { $queryParameters['searchTerm'] = $Searchterm }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Excludeitemtypes) { $queryParameters['excludeItemTypes'] = convertto-delimited $Excludeitemtypes ',' }
    if ($Includeitemtypes) { $queryParameters['includeItemTypes'] = convertto-delimited $Includeitemtypes ',' }
    if ($PSBoundParameters.ContainsKey('Isfavorite')) { $queryParameters['isFavorite'] = $Isfavorite }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Namestartswithorgreater) { $queryParameters['nameStartsWithOrGreater'] = $Namestartswithorgreater }
    if ($Namestartswith) { $queryParameters['nameStartsWith'] = $Namestartswith }
    if ($Namelessthan) { $queryParameters['nameLessThan'] = $Namelessthan }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinMusicGenre {
    <#
    .SYNOPSIS
            Gets a music genre, by name.

    .DESCRIPTION
        API Endpoint: GET /MusicGenres/{genreName}
        Operation ID: GetMusicGenre
        Tags: MusicGenres
    .PARAMETER Genrename
        Path parameter: genreName

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.
    
    .EXAMPLE
        Get-JellyfinMusicGenre
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Genrename,

        [Parameter()]
        [string]$Userid
    )


    $path = '/MusicGenres/{genreName}'
    $path = $path -replace '\{genreName\}', $Genrename
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Package Functions (6 functions)

function Get-JellyfinPackages {
    <#
    .SYNOPSIS
            Gets available packages.

    .DESCRIPTION
        API Endpoint: GET /Packages
        Operation ID: GetPackages
        Tags: Package
    .EXAMPLE
        Get-JellyfinPackages
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Packages' -Method GET
}
function Get-JellyfinPackageInfo {
    <#
    .SYNOPSIS
            Gets a package by name or assembly GUID.

    .DESCRIPTION
        API Endpoint: GET /Packages/{name}
        Operation ID: GetPackageInfo
        Tags: Package
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Assemblyguid
        The GUID of the associated assembly.
    
    .EXAMPLE
        Get-JellyfinPackageInfo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [string]$Assemblyguid
    )


    $path = '/Packages/{name}'
    $path = $path -replace '\{name\}', $Name
    $queryParameters = @{}
    if ($Assemblyguid) { $queryParameters['assemblyGuid'] = $Assemblyguid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinInstallPackage {
    <#
    .SYNOPSIS
            Installs a package.

    .DESCRIPTION
        API Endpoint: POST /Packages/Installed/{name}
        Operation ID: InstallPackage
        Tags: Package
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Assemblyguid
        GUID of the associated assembly.

    .PARAMETER Version
        Optional version. Defaults to latest version.

    .PARAMETER Repositoryurl
        Optional. Specify the repository to install from.
    
    .EXAMPLE
        Invoke-JellyfinInstallPackage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [string]$Assemblyguid,

        [Parameter()]
        [string]$Version,

        [Parameter()]
        [string]$Repositoryurl
    )


    $path = '/Packages/Installed/{name}'
    $path = $path -replace '\{name\}', $Name
    $queryParameters = @{}
    if ($Assemblyguid) { $queryParameters['assemblyGuid'] = $Assemblyguid }
    if ($Version) { $queryParameters['version'] = $Version }
    if ($Repositoryurl) { $queryParameters['repositoryUrl'] = $Repositoryurl }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinCancelPackageInstallation {
    <#
    .SYNOPSIS
            Cancels a package installation.

    .DESCRIPTION
        API Endpoint: DELETE /Packages/Installing/{packageId}
        Operation ID: CancelPackageInstallation
        Tags: Package
    .PARAMETER Packageid
        Path parameter: packageId
    
    .EXAMPLE
        Remove-JellyfinCancelPackageInstallation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Packageid
    )


    $path = '/Packages/Installing/{packageId}'
    $path = $path -replace '\{packageId\}', $Packageid

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinRepositories {
    <#
    .SYNOPSIS
            Gets all package repositories.

    .DESCRIPTION
        API Endpoint: GET /Repositories
        Operation ID: GetRepositories
        Tags: Package
    .EXAMPLE
        Get-JellyfinRepositories
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Repositories' -Method GET
}
function Set-JellyfinRepositories {
    <#
    .SYNOPSIS
            Sets the enabled and existing package repositories.

    .DESCRIPTION
        API Endpoint: POST /Repositories
        Operation ID: SetRepositories
        Tags: Package
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinRepositories
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Repositories'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Persons Functions (2 functions)

function Get-JellyfinPersons {
    <#
    .SYNOPSIS
            Gets all persons.

    .DESCRIPTION
        API Endpoint: GET /Persons
        Operation ID: GetPersons
        Tags: Persons
    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Searchterm
        The search term.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Filters
        Optional. Specify additional filters to apply.

    .PARAMETER Isfavorite
        Optional filter by items that are marked as favorite, or not. userId is required.

    .PARAMETER Enableuserdata
        Optional, include user data.

    .PARAMETER Imagetypelimit
        Optional, the max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Excludepersontypes
        Optional. If specified results will be filtered to exclude those containing the specified PersonType. Allows multiple, comma-delimited.

    .PARAMETER Persontypes
        Optional. If specified results will be filtered to include only those containing the specified PersonType. Allows multiple, comma-delimited.

    .PARAMETER Appearsinitemid
        Optional. If specified, person results will be filtered on items related to said persons.

    .PARAMETER Userid
        User id.

    .PARAMETER Enableimages
        Optional, include image information in output.
    
    .EXAMPLE
        Get-JellyfinPersons
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [string]$Searchterm,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [ValidateSet('IsFolder','IsNotFolder','IsUnplayed','IsPlayed','IsFavorite','IsResumable','Likes','Dislikes','IsFavoriteOrLikes')]
        [string[]]$Filters,

        [Parameter()]
        [nullable[bool]]$Isfavorite,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [string[]]$Excludepersontypes,

        [Parameter()]
        [string[]]$Persontypes,

        [Parameter()]
        [string]$Appearsinitemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [nullable[bool]]$Enableimages
    )


    $path = '/Persons'
    $queryParameters = @{}
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Searchterm) { $queryParameters['searchTerm'] = $Searchterm }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Filters) { $queryParameters['filters'] = convertto-delimited $Filters ',' }
    if ($PSBoundParameters.ContainsKey('Isfavorite')) { $queryParameters['isFavorite'] = $Isfavorite }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Excludepersontypes) { $queryParameters['excludePersonTypes'] = convertto-delimited $Excludepersontypes ',' }
    if ($Persontypes) { $queryParameters['personTypes'] = convertto-delimited $Persontypes ',' }
    if ($Appearsinitemid) { $queryParameters['appearsInItemId'] = $Appearsinitemid }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPerson {
    <#
    .SYNOPSIS
            Get person by name.

    .DESCRIPTION
        API Endpoint: GET /Persons/{name}
        Operation ID: GetPerson
        Tags: Persons
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.
    
    .EXAMPLE
        Get-JellyfinPerson
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Persons/{name}'
    $path = $path -replace '\{name\}', $Name
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Playlists Functions (11 functions)

function New-JellyfinPlaylist {
    <#
    .SYNOPSIS
            Creates a new playlist.

    .DESCRIPTION
        API Endpoint: POST /Playlists
        Operation ID: CreatePlaylist
        Tags: Playlists
    .PARAMETER Name
        The playlist name.

    .PARAMETER Ids
        The item ids.

    .PARAMETER Userid
        The user id.

    .PARAMETER Mediatype
        The media type.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        New-JellyfinPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string[]]$Ids,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Mediatype,

        [Parameter()]
        [object]$Body
    )


    $path = '/Playlists'
    $queryParameters = @{}
    if ($Name) { $queryParameters['name'] = $Name }
    if ($Ids) { $queryParameters['ids'] = convertto-delimited $Ids ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Mediatype) { $queryParameters['mediaType'] = convertto-delimited $Mediatype ',' }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinPlaylist {
    <#
    .SYNOPSIS
            Updates a playlist.

    .DESCRIPTION
        API Endpoint: POST /Playlists/{playlistId}
        Operation ID: UpdatePlaylist
        Tags: Playlists
    .PARAMETER Playlistid
        Path parameter: playlistId

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid,

        [Parameter()]
        [object]$Body
    )


    $path = '/Playlists/{playlistId}'
    $path = $path -replace '\{playlistId\}', $Playlistid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPlaylist {
    <#
    .SYNOPSIS
            Get a playlist.

    .DESCRIPTION
        API Endpoint: GET /Playlists/{playlistId}
        Operation ID: GetPlaylist
        Tags: Playlists
    .PARAMETER Playlistid
        Path parameter: playlistId
    
    .EXAMPLE
        Get-JellyfinPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid
    )


    $path = '/Playlists/{playlistId}'
    $path = $path -replace '\{playlistId\}', $Playlistid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function New-JellyfinItemToPlaylist {
    <#
    .SYNOPSIS
            Adds items to a playlist.

    .DESCRIPTION
        API Endpoint: POST /Playlists/{playlistId}/Items
        Operation ID: AddItemToPlaylist
        Tags: Playlists
    .PARAMETER Playlistid
        Path parameter: playlistId

    .PARAMETER Ids
        Item id, comma delimited.

    .PARAMETER Userid
        The userId.
    
    .EXAMPLE
        New-JellyfinItemToPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid,

        [Parameter()]
        [string[]]$Ids,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Playlists/{playlistId}/Items'
    $path = $path -replace '\{playlistId\}', $Playlistid
    $queryParameters = @{}
    if ($Ids) { $queryParameters['ids'] = convertto-delimited $Ids ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinItemFromPlaylist {
    <#
    .SYNOPSIS
            Removes items from a playlist.

    .DESCRIPTION
        API Endpoint: DELETE /Playlists/{playlistId}/Items
        Operation ID: RemoveItemFromPlaylist
        Tags: Playlists
    .PARAMETER Playlistid
        Path parameter: playlistId

    .PARAMETER Entryids
        The item ids, comma delimited.
    
    .EXAMPLE
        Remove-JellyfinItemFromPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid,

        [Parameter()]
        [string[]]$Entryids
    )


    $path = '/Playlists/{playlistId}/Items'
    $path = $path -replace '\{playlistId\}', $Playlistid
    $queryParameters = @{}
    if ($Entryids) { $queryParameters['entryIds'] = convertto-delimited $Entryids ',' }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPlaylistItems {
    <#
    .SYNOPSIS
            Gets the original items of a playlist.

    .DESCRIPTION
        API Endpoint: GET /Playlists/{playlistId}/Items
        Operation ID: GetPlaylistItems
        Tags: Playlists
    .PARAMETER Playlistid
        Path parameter: playlistId

    .PARAMETER Userid
        User id.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.
    
    .EXAMPLE
        Get-JellyfinPlaylistItems
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes
    )


    $path = '/Playlists/{playlistId}/Items'
    $path = $path -replace '\{playlistId\}', $Playlistid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinMoveItem {
    <#
    .SYNOPSIS
            Moves a playlist item.

    .DESCRIPTION
        API Endpoint: POST /Playlists/{playlistId}/Items/{itemId}/Move/{newIndex}
        Operation ID: MoveItem
        Tags: Playlists
    .PARAMETER Playlistid
        Path parameter: playlistId

    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Newindex
        Path parameter: newIndex
    
    .EXAMPLE
        Invoke-JellyfinMoveItem
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Newindex
    )


    $path = '/Playlists/{playlistId}/Items/{itemId}/Move/{newIndex}'
    $path = $path -replace '\{playlistId\}', $Playlistid
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{newIndex\}', $Newindex

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPlaylistUsers {
    <#
    .SYNOPSIS
            Get a playlist's users.

    .DESCRIPTION
        API Endpoint: GET /Playlists/{playlistId}/Users
        Operation ID: GetPlaylistUsers
        Tags: Playlists
    .PARAMETER Playlistid
        Path parameter: playlistId
    
    .EXAMPLE
        Get-JellyfinPlaylistUsers
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid
    )


    $path = '/Playlists/{playlistId}/Users'
    $path = $path -replace '\{playlistId\}', $Playlistid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPlaylistUser {
    <#
    .SYNOPSIS
            Get a playlist user.

    .DESCRIPTION
        API Endpoint: GET /Playlists/{playlistId}/Users/{userId}
        Operation ID: GetPlaylistUser
        Tags: Playlists
    .PARAMETER Playlistid
        Path parameter: playlistId

    .PARAMETER Userid
        Path parameter: userId
    
    .EXAMPLE
        Get-JellyfinPlaylistUser
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Userid
    )


    $path = '/Playlists/{playlistId}/Users/{userId}'
    $path = $path -replace '\{playlistId\}', $Playlistid
    $path = $path -replace '\{userId\}', $Userid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinPlaylistUser {
    <#
    .SYNOPSIS
            Modify a user of a playlist's users.

    .DESCRIPTION
        API Endpoint: POST /Playlists/{playlistId}/Users/{userId}
        Operation ID: UpdatePlaylistUser
        Tags: Playlists
    .PARAMETER Playlistid
        Path parameter: playlistId

    .PARAMETER Userid
        Path parameter: userId

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinPlaylistUser
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Userid,

        [Parameter()]
        [object]$Body
    )


    $path = '/Playlists/{playlistId}/Users/{userId}'
    $path = $path -replace '\{playlistId\}', $Playlistid
    $path = $path -replace '\{userId\}', $Userid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinUserFromPlaylist {
    <#
    .SYNOPSIS
            Remove a user from a playlist's users.

    .DESCRIPTION
        API Endpoint: DELETE /Playlists/{playlistId}/Users/{userId}
        Operation ID: RemoveUserFromPlaylist
        Tags: Playlists
    .PARAMETER Playlistid
        Path parameter: playlistId

    .PARAMETER Userid
        Path parameter: userId
    
    .EXAMPLE
        Remove-JellyfinUserFromPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Playlistid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Userid
    )


    $path = '/Playlists/{playlistId}/Users/{userId}'
    $path = $path -replace '\{playlistId\}', $Playlistid
    $path = $path -replace '\{userId\}', $Userid

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Playstate Functions (9 functions)

function Invoke-JellyfinOnPlaybackStart {
    <#
    .SYNOPSIS
            Reports that a session has begun playing an item.

    .DESCRIPTION
        API Endpoint: POST /PlayingItems/{itemId}
        Operation ID: OnPlaybackStart
        Tags: Playstate
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Mediasourceid
        The id of the MediaSource.

    .PARAMETER Audiostreamindex
        The audio stream index.

    .PARAMETER Subtitlestreamindex
        The subtitle stream index.

    .PARAMETER Playmethod
        The play method.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Canseek
        Indicates if the client can seek.
    
    .EXAMPLE
        Invoke-JellyfinOnPlaybackStart
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Playmethod,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [nullable[bool]]$Canseek
    )


    $path = '/PlayingItems/{itemId}'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Playmethod) { $queryParameters['playMethod'] = $Playmethod }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($PSBoundParameters.ContainsKey('Canseek')) { $queryParameters['canSeek'] = $Canseek }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinOnPlaybackStopped {
    <#
    .SYNOPSIS
            Reports that a session has stopped playing an item.

    .DESCRIPTION
        API Endpoint: DELETE /PlayingItems/{itemId}
        Operation ID: OnPlaybackStopped
        Tags: Playstate
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Mediasourceid
        The id of the MediaSource.

    .PARAMETER Nextmediatype
        The next media type that will play.

    .PARAMETER Positionticks
        Optional. The position, in ticks, where playback stopped. 1 tick = 10000 ms.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Playsessionid
        The play session id.
    
    .EXAMPLE
        Remove-JellyfinOnPlaybackStopped
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Nextmediatype,

        [Parameter()]
        [int]$Positionticks,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [string]$Playsessionid
    )


    $path = '/PlayingItems/{itemId}'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Nextmediatype) { $queryParameters['nextMediaType'] = $Nextmediatype }
    if ($Positionticks) { $queryParameters['positionTicks'] = $Positionticks }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinOnPlaybackProgress {
    <#
    .SYNOPSIS
            Reports a session's playback progress.

    .DESCRIPTION
        API Endpoint: POST /PlayingItems/{itemId}/Progress
        Operation ID: OnPlaybackProgress
        Tags: Playstate
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Mediasourceid
        The id of the MediaSource.

    .PARAMETER Positionticks
        Optional. The current position, in ticks. 1 tick = 10000 ms.

    .PARAMETER Audiostreamindex
        The audio stream index.

    .PARAMETER Subtitlestreamindex
        The subtitle stream index.

    .PARAMETER Volumelevel
        Scale of 0-100.

    .PARAMETER Playmethod
        The play method.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Repeatmode
        The repeat mode.

    .PARAMETER Ispaused
        Indicates if the player is paused.

    .PARAMETER Ismuted
        Indicates if the player is muted.
    
    .EXAMPLE
        Invoke-JellyfinOnPlaybackProgress
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [int]$Positionticks,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [int]$Volumelevel,

        [Parameter()]
        [string]$Playmethod,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Repeatmode,

        [Parameter()]
        [nullable[bool]]$Ispaused,

        [Parameter()]
        [nullable[bool]]$Ismuted
    )


    $path = '/PlayingItems/{itemId}/Progress'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Positionticks) { $queryParameters['positionTicks'] = $Positionticks }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Volumelevel) { $queryParameters['volumeLevel'] = $Volumelevel }
    if ($Playmethod) { $queryParameters['playMethod'] = $Playmethod }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Repeatmode) { $queryParameters['repeatMode'] = $Repeatmode }
    if ($PSBoundParameters.ContainsKey('Ispaused')) { $queryParameters['isPaused'] = $Ispaused }
    if ($PSBoundParameters.ContainsKey('Ismuted')) { $queryParameters['isMuted'] = $Ismuted }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinReportPlaybackStart {
    <#
    .SYNOPSIS
            Reports playback has started within a session.

    .DESCRIPTION
        API Endpoint: POST /Sessions/Playing
        Operation ID: ReportPlaybackStart
        Tags: Playstate
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinReportPlaybackStart
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Sessions/Playing'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinPingPlaybackSession {
    <#
    .SYNOPSIS
            Pings a playback session.

    .DESCRIPTION
        API Endpoint: POST /Sessions/Playing/Ping
        Operation ID: PingPlaybackSession
        Tags: Playstate
    .PARAMETER Playsessionid
        Playback session id.
    
    .EXAMPLE
        Invoke-JellyfinPingPlaybackSession
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Playsessionid
    )


    $path = '/Sessions/Playing/Ping'
    $queryParameters = @{}
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinReportPlaybackProgress {
    <#
    .SYNOPSIS
            Reports playback progress within a session.

    .DESCRIPTION
        API Endpoint: POST /Sessions/Playing/Progress
        Operation ID: ReportPlaybackProgress
        Tags: Playstate
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinReportPlaybackProgress
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Sessions/Playing/Progress'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinReportPlaybackStopped {
    <#
    .SYNOPSIS
            Reports playback has stopped within a session.

    .DESCRIPTION
        API Endpoint: POST /Sessions/Playing/Stopped
        Operation ID: ReportPlaybackStopped
        Tags: Playstate
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinReportPlaybackStopped
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Sessions/Playing/Stopped'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinMarkPlayedItem {
    <#
    .SYNOPSIS
            Marks an item as played for user.

    .DESCRIPTION
        API Endpoint: POST /UserPlayedItems/{itemId}
        Operation ID: MarkPlayedItem
        Tags: Playstate
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        User id.

    .PARAMETER Dateplayed
        Optional. The date the item was played.
    
    .EXAMPLE
        Invoke-JellyfinMarkPlayedItem
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Dateplayed
    )


    $path = '/UserPlayedItems/{itemId}'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Dateplayed) { $queryParameters['datePlayed'] = $Dateplayed }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinMarkUnplayedItem {
    <#
    .SYNOPSIS
            Marks an item as unplayed for user.

    .DESCRIPTION
        API Endpoint: DELETE /UserPlayedItems/{itemId}
        Operation ID: MarkUnplayedItem
        Tags: Playstate
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        User id.
    
    .EXAMPLE
        Remove-JellyfinMarkUnplayedItem
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/UserPlayedItems/{itemId}'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Plugins Functions (9 functions)

function Get-JellyfinPlugins {
    <#
    .SYNOPSIS
            Gets a list of currently installed plugins.

    .DESCRIPTION
        API Endpoint: GET /Plugins
        Operation ID: GetPlugins
        Tags: Plugins
    .EXAMPLE
        Get-JellyfinPlugins
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Plugins' -Method GET
}
function Remove-JellyfinUninstallPlugin {
    <#
    .SYNOPSIS
            Uninstalls a plugin.

    .DESCRIPTION
        API Endpoint: DELETE /Plugins/{pluginId}
        Operation ID: UninstallPlugin
        Tags: Plugins
    .PARAMETER Pluginid
        Path parameter: pluginId
    
    .EXAMPLE
        Remove-JellyfinUninstallPlugin
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Pluginid
    )


    $path = '/Plugins/{pluginId}'
    $path = $path -replace '\{pluginId\}', $Pluginid

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinUninstallPluginByVersion {
    <#
    .SYNOPSIS
            Uninstalls a plugin by version.

    .DESCRIPTION
        API Endpoint: DELETE /Plugins/{pluginId}/{version}
        Operation ID: UninstallPluginByVersion
        Tags: Plugins
    .PARAMETER Pluginid
        Path parameter: pluginId

    .PARAMETER Version
        Path parameter: version
    
    .EXAMPLE
        Remove-JellyfinUninstallPluginByVersion
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Pluginid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Version
    )


    $path = '/Plugins/{pluginId}/{version}'
    $path = $path -replace '\{pluginId\}', $Pluginid
    $path = $path -replace '\{version\}', $Version

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Disable-JellyfinPlugin {
    <#
    .SYNOPSIS
            Disable a plugin.

    .DESCRIPTION
        API Endpoint: POST /Plugins/{pluginId}/{version}/Disable
        Operation ID: DisablePlugin
        Tags: Plugins
    .PARAMETER Pluginid
        Path parameter: pluginId

    .PARAMETER Version
        Path parameter: version
    
    .EXAMPLE
        Disable-JellyfinPlugin
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Pluginid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Version
    )


    $path = '/Plugins/{pluginId}/{version}/Disable'
    $path = $path -replace '\{pluginId\}', $Pluginid
    $path = $path -replace '\{version\}', $Version

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Enable-JellyfinPlugin {
    <#
    .SYNOPSIS
            Enables a disabled plugin.

    .DESCRIPTION
        API Endpoint: POST /Plugins/{pluginId}/{version}/Enable
        Operation ID: EnablePlugin
        Tags: Plugins
    .PARAMETER Pluginid
        Path parameter: pluginId

    .PARAMETER Version
        Path parameter: version
    
    .EXAMPLE
        Enable-JellyfinPlugin
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Pluginid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Version
    )


    $path = '/Plugins/{pluginId}/{version}/Enable'
    $path = $path -replace '\{pluginId\}', $Pluginid
    $path = $path -replace '\{version\}', $Version

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPluginImage {
    <#
    .SYNOPSIS
            Gets a plugin's image.

    .DESCRIPTION
        API Endpoint: GET /Plugins/{pluginId}/{version}/Image
        Operation ID: GetPluginImage
        Tags: Plugins
    .PARAMETER Pluginid
        Path parameter: pluginId

    .PARAMETER Version
        Path parameter: version
    
    .EXAMPLE
        Get-JellyfinPluginImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Pluginid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Version
    )


    $path = '/Plugins/{pluginId}/{version}/Image'
    $path = $path -replace '\{pluginId\}', $Pluginid
    $path = $path -replace '\{version\}', $Version

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPluginConfiguration {
    <#
    .SYNOPSIS
            Gets plugin configuration.

    .DESCRIPTION
        API Endpoint: GET /Plugins/{pluginId}/Configuration
        Operation ID: GetPluginConfiguration
        Tags: Plugins
    .PARAMETER Pluginid
        Path parameter: pluginId
    
    .EXAMPLE
        Get-JellyfinPluginConfiguration
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Pluginid
    )


    $path = '/Plugins/{pluginId}/Configuration'
    $path = $path -replace '\{pluginId\}', $Pluginid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinPluginConfiguration {
    <#
    .SYNOPSIS
            Updates plugin configuration.

    .DESCRIPTION
        API Endpoint: POST /Plugins/{pluginId}/Configuration
        Operation ID: UpdatePluginConfiguration
        Tags: Plugins
    .PARAMETER Pluginid
        Path parameter: pluginId
    
    .EXAMPLE
        Set-JellyfinPluginConfiguration
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Pluginid
    )


    $path = '/Plugins/{pluginId}/Configuration'
    $path = $path -replace '\{pluginId\}', $Pluginid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPluginManifest {
    <#
    .SYNOPSIS
            Gets a plugin's manifest.

    .DESCRIPTION
        API Endpoint: POST /Plugins/{pluginId}/Manifest
        Operation ID: GetPluginManifest
        Tags: Plugins
    .PARAMETER Pluginid
        Path parameter: pluginId
    
    .EXAMPLE
        Get-JellyfinPluginManifest
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Pluginid
    )


    $path = '/Plugins/{pluginId}/Manifest'
    $path = $path -replace '\{pluginId\}', $Pluginid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region QuickConnect Functions (4 functions)

function Invoke-JellyfinAuthorizeQuickConnect {
    <#
    .SYNOPSIS
            Authorizes a pending quick connect request.

    .DESCRIPTION
        API Endpoint: POST /QuickConnect/Authorize
        Operation ID: AuthorizeQuickConnect
        Tags: QuickConnect
    .PARAMETER Code
        Quick connect code to authorize.

    .PARAMETER Userid
        The user the authorize. Access to the requested user is required.
    
    .EXAMPLE
        Invoke-JellyfinAuthorizeQuickConnect
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Code,

        [Parameter()]
        [string]$Userid
    )


    $path = '/QuickConnect/Authorize'
    $queryParameters = @{}
    if ($Code) { $queryParameters['code'] = $Code }
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinQuickConnectState {
    <#
    .SYNOPSIS
            Attempts to retrieve authentication information.

    .DESCRIPTION
        API Endpoint: GET /QuickConnect/Connect
        Operation ID: GetQuickConnectState
        Tags: QuickConnect
    .PARAMETER Secret
        Secret previously returned from the Initiate endpoint.
    
    .EXAMPLE
        Get-JellyfinQuickConnectState
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Secret
    )


    $path = '/QuickConnect/Connect'
    $queryParameters = @{}
    if ($Secret) { $queryParameters['secret'] = $Secret }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinQuickConnectEnabled {
    <#
    .SYNOPSIS
            Gets the current quick connect state.

    .DESCRIPTION
        API Endpoint: GET /QuickConnect/Enabled
        Operation ID: GetQuickConnectEnabled
        Tags: QuickConnect
    .EXAMPLE
        Get-JellyfinQuickConnectEnabled
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/QuickConnect/Enabled' -Method GET
}
function Invoke-JellyfinInitiateQuickConnect {
    <#
    .SYNOPSIS
            Initiate a new quick connect request.

    .DESCRIPTION
        API Endpoint: POST /QuickConnect/Initiate
        Operation ID: InitiateQuickConnect
        Tags: QuickConnect
    .EXAMPLE
        Invoke-JellyfinInitiateQuickConnect
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/QuickConnect/Initiate' -Method POST
}
#endregion

#region RemoteImage Functions (3 functions)

function Get-JellyfinRemoteImages {
    <#
    .SYNOPSIS
            Gets available remote images for an item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/RemoteImages
        Operation ID: GetRemoteImages
        Tags: RemoteImage
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Type
        The image type.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Providername
        Optional. The image provider to use.

    .PARAMETER Includealllanguages
        Optional. Include all languages.
    
    .EXAMPLE
        Get-JellyfinRemoteImages
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Type,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [string]$Providername,

        [Parameter()]
        [nullable[bool]]$Includealllanguages
    )


    $path = '/Items/{itemId}/RemoteImages'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Type) { $queryParameters['type'] = convertto-delimited $Type ',' }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Providername) { $queryParameters['providerName'] = $Providername }
    if ($PSBoundParameters.ContainsKey('Includealllanguages')) { $queryParameters['includeAllLanguages'] = $Includealllanguages }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinDownloadRemoteImage {
    <#
    .SYNOPSIS
            Downloads a remote image for an item.

    .DESCRIPTION
        API Endpoint: POST /Items/{itemId}/RemoteImages/Download
        Operation ID: DownloadRemoteImage
        Tags: RemoteImage
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Type
        The image type.

    .PARAMETER Imageurl
        The image url.
    
    .EXAMPLE
        Invoke-JellyfinDownloadRemoteImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory)]
        [string]$Type,

        [Parameter()]
        [string]$Imageurl
    )


    $path = '/Items/{itemId}/RemoteImages/Download'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Type) { $queryParameters['type'] = convertto-delimited $Type ',' }
    if ($Imageurl) { $queryParameters['imageUrl'] = $Imageurl }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinRemoteImageProviders {
    <#
    .SYNOPSIS
            Gets available remote image providers for an item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/RemoteImages/Providers
        Operation ID: GetRemoteImageProviders
        Tags: RemoteImage
    .PARAMETER Itemid
        Path parameter: itemId
    
    .EXAMPLE
        Get-JellyfinRemoteImageProviders
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid
    )


    $path = '/Items/{itemId}/RemoteImages/Providers'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region ScheduledTasks Functions (5 functions)

function Get-JellyfinTasks {
    <#
    .SYNOPSIS
            Get tasks.

    .DESCRIPTION
        API Endpoint: GET /ScheduledTasks
        Operation ID: GetTasks
        Tags: ScheduledTasks
    .PARAMETER Ishidden
        Optional filter tasks that are hidden, or not.

    .PARAMETER Isenabled
        Optional filter tasks that are enabled, or not.
    
    .EXAMPLE
        Get-JellyfinTasks
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [nullable[bool]]$Ishidden,

        [Parameter()]
        [nullable[bool]]$Isenabled
    )


    $path = '/ScheduledTasks'
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Ishidden')) { $queryParameters['isHidden'] = $Ishidden }
    if ($PSBoundParameters.ContainsKey('Isenabled')) { $queryParameters['isEnabled'] = $Isenabled }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinTask {
    <#
    .SYNOPSIS
            Get task by id.

    .DESCRIPTION
        API Endpoint: GET /ScheduledTasks/{taskId}
        Operation ID: GetTask
        Tags: ScheduledTasks
    .PARAMETER Taskid
        Path parameter: taskId
    
    .EXAMPLE
        Get-JellyfinTask
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Taskid
    )


    $path = '/ScheduledTasks/{taskId}'
    $path = $path -replace '\{taskId\}', $Taskid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinTask {
    <#
    .SYNOPSIS
            Update specified task triggers.

    .DESCRIPTION
        API Endpoint: POST /ScheduledTasks/{taskId}/Triggers
        Operation ID: UpdateTask
        Tags: ScheduledTasks
    .PARAMETER Taskid
        Path parameter: taskId

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinTask
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Taskid,

        [Parameter()]
        [object]$Body
    )


    $path = '/ScheduledTasks/{taskId}/Triggers'
    $path = $path -replace '\{taskId\}', $Taskid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Start-JellyfinTask {
    <#
    .SYNOPSIS
            Start specified task.

    .DESCRIPTION
        API Endpoint: POST /ScheduledTasks/Running/{taskId}
        Operation ID: StartTask
        Tags: ScheduledTasks
    .PARAMETER Taskid
        Path parameter: taskId
    
    .EXAMPLE
        Start-JellyfinTask
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Taskid
    )


    $path = '/ScheduledTasks/Running/{taskId}'
    $path = $path -replace '\{taskId\}', $Taskid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Stop-JellyfinTask {
    <#
    .SYNOPSIS
            Stop specified task.

    .DESCRIPTION
        API Endpoint: DELETE /ScheduledTasks/Running/{taskId}
        Operation ID: StopTask
        Tags: ScheduledTasks
    .PARAMETER Taskid
        Path parameter: taskId
    
    .EXAMPLE
        Stop-JellyfinTask
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Taskid
    )


    $path = '/ScheduledTasks/Running/{taskId}'
    $path = $path -replace '\{taskId\}', $Taskid

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Search Functions (1 functions)

function Get-JellyfinSearchHints {
    <#
    .SYNOPSIS
            Gets the search hint result.

    .DESCRIPTION
        API Endpoint: GET /Search/Hints
        Operation ID: GetSearchHints
        Tags: Search
    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Userid
        Optional. Supply a user id to search within a user's library or omit to search all.

    .PARAMETER Searchterm
        The search term to filter on.

    .PARAMETER Includeitemtypes
        If specified, only results with the specified item types are returned. This allows multiple, comma delimited.

    .PARAMETER Excludeitemtypes
        If specified, results with these item types are filtered out. This allows multiple, comma delimited.

    .PARAMETER Mediatypes
        If specified, only results with the specified media types are returned. This allows multiple, comma delimited.

    .PARAMETER Parentid
        If specified, only children of the parent are returned.

    .PARAMETER Ismovie
        Optional filter for movies.

    .PARAMETER Isseries
        Optional filter for series.

    .PARAMETER Isnews
        Optional filter for news.

    .PARAMETER Iskids
        Optional filter for kids.

    .PARAMETER Issports
        Optional filter for sports.

    .PARAMETER Includepeople
        Optional filter whether to include people.

    .PARAMETER Includemedia
        Optional filter whether to include media.

    .PARAMETER Includegenres
        Optional filter whether to include genres.

    .PARAMETER Includestudios
        Optional filter whether to include studios.

    .PARAMETER Includeartists
        Optional filter whether to include artists.
    
    .EXAMPLE
        Get-JellyfinSearchHints
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [string]$Userid,

        [Parameter(Mandatory)]
        [string]$Searchterm,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Includeitemtypes,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Excludeitemtypes,

        [Parameter()]
        [ValidateSet('Unknown','Video','Audio','Photo','Book')]
        [string[]]$Mediatypes,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [nullable[bool]]$Ismovie,

        [Parameter()]
        [nullable[bool]]$Isseries,

        [Parameter()]
        [nullable[bool]]$Isnews,

        [Parameter()]
        [nullable[bool]]$Iskids,

        [Parameter()]
        [nullable[bool]]$Issports,

        [Parameter()]
        [nullable[bool]]$Includepeople,

        [Parameter()]
        [nullable[bool]]$Includemedia,

        [Parameter()]
        [nullable[bool]]$Includegenres,

        [Parameter()]
        [nullable[bool]]$Includestudios,

        [Parameter()]
        [nullable[bool]]$Includeartists
    )


    $path = '/Search/Hints'
    $queryParameters = @{}
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Searchterm) { $queryParameters['searchTerm'] = $Searchterm }
    if ($Includeitemtypes) { $queryParameters['includeItemTypes'] = convertto-delimited $Includeitemtypes ',' }
    if ($Excludeitemtypes) { $queryParameters['excludeItemTypes'] = convertto-delimited $Excludeitemtypes ',' }
    if ($Mediatypes) { $queryParameters['mediaTypes'] = convertto-delimited $Mediatypes ',' }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($PSBoundParameters.ContainsKey('Ismovie')) { $queryParameters['isMovie'] = $Ismovie }
    if ($PSBoundParameters.ContainsKey('Isseries')) { $queryParameters['isSeries'] = $Isseries }
    if ($PSBoundParameters.ContainsKey('Isnews')) { $queryParameters['isNews'] = $Isnews }
    if ($PSBoundParameters.ContainsKey('Iskids')) { $queryParameters['isKids'] = $Iskids }
    if ($PSBoundParameters.ContainsKey('Issports')) { $queryParameters['isSports'] = $Issports }
    if ($PSBoundParameters.ContainsKey('Includepeople')) { $queryParameters['includePeople'] = $Includepeople }
    if ($PSBoundParameters.ContainsKey('Includemedia')) { $queryParameters['includeMedia'] = $Includemedia }
    if ($PSBoundParameters.ContainsKey('Includegenres')) { $queryParameters['includeGenres'] = $Includegenres }
    if ($PSBoundParameters.ContainsKey('Includestudios')) { $queryParameters['includeStudios'] = $Includestudios }
    if ($PSBoundParameters.ContainsKey('Includeartists')) { $queryParameters['includeArtists'] = $Includeartists }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Session Functions (16 functions)

function Get-JellyfinPasswordResetProviders {
    <#
    .SYNOPSIS
            Get all password reset providers.

    .DESCRIPTION
        API Endpoint: GET /Auth/PasswordResetProviders
        Operation ID: GetPasswordResetProviders
        Tags: Session
    .EXAMPLE
        Get-JellyfinPasswordResetProviders
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Auth/PasswordResetProviders' -Method GET
}
function Get-JellyfinAuthProviders {
    <#
    .SYNOPSIS
            Get all auth providers.

    .DESCRIPTION
        API Endpoint: GET /Auth/Providers
        Operation ID: GetAuthProviders
        Tags: Session
    .EXAMPLE
        Get-JellyfinAuthProviders
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Auth/Providers' -Method GET
}
function Get-JellyfinSessions {
    <#
    .SYNOPSIS
            Gets a list of sessions.

    .DESCRIPTION
        API Endpoint: GET /Sessions
        Operation ID: GetSessions
        Tags: Session
    .PARAMETER Controllablebyuserid
        Filter by sessions that a given user is allowed to remote control.

    .PARAMETER Deviceid
        Filter by device Id.

    .PARAMETER Activewithinseconds
        Optional. Filter by sessions that were active in the last n seconds.
    
    .EXAMPLE
        Get-JellyfinSessions
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Controllablebyuserid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [int]$Activewithinseconds
    )


    $path = '/Sessions'
    $queryParameters = @{}
    if ($Controllablebyuserid) { $queryParameters['controllableByUserId'] = $Controllablebyuserid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Activewithinseconds) { $queryParameters['activeWithinSeconds'] = $Activewithinseconds }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Send-JellyfinFullGeneralCommand {
    <#
    .SYNOPSIS
            Issues a full general command to a client.

    .DESCRIPTION
        API Endpoint: POST /Sessions/{sessionId}/Command
        Operation ID: SendFullGeneralCommand
        Tags: Session
    .PARAMETER Sessionid
        Path parameter: sessionId

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Send-JellyfinFullGeneralCommand
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Sessionid,

        [Parameter()]
        [object]$Body
    )


    $path = '/Sessions/{sessionId}/Command'
    $path = $path -replace '\{sessionId\}', $Sessionid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Send-JellyfinGeneralCommand {
    <#
    .SYNOPSIS
            Issues a general command to a client.

    .DESCRIPTION
        API Endpoint: POST /Sessions/{sessionId}/Command/{command}
        Operation ID: SendGeneralCommand
        Tags: Session
    .PARAMETER Sessionid
        Path parameter: sessionId

    .PARAMETER Command
        Path parameter: command
    
    .EXAMPLE
        Send-JellyfinGeneralCommand
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Sessionid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Command
    )


    $path = '/Sessions/{sessionId}/Command/{command}'
    $path = $path -replace '\{sessionId\}', $Sessionid
    $path = $path -replace '\{command\}', $Command

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Send-JellyfinMessageCommand {
    <#
    .SYNOPSIS
            Issues a command to a client to display a message to the user.

    .DESCRIPTION
        API Endpoint: POST /Sessions/{sessionId}/Message
        Operation ID: SendMessageCommand
        Tags: Session
    .PARAMETER Sessionid
        Path parameter: sessionId

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Send-JellyfinMessageCommand
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Sessionid,

        [Parameter()]
        [object]$Body
    )


    $path = '/Sessions/{sessionId}/Message'
    $path = $path -replace '\{sessionId\}', $Sessionid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinPlay {
    <#
    .SYNOPSIS
            Instructs a session to play an item.

    .DESCRIPTION
        API Endpoint: POST /Sessions/{sessionId}/Playing
        Operation ID: Play
        Tags: Session
    .PARAMETER Sessionid
        Path parameter: sessionId

    .PARAMETER Playcommand
        The type of play command to issue (PlayNow, PlayNext, PlayLast). Clients who have not yet implemented play next and play last may play now.

    .PARAMETER Itemids
        The ids of the items to play, comma delimited.

    .PARAMETER Startpositionticks
        The starting position of the first item.

    .PARAMETER Mediasourceid
        Optional. The media source id.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to play.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to play.

    .PARAMETER Startindex
        Optional. The start index.
    
    .EXAMPLE
        Invoke-JellyfinPlay
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Sessionid,

        [Parameter(Mandatory)]
        [string]$Playcommand,

        [Parameter(Mandatory)]
        [string[]]$Itemids,

        [Parameter()]
        [int]$Startpositionticks,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [int]$Startindex
    )


    $path = '/Sessions/{sessionId}/Playing'
    $path = $path -replace '\{sessionId\}', $Sessionid
    $queryParameters = @{}
    if ($Playcommand) { $queryParameters['playCommand'] = $Playcommand }
    if ($Itemids) { $queryParameters['itemIds'] = convertto-delimited $Itemids ',' }
    if ($Startpositionticks) { $queryParameters['startPositionTicks'] = $Startpositionticks }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Send-JellyfinPlaystateCommand {
    <#
    .SYNOPSIS
            Issues a playstate command to a client.

    .DESCRIPTION
        API Endpoint: POST /Sessions/{sessionId}/Playing/{command}
        Operation ID: SendPlaystateCommand
        Tags: Session
    .PARAMETER Sessionid
        Path parameter: sessionId

    .PARAMETER Command
        Path parameter: command

    .PARAMETER Seekpositionticks
        The optional position ticks.

    .PARAMETER Controllinguserid
        The optional controlling user id.
    
    .EXAMPLE
        Send-JellyfinPlaystateCommand
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Sessionid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Command,

        [Parameter()]
        [int]$Seekpositionticks,

        [Parameter()]
        [string]$Controllinguserid
    )


    $path = '/Sessions/{sessionId}/Playing/{command}'
    $path = $path -replace '\{sessionId\}', $Sessionid
    $path = $path -replace '\{command\}', $Command
    $queryParameters = @{}
    if ($Seekpositionticks) { $queryParameters['seekPositionTicks'] = $Seekpositionticks }
    if ($Controllinguserid) { $queryParameters['controllingUserId'] = $Controllinguserid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Send-JellyfinSystemCommand {
    <#
    .SYNOPSIS
            Issues a system command to a client.

    .DESCRIPTION
        API Endpoint: POST /Sessions/{sessionId}/System/{command}
        Operation ID: SendSystemCommand
        Tags: Session
    .PARAMETER Sessionid
        Path parameter: sessionId

    .PARAMETER Command
        Path parameter: command
    
    .EXAMPLE
        Send-JellyfinSystemCommand
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Sessionid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Command
    )


    $path = '/Sessions/{sessionId}/System/{command}'
    $path = $path -replace '\{sessionId\}', $Sessionid
    $path = $path -replace '\{command\}', $Command

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    Invoke-JellyfinRequest @invokeParams
}
function New-JellyfinUserToSession {
    <#
    .SYNOPSIS
            Adds an additional user to a session.

    .DESCRIPTION
        API Endpoint: POST /Sessions/{sessionId}/User/{userId}
        Operation ID: AddUserToSession
        Tags: Session
    .PARAMETER Sessionid
        Path parameter: sessionId

    .PARAMETER Userid
        Path parameter: userId
    
    .EXAMPLE
        New-JellyfinUserToSession
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Sessionid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Userid
    )


    $path = '/Sessions/{sessionId}/User/{userId}'
    $path = $path -replace '\{sessionId\}', $Sessionid
    $path = $path -replace '\{userId\}', $Userid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinUserFromSession {
    <#
    .SYNOPSIS
            Removes an additional user from a session.

    .DESCRIPTION
        API Endpoint: DELETE /Sessions/{sessionId}/User/{userId}
        Operation ID: RemoveUserFromSession
        Tags: Session
    .PARAMETER Sessionid
        Path parameter: sessionId

    .PARAMETER Userid
        Path parameter: userId
    
    .EXAMPLE
        Remove-JellyfinUserFromSession
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Sessionid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Userid
    )


    $path = '/Sessions/{sessionId}/User/{userId}'
    $path = $path -replace '\{sessionId\}', $Sessionid
    $path = $path -replace '\{userId\}', $Userid

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinDisplayContent {
    <#
    .SYNOPSIS
            Instructs a session to browse to an item or view.

    .DESCRIPTION
        API Endpoint: POST /Sessions/{sessionId}/Viewing
        Operation ID: DisplayContent
        Tags: Session
    .PARAMETER Sessionid
        Path parameter: sessionId

    .PARAMETER Itemtype
        The type of item to browse to.

    .PARAMETER Itemid
        The Id of the item.

    .PARAMETER Itemname
        The name of the item.
    
    .EXAMPLE
        Invoke-JellyfinDisplayContent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Sessionid,

        [Parameter(Mandatory)]
        [string]$Itemtype,

        [Parameter(Mandatory)]
        [string]$Itemid,

        [Parameter(Mandatory)]
        [string]$Itemname
    )


    $path = '/Sessions/{sessionId}/Viewing'
    $path = $path -replace '\{sessionId\}', $Sessionid
    $queryParameters = @{}
    if ($Itemtype) { $queryParameters['itemType'] = $Itemtype }
    if ($Itemid) { $queryParameters['itemId'] = $Itemid }
    if ($Itemname) { $queryParameters['itemName'] = $Itemname }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinCapabilities {
    <#
    .SYNOPSIS
            Updates capabilities for a device.

    .DESCRIPTION
        API Endpoint: POST /Sessions/Capabilities
        Operation ID: PostCapabilities
        Tags: Session
    .PARAMETER Id
        The session id.

    .PARAMETER Playablemediatypes
        A list of playable media types, comma delimited. Audio, Video, Book, Photo.

    .PARAMETER Supportedcommands
        A list of supported remote control commands, comma delimited.

    .PARAMETER Supportsmediacontrol
        Determines whether media can be played remotely..

    .PARAMETER Supportspersistentidentifier
        Determines whether the device supports a unique identifier.
    
    .EXAMPLE
        Invoke-JellyfinCapabilities
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Id,

        [Parameter()]
        [string[]]$Playablemediatypes,

        [Parameter()]
        [string[]]$Supportedcommands,

        [Parameter()]
        [nullable[bool]]$Supportsmediacontrol,

        [Parameter()]
        [nullable[bool]]$Supportspersistentidentifier
    )


    $path = '/Sessions/Capabilities'
    $queryParameters = @{}
    if ($Id) { $queryParameters['id'] = $Id }
    if ($Playablemediatypes) { $queryParameters['playableMediaTypes'] = convertto-delimited $Playablemediatypes ',' }
    if ($Supportedcommands) { $queryParameters['supportedCommands'] = convertto-delimited $Supportedcommands ',' }
    if ($PSBoundParameters.ContainsKey('Supportsmediacontrol')) { $queryParameters['supportsMediaControl'] = $Supportsmediacontrol }
    if ($PSBoundParameters.ContainsKey('Supportspersistentidentifier')) { $queryParameters['supportsPersistentIdentifier'] = $Supportspersistentidentifier }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinFullCapabilities {
    <#
    .SYNOPSIS
            Updates capabilities for a device.

    .DESCRIPTION
        API Endpoint: POST /Sessions/Capabilities/Full
        Operation ID: PostFullCapabilities
        Tags: Session
    .PARAMETER Id
        The session id.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinFullCapabilities
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Id,

        [Parameter()]
        [object]$Body
    )


    $path = '/Sessions/Capabilities/Full'
    $queryParameters = @{}
    if ($Id) { $queryParameters['id'] = $Id }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinReportSessionEnded {
    <#
    .SYNOPSIS
            Reports that a session has ended.

    .DESCRIPTION
        API Endpoint: POST /Sessions/Logout
        Operation ID: ReportSessionEnded
        Tags: Session
    .EXAMPLE
        Invoke-JellyfinReportSessionEnded
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Sessions/Logout' -Method POST
}
function Invoke-JellyfinReportViewing {
    <#
    .SYNOPSIS
            Reports that a session is viewing an item.

    .DESCRIPTION
        API Endpoint: POST /Sessions/Viewing
        Operation ID: ReportViewing
        Tags: Session
    .PARAMETER Sessionid
        The session id.

    .PARAMETER Itemid
        The item id.
    
    .EXAMPLE
        Invoke-JellyfinReportViewing
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Sessionid,

        [Parameter(Mandatory)]
        [string]$Itemid
    )


    $path = '/Sessions/Viewing'
    $queryParameters = @{}
    if ($Sessionid) { $queryParameters['sessionId'] = $Sessionid }
    if ($Itemid) { $queryParameters['itemId'] = $Itemid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Startup Functions (7 functions)

function Invoke-JellyfinCompleteWizard {
    <#
    .SYNOPSIS
            Completes the startup wizard.

    .DESCRIPTION
        API Endpoint: POST /Startup/Complete
        Operation ID: CompleteWizard
        Tags: Startup
    .EXAMPLE
        Invoke-JellyfinCompleteWizard
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Startup/Complete' -Method POST
}
function Get-JellyfinStartupConfiguration {
    <#
    .SYNOPSIS
            Gets the initial startup wizard configuration.

    .DESCRIPTION
        API Endpoint: GET /Startup/Configuration
        Operation ID: GetStartupConfiguration
        Tags: Startup
    .EXAMPLE
        Get-JellyfinStartupConfiguration
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Startup/Configuration' -Method GET
}
function Set-JellyfinInitialConfiguration {
    <#
    .SYNOPSIS
            Sets the initial startup wizard configuration.

    .DESCRIPTION
        API Endpoint: POST /Startup/Configuration
        Operation ID: UpdateInitialConfiguration
        Tags: Startup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinInitialConfiguration
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Startup/Configuration'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinFirstUser_2 {
    <#
    .SYNOPSIS
            Gets the first user.

    .DESCRIPTION
        API Endpoint: GET /Startup/FirstUser
        Operation ID: GetFirstUser_2
        Tags: Startup
    .EXAMPLE
        Get-JellyfinFirstUser_2
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Startup/FirstUser' -Method GET
}
function Set-JellyfinRemoteAccess {
    <#
    .SYNOPSIS
            Sets remote access and UPnP.

    .DESCRIPTION
        API Endpoint: POST /Startup/RemoteAccess
        Operation ID: SetRemoteAccess
        Tags: Startup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinRemoteAccess
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Startup/RemoteAccess'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinFirstUser {
    <#
    .SYNOPSIS
            Gets the first user.

    .DESCRIPTION
        API Endpoint: GET /Startup/User
        Operation ID: GetFirstUser
        Tags: Startup
    .EXAMPLE
        Get-JellyfinFirstUser
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Startup/User' -Method GET
}
function Set-JellyfinStartupUser {
    <#
    .SYNOPSIS
            Sets the user name and password.

    .DESCRIPTION
        API Endpoint: POST /Startup/User
        Operation ID: UpdateStartupUser
        Tags: Startup
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinStartupUser
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Startup/User'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Studios Functions (2 functions)

function Get-JellyfinStudios {
    <#
    .SYNOPSIS
            Gets all studios from a given item, folder, or the entire library.

    .DESCRIPTION
        API Endpoint: GET /Studios
        Operation ID: GetStudios
        Tags: Studios
    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Searchterm
        Optional. Search term.

    .PARAMETER Parentid
        Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Excludeitemtypes
        Optional. If specified, results will be filtered out based on item type. This allows multiple, comma delimited.

    .PARAMETER Includeitemtypes
        Optional. If specified, results will be filtered based on item type. This allows multiple, comma delimited.

    .PARAMETER Isfavorite
        Optional filter by items that are marked as favorite, or not.

    .PARAMETER Enableuserdata
        Optional, include user data.

    .PARAMETER Imagetypelimit
        Optional, the max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Userid
        User id.

    .PARAMETER Namestartswithorgreater
        Optional filter by items whose name is sorted equally or greater than a given input string.

    .PARAMETER Namestartswith
        Optional filter by items whose name is sorted equally than a given input string.

    .PARAMETER Namelessthan
        Optional filter by items whose name is equally or lesser than a given input string.

    .PARAMETER Enableimages
        Optional, include image information in output.

    .PARAMETER Enabletotalrecordcount
        Total record count.
    
    .EXAMPLE
        Get-JellyfinStudios
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [string]$Searchterm,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Excludeitemtypes,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Includeitemtypes,

        [Parameter()]
        [nullable[bool]]$Isfavorite,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Namestartswithorgreater,

        [Parameter()]
        [string]$Namestartswith,

        [Parameter()]
        [string]$Namelessthan,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount
    )


    $path = '/Studios'
    $queryParameters = @{}
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Searchterm) { $queryParameters['searchTerm'] = $Searchterm }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Excludeitemtypes) { $queryParameters['excludeItemTypes'] = convertto-delimited $Excludeitemtypes ',' }
    if ($Includeitemtypes) { $queryParameters['includeItemTypes'] = convertto-delimited $Includeitemtypes ',' }
    if ($PSBoundParameters.ContainsKey('Isfavorite')) { $queryParameters['isFavorite'] = $Isfavorite }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Namestartswithorgreater) { $queryParameters['nameStartsWithOrGreater'] = $Namestartswithorgreater }
    if ($Namestartswith) { $queryParameters['nameStartsWith'] = $Namestartswith }
    if ($Namelessthan) { $queryParameters['nameLessThan'] = $Namelessthan }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinStudio {
    <#
    .SYNOPSIS
            Gets a studio by name.

    .DESCRIPTION
        API Endpoint: GET /Studios/{name}
        Operation ID: GetStudio
        Tags: Studios
    .PARAMETER Name
        Path parameter: name

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.
    
    .EXAMPLE
        Get-JellyfinStudio
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Studios/{name}'
    $path = $path -replace '\{name\}', $Name
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Subtitle Functions (10 functions)

function Get-JellyfinFallbackFontList {
    <#
    .SYNOPSIS
            Gets a list of available fallback font files.

    .DESCRIPTION
        API Endpoint: GET /FallbackFont/Fonts
        Operation ID: GetFallbackFontList
        Tags: Subtitle
    .EXAMPLE
        Get-JellyfinFallbackFontList
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/FallbackFont/Fonts' -Method GET
}
function Get-JellyfinFallbackFont {
    <#
    .SYNOPSIS
            Gets a fallback font file.

    .DESCRIPTION
        API Endpoint: GET /FallbackFont/Fonts/{name}
        Operation ID: GetFallbackFont
        Tags: Subtitle
    .PARAMETER Name
        Path parameter: name
    
    .EXAMPLE
        Get-JellyfinFallbackFont
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name
    )


    $path = '/FallbackFont/Fonts/{name}'
    $path = $path -replace '\{name\}', $Name

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSearchRemoteSubtitles {
    <#
    .SYNOPSIS
            Search remote subtitles.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/RemoteSearch/Subtitles/{language}
        Operation ID: SearchRemoteSubtitles
        Tags: Subtitle
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Language
        Path parameter: language

    .PARAMETER Isperfectmatch
        Optional. Only show subtitles which are a perfect match.
    
    .EXAMPLE
        Get-JellyfinSearchRemoteSubtitles
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Language,

        [Parameter()]
        [nullable[bool]]$Isperfectmatch
    )


    $path = '/Items/{itemId}/RemoteSearch/Subtitles/{language}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{language\}', $Language
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Isperfectmatch')) { $queryParameters['isPerfectMatch'] = $Isperfectmatch }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinDownloadRemoteSubtitles {
    <#
    .SYNOPSIS
            Downloads a remote subtitle.

    .DESCRIPTION
        API Endpoint: POST /Items/{itemId}/RemoteSearch/Subtitles/{subtitleId}
        Operation ID: DownloadRemoteSubtitles
        Tags: Subtitle
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Subtitleid
        Path parameter: subtitleId
    
    .EXAMPLE
        Invoke-JellyfinDownloadRemoteSubtitles
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Subtitleid
    )


    $path = '/Items/{itemId}/RemoteSearch/Subtitles/{subtitleId}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{subtitleId\}', $Subtitleid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinRemoteSubtitles {
    <#
    .SYNOPSIS
            Gets the remote subtitles.

    .DESCRIPTION
        API Endpoint: GET /Providers/Subtitles/Subtitles/{subtitleId}
        Operation ID: GetRemoteSubtitles
        Tags: Subtitle
    .PARAMETER Subtitleid
        Path parameter: subtitleId
    
    .EXAMPLE
        Get-JellyfinRemoteSubtitles
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Subtitleid
    )


    $path = '/Providers/Subtitles/Subtitles/{subtitleId}'
    $path = $path -replace '\{subtitleId\}', $Subtitleid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSubtitlePlaylist {
    <#
    .SYNOPSIS
            Gets an HLS subtitle playlist.

    .DESCRIPTION
        API Endpoint: GET /Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/subtitles.m3u8
        Operation ID: GetSubtitlePlaylist
        Tags: Subtitle
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Index
        Path parameter: index

    .PARAMETER Mediasourceid
        Path parameter: mediaSourceId

    .PARAMETER Segmentlength
        The subtitle segment length.
    
    .EXAMPLE
        Get-JellyfinSubtitlePlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Index,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Mediasourceid,

        [Parameter(Mandatory)]
        [int]$Segmentlength
    )


    $path = '/Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/subtitles.m3u8'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{index\}', $Index
    $path = $path -replace '\{mediaSourceId\}', $Mediasourceid
    $queryParameters = @{}
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinUploadSubtitle {
    <#
    .SYNOPSIS
            Upload an external subtitle file.

    .DESCRIPTION
        API Endpoint: POST /Videos/{itemId}/Subtitles
        Operation ID: UploadSubtitle
        Tags: Subtitle
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinUploadSubtitle
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [object]$Body
    )


    $path = '/Videos/{itemId}/Subtitles'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinSubtitle {
    <#
    .SYNOPSIS
            Deletes an external subtitle file.

    .DESCRIPTION
        API Endpoint: DELETE /Videos/{itemId}/Subtitles/{index}
        Operation ID: DeleteSubtitle
        Tags: Subtitle
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Index
        Path parameter: index
    
    .EXAMPLE
        Remove-JellyfinSubtitle
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Index
    )


    $path = '/Videos/{itemId}/Subtitles/{index}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{index\}', $Index

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSubtitleWithTicks {
    <#
    .SYNOPSIS
            Gets subtitles in a specified format.

    .DESCRIPTION
        API Endpoint: GET /Videos/{routeItemId}/{routeMediaSourceId}/Subtitles/{routeIndex}/{routeStartPositionTicks}/Stream.{routeFormat}
        Operation ID: GetSubtitleWithTicks
        Tags: Subtitle
    .PARAMETER Routeitemid
        Path parameter: routeItemId

    .PARAMETER Routemediasourceid
        Path parameter: routeMediaSourceId

    .PARAMETER Routeindex
        Path parameter: routeIndex

    .PARAMETER Routestartpositionticks
        Path parameter: routeStartPositionTicks

    .PARAMETER Routeformat
        Path parameter: routeFormat

    .PARAMETER Itemid
        The item id.

    .PARAMETER Mediasourceid
        The media source id.

    .PARAMETER Index
        The subtitle stream index.

    .PARAMETER Startpositionticks
        The start position of the subtitle in ticks.

    .PARAMETER Format
        The format of the returned subtitle.

    .PARAMETER Endpositionticks
        Optional. The end position of the subtitle in ticks.

    .PARAMETER Copytimestamps
        Optional. Whether to copy the timestamps.

    .PARAMETER Addvtttimemap
        Optional. Whether to add a VTT time map.
    
    .EXAMPLE
        Get-JellyfinSubtitleWithTicks
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Routeitemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Routemediasourceid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Routeindex,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Routestartpositionticks,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Routeformat,

        [Parameter()]
        [string]$Itemid,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [int]$Index,

        [Parameter()]
        [int]$Startpositionticks,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Endpositionticks,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [nullable[bool]]$Addvtttimemap
    )


    $path = '/Videos/{routeItemId}/{routeMediaSourceId}/Subtitles/{routeIndex}/{routeStartPositionTicks}/Stream.{routeFormat}'
    $path = $path -replace '\{routeItemId\}', $Routeitemid
    $path = $path -replace '\{routeMediaSourceId\}', $Routemediasourceid
    $path = $path -replace '\{routeIndex\}', $Routeindex
    $path = $path -replace '\{routeStartPositionTicks\}', $Routestartpositionticks
    $path = $path -replace '\{routeFormat\}', $Routeformat
    $queryParameters = @{}
    if ($Itemid) { $queryParameters['itemId'] = $Itemid }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Index) { $queryParameters['index'] = $Index }
    if ($Startpositionticks) { $queryParameters['startPositionTicks'] = $Startpositionticks }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Endpositionticks) { $queryParameters['endPositionTicks'] = $Endpositionticks }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($PSBoundParameters.ContainsKey('Addvtttimemap')) { $queryParameters['addVttTimeMap'] = $Addvtttimemap }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSubtitle {
    <#
    .SYNOPSIS
            Gets subtitles in a specified format.

    .DESCRIPTION
        API Endpoint: GET /Videos/{routeItemId}/{routeMediaSourceId}/Subtitles/{routeIndex}/Stream.{routeFormat}
        Operation ID: GetSubtitle
        Tags: Subtitle
    .PARAMETER Routeitemid
        Path parameter: routeItemId

    .PARAMETER Routemediasourceid
        Path parameter: routeMediaSourceId

    .PARAMETER Routeindex
        Path parameter: routeIndex

    .PARAMETER Routeformat
        Path parameter: routeFormat

    .PARAMETER Itemid
        The item id.

    .PARAMETER Mediasourceid
        The media source id.

    .PARAMETER Index
        The subtitle stream index.

    .PARAMETER Format
        The format of the returned subtitle.

    .PARAMETER Endpositionticks
        Optional. The end position of the subtitle in ticks.

    .PARAMETER Copytimestamps
        Optional. Whether to copy the timestamps.

    .PARAMETER Addvtttimemap
        Optional. Whether to add a VTT time map.

    .PARAMETER Startpositionticks
        The start position of the subtitle in ticks.
    
    .EXAMPLE
        Get-JellyfinSubtitle
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Routeitemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Routemediasourceid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Routeindex,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Routeformat,

        [Parameter()]
        [string]$Itemid,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [int]$Index,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [int]$Endpositionticks,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [nullable[bool]]$Addvtttimemap,

        [Parameter()]
        [int]$Startpositionticks
    )


    $path = '/Videos/{routeItemId}/{routeMediaSourceId}/Subtitles/{routeIndex}/Stream.{routeFormat}'
    $path = $path -replace '\{routeItemId\}', $Routeitemid
    $path = $path -replace '\{routeMediaSourceId\}', $Routemediasourceid
    $path = $path -replace '\{routeIndex\}', $Routeindex
    $path = $path -replace '\{routeFormat\}', $Routeformat
    $queryParameters = @{}
    if ($Itemid) { $queryParameters['itemId'] = $Itemid }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Index) { $queryParameters['index'] = $Index }
    if ($Format) { $queryParameters['format'] = $Format }
    if ($Endpositionticks) { $queryParameters['endPositionTicks'] = $Endpositionticks }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($PSBoundParameters.ContainsKey('Addvtttimemap')) { $queryParameters['addVttTimeMap'] = $Addvtttimemap }
    if ($Startpositionticks) { $queryParameters['startPositionTicks'] = $Startpositionticks }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Suggestions Functions (1 functions)

function Get-JellyfinSuggestions {
    <#
    .SYNOPSIS
            Gets suggestions.

    .DESCRIPTION
        API Endpoint: GET /Items/Suggestions
        Operation ID: GetSuggestions
        Tags: Suggestions
    .PARAMETER Userid
        The user id.

    .PARAMETER Mediatype
        The media types.

    .PARAMETER Type
        The type.

    .PARAMETER Startindex
        Optional. The start index.

    .PARAMETER Limit
        Optional. The limit.

    .PARAMETER Enabletotalrecordcount
        Whether to enable the total record count.
    
    .EXAMPLE
        Get-JellyfinSuggestions
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string[]]$Mediatype,

        [Parameter()]
        [string[]]$Type,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount
    )


    $path = '/Items/Suggestions'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Mediatype) { $queryParameters['mediaType'] = convertto-delimited $Mediatype ',' }
    if ($Type) { $queryParameters['type'] = convertto-delimited $Type ',' }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region SyncPlay Functions (22 functions)

function Get-JellyfinSyncPlayGetGroup {
    <#
    .SYNOPSIS
            Gets a SyncPlay group by id.

    .DESCRIPTION
        API Endpoint: GET /SyncPlay/{id}
        Operation ID: SyncPlayGetGroup
        Tags: SyncPlay
    .PARAMETER Id
        Path parameter: id
    
    .EXAMPLE
        Get-JellyfinSyncPlayGetGroup
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Id
    )


    $path = '/SyncPlay/{id}'
    $path = $path -replace '\{id\}', $Id

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlayBuffering {
    <#
    .SYNOPSIS
            Notify SyncPlay group that member is buffering.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/Buffering
        Operation ID: SyncPlayBuffering
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlayBuffering
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/Buffering'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlayJoinGroup {
    <#
    .SYNOPSIS
            Join an existing SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/Join
        Operation ID: SyncPlayJoinGroup
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlayJoinGroup
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/Join'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlayLeaveGroup {
    <#
    .SYNOPSIS
            Leave the joined SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/Leave
        Operation ID: SyncPlayLeaveGroup
        Tags: SyncPlay
    .EXAMPLE
        Invoke-JellyfinSyncPlayLeaveGroup
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/SyncPlay/Leave' -Method POST
}
function Get-JellyfinSyncPlayGetGroups {
    <#
    .SYNOPSIS
            Gets all SyncPlay groups.

    .DESCRIPTION
        API Endpoint: GET /SyncPlay/List
        Operation ID: SyncPlayGetGroups
        Tags: SyncPlay
    .EXAMPLE
        Get-JellyfinSyncPlayGetGroups
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/SyncPlay/List' -Method GET
}
function Invoke-JellyfinSyncPlayMovePlaylistItem {
    <#
    .SYNOPSIS
            Request to move an item in the playlist in SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/MovePlaylistItem
        Operation ID: SyncPlayMovePlaylistItem
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlayMovePlaylistItem
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/MovePlaylistItem'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlayCreateGroup {
    <#
    .SYNOPSIS
            Create a new SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/New
        Operation ID: SyncPlayCreateGroup
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlayCreateGroup
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/New'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlayNextItem {
    <#
    .SYNOPSIS
            Request next item in SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/NextItem
        Operation ID: SyncPlayNextItem
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlayNextItem
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/NextItem'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlayPause {
    <#
    .SYNOPSIS
            Request pause in SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/Pause
        Operation ID: SyncPlayPause
        Tags: SyncPlay
    .EXAMPLE
        Invoke-JellyfinSyncPlayPause
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/SyncPlay/Pause' -Method POST
}
function Invoke-JellyfinSyncPlayPing {
    <#
    .SYNOPSIS
            Update session ping.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/Ping
        Operation ID: SyncPlayPing
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlayPing
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/Ping'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlayPreviousItem {
    <#
    .SYNOPSIS
            Request previous item in SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/PreviousItem
        Operation ID: SyncPlayPreviousItem
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlayPreviousItem
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/PreviousItem'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlayQueue {
    <#
    .SYNOPSIS
            Request to queue items to the playlist of a SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/Queue
        Operation ID: SyncPlayQueue
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlayQueue
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/Queue'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlayReady {
    <#
    .SYNOPSIS
            Notify SyncPlay group that member is ready for playback.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/Ready
        Operation ID: SyncPlayReady
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlayReady
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/Ready'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlayRemoveFromPlaylist {
    <#
    .SYNOPSIS
            Request to remove items from the playlist in SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/RemoveFromPlaylist
        Operation ID: SyncPlayRemoveFromPlaylist
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlayRemoveFromPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/RemoveFromPlaylist'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlaySeek {
    <#
    .SYNOPSIS
            Request seek in SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/Seek
        Operation ID: SyncPlaySeek
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlaySeek
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/Seek'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlaySetIgnoreWait {
    <#
    .SYNOPSIS
            Request SyncPlay group to ignore member during group-wait.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/SetIgnoreWait
        Operation ID: SyncPlaySetIgnoreWait
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlaySetIgnoreWait
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/SetIgnoreWait'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlaySetNewQueue {
    <#
    .SYNOPSIS
            Request to set new playlist in SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/SetNewQueue
        Operation ID: SyncPlaySetNewQueue
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlaySetNewQueue
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/SetNewQueue'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlaySetPlaylistItem {
    <#
    .SYNOPSIS
            Request to change playlist item in SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/SetPlaylistItem
        Operation ID: SyncPlaySetPlaylistItem
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlaySetPlaylistItem
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/SetPlaylistItem'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlaySetRepeatMode {
    <#
    .SYNOPSIS
            Request to set repeat mode in SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/SetRepeatMode
        Operation ID: SyncPlaySetRepeatMode
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlaySetRepeatMode
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/SetRepeatMode'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlaySetShuffleMode {
    <#
    .SYNOPSIS
            Request to set shuffle mode in SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/SetShuffleMode
        Operation ID: SyncPlaySetShuffleMode
        Tags: SyncPlay
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinSyncPlaySetShuffleMode
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/SyncPlay/SetShuffleMode'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinSyncPlayStop {
    <#
    .SYNOPSIS
            Request stop in SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/Stop
        Operation ID: SyncPlayStop
        Tags: SyncPlay
    .EXAMPLE
        Invoke-JellyfinSyncPlayStop
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/SyncPlay/Stop' -Method POST
}
function Invoke-JellyfinSyncPlayUnpause {
    <#
    .SYNOPSIS
            Request unpause in SyncPlay group.

    .DESCRIPTION
        API Endpoint: POST /SyncPlay/Unpause
        Operation ID: SyncPlayUnpause
        Tags: SyncPlay
    .EXAMPLE
        Invoke-JellyfinSyncPlayUnpause
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/SyncPlay/Unpause' -Method POST
}
#endregion

#region System Functions (10 functions)

function Get-JellyfinEndpointInfo {
    <#
    .SYNOPSIS
            Gets information about the request endpoint.

    .DESCRIPTION
        API Endpoint: GET /System/Endpoint
        Operation ID: GetEndpointInfo
        Tags: System
    .EXAMPLE
        Get-JellyfinEndpointInfo
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/System/Endpoint' -Method GET
}
function Get-JellyfinSystemInfo {
    <#
    .SYNOPSIS
            Gets information about the server.

    .DESCRIPTION
        API Endpoint: GET /System/Info
        Operation ID: GetSystemInfo
        Tags: System
    .EXAMPLE
        Get-JellyfinSystemInfo
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/System/Info' -Method GET
}
function Get-JellyfinPublicSystemInfo {
    <#
    .SYNOPSIS
            Gets public information about the server.

    .DESCRIPTION
        API Endpoint: GET /System/Info/Public
        Operation ID: GetPublicSystemInfo
        Tags: System
    .EXAMPLE
        Get-JellyfinPublicSystemInfo
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/System/Info/Public' -Method GET
}
function Get-JellyfinSystemStorage {
    <#
    .SYNOPSIS
            Gets information about the server.

    .DESCRIPTION
        API Endpoint: GET /System/Info/Storage
        Operation ID: GetSystemStorage
        Tags: System
    .EXAMPLE
        Get-JellyfinSystemStorage
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/System/Info/Storage' -Method GET
}
function Get-JellyfinServerLogs {
    <#
    .SYNOPSIS
            Gets a list of available server log files.

    .DESCRIPTION
        API Endpoint: GET /System/Logs
        Operation ID: GetServerLogs
        Tags: System
    .EXAMPLE
        Get-JellyfinServerLogs
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/System/Logs' -Method GET
}
function Get-JellyfinLogFile {
    <#
    .SYNOPSIS
            Gets a log file.

    .DESCRIPTION
        API Endpoint: GET /System/Logs/Log
        Operation ID: GetLogFile
        Tags: System
    .PARAMETER Name
        The name of the log file to get.
    
    .EXAMPLE
        Get-JellyfinLogFile
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )


    $path = '/System/Logs/Log'
    $queryParameters = @{}
    if ($Name) { $queryParameters['name'] = $Name }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPingSystem {
    <#
    .SYNOPSIS
            Pings the system.

    .DESCRIPTION
        API Endpoint: GET /System/Ping
        Operation ID: GetPingSystem
        Tags: System
    .EXAMPLE
        Get-JellyfinPingSystem
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/System/Ping' -Method GET
}
function Invoke-JellyfinPingSystem {
    <#
    .SYNOPSIS
            Pings the system.

    .DESCRIPTION
        API Endpoint: POST /System/Ping
        Operation ID: PostPingSystem
        Tags: System
    .EXAMPLE
        Invoke-JellyfinPingSystem
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/System/Ping' -Method POST
}
function Invoke-JellyfinRestartApplication {
    <#
    .SYNOPSIS
            Restarts the application.

    .DESCRIPTION
        API Endpoint: POST /System/Restart
        Operation ID: RestartApplication
        Tags: System
    .EXAMPLE
        Invoke-JellyfinRestartApplication
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/System/Restart' -Method POST
}
function Invoke-JellyfinShutdownApplication {
    <#
    .SYNOPSIS
            Shuts down the application.

    .DESCRIPTION
        API Endpoint: POST /System/Shutdown
        Operation ID: ShutdownApplication
        Tags: System
    .EXAMPLE
        Invoke-JellyfinShutdownApplication
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/System/Shutdown' -Method POST
}
#endregion

#region TimeSync Functions (1 functions)

function Get-JellyfinUtcTime {
    <#
    .SYNOPSIS
            Gets the current UTC time.

    .DESCRIPTION
        API Endpoint: GET /GetUtcTime
        Operation ID: GetUtcTime
        Tags: TimeSync
    .EXAMPLE
        Get-JellyfinUtcTime
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/GetUtcTime' -Method GET
}
#endregion

#region Tmdb Functions (1 functions)

function Get-JellyfinTmdbClientConfiguration {
    <#
    .SYNOPSIS
            Gets the TMDb image configuration options.

    .DESCRIPTION
        API Endpoint: GET /Tmdb/ClientConfiguration
        Operation ID: TmdbClientConfiguration
        Tags: Tmdb
    .EXAMPLE
        Get-JellyfinTmdbClientConfiguration
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Tmdb/ClientConfiguration' -Method GET
}
#endregion

#region Trailers Functions (1 functions)

function Get-JellyfinTrailers {
    <#
    .SYNOPSIS
            Finds movies and trailers similar to a given trailer.

    .DESCRIPTION
        API Endpoint: GET /Trailers
        Operation ID: GetTrailers
        Tags: Trailers
    .PARAMETER Userid
        The user id supplied as query parameter; this is required when not using an API key.

    .PARAMETER Maxofficialrating
        Optional filter by maximum official rating (PG, PG-13, TV-MA, etc).

    .PARAMETER Hasthemesong
        Optional filter by items with theme songs.

    .PARAMETER Hasthemevideo
        Optional filter by items with theme videos.

    .PARAMETER Hassubtitles
        Optional filter by items with subtitles.

    .PARAMETER Hasspecialfeature
        Optional filter by items with special features.

    .PARAMETER Hastrailer
        Optional filter by items with trailers.

    .PARAMETER Adjacentto
        Optional. Return items that are siblings of a supplied item.

    .PARAMETER Parentindexnumber
        Optional filter by parent index number.

    .PARAMETER Hasparentalrating
        Optional filter by items that have or do not have a parental rating.

    .PARAMETER Ishd
        Optional filter by items that are HD or not.

    .PARAMETER Is4k
        Optional filter by items that are 4K or not.

    .PARAMETER Locationtypes
        Optional. If specified, results will be filtered based on LocationType. This allows multiple, comma delimited.

    .PARAMETER Excludelocationtypes
        Optional. If specified, results will be filtered based on the LocationType. This allows multiple, comma delimited.

    .PARAMETER Ismissing
        Optional filter by items that are missing episodes or not.

    .PARAMETER Isunaired
        Optional filter by items that are unaired episodes or not.

    .PARAMETER Mincommunityrating
        Optional filter by minimum community rating.

    .PARAMETER Mincriticrating
        Optional filter by minimum critic rating.

    .PARAMETER Minpremieredate
        Optional. The minimum premiere date. Format = ISO.

    .PARAMETER Mindatelastsaved
        Optional. The minimum last saved date. Format = ISO.

    .PARAMETER Mindatelastsavedforuser
        Optional. The minimum last saved date for the current user. Format = ISO.

    .PARAMETER Maxpremieredate
        Optional. The maximum premiere date. Format = ISO.

    .PARAMETER Hasoverview
        Optional filter by items that have an overview or not.

    .PARAMETER Hasimdbid
        Optional filter by items that have an IMDb id or not.

    .PARAMETER Hastmdbid
        Optional filter by items that have a TMDb id or not.

    .PARAMETER Hastvdbid
        Optional filter by items that have a TVDb id or not.

    .PARAMETER Ismovie
        Optional filter for live tv movies.

    .PARAMETER Isseries
        Optional filter for live tv series.

    .PARAMETER Isnews
        Optional filter for live tv news.

    .PARAMETER Iskids
        Optional filter for live tv kids.

    .PARAMETER Issports
        Optional filter for live tv sports.

    .PARAMETER Excludeitemids
        Optional. If specified, results will be filtered by excluding item ids. This allows multiple, comma delimited.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Recursive
        When searching within folders, this determines whether or not the search will be recursive. true/false.

    .PARAMETER Searchterm
        Optional. Filter based on a search term.

    .PARAMETER Sortorder
        Sort Order - Ascending, Descending.

    .PARAMETER Parentid
        Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output. This allows multiple, comma delimited. Options: Budget, Chapters, DateCreated, Genres, HomePageUrl, IndexOptions, MediaStreams, Overview, ParentId, Path, People, ProviderIds, PrimaryImageAspectRatio, Revenue, SortName, Studios, Taglines.

    .PARAMETER Excludeitemtypes
        Optional. If specified, results will be filtered based on item type. This allows multiple, comma delimited.

    .PARAMETER Filters
        Optional. Specify additional filters to apply. This allows multiple, comma delimited. Options: IsFolder, IsNotFolder, IsUnplayed, IsPlayed, IsFavorite, IsResumable, Likes, Dislikes.

    .PARAMETER Isfavorite
        Optional filter by items that are marked as favorite, or not.

    .PARAMETER Mediatypes
        Optional filter by MediaType. Allows multiple, comma delimited.

    .PARAMETER Imagetypes
        Optional. If specified, results will be filtered based on those containing image types. This allows multiple, comma delimited.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited. Options: Album, AlbumArtist, Artist, Budget, CommunityRating, CriticRating, DateCreated, DatePlayed, PlayCount, PremiereDate, ProductionYear, SortName, Random, Revenue, Runtime.

    .PARAMETER Isplayed
        Optional filter by items that are played, or not.

    .PARAMETER Genres
        Optional. If specified, results will be filtered based on genre. This allows multiple, pipe delimited.

    .PARAMETER Officialratings
        Optional. If specified, results will be filtered based on OfficialRating. This allows multiple, pipe delimited.

    .PARAMETER Tags
        Optional. If specified, results will be filtered based on tag. This allows multiple, pipe delimited.

    .PARAMETER Years
        Optional. If specified, results will be filtered based on production year. This allows multiple, comma delimited.

    .PARAMETER Enableuserdata
        Optional, include user data.

    .PARAMETER Imagetypelimit
        Optional, the max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Person
        Optional. If specified, results will be filtered to include only those containing the specified person.

    .PARAMETER Personids
        Optional. If specified, results will be filtered to include only those containing the specified person id.

    .PARAMETER Persontypes
        Optional. If specified, along with Person, results will be filtered to include only those containing the specified person and PersonType. Allows multiple, comma-delimited.

    .PARAMETER Studios
        Optional. If specified, results will be filtered based on studio. This allows multiple, pipe delimited.

    .PARAMETER Artists
        Optional. If specified, results will be filtered based on artists. This allows multiple, pipe delimited.

    .PARAMETER Excludeartistids
        Optional. If specified, results will be filtered based on artist id. This allows multiple, pipe delimited.

    .PARAMETER Artistids
        Optional. If specified, results will be filtered to include only those containing the specified artist id.

    .PARAMETER Albumartistids
        Optional. If specified, results will be filtered to include only those containing the specified album artist id.

    .PARAMETER Contributingartistids
        Optional. If specified, results will be filtered to include only those containing the specified contributing artist id.

    .PARAMETER Albums
        Optional. If specified, results will be filtered based on album. This allows multiple, pipe delimited.

    .PARAMETER Albumids
        Optional. If specified, results will be filtered based on album id. This allows multiple, pipe delimited.

    .PARAMETER Ids
        Optional. If specific items are needed, specify a list of item id's to retrieve. This allows multiple, comma delimited.

    .PARAMETER Videotypes
        Optional filter by VideoType (videofile, dvd, bluray, iso). Allows multiple, comma delimited.

    .PARAMETER Minofficialrating
        Optional filter by minimum official rating (PG, PG-13, TV-MA, etc).

    .PARAMETER Islocked
        Optional filter by items that are locked.

    .PARAMETER Isplaceholder
        Optional filter by items that are placeholders.

    .PARAMETER Hasofficialrating
        Optional filter by items that have official ratings.

    .PARAMETER Collapseboxsetitems
        Whether or not to hide items behind their boxsets.

    .PARAMETER Minwidth
        Optional. Filter by the minimum width of the item.

    .PARAMETER Minheight
        Optional. Filter by the minimum height of the item.

    .PARAMETER Maxwidth
        Optional. Filter by the maximum width of the item.

    .PARAMETER Maxheight
        Optional. Filter by the maximum height of the item.

    .PARAMETER Is3d
        Optional filter by items that are 3D, or not.

    .PARAMETER Seriesstatus
        Optional filter by Series Status. Allows multiple, comma delimited.

    .PARAMETER Namestartswithorgreater
        Optional filter by items whose name is sorted equally or greater than a given input string.

    .PARAMETER Namestartswith
        Optional filter by items whose name is sorted equally than a given input string.

    .PARAMETER Namelessthan
        Optional filter by items whose name is equally or lesser than a given input string.

    .PARAMETER Studioids
        Optional. If specified, results will be filtered based on studio id. This allows multiple, pipe delimited.

    .PARAMETER Genreids
        Optional. If specified, results will be filtered based on genre id. This allows multiple, pipe delimited.

    .PARAMETER Enabletotalrecordcount
        Optional. Enable the total record count.

    .PARAMETER Enableimages
        Optional, include image information in output.
    
    .EXAMPLE
        Get-JellyfinTrailers
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Maxofficialrating,

        [Parameter()]
        [nullable[bool]]$Hasthemesong,

        [Parameter()]
        [nullable[bool]]$Hasthemevideo,

        [Parameter()]
        [nullable[bool]]$Hassubtitles,

        [Parameter()]
        [nullable[bool]]$Hasspecialfeature,

        [Parameter()]
        [nullable[bool]]$Hastrailer,

        [Parameter()]
        [string]$Adjacentto,

        [Parameter()]
        [int]$Parentindexnumber,

        [Parameter()]
        [nullable[bool]]$Hasparentalrating,

        [Parameter()]
        [nullable[bool]]$Ishd,

        [Parameter()]
        [nullable[bool]]$Is4k,

        [Parameter()]
        [string[]]$Locationtypes,

        [Parameter()]
        [string[]]$Excludelocationtypes,

        [Parameter()]
        [nullable[bool]]$Ismissing,

        [Parameter()]
        [nullable[bool]]$Isunaired,

        [Parameter()]
        [double]$Mincommunityrating,

        [Parameter()]
        [double]$Mincriticrating,

        [Parameter()]
        [string]$Minpremieredate,

        [Parameter()]
        [string]$Mindatelastsaved,

        [Parameter()]
        [string]$Mindatelastsavedforuser,

        [Parameter()]
        [string]$Maxpremieredate,

        [Parameter()]
        [nullable[bool]]$Hasoverview,

        [Parameter()]
        [nullable[bool]]$Hasimdbid,

        [Parameter()]
        [nullable[bool]]$Hastmdbid,

        [Parameter()]
        [nullable[bool]]$Hastvdbid,

        [Parameter()]
        [nullable[bool]]$Ismovie,

        [Parameter()]
        [nullable[bool]]$Isseries,

        [Parameter()]
        [nullable[bool]]$Isnews,

        [Parameter()]
        [nullable[bool]]$Iskids,

        [Parameter()]
        [nullable[bool]]$Issports,

        [Parameter()]
        [string[]]$Excludeitemids,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [nullable[bool]]$Recursive,

        [Parameter()]
        [string]$Searchterm,

        [Parameter()]
        [ValidateSet('Ascending','Descending')]
        [string[]]$Sortorder,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Excludeitemtypes,

        [Parameter()]
        [ValidateSet('IsFolder','IsNotFolder','IsUnplayed','IsPlayed','IsFavorite','IsResumable','Likes','Dislikes','IsFavoriteOrLikes')]
        [string[]]$Filters,

        [Parameter()]
        [nullable[bool]]$Isfavorite,

        [Parameter()]
        [ValidateSet('Unknown','Video','Audio','Photo','Book')]
        [string[]]$Mediatypes,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Imagetypes,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [nullable[bool]]$Isplayed,

        [Parameter()]
        [string[]]$Genres,

        [Parameter()]
        [string[]]$Officialratings,

        [Parameter()]
        [string[]]$Tags,

        [Parameter()]
        [string[]]$Years,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [string]$Person,

        [Parameter()]
        [string[]]$Personids,

        [Parameter()]
        [string[]]$Persontypes,

        [Parameter()]
        [string[]]$Studios,

        [Parameter()]
        [string[]]$Artists,

        [Parameter()]
        [string[]]$Excludeartistids,

        [Parameter()]
        [string[]]$Artistids,

        [Parameter()]
        [string[]]$Albumartistids,

        [Parameter()]
        [string[]]$Contributingartistids,

        [Parameter()]
        [string[]]$Albums,

        [Parameter()]
        [string[]]$Albumids,

        [Parameter()]
        [string[]]$Ids,

        [Parameter()]
        [string[]]$Videotypes,

        [Parameter()]
        [string]$Minofficialrating,

        [Parameter()]
        [nullable[bool]]$Islocked,

        [Parameter()]
        [nullable[bool]]$Isplaceholder,

        [Parameter()]
        [nullable[bool]]$Hasofficialrating,

        [Parameter()]
        [nullable[bool]]$Collapseboxsetitems,

        [Parameter()]
        [int]$Minwidth,

        [Parameter()]
        [int]$Minheight,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [nullable[bool]]$Is3d,

        [Parameter()]
        [string[]]$Seriesstatus,

        [Parameter()]
        [string]$Namestartswithorgreater,

        [Parameter()]
        [string]$Namestartswith,

        [Parameter()]
        [string]$Namelessthan,

        [Parameter()]
        [string[]]$Studioids,

        [Parameter()]
        [string[]]$Genreids,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount,

        [Parameter()]
        [nullable[bool]]$Enableimages
    )


    $path = '/Trailers'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Maxofficialrating) { $queryParameters['maxOfficialRating'] = $Maxofficialrating }
    if ($PSBoundParameters.ContainsKey('Hasthemesong')) { $queryParameters['hasThemeSong'] = $Hasthemesong }
    if ($PSBoundParameters.ContainsKey('Hasthemevideo')) { $queryParameters['hasThemeVideo'] = $Hasthemevideo }
    if ($PSBoundParameters.ContainsKey('Hassubtitles')) { $queryParameters['hasSubtitles'] = $Hassubtitles }
    if ($PSBoundParameters.ContainsKey('Hasspecialfeature')) { $queryParameters['hasSpecialFeature'] = $Hasspecialfeature }
    if ($PSBoundParameters.ContainsKey('Hastrailer')) { $queryParameters['hasTrailer'] = $Hastrailer }
    if ($Adjacentto) { $queryParameters['adjacentTo'] = $Adjacentto }
    if ($Parentindexnumber) { $queryParameters['parentIndexNumber'] = $Parentindexnumber }
    if ($PSBoundParameters.ContainsKey('Hasparentalrating')) { $queryParameters['hasParentalRating'] = $Hasparentalrating }
    if ($PSBoundParameters.ContainsKey('Ishd')) { $queryParameters['isHd'] = $Ishd }
    if ($PSBoundParameters.ContainsKey('Is4k')) { $queryParameters['is4K'] = $Is4k }
    if ($Locationtypes) { $queryParameters['locationTypes'] = convertto-delimited $Locationtypes ',' }
    if ($Excludelocationtypes) { $queryParameters['excludeLocationTypes'] = convertto-delimited $Excludelocationtypes ',' }
    if ($PSBoundParameters.ContainsKey('Ismissing')) { $queryParameters['isMissing'] = $Ismissing }
    if ($PSBoundParameters.ContainsKey('Isunaired')) { $queryParameters['isUnaired'] = $Isunaired }
    if ($Mincommunityrating) { $queryParameters['minCommunityRating'] = $Mincommunityrating }
    if ($Mincriticrating) { $queryParameters['minCriticRating'] = $Mincriticrating }
    if ($Minpremieredate) { $queryParameters['minPremiereDate'] = $Minpremieredate }
    if ($Mindatelastsaved) { $queryParameters['minDateLastSaved'] = $Mindatelastsaved }
    if ($Mindatelastsavedforuser) { $queryParameters['minDateLastSavedForUser'] = $Mindatelastsavedforuser }
    if ($Maxpremieredate) { $queryParameters['maxPremiereDate'] = $Maxpremieredate }
    if ($PSBoundParameters.ContainsKey('Hasoverview')) { $queryParameters['hasOverview'] = $Hasoverview }
    if ($PSBoundParameters.ContainsKey('Hasimdbid')) { $queryParameters['hasImdbId'] = $Hasimdbid }
    if ($PSBoundParameters.ContainsKey('Hastmdbid')) { $queryParameters['hasTmdbId'] = $Hastmdbid }
    if ($PSBoundParameters.ContainsKey('Hastvdbid')) { $queryParameters['hasTvdbId'] = $Hastvdbid }
    if ($PSBoundParameters.ContainsKey('Ismovie')) { $queryParameters['isMovie'] = $Ismovie }
    if ($PSBoundParameters.ContainsKey('Isseries')) { $queryParameters['isSeries'] = $Isseries }
    if ($PSBoundParameters.ContainsKey('Isnews')) { $queryParameters['isNews'] = $Isnews }
    if ($PSBoundParameters.ContainsKey('Iskids')) { $queryParameters['isKids'] = $Iskids }
    if ($PSBoundParameters.ContainsKey('Issports')) { $queryParameters['isSports'] = $Issports }
    if ($Excludeitemids) { $queryParameters['excludeItemIds'] = convertto-delimited $Excludeitemids ',' }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($PSBoundParameters.ContainsKey('Recursive')) { $queryParameters['recursive'] = $Recursive }
    if ($Searchterm) { $queryParameters['searchTerm'] = $Searchterm }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Excludeitemtypes) { $queryParameters['excludeItemTypes'] = convertto-delimited $Excludeitemtypes ',' }
    if ($Filters) { $queryParameters['filters'] = convertto-delimited $Filters ',' }
    if ($PSBoundParameters.ContainsKey('Isfavorite')) { $queryParameters['isFavorite'] = $Isfavorite }
    if ($Mediatypes) { $queryParameters['mediaTypes'] = convertto-delimited $Mediatypes ',' }
    if ($Imagetypes) { $queryParameters['imageTypes'] = convertto-delimited $Imagetypes ',' }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($PSBoundParameters.ContainsKey('Isplayed')) { $queryParameters['isPlayed'] = $Isplayed }
    if ($Genres) { $queryParameters['genres'] = convertto-delimited $Genres ',' }
    if ($Officialratings) { $queryParameters['officialRatings'] = convertto-delimited $Officialratings ',' }
    if ($Tags) { $queryParameters['tags'] = convertto-delimited $Tags ',' }
    if ($Years) { $queryParameters['years'] = convertto-delimited $Years ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Person) { $queryParameters['person'] = $Person }
    if ($Personids) { $queryParameters['personIds'] = convertto-delimited $Personids ',' }
    if ($Persontypes) { $queryParameters['personTypes'] = convertto-delimited $Persontypes ',' }
    if ($Studios) { $queryParameters['studios'] = convertto-delimited $Studios ',' }
    if ($Artists) { $queryParameters['artists'] = convertto-delimited $Artists ',' }
    if ($Excludeartistids) { $queryParameters['excludeArtistIds'] = convertto-delimited $Excludeartistids ',' }
    if ($Artistids) { $queryParameters['artistIds'] = convertto-delimited $Artistids ',' }
    if ($Albumartistids) { $queryParameters['albumArtistIds'] = convertto-delimited $Albumartistids ',' }
    if ($Contributingartistids) { $queryParameters['contributingArtistIds'] = convertto-delimited $Contributingartistids ',' }
    if ($Albums) { $queryParameters['albums'] = convertto-delimited $Albums ',' }
    if ($Albumids) { $queryParameters['albumIds'] = convertto-delimited $Albumids ',' }
    if ($Ids) { $queryParameters['ids'] = convertto-delimited $Ids ',' }
    if ($Videotypes) { $queryParameters['videoTypes'] = convertto-delimited $Videotypes ',' }
    if ($Minofficialrating) { $queryParameters['minOfficialRating'] = $Minofficialrating }
    if ($PSBoundParameters.ContainsKey('Islocked')) { $queryParameters['isLocked'] = $Islocked }
    if ($PSBoundParameters.ContainsKey('Isplaceholder')) { $queryParameters['isPlaceHolder'] = $Isplaceholder }
    if ($PSBoundParameters.ContainsKey('Hasofficialrating')) { $queryParameters['hasOfficialRating'] = $Hasofficialrating }
    if ($PSBoundParameters.ContainsKey('Collapseboxsetitems')) { $queryParameters['collapseBoxSetItems'] = $Collapseboxsetitems }
    if ($Minwidth) { $queryParameters['minWidth'] = $Minwidth }
    if ($Minheight) { $queryParameters['minHeight'] = $Minheight }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($PSBoundParameters.ContainsKey('Is3d')) { $queryParameters['is3D'] = $Is3d }
    if ($Seriesstatus) { $queryParameters['seriesStatus'] = convertto-delimited $Seriesstatus ',' }
    if ($Namestartswithorgreater) { $queryParameters['nameStartsWithOrGreater'] = $Namestartswithorgreater }
    if ($Namestartswith) { $queryParameters['nameStartsWith'] = $Namestartswith }
    if ($Namelessthan) { $queryParameters['nameLessThan'] = $Namelessthan }
    if ($Studioids) { $queryParameters['studioIds'] = convertto-delimited $Studioids ',' }
    if ($Genreids) { $queryParameters['genreIds'] = convertto-delimited $Genreids ',' }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Trickplay Functions (2 functions)

function Get-JellyfinTrickplayTileImage {
    <#
    .SYNOPSIS
            Gets a trickplay tile image.

    .DESCRIPTION
        API Endpoint: GET /Videos/{itemId}/Trickplay/{width}/{index}.jpg
        Operation ID: GetTrickplayTileImage
        Tags: Trickplay
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Width
        Path parameter: width

    .PARAMETER Index
        Path parameter: index

    .PARAMETER Mediasourceid
        The media version id, if using an alternate version.
    
    .EXAMPLE
        Get-JellyfinTrickplayTileImage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Width,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Index,

        [Parameter()]
        [string]$Mediasourceid
    )


    $path = '/Videos/{itemId}/Trickplay/{width}/{index}.jpg'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{width\}', $Width
    $path = $path -replace '\{index\}', $Index
    $queryParameters = @{}
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinTrickplayHlsPlaylist {
    <#
    .SYNOPSIS
            Gets an image tiles playlist for trickplay.

    .DESCRIPTION
        API Endpoint: GET /Videos/{itemId}/Trickplay/{width}/tiles.m3u8
        Operation ID: GetTrickplayHlsPlaylist
        Tags: Trickplay
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Width
        Path parameter: width

    .PARAMETER Mediasourceid
        The media version id, if using an alternate version.
    
    .EXAMPLE
        Get-JellyfinTrickplayHlsPlaylist
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Width,

        [Parameter()]
        [string]$Mediasourceid
    )


    $path = '/Videos/{itemId}/Trickplay/{width}/tiles.m3u8'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{width\}', $Width
    $queryParameters = @{}
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region TvShows Functions (4 functions)

function Get-JellyfinEpisodes {
    <#
    .SYNOPSIS
            Gets episodes for a tv season.

    .DESCRIPTION
        API Endpoint: GET /Shows/{seriesId}/Episodes
        Operation ID: GetEpisodes
        Tags: TvShows
    .PARAMETER Seriesid
        Path parameter: seriesId

    .PARAMETER Userid
        The user id.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output. This allows multiple, comma delimited. Options: Budget, Chapters, DateCreated, Genres, HomePageUrl, IndexOptions, MediaStreams, Overview, ParentId, Path, People, ProviderIds, PrimaryImageAspectRatio, Revenue, SortName, Studios, Taglines, TrailerUrls.

    .PARAMETER Season
        Optional filter by season number.

    .PARAMETER Seasonid
        Optional. Filter by season id.

    .PARAMETER Ismissing
        Optional. Filter by items that are missing episodes or not.

    .PARAMETER Adjacentto
        Optional. Return items that are siblings of a supplied item.

    .PARAMETER Startitemid
        Optional. Skip through the list until a given item is found.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Enableimages
        Optional, include image information in output.

    .PARAMETER Imagetypelimit
        Optional, the max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited. Options: Album, AlbumArtist, Artist, Budget, CommunityRating, CriticRating, DateCreated, DatePlayed, PlayCount, PremiereDate, ProductionYear, SortName, Random, Revenue, Runtime.
    
    .EXAMPLE
        Get-JellyfinEpisodes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Seriesid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [int]$Season,

        [Parameter()]
        [string]$Seasonid,

        [Parameter()]
        [nullable[bool]]$Ismissing,

        [Parameter()]
        [string]$Adjacentto,

        [Parameter()]
        [string]$Startitemid,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [string]$Sortby
    )


    $path = '/Shows/{seriesId}/Episodes'
    $path = $path -replace '\{seriesId\}', $Seriesid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Season) { $queryParameters['season'] = $Season }
    if ($Seasonid) { $queryParameters['seasonId'] = $Seasonid }
    if ($PSBoundParameters.ContainsKey('Ismissing')) { $queryParameters['isMissing'] = $Ismissing }
    if ($Adjacentto) { $queryParameters['adjacentTo'] = $Adjacentto }
    if ($Startitemid) { $queryParameters['startItemId'] = $Startitemid }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSeasons {
    <#
    .SYNOPSIS
            Gets seasons for a tv series.

    .DESCRIPTION
        API Endpoint: GET /Shows/{seriesId}/Seasons
        Operation ID: GetSeasons
        Tags: TvShows
    .PARAMETER Seriesid
        Path parameter: seriesId

    .PARAMETER Userid
        The user id.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output. This allows multiple, comma delimited. Options: Budget, Chapters, DateCreated, Genres, HomePageUrl, IndexOptions, MediaStreams, Overview, ParentId, Path, People, ProviderIds, PrimaryImageAspectRatio, Revenue, SortName, Studios, Taglines, TrailerUrls.

    .PARAMETER Isspecialseason
        Optional. Filter by special season.

    .PARAMETER Ismissing
        Optional. Filter by items that are missing episodes or not.

    .PARAMETER Adjacentto
        Optional. Return items that are siblings of a supplied item.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Enableuserdata
        Optional. Include user data.
    
    .EXAMPLE
        Get-JellyfinSeasons
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Seriesid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [nullable[bool]]$Isspecialseason,

        [Parameter()]
        [nullable[bool]]$Ismissing,

        [Parameter()]
        [string]$Adjacentto,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [nullable[bool]]$Enableuserdata
    )


    $path = '/Shows/{seriesId}/Seasons'
    $path = $path -replace '\{seriesId\}', $Seriesid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($PSBoundParameters.ContainsKey('Isspecialseason')) { $queryParameters['isSpecialSeason'] = $Isspecialseason }
    if ($PSBoundParameters.ContainsKey('Ismissing')) { $queryParameters['isMissing'] = $Ismissing }
    if ($Adjacentto) { $queryParameters['adjacentTo'] = $Adjacentto }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinNextUp {
    <#
    .SYNOPSIS
            Gets a list of next up episodes.

    .DESCRIPTION
        API Endpoint: GET /Shows/NextUp
        Operation ID: GetNextUp
        Tags: TvShows
    .PARAMETER Userid
        The user id of the user to get the next up episodes for.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Seriesid
        Optional. Filter by series id.

    .PARAMETER Parentid
        Optional. Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Nextupdatecutoff
        Optional. Starting date of shows to show in Next Up section.

    .PARAMETER Enabletotalrecordcount
        Whether to enable the total records count. Defaults to true.

    .PARAMETER Disablefirstepisode
        Whether to disable sending the first episode in a series as next up.

    .PARAMETER Enableresumable
        Whether to include resumable episodes in next up results.

    .PARAMETER Enablerewatching
        Whether to include watched episodes in next up results.
    
    .EXAMPLE
        Get-JellyfinNextUp
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [string]$Seriesid,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [string]$Nextupdatecutoff,

        [Parameter()]
        [nullable[bool]]$Enabletotalrecordcount,

        [Parameter()]
        [nullable[bool]]$Disablefirstepisode,

        [Parameter()]
        [nullable[bool]]$Enableresumable,

        [Parameter()]
        [nullable[bool]]$Enablerewatching
    )


    $path = '/Shows/NextUp'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Seriesid) { $queryParameters['seriesId'] = $Seriesid }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Nextupdatecutoff) { $queryParameters['nextUpDateCutoff'] = $Nextupdatecutoff }
    if ($PSBoundParameters.ContainsKey('Enabletotalrecordcount')) { $queryParameters['enableTotalRecordCount'] = $Enabletotalrecordcount }
    if ($PSBoundParameters.ContainsKey('Disablefirstepisode')) { $queryParameters['disableFirstEpisode'] = $Disablefirstepisode }
    if ($PSBoundParameters.ContainsKey('Enableresumable')) { $queryParameters['enableResumable'] = $Enableresumable }
    if ($PSBoundParameters.ContainsKey('Enablerewatching')) { $queryParameters['enableRewatching'] = $Enablerewatching }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinUpcomingEpisodes {
    <#
    .SYNOPSIS
            Gets a list of upcoming episodes.

    .DESCRIPTION
        API Endpoint: GET /Shows/Upcoming
        Operation ID: GetUpcomingEpisodes
        Tags: TvShows
    .PARAMETER Userid
        The user id of the user to get the upcoming episodes for.

    .PARAMETER Startindex
        Optional. The record index to start at. All items with a lower index will be dropped from the results.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Parentid
        Optional. Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Enableimages
        Optional. Include image information in output.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Enableuserdata
        Optional. Include user data.
    
    .EXAMPLE
        Get-JellyfinUpcomingEpisodes
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [nullable[bool]]$Enableuserdata
    )


    $path = '/Shows/Upcoming'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region UniversalAudio Functions (2 functions)

function Get-JellyfinUniversalAudioStream {
    <#
    .SYNOPSIS
            Gets an audio stream.

    .DESCRIPTION
        API Endpoint: GET /Audio/{itemId}/universal
        Operation ID: GetUniversalAudioStream
        Tags: UniversalAudio
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Container
        Optional. The audio container.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Userid
        Optional. The user id.

    .PARAMETER Audiocodec
        Optional. The audio codec to transcode to.

    .PARAMETER Maxaudiochannels
        Optional. The maximum number of audio channels.

    .PARAMETER Transcodingaudiochannels
        Optional. The number of how many audio channels to transcode to.

    .PARAMETER Maxstreamingbitrate
        Optional. The maximum streaming bitrate.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Transcodingcontainer
        Optional. The container to transcode to.

    .PARAMETER Transcodingprotocol
        Optional. The transcoding protocol.

    .PARAMETER Maxaudiosamplerate
        Optional. The maximum audio sample rate.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Enableremotemedia
        Optional. Whether to enable remote media.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Enableredirection
        Whether to enable redirection. Defaults to true.
    
    .EXAMPLE
        Get-JellyfinUniversalAudioStream
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string[]]$Container,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [int]$Transcodingaudiochannels,

        [Parameter()]
        [int]$Maxstreamingbitrate,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [string]$Transcodingcontainer,

        [Parameter()]
        [string]$Transcodingprotocol,

        [Parameter()]
        [int]$Maxaudiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [nullable[bool]]$Enableremotemedia,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [nullable[bool]]$Enableredirection
    )


    $path = '/Audio/{itemId}/universal'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Container) { $queryParameters['container'] = convertto-delimited $Container ',' }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Transcodingaudiochannels) { $queryParameters['transcodingAudioChannels'] = $Transcodingaudiochannels }
    if ($Maxstreamingbitrate) { $queryParameters['maxStreamingBitrate'] = $Maxstreamingbitrate }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Transcodingcontainer) { $queryParameters['transcodingContainer'] = $Transcodingcontainer }
    if ($Transcodingprotocol) { $queryParameters['transcodingProtocol'] = $Transcodingprotocol }
    if ($Maxaudiosamplerate) { $queryParameters['maxAudioSampleRate'] = $Maxaudiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($PSBoundParameters.ContainsKey('Enableremotemedia')) { $queryParameters['enableRemoteMedia'] = $Enableremotemedia }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($PSBoundParameters.ContainsKey('Enableredirection')) { $queryParameters['enableRedirection'] = $Enableredirection }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinUniversalAudioStream {
    <#
    .SYNOPSIS
            Gets an audio stream.

    .DESCRIPTION
        API Endpoint: HEAD /Audio/{itemId}/universal
        Operation ID: HeadUniversalAudioStream
        Tags: UniversalAudio
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Container
        Optional. The audio container.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Userid
        Optional. The user id.

    .PARAMETER Audiocodec
        Optional. The audio codec to transcode to.

    .PARAMETER Maxaudiochannels
        Optional. The maximum number of audio channels.

    .PARAMETER Transcodingaudiochannels
        Optional. The number of how many audio channels to transcode to.

    .PARAMETER Maxstreamingbitrate
        Optional. The maximum streaming bitrate.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Transcodingcontainer
        Optional. The container to transcode to.

    .PARAMETER Transcodingprotocol
        Optional. The transcoding protocol.

    .PARAMETER Maxaudiosamplerate
        Optional. The maximum audio sample rate.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Enableremotemedia
        Optional. Whether to enable remote media.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Enableredirection
        Whether to enable redirection. Defaults to true.
    
    .EXAMPLE
        Test-JellyfinUniversalAudioStream
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string[]]$Container,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [int]$Transcodingaudiochannels,

        [Parameter()]
        [int]$Maxstreamingbitrate,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [string]$Transcodingcontainer,

        [Parameter()]
        [string]$Transcodingprotocol,

        [Parameter()]
        [int]$Maxaudiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [nullable[bool]]$Enableremotemedia,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [nullable[bool]]$Enableredirection
    )


    $path = '/Audio/{itemId}/universal'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Container) { $queryParameters['container'] = convertto-delimited $Container ',' }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Transcodingaudiochannels) { $queryParameters['transcodingAudioChannels'] = $Transcodingaudiochannels }
    if ($Maxstreamingbitrate) { $queryParameters['maxStreamingBitrate'] = $Maxstreamingbitrate }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Transcodingcontainer) { $queryParameters['transcodingContainer'] = $Transcodingcontainer }
    if ($Transcodingprotocol) { $queryParameters['transcodingProtocol'] = $Transcodingprotocol }
    if ($Maxaudiosamplerate) { $queryParameters['maxAudioSampleRate'] = $Maxaudiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($PSBoundParameters.ContainsKey('Enableremotemedia')) { $queryParameters['enableRemoteMedia'] = $Enableremotemedia }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($PSBoundParameters.ContainsKey('Enableredirection')) { $queryParameters['enableRedirection'] = $Enableredirection }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region User Functions (14 functions)

function Get-JellyfinUsers {
    <#
    .SYNOPSIS
            Gets a list of users.

    .DESCRIPTION
        API Endpoint: GET /Users
        Operation ID: GetUsers
        Tags: User
    .PARAMETER Ishidden
        Optional filter by IsHidden=true or false.

    .PARAMETER Isdisabled
        Optional filter by IsDisabled=true or false.
    
    .EXAMPLE
        Get-JellyfinUsers
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [nullable[bool]]$Ishidden,

        [Parameter()]
        [nullable[bool]]$Isdisabled
    )


    $path = '/Users'
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Ishidden')) { $queryParameters['isHidden'] = $Ishidden }
    if ($PSBoundParameters.ContainsKey('Isdisabled')) { $queryParameters['isDisabled'] = $Isdisabled }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinUser {
    <#
    .SYNOPSIS
            Updates a user.

    .DESCRIPTION
        API Endpoint: POST /Users
        Operation ID: UpdateUser
        Tags: User
    .PARAMETER Userid
        The user id.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinUser
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [object]$Body
    )


    $path = '/Users'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinUserById {
    <#
    .SYNOPSIS
            Gets a user by Id.

    .DESCRIPTION
        API Endpoint: GET /Users/{userId}
        Operation ID: GetUserById
        Tags: User
    .PARAMETER Userid
        Path parameter: userId
    
    .EXAMPLE
        Get-JellyfinUserById
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Userid
    )


    $path = '/Users/{userId}'
    $path = $path -replace '\{userId\}', $Userid

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinUser {
    <#
    .SYNOPSIS
            Deletes a user.

    .DESCRIPTION
        API Endpoint: DELETE /Users/{userId}
        Operation ID: DeleteUser
        Tags: User
    .PARAMETER Userid
        Path parameter: userId
    
    .EXAMPLE
        Remove-JellyfinUser
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Userid
    )


    $path = '/Users/{userId}'
    $path = $path -replace '\{userId\}', $Userid

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinUserPolicy {
    <#
    .SYNOPSIS
            Updates a user policy.

    .DESCRIPTION
        API Endpoint: POST /Users/{userId}/Policy
        Operation ID: UpdateUserPolicy
        Tags: User
    .PARAMETER Userid
        Path parameter: userId

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinUserPolicy
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Userid,

        [Parameter()]
        [object]$Body
    )


    $path = '/Users/{userId}/Policy'
    $path = $path -replace '\{userId\}', $Userid

    $invokeParams = @{
        Path = $path
        Method = 'POST'
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinAuthenticateUserByName {
    <#
    .SYNOPSIS
            Authenticates a user by name.

    .DESCRIPTION
        API Endpoint: POST /Users/AuthenticateByName
        Operation ID: AuthenticateUserByName
        Tags: User
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinAuthenticateUserByName
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Users/AuthenticateByName'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinAuthenticateWithQuickConnect {
    <#
    .SYNOPSIS
            Authenticates a user with quick connect.

    .DESCRIPTION
        API Endpoint: POST /Users/AuthenticateWithQuickConnect
        Operation ID: AuthenticateWithQuickConnect
        Tags: User
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinAuthenticateWithQuickConnect
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Users/AuthenticateWithQuickConnect'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinUserConfiguration {
    <#
    .SYNOPSIS
            Updates a user configuration.

    .DESCRIPTION
        API Endpoint: POST /Users/Configuration
        Operation ID: UpdateUserConfiguration
        Tags: User
    .PARAMETER Userid
        The user id.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinUserConfiguration
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [object]$Body
    )


    $path = '/Users/Configuration'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinForgotPassword {
    <#
    .SYNOPSIS
            Initiates the forgot password process for a local user.

    .DESCRIPTION
        API Endpoint: POST /Users/ForgotPassword
        Operation ID: ForgotPassword
        Tags: User
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinForgotPassword
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Users/ForgotPassword'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinForgotPasswordPin {
    <#
    .SYNOPSIS
            Redeems a forgot password pin.

    .DESCRIPTION
        API Endpoint: POST /Users/ForgotPassword/Pin
        Operation ID: ForgotPasswordPin
        Tags: User
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Invoke-JellyfinForgotPasswordPin
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Users/ForgotPassword/Pin'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinCurrentUser {
    <#
    .SYNOPSIS
            Gets the user based on auth token.

    .DESCRIPTION
        API Endpoint: GET /Users/Me
        Operation ID: GetCurrentUser
        Tags: User
    .EXAMPLE
        Get-JellyfinCurrentUser
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Users/Me' -Method GET
}
function New-JellyfinUserByName {
    <#
    .SYNOPSIS
            Creates a user.

    .DESCRIPTION
        API Endpoint: POST /Users/New
        Operation ID: CreateUserByName
        Tags: User
    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        New-JellyfinUserByName
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Body
    )

    $invokeParams = @{
        Path = '/Users/New'
        Method = 'POST'
    }
    if ($Body) { $invokeParams['Body'] = $Body }
    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinUserPassword {
    <#
    .SYNOPSIS
            Updates a user's password.

    .DESCRIPTION
        API Endpoint: POST /Users/Password
        Operation ID: UpdateUserPassword
        Tags: User
    .PARAMETER Userid
        The user id.

    .PARAMETER Body
        Request body content
    
    .EXAMPLE
        Set-JellyfinUserPassword
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [object]$Body
    )


    $path = '/Users/Password'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    if ($Body) { $invokeParams['Body'] = $Body }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinPublicUsers {
    <#
    .SYNOPSIS
            Gets a list of publicly visible users for display on a login screen.

    .DESCRIPTION
        API Endpoint: GET /Users/Public
        Operation ID: GetPublicUsers
        Tags: User
    .EXAMPLE
        Get-JellyfinPublicUsers
    #>
    [CmdletBinding()]
    param()

    Invoke-JellyfinRequest -Path '/Users/Public' -Method GET
}
#endregion

#region UserLibrary Functions (10 functions)

function Get-JellyfinItem {
    <#
    .SYNOPSIS
            Gets an item from a user's library.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}
        Operation ID: GetItem
        Tags: UserLibrary
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        User id.
    
    .EXAMPLE
        Get-JellyfinItem
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Items/{itemId}'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinIntros {
    <#
    .SYNOPSIS
            Gets intros to play before the main media item plays.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/Intros
        Operation ID: GetIntros
        Tags: UserLibrary
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        User id.
    
    .EXAMPLE
        Get-JellyfinIntros
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Items/{itemId}/Intros'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinLocalTrailers {
    <#
    .SYNOPSIS
            Gets local trailers for an item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/LocalTrailers
        Operation ID: GetLocalTrailers
        Tags: UserLibrary
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        User id.
    
    .EXAMPLE
        Get-JellyfinLocalTrailers
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Items/{itemId}/LocalTrailers'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinSpecialFeatures {
    <#
    .SYNOPSIS
            Gets special features for an item.

    .DESCRIPTION
        API Endpoint: GET /Items/{itemId}/SpecialFeatures
        Operation ID: GetSpecialFeatures
        Tags: UserLibrary
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        User id.
    
    .EXAMPLE
        Get-JellyfinSpecialFeatures
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Items/{itemId}/SpecialFeatures'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinLatestMedia {
    <#
    .SYNOPSIS
            Gets latest media.

    .DESCRIPTION
        API Endpoint: GET /Items/Latest
        Operation ID: GetLatestMedia
        Tags: UserLibrary
    .PARAMETER Userid
        User id.

    .PARAMETER Parentid
        Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Includeitemtypes
        Optional. If specified, results will be filtered based on item type. This allows multiple, comma delimited.

    .PARAMETER Isplayed
        Filter by items that are played, or not.

    .PARAMETER Enableimages
        Optional. include image information in output.

    .PARAMETER Imagetypelimit
        Optional. the max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Enableuserdata
        Optional. include user data.

    .PARAMETER Limit
        Return item limit.

    .PARAMETER Groupitems
        Whether or not to group items into a parent container.
    
    .EXAMPLE
        Get-JellyfinLatestMedia
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Includeitemtypes,

        [Parameter()]
        [nullable[bool]]$Isplayed,

        [Parameter()]
        [nullable[bool]]$Enableimages,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [nullable[bool]]$Groupitems
    )


    $path = '/Items/Latest'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Includeitemtypes) { $queryParameters['includeItemTypes'] = convertto-delimited $Includeitemtypes ',' }
    if ($PSBoundParameters.ContainsKey('Isplayed')) { $queryParameters['isPlayed'] = $Isplayed }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($PSBoundParameters.ContainsKey('Groupitems')) { $queryParameters['groupItems'] = $Groupitems }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinRootFolder {
    <#
    .SYNOPSIS
            Gets the root folder from a user's library.

    .DESCRIPTION
        API Endpoint: GET /Items/Root
        Operation ID: GetRootFolder
        Tags: UserLibrary
    .PARAMETER Userid
        User id.
    
    .EXAMPLE
        Get-JellyfinRootFolder
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid
    )


    $path = '/Items/Root'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinMarkFavoriteItem {
    <#
    .SYNOPSIS
            Marks an item as a favorite.

    .DESCRIPTION
        API Endpoint: POST /UserFavoriteItems/{itemId}
        Operation ID: MarkFavoriteItem
        Tags: UserLibrary
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        User id.
    
    .EXAMPLE
        Invoke-JellyfinMarkFavoriteItem
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/UserFavoriteItems/{itemId}'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinUnmarkFavoriteItem {
    <#
    .SYNOPSIS
            Unmarks item as a favorite.

    .DESCRIPTION
        API Endpoint: DELETE /UserFavoriteItems/{itemId}
        Operation ID: UnmarkFavoriteItem
        Tags: UserLibrary
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        User id.
    
    .EXAMPLE
        Remove-JellyfinUnmarkFavoriteItem
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/UserFavoriteItems/{itemId}'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinUserItemRating {
    <#
    .SYNOPSIS
            Deletes a user's saved personal rating for an item.

    .DESCRIPTION
        API Endpoint: DELETE /UserItems/{itemId}/Rating
        Operation ID: DeleteUserItemRating
        Tags: UserLibrary
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        User id.
    
    .EXAMPLE
        Remove-JellyfinUserItemRating
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/UserItems/{itemId}/Rating'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Set-JellyfinUserItemRating {
    <#
    .SYNOPSIS
            Updates a user's rating for an item.

    .DESCRIPTION
        API Endpoint: POST /UserItems/{itemId}/Rating
        Operation ID: UpdateUserItemRating
        Tags: UserLibrary
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        User id.

    .PARAMETER Likes
        Whether this M:Jellyfin.Api.Controllers.UserLibraryController.UpdateUserItemRating(System.Nullable{System.Guid},System.Guid,System.Nullable{System.Boolean}) is likes.
    
    .EXAMPLE
        Set-JellyfinUserItemRating
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [nullable[bool]]$Likes
    )


    $path = '/UserItems/{itemId}/Rating'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($PSBoundParameters.ContainsKey('Likes')) { $queryParameters['likes'] = $Likes }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region UserViews Functions (2 functions)

function Get-JellyfinUserViews {
    <#
    .SYNOPSIS
            Get user views.

    .DESCRIPTION
        API Endpoint: GET /UserViews
        Operation ID: GetUserViews
        Tags: UserViews
    .PARAMETER Userid
        User id.

    .PARAMETER Includeexternalcontent
        Whether or not to include external views such as channels or live tv.

    .PARAMETER Presetviews
        Preset views.

    .PARAMETER Includehidden
        Whether or not to include hidden content.
    
    .EXAMPLE
        Get-JellyfinUserViews
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [nullable[bool]]$Includeexternalcontent,

        [Parameter()]
        [string[]]$Presetviews,

        [Parameter()]
        [nullable[bool]]$Includehidden
    )


    $path = '/UserViews'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($PSBoundParameters.ContainsKey('Includeexternalcontent')) { $queryParameters['includeExternalContent'] = $Includeexternalcontent }
    if ($Presetviews) { $queryParameters['presetViews'] = convertto-delimited $Presetviews ',' }
    if ($PSBoundParameters.ContainsKey('Includehidden')) { $queryParameters['includeHidden'] = $Includehidden }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinGroupingOptions {
    <#
    .SYNOPSIS
            Get user view grouping options.

    .DESCRIPTION
        API Endpoint: GET /UserViews/GroupingOptions
        Operation ID: GetGroupingOptions
        Tags: UserViews
    .PARAMETER Userid
        User id.
    
    .EXAMPLE
        Get-JellyfinGroupingOptions
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Userid
    )


    $path = '/UserViews/GroupingOptions'
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region VideoAttachments Functions (1 functions)

function Get-JellyfinAttachment {
    <#
    .SYNOPSIS
            Get video attachment.

    .DESCRIPTION
        API Endpoint: GET /Videos/{videoId}/{mediaSourceId}/Attachments/{index}
        Operation ID: GetAttachment
        Tags: VideoAttachments
    .PARAMETER Videoid
        Path parameter: videoId

    .PARAMETER Mediasourceid
        Path parameter: mediaSourceId

    .PARAMETER Index
        Path parameter: index
    
    .EXAMPLE
        Get-JellyfinAttachment
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Videoid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Mediasourceid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Index
    )


    $path = '/Videos/{videoId}/{mediaSourceId}/Attachments/{index}'
    $path = $path -replace '\{videoId\}', $Videoid
    $path = $path -replace '\{mediaSourceId\}', $Mediasourceid
    $path = $path -replace '\{index\}', $Index

    $invokeParams = @{
        Path = $path
        Method = 'GET'
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Videos Functions (7 functions)

function Get-JellyfinAdditionalPart {
    <#
    .SYNOPSIS
            Gets additional parts for a video.

    .DESCRIPTION
        API Endpoint: GET /Videos/{itemId}/AdditionalParts
        Operation ID: GetAdditionalPart
        Tags: Videos
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.
    
    .EXAMPLE
        Get-JellyfinAdditionalPart
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Videos/{itemId}/AdditionalParts'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Remove-JellyfinAlternateSources {
    <#
    .SYNOPSIS
            Removes alternate video sources.

    .DESCRIPTION
        API Endpoint: DELETE /Videos/{itemId}/AlternateSources
        Operation ID: DeleteAlternateSources
        Tags: Videos
    .PARAMETER Itemid
        Path parameter: itemId
    
    .EXAMPLE
        Remove-JellyfinAlternateSources
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid
    )


    $path = '/Videos/{itemId}/AlternateSources'
    $path = $path -replace '\{itemId\}', $Itemid

    $invokeParams = @{
        Path = $path
        Method = 'DELETE'
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinVideoStream {
    <#
    .SYNOPSIS
            Gets a video stream.

    .DESCRIPTION
        API Endpoint: GET /Videos/{itemId}/stream
        Operation ID: GetVideoStream
        Tags: Videos
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Container
        The video container. Possible values are: ts, webm, asf, wmv, ogv, mp4, m4v, mkv, mpeg, mpg, avi, 3gp, wmv, wtv, m2ts, mov, iso, flv.

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3. If omitted the server will auto-select using the url's extension.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Maxwidth
        Optional. The maximum horizontal resolution of the encoded video.

    .PARAMETER Maxheight
        Optional. The maximum vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264. If omitted the server will auto-select using the url's extension.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.
    
    .EXAMPLE
        Get-JellyfinVideoStream
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Container,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding
    )


    $path = '/Videos/{itemId}/stream'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Container) { $queryParameters['container'] = convertto-delimited $Container ',' }
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinVideoStream {
    <#
    .SYNOPSIS
            Gets a video stream.

    .DESCRIPTION
        API Endpoint: HEAD /Videos/{itemId}/stream
        Operation ID: HeadVideoStream
        Tags: Videos
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Container
        The video container. Possible values are: ts, webm, asf, wmv, ogv, mp4, m4v, mkv, mpeg, mpg, avi, 3gp, wmv, wtv, m2ts, mov, iso, flv.

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3. If omitted the server will auto-select using the url's extension.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Maxwidth
        Optional. The maximum horizontal resolution of the encoded video.

    .PARAMETER Maxheight
        Optional. The maximum vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264. If omitted the server will auto-select using the url's extension.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.
    
    .EXAMPLE
        Test-JellyfinVideoStream
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter()]
        [string]$Container,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding
    )


    $path = '/Videos/{itemId}/stream'
    $path = $path -replace '\{itemId\}', $Itemid
    $queryParameters = @{}
    if ($Container) { $queryParameters['container'] = convertto-delimited $Container ',' }
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinVideoStreamByContainer {
    <#
    .SYNOPSIS
            Gets a video stream.

    .DESCRIPTION
        API Endpoint: GET /Videos/{itemId}/stream.{container}
        Operation ID: GetVideoStreamByContainer
        Tags: Videos
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Container
        Path parameter: container

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3. If omitted the server will auto-select using the url's extension.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Maxwidth
        Optional. The maximum horizontal resolution of the encoded video.

    .PARAMETER Maxheight
        Optional. The maximum vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264. If omitted the server will auto-select using the url's extension.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.
    
    .EXAMPLE
        Get-JellyfinVideoStreamByContainer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Container,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding
    )


    $path = '/Videos/{itemId}/stream.{container}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{container\}', $Container
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Test-JellyfinVideoStreamByContainer {
    <#
    .SYNOPSIS
            Gets a video stream.

    .DESCRIPTION
        API Endpoint: HEAD /Videos/{itemId}/stream.{container}
        Operation ID: HeadVideoStreamByContainer
        Tags: Videos
    .PARAMETER Itemid
        Path parameter: itemId

    .PARAMETER Container
        Path parameter: container

    .PARAMETER Static
        Optional. If true, the original file will be streamed statically without any encoding. Use either no url extension or the original file extension. true/false.

    .PARAMETER Params
        The streaming parameters.

    .PARAMETER Tag
        The tag.

    .PARAMETER Deviceprofileid
        Optional. The dlna device profile id to utilize.

    .PARAMETER Playsessionid
        The play session id.

    .PARAMETER Segmentcontainer
        The segment container.

    .PARAMETER Segmentlength
        The segment length.

    .PARAMETER Minsegments
        The minimum number of segments.

    .PARAMETER Mediasourceid
        The media version id, if playing an alternate version.

    .PARAMETER Deviceid
        The device id of the client requesting. Used to stop encoding processes when needed.

    .PARAMETER Audiocodec
        Optional. Specify an audio codec to encode to, e.g. mp3. If omitted the server will auto-select using the url's extension.

    .PARAMETER Enableautostreamcopy
        Whether or not to allow automatic stream copy if requested values match the original source. Defaults to true.

    .PARAMETER Allowvideostreamcopy
        Whether or not to allow copying of the video stream url.

    .PARAMETER Allowaudiostreamcopy
        Whether or not to allow copying of the audio stream url.

    .PARAMETER Breakonnonkeyframes
        Optional. Whether to break on non key frames.

    .PARAMETER Audiosamplerate
        Optional. Specify a specific audio sample rate, e.g. 44100.

    .PARAMETER Maxaudiobitdepth
        Optional. The maximum audio bit depth.

    .PARAMETER Audiobitrate
        Optional. Specify an audio bitrate to encode to, e.g. 128000. If omitted this will be left to encoder defaults.

    .PARAMETER Audiochannels
        Optional. Specify a specific number of audio channels to encode to, e.g. 2.

    .PARAMETER Maxaudiochannels
        Optional. Specify a maximum number of audio channels to encode to, e.g. 2.

    .PARAMETER Profile
        Optional. Specify a specific an encoder profile (varies by encoder), e.g. main, baseline, high.

    .PARAMETER Level
        Optional. Specify a level for the encoder profile (varies by encoder), e.g. 3, 3.1.

    .PARAMETER Framerate
        Optional. A specific video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Maxframerate
        Optional. A specific maximum video framerate to encode to, e.g. 23.976. Generally this should be omitted unless the device has specific requirements.

    .PARAMETER Copytimestamps
        Whether or not to copy timestamps when transcoding with an offset. Defaults to false.

    .PARAMETER Starttimeticks
        Optional. Specify a starting offset, in ticks. 1 tick = 10000 ms.

    .PARAMETER Width
        Optional. The fixed horizontal resolution of the encoded video.

    .PARAMETER Height
        Optional. The fixed vertical resolution of the encoded video.

    .PARAMETER Maxwidth
        Optional. The maximum horizontal resolution of the encoded video.

    .PARAMETER Maxheight
        Optional. The maximum vertical resolution of the encoded video.

    .PARAMETER Videobitrate
        Optional. Specify a video bitrate to encode to, e.g. 500000. If omitted this will be left to encoder defaults.

    .PARAMETER Subtitlestreamindex
        Optional. The index of the subtitle stream to use. If omitted no subtitles will be used.

    .PARAMETER Subtitlemethod
        Optional. Specify the subtitle delivery method.

    .PARAMETER Maxrefframes
        Optional.

    .PARAMETER Maxvideobitdepth
        Optional. The maximum video bit depth.

    .PARAMETER Requireavc
        Optional. Whether to require avc.

    .PARAMETER Deinterlace
        Optional. Whether to deinterlace the video.

    .PARAMETER Requirenonanamorphic
        Optional. Whether to require a non anamorphic stream.

    .PARAMETER Transcodingmaxaudiochannels
        Optional. The maximum number of audio channels to transcode.

    .PARAMETER Cpucorelimit
        Optional. The limit of how many cpu cores to use.

    .PARAMETER Livestreamid
        The live stream id.

    .PARAMETER Enablempegtsm2tsmode
        Optional. Whether to enable the MpegtsM2Ts mode.

    .PARAMETER Videocodec
        Optional. Specify a video codec to encode to, e.g. h264. If omitted the server will auto-select using the url's extension.

    .PARAMETER Subtitlecodec
        Optional. Specify a subtitle codec to encode to.

    .PARAMETER Transcodereasons
        Optional. The transcoding reason.

    .PARAMETER Audiostreamindex
        Optional. The index of the audio stream to use. If omitted the first audio stream will be used.

    .PARAMETER Videostreamindex
        Optional. The index of the video stream to use. If omitted the first video stream will be used.

    .PARAMETER Context
        Optional. The MediaBrowser.Model.Dlna.EncodingContext.

    .PARAMETER Streamoptions
        Optional. The streaming options.

    .PARAMETER Enableaudiovbrencoding
        Optional. Whether to enable Audio Encoding.
    
    .EXAMPLE
        Test-JellyfinVideoStreamByContainer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Itemid,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Container,

        [Parameter()]
        [nullable[bool]]$Static,

        [Parameter()]
        [string]$Params,

        [Parameter()]
        [string]$Tag,

        [Parameter()]
        [string]$Deviceprofileid,

        [Parameter()]
        [string]$Playsessionid,

        [Parameter()]
        [string]$Segmentcontainer,

        [Parameter()]
        [int]$Segmentlength,

        [Parameter()]
        [int]$Minsegments,

        [Parameter()]
        [string]$Mediasourceid,

        [Parameter()]
        [string]$Deviceid,

        [Parameter()]
        [string]$Audiocodec,

        [Parameter()]
        [nullable[bool]]$Enableautostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowvideostreamcopy,

        [Parameter()]
        [nullable[bool]]$Allowaudiostreamcopy,

        [Parameter()]
        [nullable[bool]]$Breakonnonkeyframes,

        [Parameter()]
        [int]$Audiosamplerate,

        [Parameter()]
        [int]$Maxaudiobitdepth,

        [Parameter()]
        [int]$Audiobitrate,

        [Parameter()]
        [int]$Audiochannels,

        [Parameter()]
        [int]$Maxaudiochannels,

        [Parameter()]
        [string]$Profile,

        [Parameter()]
        [string]$Level,

        [Parameter()]
        [double]$Framerate,

        [Parameter()]
        [double]$Maxframerate,

        [Parameter()]
        [nullable[bool]]$Copytimestamps,

        [Parameter()]
        [int]$Starttimeticks,

        [Parameter()]
        [int]$Width,

        [Parameter()]
        [int]$Height,

        [Parameter()]
        [int]$Maxwidth,

        [Parameter()]
        [int]$Maxheight,

        [Parameter()]
        [int]$Videobitrate,

        [Parameter()]
        [int]$Subtitlestreamindex,

        [Parameter()]
        [string]$Subtitlemethod,

        [Parameter()]
        [int]$Maxrefframes,

        [Parameter()]
        [int]$Maxvideobitdepth,

        [Parameter()]
        [nullable[bool]]$Requireavc,

        [Parameter()]
        [nullable[bool]]$Deinterlace,

        [Parameter()]
        [nullable[bool]]$Requirenonanamorphic,

        [Parameter()]
        [int]$Transcodingmaxaudiochannels,

        [Parameter()]
        [int]$Cpucorelimit,

        [Parameter()]
        [string]$Livestreamid,

        [Parameter()]
        [nullable[bool]]$Enablempegtsm2tsmode,

        [Parameter()]
        [string]$Videocodec,

        [Parameter()]
        [string]$Subtitlecodec,

        [Parameter()]
        [string]$Transcodereasons,

        [Parameter()]
        [int]$Audiostreamindex,

        [Parameter()]
        [int]$Videostreamindex,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$Streamoptions,

        [Parameter()]
        [nullable[bool]]$Enableaudiovbrencoding
    )


    $path = '/Videos/{itemId}/stream.{container}'
    $path = $path -replace '\{itemId\}', $Itemid
    $path = $path -replace '\{container\}', $Container
    $queryParameters = @{}
    if ($PSBoundParameters.ContainsKey('Static')) { $queryParameters['static'] = $Static }
    if ($Params) { $queryParameters['params'] = $Params }
    if ($Tag) { $queryParameters['tag'] = $Tag }
    if ($Deviceprofileid) { $queryParameters['deviceProfileId'] = $Deviceprofileid }
    if ($Playsessionid) { $queryParameters['playSessionId'] = $Playsessionid }
    if ($Segmentcontainer) { $queryParameters['segmentContainer'] = $Segmentcontainer }
    if ($Segmentlength) { $queryParameters['segmentLength'] = $Segmentlength }
    if ($Minsegments) { $queryParameters['minSegments'] = $Minsegments }
    if ($Mediasourceid) { $queryParameters['mediaSourceId'] = $Mediasourceid }
    if ($Deviceid) { $queryParameters['deviceId'] = $Deviceid }
    if ($Audiocodec) { $queryParameters['audioCodec'] = $Audiocodec }
    if ($PSBoundParameters.ContainsKey('Enableautostreamcopy')) { $queryParameters['enableAutoStreamCopy'] = $Enableautostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowvideostreamcopy')) { $queryParameters['allowVideoStreamCopy'] = $Allowvideostreamcopy }
    if ($PSBoundParameters.ContainsKey('Allowaudiostreamcopy')) { $queryParameters['allowAudioStreamCopy'] = $Allowaudiostreamcopy }
    if ($PSBoundParameters.ContainsKey('Breakonnonkeyframes')) { $queryParameters['breakOnNonKeyFrames'] = $Breakonnonkeyframes }
    if ($Audiosamplerate) { $queryParameters['audioSampleRate'] = $Audiosamplerate }
    if ($Maxaudiobitdepth) { $queryParameters['maxAudioBitDepth'] = $Maxaudiobitdepth }
    if ($Audiobitrate) { $queryParameters['audioBitRate'] = $Audiobitrate }
    if ($Audiochannels) { $queryParameters['audioChannels'] = $Audiochannels }
    if ($Maxaudiochannels) { $queryParameters['maxAudioChannels'] = $Maxaudiochannels }
    if ($Profile) { $queryParameters['profile'] = $Profile }
    if ($Level) { $queryParameters['level'] = $Level }
    if ($Framerate) { $queryParameters['framerate'] = $Framerate }
    if ($Maxframerate) { $queryParameters['maxFramerate'] = $Maxframerate }
    if ($PSBoundParameters.ContainsKey('Copytimestamps')) { $queryParameters['copyTimestamps'] = $Copytimestamps }
    if ($Starttimeticks) { $queryParameters['startTimeTicks'] = $Starttimeticks }
    if ($Width) { $queryParameters['width'] = $Width }
    if ($Height) { $queryParameters['height'] = $Height }
    if ($Maxwidth) { $queryParameters['maxWidth'] = $Maxwidth }
    if ($Maxheight) { $queryParameters['maxHeight'] = $Maxheight }
    if ($Videobitrate) { $queryParameters['videoBitRate'] = $Videobitrate }
    if ($Subtitlestreamindex) { $queryParameters['subtitleStreamIndex'] = $Subtitlestreamindex }
    if ($Subtitlemethod) { $queryParameters['subtitleMethod'] = $Subtitlemethod }
    if ($Maxrefframes) { $queryParameters['maxRefFrames'] = $Maxrefframes }
    if ($Maxvideobitdepth) { $queryParameters['maxVideoBitDepth'] = $Maxvideobitdepth }
    if ($PSBoundParameters.ContainsKey('Requireavc')) { $queryParameters['requireAvc'] = $Requireavc }
    if ($PSBoundParameters.ContainsKey('Deinterlace')) { $queryParameters['deInterlace'] = $Deinterlace }
    if ($PSBoundParameters.ContainsKey('Requirenonanamorphic')) { $queryParameters['requireNonAnamorphic'] = $Requirenonanamorphic }
    if ($Transcodingmaxaudiochannels) { $queryParameters['transcodingMaxAudioChannels'] = $Transcodingmaxaudiochannels }
    if ($Cpucorelimit) { $queryParameters['cpuCoreLimit'] = $Cpucorelimit }
    if ($Livestreamid) { $queryParameters['liveStreamId'] = $Livestreamid }
    if ($PSBoundParameters.ContainsKey('Enablempegtsm2tsmode')) { $queryParameters['enableMpegtsM2TsMode'] = $Enablempegtsm2tsmode }
    if ($Videocodec) { $queryParameters['videoCodec'] = $Videocodec }
    if ($Subtitlecodec) { $queryParameters['subtitleCodec'] = $Subtitlecodec }
    if ($Transcodereasons) { $queryParameters['transcodeReasons'] = $Transcodereasons }
    if ($Audiostreamindex) { $queryParameters['audioStreamIndex'] = $Audiostreamindex }
    if ($Videostreamindex) { $queryParameters['videoStreamIndex'] = $Videostreamindex }
    if ($Context) { $queryParameters['context'] = $Context }
    if ($Streamoptions) { $queryParameters['streamOptions'] = $Streamoptions }
    if ($PSBoundParameters.ContainsKey('Enableaudiovbrencoding')) { $queryParameters['enableAudioVbrEncoding'] = $Enableaudiovbrencoding }

    $invokeParams = @{
        Path = $path
        Method = 'HEAD'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Invoke-JellyfinMergeVersions {
    <#
    .SYNOPSIS
            Merges videos into a single record.

    .DESCRIPTION
        API Endpoint: POST /Videos/MergeVersions
        Operation ID: MergeVersions
        Tags: Videos
    .PARAMETER Ids
        Item id list. This allows multiple, comma delimited.
    
    .EXAMPLE
        Invoke-JellyfinMergeVersions
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Ids
    )


    $path = '/Videos/MergeVersions'
    $queryParameters = @{}
    if ($Ids) { $queryParameters['ids'] = convertto-delimited $Ids ',' }

    $invokeParams = @{
        Path = $path
        Method = 'POST'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion

#region Years Functions (2 functions)

function Get-JellyfinYears {
    <#
    .SYNOPSIS
            Get years.

    .DESCRIPTION
        API Endpoint: GET /Years
        Operation ID: GetYears
        Tags: Years
    .PARAMETER Startindex
        Skips over a given number of items within the results. Use for paging.

    .PARAMETER Limit
        Optional. The maximum number of records to return.

    .PARAMETER Sortorder
        Sort Order - Ascending,Descending.

    .PARAMETER Parentid
        Specify this to localize the search to a specific item or folder. Omit to use the root.

    .PARAMETER Fields
        Optional. Specify additional fields of information to return in the output.

    .PARAMETER Excludeitemtypes
        Optional. If specified, results will be excluded based on item type. This allows multiple, comma delimited.

    .PARAMETER Includeitemtypes
        Optional. If specified, results will be included based on item type. This allows multiple, comma delimited.

    .PARAMETER Mediatypes
        Optional. Filter by MediaType. Allows multiple, comma delimited.

    .PARAMETER Sortby
        Optional. Specify one or more sort orders, comma delimited. Options: Album, AlbumArtist, Artist, Budget, CommunityRating, CriticRating, DateCreated, DatePlayed, PlayCount, PremiereDate, ProductionYear, SortName, Random, Revenue, Runtime.

    .PARAMETER Enableuserdata
        Optional. Include user data.

    .PARAMETER Imagetypelimit
        Optional. The max number of images to return, per image type.

    .PARAMETER Enableimagetypes
        Optional. The image types to include in the output.

    .PARAMETER Userid
        User Id.

    .PARAMETER Recursive
        Search recursively.

    .PARAMETER Enableimages
        Optional. Include image information in output.
    
    .EXAMPLE
        Get-JellyfinYears
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Startindex,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [ValidateSet('Ascending','Descending')]
        [string[]]$Sortorder,

        [Parameter()]
        [string]$Parentid,

        [Parameter()]
        [ValidateSet('AirTime','CanDelete','CanDownload','ChannelInfo','Chapters','Trickplay','ChildCount','CumulativeRunTimeTicks','CustomRating','DateCreated','DateLastMediaAdded','DisplayPreferencesId','Etag','ExternalUrls','Genres','ItemCounts','MediaSourceCount','MediaSources','OriginalTitle','Overview','ParentId','Path','People','PlayAccess','ProductionLocations','ProviderIds','PrimaryImageAspectRatio','RecursiveItemCount','Settings','SeriesStudio','SortName','SpecialEpisodeNumbers','Studios','Taglines','Tags','RemoteTrailers','MediaStreams','SeasonUserData','DateLastRefreshed','DateLastSaved','RefreshState','ChannelImage','EnableMediaSourceDisplay','Width','Height','ExtraIds','LocalTrailerCount','IsHD','SpecialFeatureCount')]
        [string[]]$Fields,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Excludeitemtypes,

        [Parameter()]
        [ValidateSet('AggregateFolder','Audio','AudioBook','BasePluginFolder','Book','BoxSet','Channel','ChannelFolderItem','CollectionFolder','Episode','Folder','Genre','ManualPlaylistsFolder','Movie','LiveTvChannel','LiveTvProgram','MusicAlbum','MusicArtist','MusicGenre','MusicVideo','Person','Photo','PhotoAlbum','Playlist','PlaylistsFolder','Program','Recording','Season','Series','Studio','Trailer','TvChannel','TvProgram','UserRootFolder','UserView','Video','Year')]
        [string[]]$Includeitemtypes,

        [Parameter()]
        [ValidateSet('Unknown','Video','Audio','Photo','Book')]
        [string[]]$Mediatypes,

        [Parameter()]
        [ValidateSet('Default','AiredEpisodeOrder','Album','AlbumArtist','Artist','DateCreated','OfficialRating','DatePlayed','PremiereDate','StartDate','SortName','Name','Random','Runtime','CommunityRating','ProductionYear','PlayCount','CriticRating','IsFolder','IsUnplayed','IsPlayed','SeriesSortName','VideoBitRate','AirTime','Studio','IsFavoriteOrLiked','DateLastContentAdded','SeriesDatePlayed','ParentIndexNumber','IndexNumber')]
        [string[]]$Sortby,

        [Parameter()]
        [nullable[bool]]$Enableuserdata,

        [Parameter()]
        [int]$Imagetypelimit,

        [Parameter()]
        [ValidateSet('Primary','Art','Backdrop','Banner','Logo','Thumb','Disc','Box','Screenshot','Menu','Chapter','BoxRear','Profile')]
        [string[]]$Enableimagetypes,

        [Parameter()]
        [string]$Userid,

        [Parameter()]
        [nullable[bool]]$Recursive,

        [Parameter()]
        [nullable[bool]]$Enableimages
    )


    $path = '/Years'
    $queryParameters = @{}
    if ($Startindex) { $queryParameters['startIndex'] = $Startindex }
    if ($Limit) { $queryParameters['limit'] = $Limit }
    if ($Sortorder) { $queryParameters['sortOrder'] = convertto-delimited $Sortorder ',' }
    if ($Parentid) { $queryParameters['parentId'] = $Parentid }
    if ($Fields) { $queryParameters['fields'] = convertto-delimited $Fields ',' }
    if ($Excludeitemtypes) { $queryParameters['excludeItemTypes'] = convertto-delimited $Excludeitemtypes ',' }
    if ($Includeitemtypes) { $queryParameters['includeItemTypes'] = convertto-delimited $Includeitemtypes ',' }
    if ($Mediatypes) { $queryParameters['mediaTypes'] = convertto-delimited $Mediatypes ',' }
    if ($Sortby) { $queryParameters['sortBy'] = convertto-delimited $Sortby ',' }
    if ($PSBoundParameters.ContainsKey('Enableuserdata')) { $queryParameters['enableUserData'] = $Enableuserdata }
    if ($Imagetypelimit) { $queryParameters['imageTypeLimit'] = $Imagetypelimit }
    if ($Enableimagetypes) { $queryParameters['enableImageTypes'] = convertto-delimited $Enableimagetypes ',' }
    if ($Userid) { $queryParameters['userId'] = $Userid }
    if ($PSBoundParameters.ContainsKey('Recursive')) { $queryParameters['recursive'] = $Recursive }
    if ($PSBoundParameters.ContainsKey('Enableimages')) { $queryParameters['enableImages'] = $Enableimages }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
function Get-JellyfinYear {
    <#
    .SYNOPSIS
            Gets a year.

    .DESCRIPTION
        API Endpoint: GET /Years/{year}
        Operation ID: GetYear
        Tags: Years
    .PARAMETER Year
        Path parameter: year

    .PARAMETER Userid
        Optional. Filter by user id, and attach user data.
    
    .EXAMPLE
        Get-JellyfinYear
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]$Year,

        [Parameter()]
        [string]$Userid
    )


    $path = '/Years/{year}'
    $path = $path -replace '\{year\}', $Year
    $queryParameters = @{}
    if ($Userid) { $queryParameters['userId'] = $Userid }

    $invokeParams = @{
        Path = $path
        Method = 'GET'
        QueryParameters = $queryParameters
    }

    Invoke-JellyfinRequest @invokeParams
}
#endregion



