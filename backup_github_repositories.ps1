﻿<#

.SYNOPSIS
Automatically backups all remote GitHub repositories.

.DESCRIPTION
This script automatically backups all remote GitHub repositories of a user or an organisation to a local directory.

.PARAMETER userName
Specifies the GitHub user name.

.PARAMETER userSecret
Specifies the password or personal access token of the GitHub user.

.PARAMETER organisationName
Specifies the optional GitHub organisation name.

.PARAMETER backupDirectory
Overrides the default backup directory.

.EXAMPLE
.\backup_github_repositories.ps1 -userName "user" -userSecret "secret"

.EXAMPLE
.\backup_github_repositories.ps1 -userName "user" -userSecret "secret" -organisationName "organisation"

.EXAMPLE
.\backup_github_repositories.ps1 -backupDirectory "C:\myBackupDirectory"

#>
[CmdletBinding()]
Param (

    [Parameter(
        Mandatory=$true,
        HelpMessage="The name of a GitHub user that has access to the GitHub API."
    )]
    [string]$userName,

    [Parameter(
        Mandatory=$true,
        HelpMessage="The password or personal access token of the GitHub user."
    )]
    [string]$userSecret,

    [string]$organisationName,

    [string]$backupDirectory = $(Join-Path -Path $PSScriptRoot -ChildPath $(Get-Date -UFormat "%Y-%m-%d"))
)

#
# Clone a remote GitHub repository into a local directory.
#
# @see https://git-scm.com/docs/git-clone#git-clone---mirror
#
function Backup-GitHubRepository([string] $fullName, [string] $directory) {

    Write-Host "Starting backup of https://github.com/${fullName} to ${directory}..." -ForegroundColor DarkYellow

    git clone --mirror "git@github.com:${fullName}.git" "${directory}"
}

#
# Calculate the total repositories size in megabytes based on GitHubs 'size' property.
#
function Get-TotalRepositoriesSizeInMegabytes([object] $repositories) {

    $totalSizeInKilobytes = 0
    ForEach ($repository in $repositories) {
        $totalSizeInKilobytes += $repository.size
    }

    $([math]::Round($totalSizeInKilobytes/1024))
}

# Measure the execution time of the backup script.
$stopwatch = [System.Diagnostics.Stopwatch]::startNew()

# Use TLS v1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#
# Use different API endpoints for user and organisation repositories.
#
# @see https://developer.github.com/v3/repos/#list-organization-repositories
# @see https://developer.github.com/v3/repos/#list-your-repositories
#
if($organisationName) {

    $gitHubRepositoriesUrl = "https://api.github.com/orgs/${organisationName}/repos?type=all&per_page=100&page=1"

} else {

    $gitHubRepositoriesUrl = "https://api.github.com/user/repos?affiliation=owner&per_page=100&page=1"
}

#
# Compose a Basic Authentication request header.
#
# @see https://developer.github.com/v3/auth/#basic-authentication
#
$basicAuthenticationCredentials = "${userName}:${userSecret}"
$encodedBasicAuthenticationCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($basicAuthenticationCredentials))
$requestHeaders = @{
    Authorization = "Basic $encodedBasicAuthenticationCredentials"
}

# Request the GitHub API to get all repositories of a user or an organisation.
Write-Host "Requesting '${gitHubRepositoriesUrl}'..." –foregroundcolor Yellow
$repositories = Invoke-WebRequest -Uri $gitHubRepositoriesUrl -Headers $requestHeaders | Select-Object -ExpandProperty Content | ConvertFrom-Json

# Print a userfriendly message what will happen next.
$totalSizeInMegabytes = Get-TotalRepositoriesSizeInMegabytes -repositories $repositories
Write-Host "Cloning $($repositories.Count) repositories (~${totalSizeInMegabytes} MB) into '${backupDirectory}'..." –foregroundcolor Yellow

# Clone each repository into the backup directory.
ForEach ($repository in $repositories) {

    Backup-GitHubRepository -FullName $repository.full_name `
                            -Directory $(Join-Path -Path $backupDirectory -ChildPath $repository.name)
}

$stopwatch.Stop()
$durationInSeconds = $stopwatch.Elapsed.Seconds
Write-Host "Successfully finished the backup in ${durationInSeconds} seconds..." –foregroundcolor Yellow
