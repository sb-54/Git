# ============================================================================
# Microsoft Intune - Android Device Patch Level Report (ALL VERSIONS)
# ============================================================================
# This script uses Microsoft Graph API to retrieve Android OS version 
# and security patch information from Microsoft Intune
#
# Features:
# - Comprehensive Android device patch level reporting
# - Captures ALL Android versions (no filtering)
# - Logging to macOS iCloud Documents folder
# - Multiple CSV exports for analysis
#
# Requirements:
# - Microsoft.Graph PowerShell module
# - Intune Administrator or Global Reader role
# - DeviceManagementManagedDevices.Read.All permission
#
# Author: Generated for Intune Android Reporting
# Version: 3.0 All Android Devices (FIXED)
# ============================================================================

# ============================================================================
# LOGGING CONFIGURATION
# ============================================================================

# Set log file path to macOS iCloud Documents
$logBasePath = "/Users/hea2eq/Library/Mobile Documents/com~apple~CloudDocs/Logs"
$logFileName = "Intune-AndroidPatchReport-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$logFilePath = Join-Path -Path $logBasePath -ChildPath $logFileName

# Create log directory if it doesn't exist
if (-not (Test-Path -Path $logBasePath)) {
    try {
        New-Item -ItemType Directory -Path $logBasePath -Force | Out-Null
        Write-Host "Created log directory: $logBasePath" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Could not create log directory at $logBasePath" -ForegroundColor Yellow
        Write-Host "Logs will only be displayed on console" -ForegroundColor Yellow
    }
}

# ============================================================================
# FIXED: Write-Log Function with AllowEmptyString Support
# ============================================================================
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info',
        
        [Parameter(Mandatory=$false)]
        [ConsoleColor]$Color = 'White'
    )
    
    # Create log entry with timestamp
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console
    Write-Host $Message -ForegroundColor $Color
    
    # Write to log file if path exists
    if (Test-Path -Path $logBasePath) {
        try {
            Add-Content -Path $logFilePath -Value $logEntry -ErrorAction SilentlyContinue
        }
        catch {
            # Silently fail if we can't write to log file
        }
    }
}

# ============================================================================
# MAIN SCRIPT START
# ============================================================================

Write-Log -Message "===============================================" -Level Info -Color Cyan
Write-Log -Message "All Android Devices Patch Level Report Generator" -Level Info -Color Cyan
Write-Log -Message "===============================================" -Level Info -Color Cyan
Write-Log -Message "Log file: $logFilePath" -Level Info -Color Gray
Write-Log -Message "" -Level Info

# Connect to Microsoft Graph with required permissions
Write-Log -Message "Connecting to Microsoft Graph..." -Level Info -Color Cyan
try {
    Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All" | Out-Null
    Write-Log -Message "Successfully connected to Microsoft Graph" -Level Success -Color Green
}
catch {
    Write-Log -Message "Failed to connect to Microsoft Graph: $($_.Exception.Message)" -Level Error -Color Red
    exit 1
}

Write-Log -Message "" -Level Info
Write-Log -Message "===============================================" -Level Info -Color Cyan
Write-Log -Message "Starting All Android Device Query" -Level Info -Color Cyan
Write-Log -Message "===============================================" -Level Info -Color Cyan
Write-Log -Message "" -Level Info

# ============================================================================
# Method 1: Get All Android Devices with Security Patch Level (ALL VERSIONS)
# ============================================================================
Write-Log -Message "[1/3] Fetching All Android Enterprise devices..." -Level Info -Color Green

$androidDevices = @()
$pageCount = 0

