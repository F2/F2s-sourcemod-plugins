$ErrorActionPreference = "Stop"

function ZipFiles($zipfilename, $sourcedir)
{
   Add-Type -Assembly System.IO.Compression.FileSystem
   $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
   [System.IO.Compression.ZipFile]::CreateFromDirectory($sourcedir, $zipfilename, $compressionLevel, $false)
}

function ZipFile($zipfilename, $sourcefile)
{
    $sourceDir = Split-Path (Resolve-Path $sourcefile)
    $tempDir = Join-Path $sourceDir "tempZipDir/"
    New-Item $tempDir -ItemType Directory
    Copy-Item $sourcefile $tempDir
    ZipFiles $zipfilename $tempDir
    Write-Host "Want to remove: $($tempDir)"
    Remove-Item (Join-Path $tempDir (Split-Path -Leaf $sourcefile))
    Remove-Item $tempDir
}

if (Test-Path dist) {
    Get-ChildItem -Path "dist" -Recurse | Remove-Item -Force -Recurse
}

New-Item -ItemType directory -Path (Join-Path "dist" "release")
New-Item -ItemType directory -Path (Join-Path "dist" "source")
New-Item -ItemType directory -Path (Join-Path "dist" "ftp")
Copy-Item -Path "includes" -Destination (Join-Path "dist" "source") -Recurse


$plugins = @("waitforstv", "medicstats", "supstats2", "logstf", "restorescore", "countdown", "fixstvslot", "pause", "recordstv", "classwarning", "afk");

foreach ($p in $plugins) {
    Write-Host "Compiling $p..."
    & "spcomp" (Join-Path $p "$p.sp") "-i" (Join-Path $PSScriptRoot includes) "-w217"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed compilation of $p"
        Exit 1
    }

    # Copy the .smx and update.txt file to UPDATE
    New-Item -ItemType directory -Path (Join-Path "dist" "ftp\$p\plugins")
    Copy-Item -Path (Join-Path $p "update.txt") -Destination (Join-Path "dist" "ftp\$p")
    Copy-Item -Path (Join-Path $p "$p.smx") -Destination (Join-Path "dist" "ftp\$p\plugins")

    # Copy the .smx file to the common RELEASE directory
    Copy-Item -Path (Join-Path $p "$p.smx") -Destination (Join-Path "dist" "release")

    # Copy the .sp file to the common SOURCE directory
    Copy-Item -Path (Join-Path $p "$p.sp") -Destination (Join-Path "dist" "source")

    # Zip the single smx file
    ZipFile (Join-Path "dist" "ftp\$p.zip") (Join-Path $p "$p.smx")
}

# Zip the common RELEASE directory
ZipFiles (Join-Path "dist" "ftp\f2-sourcemod-plugins.zip") (Join-Path "dist" "release")

# Zip the common SOURCE directory
ZipFiles (Join-Path "dist" "ftp\f2-sourcemod-plugins-src.zip") (Join-Path "dist" "source")

Write-Host "Finished successfully"
