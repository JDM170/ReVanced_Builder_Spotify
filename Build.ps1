<#
    .SYNOPSIS
    Build ReVanced app using latest components:
      * YouTube (latest supported);
      * ReVanced CLI;
      * ReVanced Patches;
      * ReVanced Integrations;
      * ReVanced microG GmsCore;
      * Azul Zulu.

    .NOTES
    After compiling, microg.apk and compiled revanced.apk will be located in "Script location folder folder\ReVanced"

    .LINKS
    https://github.com/revanced
#>

# Requires -Version 5.1
# Doesn't work on PowerShell 7.2 due it doesn't contains IE parser engine. You have to use a 3rd party module to make it work like it's presented in CI/CD config: AngleSharp

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($Host.Version.Major -eq 5)
{
    # Progress bar can significantly impact cmdlet performance
    # https://github.com/PowerShell/PowerShell/issues/2138
    $Script:ProgressPreference = "SilentlyContinue"
}

# Download all files to "Script location folder\ReVanced"
$CurrentFolder = Split-Path $MyInvocation.MyCommand.Path -Parent
if (-not (Test-Path -Path "$CurrentFolder\ReVanced"))
{
    New-Item -Path "$CurrentFolder\ReVanced" -ItemType Directory -Force
}

$LatestSupported = "9-0-44-478"

Write-Verbose -Message "" -Verbose
Write-Verbose -Message "Downloading the latest supported Spotify apk" -Verbose
# We need a NON-bundle version
# https://www.apkmirror.com/apk/spotify-ab/spotify-music-podcasts/
$apkMirrorLink = "https://www.apkmirror.com/apk/spotify-ab/spotify-music-podcasts/spotify-music-and-podcasts-$LatestSupported-release/"
$Parameters = @{
    Uri             = $apkMirrorLink
    UseBasicParsing = $false # Disabled
    Verbose         = $true
}
$Request = Invoke-Webrequest @Parameters
$Request.ParsedHtml.getElementsByClassName("table-row headerFont") | ForEach-Object -Process {
    foreach ($child in $_.children)
    {
        if ($child.innerText -eq "nodpi")
        {
            $apkPackageLink = ($_.getElementsByTagName("a") | Select-Object -First 1).nameProp
            break
        }
    }
}
$apkMirrorLink += $apkPackageLink # actual APK link (not BUNDLE)

# Get unique key to generate direct link
$Parameters = @{
    Uri             = $apkMirrorLink
    UseBasicParsing = $false # Disabled
    Verbose         = $true
}
$Request = Invoke-Webrequest @Parameters
$nameProp = $Request.ParsedHtml.getElementsByClassName("accent_bg btn btn-flat downloadButton") | ForEach-Object -Process {$_.nameProp}

$Parameters = @{
    Uri = $apkMirrorLink + "/download/$($nameProp)"
    UseBasicParsing = $false # Disabled
    Verbose         = $true
}
$URL_Part = ((Invoke-Webrequest @Parameters).Links | Where-Object -FilterScript {$_.innerHTML -eq "here"}).href
# Replace "&amp;" with "&" to make it work
$URL_Part = $URL_Part.Replace("&amp;", "&")

# Finally, get the real link
$Parameters = @{
    Uri             = "https://www.apkmirror.com$URL_Part"
    OutFile         = "$CurrentFolder\ReVanced\spotify.apk"
    UseBasicParsing = $true
    Verbose         = $true
}
Invoke-Webrequest @Parameters

Write-Verbose -Message "" -Verbose
Write-Verbose -Message "Downloading ReVanced CLI" -Verbose
# https://github.com/revanced/revanced-cli
$Parameters = @{
    Uri             = "https://api.github.com/repos/revanced/revanced-cli/releases/latest"
    UseBasicParsing = $true
    Verbose         = $true
}
$URL = ((Invoke-RestMethod @Parameters).assets | Where-Object -FilterScript {$_.content_type -eq "application/java-archive"}).browser_download_url
$Parameters = @{
    Uri             = $URL
    Outfile         = "$CurrentFolder\ReVanced\revanced-cli.jar"
    UseBasicParsing = $true
    Verbose         = $true
}
Invoke-RestMethod @Parameters