# Filter for ALL Android devices (no version restriction)
$uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=(deviceType eq 'androidEnterprise' or deviceType eq 'android')&`$select=id,deviceName,userPrincipalName,manufacturer,model,osVersion,androidSecurityPatchLevel,lastSyncDateTime,complianceState,enrolledDateTime"

try {
    do {
        $pageCount++
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET
        
        foreach ($device in $response.value) {
            $androidDevices += [PSCustomObject]@{
                DeviceId = $device.id
                DeviceName = $device.deviceName
                UserPrincipalName = $device.userPrincipalName
                Manufacturer = $device.manufacturer
                Model = $device.model
                OSVersion = $device.osVersion
                SecurityPatchLevel = $device.androidSecurityPatchLevel
                LastSyncDate = $device.lastSyncDateTime
                ComplianceState = $device.complianceState
                EnrolledDate = $device.enrolledDateTime
            }
        }
        
        $totalDevices = $androidDevices.Count
        $deviceCount = ($response.value).Count
        Write-Log -Message "  Page $pageCount`: Retrieved $deviceCount devices (Total: $totalDevices)" -Level Info -Color Gray
        
        $uri = $response.'@odata.nextLink'
    } while ($uri)
    
    Write-Log -Message "Retrieved $($androidDevices.Count) total Android devices (all versions)" -Level Success -Color Cyan
}
catch {
    Write-Log -Message "Error fetching Android devices: $($_.Exception.Message)" -Level Error -Color Red
}

Write-Log -Message "" -Level Info

# ============================================================================
# Method 2: Analyze Patch Level Status
# ============================================================================
Write-Log -Message "[2/3] Analyzing security patch levels..." -Level Info -Color Green

$currentDate = Get-Date
$patchAnalysis = @()

try {
    foreach ($device in $androidDevices) {
        $patchStatus = "Unknown"
        $daysOld = $null
        $recommendation = ""
        
        if ($device.SecurityPatchLevel) {
            try {
                $patchDate = [DateTime]::ParseExact($device.SecurityPatchLevel, "yyyy-MM-dd", $null)
                $daysOld = ($currentDate - $patchDate).Days
                
                if ($daysOld -le 90) {
                    $patchStatus = "Up to Date"
                    $recommendation = "No action required"
                }
                elseif ($daysOld -le 180) {
                    $patchStatus = "Moderately Outdated"
                    $recommendation = "Consider updating"
                }
                else {
                    $patchStatus = "Critically Outdated"
                    $recommendation = "Update immediately"
                }
            }
            catch {
                try {
                    $patchDate = [DateTime]::ParseExact($device.SecurityPatchLevel, "yyyy-MM", $null)
                    $daysOld = ($currentDate - $patchDate).Days
                    
                    if ($daysOld -le 90) {
                        $patchStatus = "Up to Date"
                        $recommendation = "No action required"
                    }
                    elseif ($daysOld -le 180) {
                        $patchStatus = "Moderately Outdated"
                        $recommendation = "Consider updating"
                    }
                    else {
                        $patchStatus = "Critically Outdated"
                        $recommendation = "Update immediately"
                    }
                }
                catch {
                    $patchStatus = "Invalid Date Format"
                    $recommendation = "Check device manually"
                    $devNameMsg = $device.DeviceName
                    $patchLevelMsg = $device.SecurityPatchLevel
                    Write-Log -Message "  Invalid patch date format for $devNameMsg`: $patchLevelMsg" -Level Warning -Color Yellow
                }
            }
        }
        else {
            $patchStatus = "Not Reported"
            $recommendation = "Check device sync status"
        }
        
        $patchAnalysis += [PSCustomObject]@{
            DeviceName = $device.DeviceName
            UserPrincipalName = $device.UserPrincipalName
            Manufacturer = $device.Manufacturer
            Model = $device.Model
            OSVersion = $device.OSVersion
            SecurityPatchLevel = $device.SecurityPatchLevel
            PatchStatus = $patchStatus
            DaysOldPatch = $daysOld
            LastSync = $device.LastSyncDate
            ComplianceState = $device.ComplianceState
            Recommendation = $recommendation
        }
    }
    
    Write-Log -Message "Patch analysis completed for all $($patchAnalysis.Count) devices" -Level Success -Color Green
}
catch {
    Write-Log -Message "Error during patch analysis: $($_.Exception.Message)" -Level Error -Color Red
}

Write-Log -Message "" -Level Info

