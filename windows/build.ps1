param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $PSScriptRoot "PotatusHub\PotatusHub.csproj"
$publish = Join-Path $root "publish\$Runtime"
$archive = Join-Path $root "potatus-hub-0.4.1-windows-x64.zip"
$checksum = Join-Path $root "potatus-hub-0.4.1-windows-x64.sha256"

dotnet publish $project `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $publish

if (Test-Path $archive) { Remove-Item $archive }
Compress-Archive -Path "$publish\*" -DestinationPath $archive
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $(Split-Path $archive -Leaf)" | Set-Content $checksum

Write-Host "Created: $archive"
Write-Host "SHA-256: $hash"
