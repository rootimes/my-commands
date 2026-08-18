[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [Alias("Profile")]
    [string]$ProfileName = "all",

    [switch]$DryRun,
    [switch]$SkipExtensions
)

$ErrorActionPreference = "Stop"

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$vscodeUserDirectory = Join-Path $env:APPDATA "Code\User"
$profileRegistryPath = Join-Path $vscodeUserDirectory "globalStorage\storage.json"
$liveProfilesDirectory = Join-Path $vscodeUserDirectory "profiles"
$sourceProfilesDirectory = Join-Path $repositoryRoot "windows\vscode\profiles"
$defaultProfileSourceDirectory = Join-Path $sourceProfilesDirectory "default"
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

function Set-RepositoryFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $normalizedContent = ($Content -replace "`r`n", "`n").TrimEnd("`r", "`n") + "`n"
    $currentContent = if (Test-Path -LiteralPath $Path) {
        (Get-Content -Raw -Encoding utf8 -LiteralPath $Path) -replace "`r`n", "`n"
    } else {
        $null
    }

    if ($null -ne $currentContent -and $currentContent -ceq $normalizedContent) {
        Write-Verbose "Unchanged: $Path"
        return
    }

    if ($DryRun) {
        Write-Host "[dry-run] Would update $Path"
        return
    }

    $parentDirectory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parentDirectory)) {
        New-Item -ItemType Directory -Force -Path $parentDirectory | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $normalizedContent, $utf8WithoutBom)
    Write-Host "Updated $Path"
}

function ConvertTo-ExtensionInventory {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExtensionIds)

    if ($ExtensionIds.Count -eq 0) {
        return "[]"
    }

    return ConvertTo-Json -InputObject @($ExtensionIds) -Depth 2
}

function Get-VSCodeExtensions {
    param(
        [Parameter(Mandatory)][System.Management.Automation.ApplicationInfo]$CodeCommand,
        [string]$ProfileName
    )

    $arguments = @("--list-extensions")
    if ($ProfileName) {
        $arguments = @("--profile", $ProfileName) + $arguments
    }

    $extensionIds = @(& $CodeCommand.Source @arguments)
    if ($LASTEXITCODE -ne 0) {
        $target = if ($ProfileName) { "profile '$ProfileName'" } else { "the Default Profile" }
        throw "Failed to list extensions for $target."
    }

    return @(
        $extensionIds |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

if (-not (Test-Path -LiteralPath $vscodeUserDirectory)) {
    throw "VS Code user directory not found: $vscodeUserDirectory"
}

if (-not (Test-Path -LiteralPath $profileRegistryPath)) {
    throw "VS Code profile registry not found: $profileRegistryPath"
}

if (-not (Test-Path -LiteralPath $sourceProfilesDirectory)) {
    throw "Repository profile directory not found: $sourceProfilesDirectory"
}

if (-not (Test-Path -LiteralPath $defaultProfileSourceDirectory)) {
    throw "Default Profile source directory not found: $defaultProfileSourceDirectory"
}

$includeDefault = $ProfileName -ieq "all" -or $ProfileName -ieq "default"
if ($includeDefault) {
    $defaultSettingsPath = Join-Path $vscodeUserDirectory "settings.json"
    if (Test-Path -LiteralPath $defaultSettingsPath) {
        $defaultSettings = Get-Content -Raw -Encoding utf8 -LiteralPath $defaultSettingsPath
        Set-RepositoryFile `
            -Path (Join-Path $defaultProfileSourceDirectory "settings.json") `
            -Content $defaultSettings
    }

    $defaultKeybindingsPath = Join-Path $vscodeUserDirectory "keybindings.json"
    if (Test-Path -LiteralPath $defaultKeybindingsPath) {
        $defaultKeybindings = Get-Content -Raw -Encoding utf8 -LiteralPath $defaultKeybindingsPath
        Set-RepositoryFile `
            -Path (Join-Path $defaultProfileSourceDirectory "keybindings.json") `
            -Content $defaultKeybindings
    }
}

$codeCommand = if ($SkipExtensions) {
    $null
} else {
    Get-Command code -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

if (-not $SkipExtensions -and -not $codeCommand) {
    throw "The 'code' command was not found. Use -SkipExtensions to sync settings only."
}

if ($codeCommand -and $includeDefault) {
    $defaultExtensions = @(Get-VSCodeExtensions -CodeCommand $codeCommand)
    Set-RepositoryFile `
        -Path (Join-Path $defaultProfileSourceDirectory "extensions.json") `
        -Content (ConvertTo-ExtensionInventory -ExtensionIds $defaultExtensions)
}

$storage = Get-Content -Raw -Encoding utf8 -LiteralPath $profileRegistryPath | ConvertFrom-Json
$registeredProfiles = @($storage.userDataProfiles | Where-Object {
    $_.location -and $_.location -notlike "builtin/*"
})

$selectedRegisteredProfiles = @(
    if ($ProfileName -ieq "all") {
        $registeredProfiles
    } elseif ($ProfileName -ine "default") {
        $registeredProfiles | Where-Object { $_.name -ieq $ProfileName }
    }
)

if ($ProfileName -ine "all" -and $ProfileName -ine "default" -and
    $selectedRegisteredProfiles.Count -ne 1) {
    $availableNames = (@("default") + @($registeredProfiles.name) + @("all")) -join ", "
    throw "Unknown VS Code Profile '$ProfileName'. Available Profiles: $availableNames"
}

$sourceProfiles = @(
    Get-ChildItem -Directory -LiteralPath $sourceProfilesDirectory |
        Where-Object Name -INE "default"
)

foreach ($profile in $selectedRegisteredProfiles | Sort-Object name) {
    if ($profile.name -ieq "default") {
        Write-Warning "Named VS Code Profile '$($profile.name)' conflicts with the reserved Default source folder; skipping it."
        continue
    }

    $sourceMatches = @($sourceProfiles | Where-Object { $_.Name -ieq $profile.name })
    if ($sourceMatches.Count -gt 1) {
        Write-Warning "Multiple source folders match VS Code Profile '$($profile.name)'; skipping it."
        continue
    }

    $sourceProfileDirectory = if ($sourceMatches.Count -eq 1) {
        $sourceMatches[0].FullName
    } else {
        $directoryName = ([string]$profile.name).ToLowerInvariant()
        if ($directoryName -in @("", ".", "..") -or
            $directoryName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            Write-Warning "VS Code Profile name '$($profile.name)' cannot be used as a source directory; skipping it."
            continue
        }

        Join-Path $sourceProfilesDirectory $directoryName
    }

    $liveProfileDirectory = Join-Path $liveProfilesDirectory $profile.location
    $liveSettingsPath = Join-Path $liveProfileDirectory "settings.json"

    if (Test-Path -LiteralPath $liveSettingsPath) {
        $settings = Get-Content -Raw -Encoding utf8 -LiteralPath $liveSettingsPath
        Set-RepositoryFile `
            -Path (Join-Path $sourceProfileDirectory "settings.json") `
            -Content $settings
    } else {
        Set-RepositoryFile `
            -Path (Join-Path $sourceProfileDirectory "settings.json") `
            -Content "{}"
    }

    if ($codeCommand) {
        $profileExtensions = @(Get-VSCodeExtensions `
            -CodeCommand $codeCommand `
            -ProfileName ([string]$profile.name))
        Set-RepositoryFile `
            -Path (Join-Path $sourceProfileDirectory "extensions.json") `
            -Content (ConvertTo-ExtensionInventory -ExtensionIds $profileExtensions)
    }
}

Write-Host "VS Code configuration capture completed."