# ============================================================================
# Method 3: Generate Reports Using Intune Export API
# ============================================================================
Write-Log -Message "[3/3] Generating comprehensive device report via Export API..." -Level Info -Color Green

$exportUri = "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs"

try {
    $exportBody = @{
        reportName = "Devices"
        format = "csv"
        filter = "(OperatingSystem eq 'Android')"
        select = @("DeviceId", "DeviceName", "UPN", "OS", "OSVersion", "LastContact", "CompliantState", "Ownership", "StorageTotal", "StorageFree")
    } | ConvertTo-Json
    
    $exportJob = Invoke-MgGraphRequest -Uri $exportUri -Method POST -Body $exportBody -ContentType "application/json"
    $exportJobId = $exportJob.id
    
    Write-Log -Message "Export job created with ID: $exportJobId" -Level Info -Color Yellow
    Write-Log -Message "Waiting for export to complete..." -Level Info -Color Yellow
    
    $maxAttempts = 20
    $attempt = 0
    
    do {
        Start-Sleep -Seconds 5
        $attempt++
        $jobStatus = Invoke-MgGraphRequest -Uri "$exportUri/$exportJobId" -Method GET
        $jobStatusValue = $jobStatus.status
        Write-Log -Message "  Attempt $attempt/$maxAttempts - Status: $jobStatusValue" -Level Info -Color Yellow
    } while ($jobStatus.status -ne "completed" -and $attempt -lt $maxAttempts)
    
    if ($jobStatus.status -eq "completed" -and $jobStatus.url) {
        Write-Log -Message "Downloading comprehensive device report..." -Level Info -Color Green
        $reportContent = Invoke-WebRequest -Uri $jobStatus.url -Method GET
        $reportContent.Content | Out-File -FilePath "AllAndroidDevices_Full_Report.csv"
        Write-Log -Message "Full report saved to AllAndroidDevices_Full_Report.csv" -Level Success -Color Green
    }
    else {
        Write-Log -Message "Export job did not complete within timeout period" -Level Warning -Color Yellow
    }
}
catch {
    Write-Log -Message "Could not generate export report: $($_.Exception.Message)" -Level Warning -Color Yellow
}

Write-Log -Message "" -Level Info

# ============================================================================
# Display Summary Statistics
# ============================================================================
Write-Log -Message "===============================================" -Level Info -Color Cyan
Write-Log -Message "ALL ANDROID DEVICES PATCH STATUS SUMMARY" -Level Info -Color Cyan
Write-Log -Message "===============================================" -Level Info -Color Cyan
Write-Log -Message "" -Level Info

$totalCount = $androidDevices.Count
Write-Log -Message "Total Android Devices (All Versions): $totalCount" -Level Info -Color White

Write-Log -Message "" -Level Info
Write-Log -Message "Security Patch Status Distribution:" -Level Info -Color Yellow

$statusSummary = $patchAnalysis | Group-Object PatchStatus | Select-Object Name, Count
foreach ($status in $statusSummary) {
    $statusName = $status.Name
    $statusCount = $status.Count
    Write-Log -Message "  $statusName`: $statusCount" -Level Info -Color White
}

$complianceSummary = $patchAnalysis | Group-Object ComplianceState | Select-Object Name, Count

Write-Log -Message "" -Level Info
Write-Log -Message "Device Compliance Status:" -Level Info -Color Yellow
foreach ($compliance in $complianceSummary) {
    $complianceName = $compliance.Name
    $complianceCount = $compliance.Count
    Write-Log -Message "  $complianceName`: $complianceCount" -Level Info -Color White
}

$outdatedDevices = $patchAnalysis | Where-Object { $_.PatchStatus -eq "Critically Outdated" -or $_.PatchStatus -eq "Moderately Outdated" } | Sort-Object DaysOldPatch -Descending

