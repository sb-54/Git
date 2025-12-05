# ---------------------------------------------------------------------------
# Lenovo_Serialinfo.ps1 - Prerequisites & Configuration Instructions
# ---------------------------------------------------------------------------
# This script retrieves Lenovo device warranty information via Microsoft Graph,
# exports the results to CSV, and logs activity locally.
#
# PREREQUISITES:
#   1. PowerShell 7+ is recommended.
#   2. Microsoft.Graph PowerShell module v1.0.0+ must be installed.
#         Install-Module Microsoft.Graph -Scope CurrentUser
#   3. The executing account must have:
#         - Permission to access Microsoft Graph API:
#             DeviceManagementManagedDevices.Read.All
#         - Permission to send email via the configured SMTP server.
#   4. Internet access is required for Lenovo API queries.
#   5. The script requires local write access to C:\Reports and C:\Temp.
#
# CONFIGURATION - MUST SET:
#   - $clientId       : Lenovo API ClientID for warranty requests
#
# USAGE:
#   1. Fill in all configuration variables above.
#   2. Run the script in a PowerShell session with necessary privileges.
#   3. On first run, you will be prompted to authenticate to Microsoft Graph.
#
# NOTE:
#   - The script logs activity to C:\Temp\Lenovo_Warranty_Log.txt.
#   - Review and test in a non-production environment before deployment.
# ---------------------------------------------------------------------------

# Set file paths
$uploadFileName = "Lenovo_Warranty_Report.csv"
$localExportPath = "C:\Reports\$uploadFileName"
$logPath = "C:\Temp\Lenovo_Warranty_Log.txt"

# Lenovo API ClientID - MUST SET

$clientId = "vnDi8AEZeyL/w8p8ZLcxzw=="

# Ensure ImportExcel module is available
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Install-Module -Name ImportExcel -Scope CurrentUser -Force
}
Import-Module ImportExcel

# Ensure directories exist
if (!(Test-Path -Path "C:\Reports")) { New-Item -Path "C:\Reports" -ItemType Directory | Out-Null }
if (!(Test-Path -Path "C:\Temp")) { New-Item -Path "C:\Temp" -ItemType Directory | Out-Null }

# Start logging
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Script started." | Out-File -FilePath $logPath -Encoding UTF8

# Read serial numbers from CSV
$serialsCsvPath = "C:\Script\serials.csv"
if (!(Test-Path -Path $serialsCsvPath)) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Error: Serial numbers file not found at $serialsCsvPath" | Out-File -FilePath $logPath -Append
    Write-Host "Serial numbers file not found at $serialsCsvPath. Exiting script."
    exit 1
}

$serialNumbers = Import-Csv -Path $serialsCsvPath | Select-Object -ExpandProperty SerialNumber
Write-Host "Total serial numbers read from CSV: $($serialNumbers.Count)"

## Initialize response array before loop
$allResponses = @()