Write-Verbose -Message "" -Verbose
Write-Verbose -Message "Downloading ReVanced patches" -Verbose
# https://github.com/revanced/revanced-patches
$Parameters = @{
    Uri             = "https://api.github.com/repos/revanced/revanced-patches/releases/latest"
    UseBasicParsing = $true
    Verbose         = $true
}
$URL = ((Invoke-RestMethod @Parameters).assets | Where-Object -FilterScript {$_.content_type -eq "text/plain"}).browser_download_url
$Parameters = @{
    Uri             = $URL
    Outfile         = "$CurrentFolder\ReVanced\revanced-patches.rvp"
    UseBasicParsing = $true
    Verbose         = $true
}
Invoke-RestMethod @Parameters

# Sometimes older version of zulu-jdk causes conflict, so remove older version before proceeding.
if (Test-Path -Path "$CurrentFolder\ReVanced\jdk")
{
    Remove-Item -Path "$CurrentFolder\ReVanced\jdk" -Recurse -Force
}

Write-Verbose -Message "" -Verbose
Write-Verbose -Message "Downloading Azul Zulu" -Verbose
# https://github.com/ScoopInstaller/Java/blob/master/bucket/zulu-jdk.json
$Parameters = @{
    Uri             = "https://raw.githubusercontent.com/ScoopInstaller/Java/master/bucket/zulu-jdk.json"
    UseBasicParsing = $true
    Verbose         = $true
}
$URL = (Invoke-RestMethod @Parameters).architecture."64bit".url
$Parameters = @{
    Uri             = $URL
    Outfile         = "$CurrentFolder\ReVanced\jdk_windows-x64_bin.zip"
    UseBasicParsing = $true
    Verbose         = $true
}
Invoke-RestMethod @Parameters

# Expand jdk_windows-x64_bin archive
$Parameters = @{
    Path            = "$CurrentFolder\ReVanced\jdk_windows-x64_bin.zip"
    DestinationPath = "$CurrentFolder\ReVanced\jdk"
    Force           = $true
    Verbose         = $true
}
Expand-Archive @Parameters

Remove-Item -Path "$CurrentFolder\ReVanced\jdk_windows-x64_bin.zip" -Force

# Let's create patched APK
& "$CurrentFolder\ReVanced\jdk\zulu*win_x64\bin\java.exe" `
-jar "$CurrentFolder\ReVanced\revanced-cli.jar" patch `
--patches "$CurrentFolder\ReVanced\revanced-patches.rvp" `
--disable "Custom theme" `
--purge `
--temporary-files-path "$CurrentFolder\ReVanced\Temp" `
--out "$CurrentFolder\ReVanced\revanced_spotify.apk" `
"$CurrentFolder\ReVanced\spotify.apk"

# Open working directory with builded files
# Invoke-Item -Path "$CurrentFolder\ReVanced"

# Remove temp directory, because cli failed to clean up directory
# Remove-Item -Path "$CurrentFolder\ReVanced\Temp" -Recurse -Force -Confirm:$false

$Files = @(
    "$CurrentFolder\ReVanced\Temp",
    "$CurrentFolder\ReVanced\jdk",
    "$CurrentFolder\ReVanced\revanced-cli.jar",
    "$CurrentFolder\ReVanced\revanced-patches.rvp",
    "$CurrentFolder\ReVanced\spotify.apk"
)
Remove-Item -Path $Files -Recurse -Force

Write-Warning -Message "Latest available revanced_spotify.apk & microg.apk are ready in `"$CurrentFolder\ReVanced`""
