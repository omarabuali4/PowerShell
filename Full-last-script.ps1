<# --- CONFIG --- #>
$appNamesToMatch = @("WhatsApp", "Telegram", "Instagram", "Twitter", "Firefox")    # Target apps
$bundleExtensions = @("*.msixbundle")  # App bundles to delete
$allowedAppExtensions = @("*.exe", "*.dll", "*.bin", "*.pdb", "*.pak", "unins000.exe") # Only delete these extensions
$bundleNamePatterns = @("WhatsApp", "Telegram", "Instagram", "Twitter", "Firefox")  # For bundle name matching
$searchPaths = (Get-PSDrive -PSProvider FileSystem).Root  # All drives (C:\, D:\, etc.)

# Timestamp function
function Get-Timestamp { return Get-Date -Format "yyyy-MM-dd HH:mm:ss" }

# Check if process matches our target apps
function Is-TargetAppProcess($proc, $names) {
    try {
        $fileInfo = (Get-Item $proc.Path -ErrorAction SilentlyContinue).VersionInfo
        foreach ($name in $names) {
            if ($fileInfo.ProductName -match $name -or $proc.Path -match $name) { return $true }
        }
    } catch {}
    return $false
}

# --- STEP 1: Handle running processes FIRST ---
Write-Host "[$(Get-Timestamp)] Scanning for running target apps..."
$targetProcs = Get-Process | Where-Object { $_.Path -and (Is-TargetAppProcess $_ $appNamesToMatch) } -ErrorAction SilentlyContinue

if ($targetProcs) {
    foreach ($proc in $targetProcs) {
        $appPath = $proc.Path
        $appFolder = Split-Path $appPath -Parent
        Write-Host "[$(Get-Timestamp)] Detected target app at: $appPath"

        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Write-Host "[$(Get-Timestamp)] Killed process: $($proc.ProcessName)"
        } catch {
            Write-Host "[$(Get-Timestamp)] Failed to kill process: $($proc.ProcessName)"
        }

        Start-Sleep -Seconds 2

        # Delete binaries only (no dummy files created)
        foreach ($ext in $allowedAppExtensions) {
            Get-ChildItem -Path $appFolder -Filter $ext -File -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                    Write-Host "[$(Get-Timestamp)] Deleted: $($_.FullName)"
                } catch {
                    Write-Host "[$(Get-Timestamp)] Failed to delete: $($_.FullName)"
                }
            }
        }
    }
} else {
    Write-Host "[$(Get-Timestamp)] No running target apps found."
}


# --- STEP 3: Remove UWP (Store) versions ---
foreach ($name in $appNamesToMatch) {
    try {
        $pkg = Get-AppxPackage | Where-Object { $_.Name -match $name }
        if ($pkg) {
            Write-Host "[$(Get-Timestamp)] Removing Store package: $($pkg.PackageFullName)"
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "[$(Get-Timestamp)] Failed to remove package: $name"
    }
}

# --- STEP 4: Delete matching MSIX bundles ---
Write-Host "[$(Get-Timestamp)] Scanning for target MSIX bundles..."
$foundBundles = @()
Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    $drive = $_.Root
    foreach ($ext in $bundleExtensions) {
        try {
            $found = Get-ChildItem -Path $drive -Recurse -Include $ext -ErrorAction SilentlyContinue
            foreach ($file in $found) {
                $lowerName = $file.Name.ToLower()
                if ($bundleNamePatterns | ForEach-Object { if ($lowerName -like "*$($_.ToLower())*") { return $true } }) {
                    $foundBundles += $file
                }
            }
        } catch {
            Write-Host "[$(Get-Timestamp)] Error scanning $drive : $_"
        }
    }
}


# --- STEP 2: Search for leftover binaries (after running apps are handled) ---
Write-Host "[$(Get-Timestamp)] Searching for application files..."
foreach ($path in $searchPaths) {
    foreach ($app in $appNamesToMatch) {
        foreach ($ext in $allowedAppExtensions) {
            try {
                $files = Get-ChildItem -Path $path -Filter $ext -Recurse -File -ErrorAction SilentlyContinue | 
                         Where-Object { $_.FullName -match $app }
                foreach ($file in $files) {
                    try {
                        Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                        Write-Host "[$(Get-Timestamp)] Deleted file: $($file.FullName)"
                    } catch {
                        Write-Host "[$(Get-Timestamp)] Failed to delete file: $($file.FullName)"
                    }
                }
            } catch {
                Write-Host "[$(Get-Timestamp)] Error searching in $path for $app files: $_"
            }
        }
    }
}

if ($foundBundles.Count -gt 0) {
    foreach ($bundle in $foundBundles) {
        try {
            Write-Host "[$(Get-Timestamp)] Deleting bundle: $($bundle.FullName)"
            Remove-Item -Path $bundle.FullName -Force -ErrorAction Stop
        } catch {
            Write-Host "[$(Get-Timestamp)] Failed to delete bundle: $($bundle.FullName)"
        }
    }
} else {
    Write-Host "[$(Get-Timestamp)] No matching MSIX bundles found."
}