Write-Log -Message "" -Level Info
if ($outdatedDevices.Count -gt 0) {
    $outdatedCount = $outdatedDevices.Count
    Write-Log -Message "WARNING: $outdatedCount device(s) need security updates!" -Level Warning -Color Red
    Write-Log -Message "" -Level Info
    Write-Log -Message "Top 10 Most Outdated Devices:" -Level Info -Color Yellow
    $topOutdated = $outdatedDevices | Select-Object DeviceName, SecurityPatchLevel, DaysOldPatch, Recommendation -First 10
    foreach ($device in $topOutdated) {
        $devName = $device.DeviceName
        $devPatch = $device.SecurityPatchLevel
        $devDays = $device.DaysOldPatch
        $devRec = $device.Recommendation
        Write-Log -Message "  $devName - Patch: $devPatch - Age: $devDays days - Action: $devRec" -Level Info -Color White
    }
}

$manufacturerSummary = $patchAnalysis | Group-Object Manufacturer | Select-Object Name, Count | Sort-Object Count -Descending

Write-Log -Message "" -Level Info
Write-Log -Message "Device Manufacturer Distribution:" -Level Info -Color Yellow
foreach ($mfr in $manufacturerSummary) {
    $mfrName = $mfr.Name
    $mfrCount = $mfr.Count
    Write-Log -Message "  $mfrName`: $mfrCount" -Level Info -Color White
}

$osVersionSummary = $patchAnalysis | Group-Object OSVersion | Select-Object Name, Count | Sort-Object Name -Descending

Write-Log -Message "" -Level Info
Write-Log -Message "Android OS Version Distribution:" -Level Info -Color Yellow
foreach ($osVer in $osVersionSummary) {
    $osVerName = $osVer.Name
    $osVerCount = $osVer.Count
    Write-Log -Message "  Android $osVerName`: $osVerCount" -Level Info -Color White
}

Write-Log -Message "" -Level Info

# ============================================================================
# Export Results to CSV
# ============================================================================
Write-Log -Message "Exporting detailed reports..." -Level Info -Color Green

$scriptDirectory = Get-Location

try {
    $exportPath1 = Join-Path -Path $scriptDirectory -ChildPath "AllAndroidDevices_Inventory.csv"
    $androidDevices | Export-Csv -Path $exportPath1 -NoTypeInformation
    Write-Log -Message "- Device inventory exported to: AllAndroidDevices_Inventory.csv" -Level Success -Color White
}
catch {
    Write-Log -Message "- Failed to export device inventory: $($_.Exception.Message)" -Level Error -Color Red
}

try {
    $exportPath2 = Join-Path -Path $scriptDirectory -ChildPath "AllAndroidDevices_PatchAnalysis.csv"
    $patchAnalysis | Export-Csv -Path $exportPath2 -NoTypeInformation
    Write-Log -Message "- Patch analysis exported to: AllAndroidDevices_PatchAnalysis.csv" -Level Success -Color White
}
catch {
    Write-Log -Message "- Failed to export patch analysis: $($_.Exception.Message)" -Level Error -Color Red
}

try {
    if ($outdatedDevices.Count -gt 0) {
        $exportPath3 = Join-Path -Path $scriptDirectory -ChildPath "AllAndroidDevices_NeedingUpdates.csv"
        $outdatedDevices | Export-Csv -Path $exportPath3 -NoTypeInformation
        Write-Log -Message "- Devices needing updates exported to: AllAndroidDevices_NeedingUpdates.csv" -Level Success -Color White
    }
}
catch {
    Write-Log -Message "- Failed to export outdated devices list: $($_.Exception.Message)" -Level Error -Color Red
}

try {
    $exportPath4 = Join-Path -Path $scriptDirectory -ChildPath "AllAndroidDevices_ManufacturerSummary.csv"
    $manufacturerSummary | Export-Csv -Path $exportPath4 -NoTypeInformation
    Write-Log -Message "- Manufacturer summary exported to: AllAndroidDevices_ManufacturerSummary.csv" -Level Success -Color White
}
catch {
    Write-Log -Message "- Failed to export manufacturer summary: $($_.Exception.Message)" -Level Error -Color Red
}

