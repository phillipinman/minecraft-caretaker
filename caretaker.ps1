$ErrorActionPreference = "Stop"
# Fixes a silly bug Microsoft never bothered to fix in 5.1 which is slow downloads if you have the progress bar shown. -_-
$ProgressPreference = 'SilentlyContinue'

<#
Make the staging server directory which we will use for a testing server before we deploy to prod.
#>
function New-ServerDirectory() {
    if (-Not (Test-Path -Path "./staging-server")) {
        New-Item -Name "staging-server" -ItemType "Directory"
    }
}

<#
We get the latest Minecraft version group, like 1.18.2, and then get the latest build from paper.io.
Paper doesnt provide a direct link for the latest download and according to people on the fourms no one should be auto updating anyways, I disagree and have other things to do than to update the server manually every week, as im sure you do.
#>
function Get-LatestServerVersion() {
    $versionResponse = Invoke-WebRequest -Uri "https://papermc.io/api/v2/projects/paper" | ConvertFrom-Json
    $buildResponse = Invoke-WebRequest -Uri "https://papermc.io/api/v2/projects/paper/versions/$($versionResponse.versions[-1])" | ConvertFrom-Json
    $downloadNameResponse = Invoke-WebRequest -Uri "https://papermc.io/api/v2/projects/paper/versions/$($versionResponse.versions[-1])/builds/$($buildResponse.builds[-1])" | ConvertFrom-Json

    if (-Not (Test-Path -Path "./staging-server/server.jar")) {
        Write-Output "Downloading Latest Server Jar"
        Invoke-WebRequest -Uri "https://papermc.io/api/v2/projects/paper/versions/$($versionResponse.versions[-1])/builds/$($buildResponse.builds[-1])/downloads/$($downloadNameResponse.downloads.application.name)" -Outfile "./staging-server/server.jar"
    }
    else {
        if (-Not ($($(Get-FileHash -Path "./staging-server/server.jar" -Algorithm SHA256).Hash.ToLower()) -eq ($($downloadNameResponse.downloads.application.sha256)))) {
            Write-Output "File Hash does not Match!"
            Write-Output "Downloading Latest Server Jar"
            Invoke-WebRequest -Uri "https://papermc.io/api/v2/projects/paper/versions/$($versionResponse.versions[-1])/builds/$($buildResponse.builds[-1])/downloads/$($downloadNameResponse.downloads.application.name)" -Outfile "./staging-server/server.jar"
        }
    }
}

<#
Lets generate our start files with Aikar's recommended flags.
#>
function New-ServerStartFile() {
    if (-Not (Test-Path -Path "./staging-server/start.*")) {
        $flags = "java -Xms4G -Xmx4G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar server.jar nogui"
        $flags | Out-File -FilePath "./staging-server/start.sh"
        $flags | Out-File -FilePath "./staging-server/start.bat"
    }
}

<#
Consent to stuff you don't understand or care about. Is this legally binding if someone under the age of 18 runs a server?
#>
function New-MinecraftEULA() {
    if (-Not (Test-Path -Path "./staging-server/eula.txt")) {
        "eula=true" | Out-File -FilePath "./staging-server/eula.txt"
    }
}

<#
Creates the Ops File so that servers that get deployed don't lose their OPs. This can be removed if permissions are handled by a plugin in a Database.
#>
function New-OPsFile() {
    if (-Not (Test-Path -Path "./staging-server/ops.json")) {
@'
[
    {
        "uuid": "",
        "name": "Player",
        "level": 4,
        "bypassesPlayerLimit": false
    }
]
'@ | Out-File -FilePath "./staging-server/ops.json"
    }
}

<#
We create the server.properties file to enable our datapack to execute high permission commands, specifically the /stop command for automated testing of the server.
#>
function New-ServerPropertiesFile() {
    if (-Not (Test-Path -Path "./staging-server/server.properties")) {
@'
function-permission-level=4
'@ | Out-File -FilePath "./staging-server/server.properties"
    }
}

<#
Lets take the files in /datapacks/shutdown and turn it into a datapack we can use to shutdown the server automatically, for testing reasons.
#>
function New-TestingDataPack() {

    if (-Not (Test-Path -Path "./staging-server/world/datapacks")) {
        New-Item -Name "datapacks" -ItemType "Directory" -Path "./staging-server/world/"
        Compress-Archive -Path "./datapacks/shutdown/*" -Destination "./staging-server/world/datapacks/shutdown.zip"
    }
}

<#
We need to test the downloaded JAR to make sure it actually loads a server successfully before we update our production files.
If it exits with any other code except 0 we assume something went wrong. Simple in practice and if we need to know the reason for the crash we can just check the crash logs.
#>
function Test-MinecraftServerBuild() {
    Start-Process -FilePath "./staging-server/start.bat" -WorkingDirectory "./staging-server" -Wait

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Test Server Exited with Error! Manually review the crash log."
        Exit 1
    }
    else {
        Write-Output "Test Server Exited Normally"
    }
}

<#
Here we assume that the server layout is server*. For every folder that matches we copy our successfully tested server files into these folders.
#>
function Update-ServerFiles() {

    Get-ChildItem -Path "./server*" -Directory | ForEach-Object -Process {
        Copy-Item -Path "./staging-server/*" -Destination "./$($_.name)" -Recurse -Force
    }
}

New-ServerDirectory
Get-LatestServerVersion
New-ServerStartFile
New-MinecraftEULA
New-OPsFile
New-ServerPropertiesFile

New-TestingDataPack
#Test-MinecraftServerBuild

Update-ServerFiles