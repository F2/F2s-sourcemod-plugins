function ConvertFrom-KeyValues {
    param(
        [string]$text
    )

    $lines = $text -split "`r?`n"
    $stack = @()
    $current = @{}
    $pendingKey = $null

    foreach ($line in $lines) {
        $line = $line.Trim()
        if ($line -eq "" -or $line.StartsWith("//")) { continue }

        # "Key" "Value"
        if ($line -match '^\s*"([^"]+)"\s+"([^"]+)"\s*$') {
            $k = $matches[1]
            $v = $matches[2]
            if ($current.ContainsKey($k)) {
                # If key already exists, convert to array
                if ($current[$k] -isnot [array]) {
                    $current[$k] = @($current[$k])
                }
                $current[$k] += $v
            }
            else {
                $current[$k] = $v
            }
            continue
        }

        # "Key"
        if ($line -match '^\s*"([^"]+)"\s*$') {
            $pendingKey = $matches[1]
            continue
        }

        # {
        if ($line -eq "{") {
            $stack += @($current)
            $newDict = @{}
            if ($pendingKey) {
                $current[$pendingKey] = $newDict
                $current = $newDict
                $pendingKey = $null
            }
            continue
        }

        # }
        if ($line -eq "}") {
            $current = $stack[-1]
            $stack = $stack[0..($stack.Count - 2)]
            continue
        }

        Write-Error "KeyValue parsing failed: $line"
        exit 1
    }

    return $current
}

function Test-UpdaterFile {
    param(
        [string]$KeyValueFile
    )

    if (-not $KeyValueFile -or -not (Test-Path $KeyValueFile)) {
        Write-Error "KeyValue file not specified or does not exist: $KeyValueFile"
        exit 1
    }

    $text = Get-Content $KeyValueFile -Raw
    $parsed = ConvertFrom-KeyValues -text $text

    $missingSections = @()

    if (-not $parsed.ContainsKey("Updater")) {
        $missingSections += "Updater"
    }
    else {
        $updater = $parsed["Updater"]
        if (-not $updater.ContainsKey("Information")) {
            $missingSections += "Updater.Information"
        }
        else {
            $info = $updater["Information"]
            if (-not $info.ContainsKey("Version") -or -not $info["Version"].ContainsKey("Latest")) {
                $missingSections += "Updater.Information.Version.Latest"
            }
            if (-not $info.ContainsKey("Notes")) {
                $missingSections += "Updater.Information.Notes"
            }
        }
        if (-not $updater.ContainsKey("Files") -or -not $updater["Files"].ContainsKey("Plugin")) {
            $missingSections += "Updater.Files.Plugin"
        }
    }

    if ($missingSections.Count -eq 0) {
        return $true
    }
    else {
        Write-Host "Missing sections:"
        $missingSections | ForEach-Object { Write-Host "- $_" }
        return $false
    }
}