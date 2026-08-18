[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Profile = "all",

    [switch]$DryRun,

    [switch]$SkipExtensions
)

$ErrorActionPreference = "Stop"

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$profilesSourceDirectory = Join-Path $repositoryRoot "windows\vscode\profiles"
$vscodeUserDirectory = Join-Path $env:APPDATA "Code\User"
$profilesTargetDirectory = Join-Path $vscodeUserDirectory "profiles"
$profileRegistryPath = Join-Path $vscodeUserDirectory "globalStorage\storage.json"

if (-not (Test-Path -LiteralPath $profilesSourceDirectory)) {
    throw "Windows VS Code Profile source directory not found: $profilesSourceDirectory"
}

if (-not (Test-Path -LiteralPath $vscodeUserDirectory)) {
    throw "VS Code user directory not found: $vscodeUserDirectory"
}

$availableProfiles = @(Get-ChildItem -Directory -LiteralPath $profilesSourceDirectory | Sort-Object Name)
$selectedProfiles = if ($Profile -ieq "all") {
    $availableProfiles
} else {
    @($availableProfiles | Where-Object Name -IEQ $Profile)
}

if ($selectedProfiles.Count -eq 0) {
    $availableNames = ($availableProfiles.Name -join ", ")
    throw "Unknown Windows VS Code Profile '$Profile'. Available Profiles: $availableNames, all"
}

function Set-ProfileFile {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$DisplayName
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return
    }

    $changed = -not (Test-Path -LiteralPath $TargetPath)
    if (-not $changed) {
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePath).Hash
        $targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $TargetPath).Hash
        $changed = $sourceHash -ne $targetHash
    }

    if (-not $changed) {
        Write-Verbose "Already current: $DisplayName"
        return
    }

    if ($DryRun) {
        Write-Host "[dry-run] Would update $DisplayName"
        return
    }

    $targetParent = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $targetParent)) {
        New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
    }

    Copy-Item -Force -LiteralPath $SourcePath -Destination $TargetPath
    Write-Host "Updated $DisplayName"
}

function Install-ProfileExtensions {
    param(
        [Parameter(Mandatory)][System.Management.Automation.ApplicationInfo]$CodeCommand,
        [Parameter(Mandatory)][string]$ExtensionsPath,
        [Parameter(Mandatory)][string]$DisplayName,
        [string]$CodeProfileName
    )

    if (-not (Test-Path -LiteralPath $ExtensionsPath)) {
        return
    }

    $extensionInventory = Get-Content -Raw -Encoding utf8 -LiteralPath $ExtensionsPath |
        ConvertFrom-Json
    $desiredExtensions = @(
        foreach ($extension in $extensionInventory) {
            $extensionId = ([string]$extension).Trim()
            if ($extensionId) {
                $extensionId
            }
        }
    ) | Sort-Object -Unique

    $listArguments = @("--list-extensions")
    if ($CodeProfileName) {
        $listArguments = @("--profile", $CodeProfileName) + $listArguments
    }

    $installedExtensions = @(& $CodeCommand.Source @listArguments)
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list extensions for VS Code Profile '$DisplayName'."
    }

    $missingExtensions = @(
        $desiredExtensions | Where-Object { $installedExtensions -inotcontains $_ }
    )

    if ($DryRun) {
        foreach ($extensionId in $missingExtensions) {
            Write-Host "[dry-run] Would install '$extensionId' for '$DisplayName'"
        }
        return
    }

    if ($missingExtensions.Count -eq 0) {
        return
    }

    $installArguments = @()
    if ($CodeProfileName) {
        $installArguments += @("--profile", $CodeProfileName)
    }
    foreach ($extensionId in $missingExtensions) {
        $installArguments += @("--install-extension", $extensionId)
    }
    $installArguments += "--force"

    Write-Host "Installing $($missingExtensions.Count) extension(s) for '$DisplayName'..."
    & $CodeCommand.Source @installArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install extensions for VS Code Profile '$DisplayName': $($missingExtensions -join ', ')"
    }
}

$namedProfilesSelected = @($selectedProfiles | Where-Object Name -INE "default").Count -gt 0
$registeredProfiles = @()
if ($namedProfilesSelected) {
    if (-not (Test-Path -LiteralPath $profileRegistryPath)) {
        throw "VS Code Profile registry not found: $profileRegistryPath"
    }

    $storage = Get-Content -Raw -Encoding utf8 -LiteralPath $profileRegistryPath | ConvertFrom-Json
    $registeredProfiles = @($storage.userDataProfiles | Where-Object {
        $_.location -and $_.location -notlike "builtin/*"
    })
}

$codeCommand = if ($SkipExtensions) {
    $null
} else {
    Get-Command code -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

if (-not $SkipExtensions -and -not $codeCommand) {
    Write-Warning "The 'code' command was not found; extension synchronization was skipped."
}

foreach ($sourceProfile in $selectedProfiles) {
    $isDefault = $sourceProfile.Name -ieq "default"
    $displayName = if ($isDefault) { "Default" } else { $sourceProfile.Name }
    $codeProfileName = $null

    if ($isDefault) {
        $targetProfileDirectory = $vscodeUserDirectory
    } else {
        $profileMatches = @($registeredProfiles | Where-Object { $_.name -ieq $sourceProfile.Name })
        if ($profileMatches.Count -ne 1) {
            $message = "VS Code Profile '$($sourceProfile.Name)' was not found by exact name."
            if ($Profile -ieq "all") {
                Write-Warning "$message Skipping it."
                continue
            }
            throw $message
        }

        $registeredProfile = $profileMatches[0]
        $targetProfileDirectory = Join-Path $profilesTargetDirectory $registeredProfile.location
        $codeProfileName = [string]$registeredProfile.name

        if (-not (Test-Path -LiteralPath $targetProfileDirectory)) {
            throw "Target directory for VS Code Profile '$displayName' does not exist: $targetProfileDirectory"
        }
    }

    if ($codeCommand) {
        Install-ProfileExtensions `
            -CodeCommand $codeCommand `
            -ExtensionsPath (Join-Path $sourceProfile.FullName "extensions.json") `
            -DisplayName $displayName `
            -CodeProfileName $codeProfileName
    }

    # Installing an extension can change Profile settings (for example, an icon
    # theme may select itself). Apply the repository files last so they win.
    Set-ProfileFile `
        -SourcePath (Join-Path $sourceProfile.FullName "settings.json") `
        -TargetPath (Join-Path $targetProfileDirectory "settings.json") `
        -DisplayName "$displayName settings"

    if ($isDefault) {
        Set-ProfileFile `
            -SourcePath (Join-Path $sourceProfile.FullName "keybindings.json") `
            -TargetPath (Join-Path $targetProfileDirectory "keybindings.json") `
            -DisplayName "$displayName keybindings"
    }
}

Write-Host "Windows VS Code Profile apply completed."
