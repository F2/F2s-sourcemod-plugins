$ErrorActionPreference = "Stop"

function ZipFiles($zipfilename, $sourcedir)
{
   Add-Type -Assembly System.IO.Compression.FileSystem
   $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
   [System.IO.Compression.ZipFile]::CreateFromDirectory($sourcedir, $zipfilename, $compressionLevel, $false)
}

if (Test-Path dist) {
    Get-ChildItem -Path "dist" -Recurse | Remove-Item -force -recurse
}

New-Item -ItemType directory -Path dist\release
New-Item -ItemType directory -Path dist\source\includes
New-Item -ItemType directory -Path dist\ftp

$plugins = @("waitforstv", "medicstats", "supstats2", "logstf", "restorescore", "fixstvslot", "pause", "recordstv", "classwarning", "afk");

foreach ($p in $plugins) {
    Write-Host "Compiling $p..."
    Write-Host "Command: & spcomp $p/$p.sp -i $(Join-Path $PSScriptRoot includes) -w217"
    & "spcomp" "$p/$p.sp" "-i" (Join-Path $PSScriptRoot includes) "-w217"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed compilation of $p"
        Exit 1
    }
}

Write-Host "Finished successfully"
