# --- CONFIG --- #
$appNamesToMatch = @("WhatsApp", "Telegram", "Instagram", "Twitter", "Firefox")    # Target apps
$bundleExtensions = @("*.msixbundle")  # App bundles to delete
$allowedAppExtensions = @("*.exe", "*.dll", "*.bin", "*.pdb", "*.pak", "unins000.exe") # Only delete these extensions
$bundleNamePatterns = @("WhatsApp", "Telegram", "Instagram", "Twitter", "Firefox")  # For bundle name matching
$searchPaths = (Get-PSDrive -PSProvider FileSystem).Root  # All drives (C:\, D:\, etc.)

# Timestamp function
function Get-Timestamp { return Get-Date -Format "yyyy-MM-dd HH:mm:ss" }

# Show Policy Violation Alert
function Show-PolicyAlert {
    Add-Type -AssemblyName PresentationFramework
    $alertScript = {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("Unauthorized software has been detected on this device. This is a serious violation of company policy and has been reported to the IT Department.", "Policy Violation Detected", "OK", "Warning")
    }
    Start-Job $alertScript | Out-Null
}

# Logging
function Write-PolicyLog {
    $logFolder = "C:\CompanyLogs"
    $logFile = "$logFolder\policy_violations.log"
    if (!(Test-Path $logFolder)) { New-Item -ItemType Directory -Path $logFolder -Force | Out-Null }
    $timestamp = Get-Timestamp
    Add-Content -Path $logFile -Value "[$timestamp] $($args[0])"
}

# Check if process matches our target apps
function Is-TargetAppProcess($proc, $names) {
    try {
        $fileInfo = (Get-Item -LiteralPath $proc.Path -ErrorAction SilentlyContinue).VersionInfo
        foreach ($name in $names) {
            if ($fileInfo.ProductName -match $name -or $proc.Path -match $name) { return $true }
        }
    } catch {}
    return $false
}

# --- STEP 1: Handle running processes ---
Write-Host "[$(Get-Timestamp)] Scanning for running target apps..."
$targetProcs = Get-Process | Where-Object { $_.Path -and (Is-TargetAppProcess $_ $appNamesToMatch) } -ErrorAction SilentlyContinue

if ($targetProcs) {
    Show-PolicyAlert
    Write-PolicyLog "Policy violation: Found running restricted apps."

    foreach ($proc in $targetProcs) {
        $appPath = $proc.Path
        $appFolder = Split-Path $appPath -Parent
        Write-Host "[$(Get-Timestamp)] Detected: `"$appPath`""
        Write-PolicyLog "Detected: $appPath"

        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        Start-Sleep -Seconds 2

        foreach ($ext in $allowedAppExtensions) {
            Get-ChildItem -LiteralPath $appFolder -Filter $ext -File -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    Write-Host "[$(Get-Timestamp)] Deleted: `"$($_.FullName)`""
                    Write-PolicyLog "Deleted: $($_.FullName)"
                } catch {
                    Write-Host "[$(Get-Timestamp)] Failed: `"$($_.FullName)`""
                }
            }
        }
    }
} else {
    Write-Host "[$(Get-Timestamp)] No running target apps found."
}

# --- STEP 2: Remove UWP (Store) versions ---
foreach ($name in $appNamesToMatch) {
    try {
        $pkg = Get-AppxPackage | Where-Object { $_.Name -match $name }
        if ($pkg) {
            Write-Host "[$(Get-Timestamp)] Removing Store package: $($pkg.PackageFullName)"
            Write-PolicyLog "Removing Store package: $($pkg.PackageFullName)"
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
        }
    } catch {}
}

# --- STEP 3: Delete MSIX bundles ---
Write-Host "[$(Get-Timestamp)] Scanning for target MSIX bundles..."
$foundBundles = @()
foreach ($drive in $searchPaths) {
    foreach ($ext in $bundleExtensions) {
        try {
            Get-ChildItem -LiteralPath $drive -Recurse -Include $ext -ErrorAction SilentlyContinue | ForEach-Object {
                $lowerName = $_.Name.ToLower()
                if ($bundleNamePatterns | ForEach-Object { if ($lowerName -like "*$($_.ToLower())*") { return $true } }) {
                    $foundBundles += $_
                    Write-Host "[$(Get-Timestamp)] Found bundle: `"$($_.FullName)`""
                    Write-PolicyLog "Found bundle: $($_.FullName)"
                }
            }
        } catch {}
    }
}

# --- STEP 4: Delete leftover binaries ---
Write-Host "[$(Get-Timestamp)] Searching for application files..."
foreach ($path in $searchPaths) {
    foreach ($app in $appNamesToMatch) {
        foreach ($ext in $allowedAppExtensions) {
            try {
                Get-ChildItem -LiteralPath $path -Filter $ext -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match $app } | ForEach-Object {
                    try {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                        Write-Host "[$(Get-Timestamp)] Deleted file: `"$($_.FullName)`""
                        Write-PolicyLog "Deleted file: $($_.FullName)"
                    } catch {}
                }
            } catch {}
        }
    }
}

# --- Delete found bundles ---
if ($foundBundles.Count -gt 0) {
    foreach ($bundle in $foundBundles) {
        try {
            Write-Host "[$(Get-Timestamp)] Deleting bundle: `"$($bundle.FullName)`""
            Remove-Item -LiteralPath $bundle.FullName -Force -ErrorAction SilentlyContinue
            Write-PolicyLog "Deleted bundle: $($bundle.FullName)"
        } catch {}
    }
} else {
    Write-Host "[$(Get-Timestamp)] No matching MSIX bundles found."
}