try {
    $exportPath5 = Join-Path -Path $scriptDirectory -ChildPath "AllAndroidDevices_OSVersionSummary.csv"
    $osVersionSummary | Export-Csv -Path $exportPath5 -NoTypeInformation
    Write-Log -Message "- OS version summary exported to: AllAndroidDevices_OSVersionSummary.csv" -Level Success -Color White
}
catch {
    Write-Log -Message "- Failed to export OS version summary: $($_.Exception.Message)" -Level Error -Color Red
}

Write-Log -Message "" -Level Info
Write-Log -Message "===============================================" -Level Info -Color Cyan
Write-Log -Message "Report Generation Complete!" -Level Info -Color Green
Write-Log -Message "===============================================" -Level Info -Color Cyan
Write-Log -Message "" -Level Info

# ============================================================================
# Important Information
# ============================================================================
Write-Log -Message "IMPORTANT INFORMATION:" -Level Info -Color Yellow
Write-Log -Message "" -Level Info
Write-Log -Message "Android Update Capabilities in Microsoft Graph:" -Level Info -Color Gray
Write-Log -Message "" -Level Info
Write-Log -Message "WHAT YOU CAN SEE:" -Level Info -Color Gray
Write-Log -Message "  ✓ Current Android OS version" -Level Info -Color Gray
Write-Log -Message "  ✓ Android Security Patch Level" -Level Info -Color Gray
Write-Log -Message "  ✓ Last device sync date" -Level Info -Color Gray
Write-Log -Message "  ✓ Device compliance state" -Level Info -Color Gray
Write-Log -Message "  ✓ All Android versions captured" -Level Info -Color Gray
Write-Log -Message "" -Level Info
Write-Log -Message "NEXT STEPS FOR ALL ANDROID DEVICES:" -Level Info -Color Gray
Write-Log -Message "  1. Review patch status in generated CSV files" -Level Info -Color Gray
Write-Log -Message "  2. Create compliance policies for minimum patch levels" -Level Info -Color Gray
Write-Log -Message "  3. Use Samsung Knox E-FOTA to push updates on Samsung devices" -Level Info -Color Gray
Write-Log -Message "  4. Create Conditional Access policies to enforce compliance" -Level Info -Color Gray
Write-Log -Message "  5. Set system update policies to Automatic for each Android version" -Level Info -Color Gray
Write-Log -Message "" -Level Info

Write-Log -Message "Files created in current directory:" -Level Info -Color Cyan
Write-Log -Message "  - AllAndroidDevices_Inventory.csv" -Level Info -Color White
Write-Log -Message "  - AllAndroidDevices_PatchAnalysis.csv" -Level Info -Color White
Write-Log -Message "  - AllAndroidDevices_NeedingUpdates.csv" -Level Info -Color White
Write-Log -Message "  - AllAndroidDevices_ManufacturerSummary.csv" -Level Info -Color White
Write-Log -Message "  - AllAndroidDevices_OSVersionSummary.csv" -Level Info -Color White
Write-Log -Message "  - AllAndroidDevices_Full_Report.csv" -Level Info -Color White

Write-Log -Message "" -Level Info
Write-Log -Message "Log file location:" -Level Info -Color Cyan
Write-Log -Message "  $logFilePath" -Level Info -Color White

Write-Log -Message "" -Level Info

# Disconnect from Microsoft Graph
Write-Log -Message "Disconnecting from Microsoft Graph..." -Level Info -Color Cyan
try {
    Disconnect-MgGraph | Out-Null
    Write-Log -Message "Successfully disconnected" -Level Success -Color Green
}
catch {
    Write-Log -Message "Warning: Could not disconnect cleanly: $($_.Exception.Message)" -Level Warning -Color Yellow
}

Write-Log -Message "" -Level Info
Write-Log -Message "Script execution completed successfully!" -Level Success -Color Green
Write-Log -Message "" -Level Info

Write-Host "`nLog file saved to: $logFilePath" -ForegroundColor Cyan
