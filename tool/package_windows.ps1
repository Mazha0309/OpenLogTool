[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Version,

    [string]$BuildDirectory = "build/windows/x64/runner/Release",

    [string]$OutputDirectory = "dist",

    [switch]$SmokeTest
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Resolve-FromRepository([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

$bundleDirectory = Resolve-FromRepository $BuildDirectory
$artifactDirectory = Resolve-FromRepository $OutputDirectory

$requiredFiles = @(
    "openlogtool.exe",
    "openlogtool_core.dll",
    "flutter_windows.dll"
)

foreach ($relativePath in $requiredFiles) {
    $file = Join-Path $bundleDirectory $relativePath
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required Windows bundle file is missing: $file"
    }

    if ((Get-Item -LiteralPath $file).Length -eq 0) {
        throw "Required Windows bundle file is empty: $file"
    }
}

$flutterAssets = Join-Path $bundleDirectory "data/flutter_assets"
if (-not (Test-Path -LiteralPath $flutterAssets -PathType Container)) {
    throw "Flutter assets directory is missing: $flutterAssets"
}

New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
$safeVersion = $Version -replace '[^0-9A-Za-z._+-]', '-'
$artifactPath = Join-Path $artifactDirectory "OpenLogTool-Windows-x64-$safeVersion.zip"

Compress-Archive `
    -Path (Join-Path $bundleDirectory "*") `
    -DestinationPath $artifactPath `
    -CompressionLevel Optimal `
    -Force

$verificationDirectory = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    "openlogtool-windows-$([guid]::NewGuid().ToString('N'))"

try {
    Expand-Archive -LiteralPath $artifactPath -DestinationPath $verificationDirectory

    foreach ($relativePath in $requiredFiles) {
        $file = Join-Path $verificationDirectory $relativePath
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Packaged Windows file is missing after extraction: $relativePath"
        }
    }

    if ($SmokeTest) {
        $executable = Join-Path $verificationDirectory "openlogtool.exe"
        $process = Start-Process -FilePath $executable `
            -WorkingDirectory $verificationDirectory `
            -PassThru
        try {
            Start-Sleep -Seconds 10
            if ($process.HasExited) {
                throw "OpenLogTool exited during the Windows smoke test (exit code $($process.ExitCode))"
            }
        }
        finally {
            if (-not $process.HasExited) {
                Stop-Process -Id $process.Id -Force
                $process.WaitForExit()
            }
        }
    }
}
finally {
    if (Test-Path -LiteralPath $verificationDirectory) {
        Remove-Item -LiteralPath $verificationDirectory -Recurse -Force
    }
}

$hash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
$hashPath = "$artifactPath.sha256"
$hashLine = "$hash  $([System.IO.Path]::GetFileName($artifactPath))`n"
[System.IO.File]::WriteAllText($hashPath, $hashLine)

Write-Output "Windows artifact: $artifactPath"
Write-Output "SHA-256: $hash"