foreach ($serialNumber in $serialNumbers) {

    $maxRetries = 3
    $retryDelay = 2
    $success = $false

    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            # Prepare POST request to Lenovo Warranty API v2.5
            $uri = "https://supportapi.lenovo.com/v2.5/warranty"
            $headers = @{
                "ClientID" = $clientId
                "Content-Type" = "application/x-www-form-urlencoded"
            }
            $body = "Serial=$serialNumber"

            $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body

            if ($null -ne $response -and $response.warranty -and $response.warranty.Count -gt 0) {
                # Extract first warranty record (assuming it exists)
                $warrantyInfo = $response.warranty[0]

                # Build list of all warrantyInfo property names
                $props = $warrantyInfo.PSObject.Properties.Name

                # Log available date fields for debugging
                "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Fields for ${serialNumber}: $($props -join ', ')" | Out-File -FilePath $logPath -Append

                # Detect purchase or registration date field
                $purchaseField = $props | Where-Object { $_ -match '(?i)purchase' -or $_ -match '(?i)register' } | Select-Object -First 1
                # Detect ship date field
                $shipField     = $props | Where-Object { $_ -match '(?i)ship' } | Select-Object -First 1
                # Detect warranty start date (contains 'start' but not 'ship' or 'purchase')
                $startField    = $props | Where-Object { $_ -match '(?i)start' -and $_ -notmatch '(?i)ship' -and $_ -notmatch '(?i)purchase' } | Select-Object -First 1
                # Detect warranty end date
                $endField      = $props | Where-Object { $_ -match '(?i)end' } | Select-Object -First 1

                # Parse each date if available
                $purchaseDate       = if ($purchaseField -and $warrantyInfo.$purchaseField)     { Get-Date $warrantyInfo.$purchaseField     -Format 'yyyy-MM-dd' } else { "" }
                $shipDate           = if ($shipField     -and $warrantyInfo.$shipField)         { Get-Date $warrantyInfo.$shipField         -Format 'yyyy-MM-dd' } else { "" }
                $warrantyStartDate  = if ($startField    -and $warrantyInfo.$startField)        { Get-Date $warrantyInfo.$startField        -Format 'yyyy-MM-dd' } else { "" }
                $warrantyEndDate    = if ($endField      -and $warrantyInfo.$endField)          { Get-Date $warrantyInfo.$endField          -Format 'yyyy-MM-dd' } else { "" }

                # Determine warranty active status based on end date
                $today = Get-Date
                if ($warrantyEndDate -and (Get-Date $warrantyEndDate) -ge $today) {
                    $isActive = "True"
                } else {
                    $isActive = "False"
                }

                # (Optional) Log API status for debugging
                "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] API status for ${serialNumber}: $($warrantyInfo.status)" | Out-File -FilePath $logPath -Append

                # Ensure PurchaseDate and ShipDate are populated: use warranty dates if direct fields missing
                if ([string]::IsNullOrEmpty($purchaseDate)) { $purchaseDate = $warrantyStartDate }
                if ([string]::IsNullOrEmpty($shipDate))     { $shipDate     = $warrantyEndDate }

                # Build consolidated response object
                $allResponses += [PSCustomObject]@{
                    Serial             = $serialNumber
                    Product            = $response.Product
                    InWarranty         = $isActive
                    PurchaseDate       = $purchaseDate
                    ShipDate           = $shipDate
                    WarrantyStartDate  = $warrantyStartDate
                    WarrantyEndDate    = $warrantyEndDate
                    Country            = $response.Country
                }

                "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Success: $serialNumber processed." | Out-File -FilePath $logPath -Append
                Write-Host "Processed serial number ${serialNumber}: Success"
                $success = $true
                break
            } else {
                "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Warning: No warranty data returned for $serialNumber." | Out-File -FilePath $logPath -Append
                Write-Host "Processed serial number ${serialNumber}: No warranty data returned."
            }
        } catch {
            "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Warning: Attempt $i of $maxRetries failed for $serialNumber. Error: $_" | Out-File -FilePath $logPath -Append
            Write-Host "Processed serial number ${serialNumber}: Attempt $i failed with error: $($_.Exception.Message)"
            Start-Sleep -Seconds $retryDelay
        }
    }

    if (-not $success) {
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Error: Skipping $serialNumber after $maxRetries failed attempts." | Out-File -FilePath $logPath -Append
        Write-Host "Processed serial number ${serialNumber}: Failed after $maxRetries attempts."
    }
}


# Export consolidated CSV for all serials
$allResponses | Export-Csv -Path $localExportPath -NoTypeInformation -Encoding UTF8
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] CSV exported to $localExportPath" | Out-File -FilePath $logPath -Append

Write-Host "Processing complete. Total serial numbers processed: $($serialNumbers.Count). Successful warranty fetches: $($allResponses.Count)."

"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Script completed." | Out-File -FilePath $logPath -Append
