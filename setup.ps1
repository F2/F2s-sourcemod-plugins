#Requires -Version 6

$ErrorActionPreference = "Stop"

Push-Location $PSScriptRoot

Write-Host -NoNewline "Updating PATH environment variable... "
$env:PATH += ";$PSScriptRoot;"
$env:PATH += Join-Path $PSScriptRoot "sourcemod-binaries" "addons" "sourcemod" "scripting"
Write-Host "DONE!"

Write-Host -NoNewline "Installing SourceMod binaries... "
if (Test-Path "sourcemod-binaries") {
    Write-Host "already installed."
}
else {
    $sourcemodFilename = "sourcemod-1.10.0-git6545-windows.zip"
    $sourcemodUrl = "https://sm.alliedmods.net/smdrop/1.10/" + $sourcemodFilename
    Invoke-WebRequest $sourcemodUrl -OutFile $sourcemodFilename
    Expand-Archive $sourcemodFilename -DestinationPath "sourcemod-binaries"
    Remove-Item $sourcemodFilename

    Write-Host "DONE!"
}

Write-Host ""
Write-Host "You can now compile a plugin in one of the following ways:"
Write-Host ""
Write-Host "compile logstf" -ForegroundColor Yellow
Write-Host ""
Write-Host "compile logstf/logstf.sp" -ForegroundColor Yellow
Write-Host ""
Write-Host "cd logstf" -ForegroundColor Yellow
Write-Host "compile" -ForegroundColor Yellow

Pop-Location