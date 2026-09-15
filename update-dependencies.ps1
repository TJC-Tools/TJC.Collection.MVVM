$ErrorActionPreference = 'Stop'

$repositoryRoot = $PSScriptRoot
$repositoryName = Split-Path -Leaf $repositoryRoot
$projectPath = Join-Path $repositoryRoot "$repositoryName\$repositoryName.csproj"
$branchName = 'update-dependencies'

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    & git -C $repositoryRoot @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Invoke-Dotnet {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path -LiteralPath $projectPath)) {
    throw "Project file not found: $projectPath"
}

$originalBranch = (& git -C $repositoryRoot branch --show-current).Trim()
$worktreeStatus = & git -C $repositoryRoot status --porcelain
if ($worktreeStatus) {
    throw 'The working tree is not clean. Commit or stash existing changes before running this script.'
}

try {
    Invoke-Git @('checkout', 'main')
    Invoke-Git @('pull', '--ff-only', 'origin', 'main')

    $existingBranch = & git -C $repositoryRoot branch --list $branchName
    if ($existingBranch) {
        Invoke-Git @('branch', '-D', $branchName)
    }

    Invoke-Git @('checkout', '-b', $branchName)

    [xml] $project = Get-Content -LiteralPath $projectPath
    $packageReferences = @($project.SelectNodes('//PackageReference'))
    if ($packageReferences.Count -eq 0) {
        throw "No PackageReference entries found in $projectPath"
    }

    foreach ($packageReference in $packageReferences) {
        $packageId = $packageReference.GetAttribute('Include')
        if ([string]::IsNullOrWhiteSpace($packageId)) {
            throw "A PackageReference in $projectPath has no Include value."
        }

        Write-Host "Updating $packageId..."
        Invoke-Dotnet @('add', $projectPath, 'package', $packageId)
    }

    $updatedFiles = & git -C $repositoryRoot status --porcelain
    if (-not $updatedFiles) {
        Write-Host 'All packages are already up to date; nothing to commit.'
    }
    else {
        Invoke-Git @('add', $projectPath)
        Invoke-Git @('commit', '-m', 'chore: update dependencies')
        Invoke-Git @('push', '--set-upstream', 'origin', $branchName)
    }
}
finally {
    $currentBranch = (& git -C $repositoryRoot branch --show-current).Trim()
    if ($currentBranch -eq $branchName) {
        Invoke-Git @('checkout', 'main')
    }
    elseif ($currentBranch -ne 'main' -and $originalBranch -eq 'main') {
        Invoke-Git @('checkout', 'main')
    }
}

Start-Process "https://github.com/TJC-Tools/$repositoryName/compare/main...$branchName"