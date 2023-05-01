param(
    [string]$filename
)

$ErrorActionPreference = "Stop"

# Allow writing "compile" in a directory with exactly one .sp file
if (-not $filename) {
    $files = Get-ChildItem -Filter *.sp
    if ($files.Count -ne 1) {
        throw "Could not find one .sp file in current directory"
    }

    $filename = $files[0].Name
}

# Allow writing "compile logstf" in the root folder
if (-not (Test-Path $filename -PathType Leaf)) {
    $possiblePath = Join-Path $filename ($filename + ".sp")
    Write-Host "Testing: " $possiblePath
    if (Test-Path $possiblePath -PathType Leaf) {
        Push-Location $filename
    }
}

& "spcomp" "$filename" "-i" "$(Join-Path $PSScriptRoot includes)"

Pop-Location