param(
    [string]$path
)

$ErrorActionPreference = "Stop"

# Allow writing "compile" in a directory with exactly one .sp file
if (-not $path) {
    $files = Get-ChildItem -Filter *.sp
    if ($files.Count -ne 1) {
        throw "Could not find one .sp file in current directory"
    }

    $path = $files[0].Name
}

# Allow writing "compile logstf" in the root folder
if (-not (Test-Path $path -PathType Leaf)) {
    $possiblePath = Join-Path $path ($path + ".sp")
    if (Test-Path $possiblePath -PathType Leaf) {
        $path = $possiblePath
    }
}

if (-not $path.EndsWith('.sp')) {
    $path += '.sp'
}

$directory = [System.IO.Path]::GetDirectoryName($path)
$filenameOnly = [System.IO.Path]::GetFileName($path)

Push-Location $directory

& "spcomp64" "$filenameOnly" "-i" "$(Join-Path $PSScriptRoot includes)"

Pop-Location