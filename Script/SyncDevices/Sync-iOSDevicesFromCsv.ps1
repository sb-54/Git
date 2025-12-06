<#
.SYNOPSIS
    Syncs iOS/iPadOS devices using Microsoft Graph API.

.DESCRIPTION
    This script initiates device sync requests for iOS/iPadOS devices using the Microsoft Graph API.
    Devices can be synced individually by serial number, from a CSV file, or by device ID.

.REQUIREMENTS
    - PowerShell 7+ (macOS / cross-platform)
    - Microsoft.Graph PowerShell module
    - Intune Graph delegated permissions:
        DeviceManagementManagedDevices.ReadWrite.All

.NOTES
    Author:  L3mon
#>

# Check if already connected to Microsoft Graph
$context = Get-MgContext -ErrorAction SilentlyContinue

if (-not $context -or $context.Scopes -notcontains 'DeviceManagementManagedDevices.ReadWrite.All') {
    Connect-MgGraph -Scopes 'DeviceManagementManagedDevices.ReadWrite.All' -NoWelcome
}

# Function to sync a device by device ID
Function Invoke-iOSDeviceSync() {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $DeviceId
    )
    
    $graphApiVersion = 'Beta'
    $Resource = "deviceManagement/managedDevices/$DeviceId/syncDevice"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
    
    try {
        Invoke-MgGraphRequest -Uri $uri -Method Post -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# Function to get device ID from serial number
Function Get-iOSDeviceIdBySerial() {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $SerialNumber
    )
    
    $graphApiVersion = 'Beta'
    $uri = "https://graph.microsoft.com/$graphApiVersion/deviceManagement/managedDevices?`$filter=serialNumber eq '$SerialNumber'"
    
    try {
        $device = (Invoke-MgGraphRequest -Uri $uri -Method Get -ErrorAction Stop).Value
        return $device.id
    }
    catch {
        return $null
    }
}

try {
    $CSVPath = "/Users/hea2eq/Downloads/SyncDevices.csv"
    
    if (-not (Test-Path $CSVPath)) {
        throw "CSV file not found at: $CSVPath"
    }
    
    $Devices = Import-Csv -Path $CSVPath
    
    if (-not $Devices -or $Devices.Count -eq 0) {
        throw "CSV is empty or unreadable"
    }

    if (-not ($Devices | Get-Member -Name 'Serial')) {
        throw "CSV must contain 'Serial' column."
    }
    
    # Clean up data and remove empty entries
    $Devices = $Devices | ForEach-Object {
        if ($_.Serial) { $_.Serial = $_.Serial.Trim() }
        $_
    } | Where-Object { $_.Serial }
    
    if (-not $Devices) {
        throw "No valid device entries found with Serial"
    }
    
    $totalSynced = 0
    $totalFailed = 0
    
    Write-Host ""
    Write-Host "=== iOS Device Sync via Microsoft Graph ==="
    Write-Host ""
    Write-Host "Serial        Status"
    Write-Host "------        ------"
    
    foreach ($device in $Devices) {
        $serial = $device.Serial
        
        # Get device ID from serial number
        $deviceId = Get-iOSDeviceIdBySerial -SerialNumber $serial
        
        if ($null -eq $deviceId) {
            Write-Host "$($serial.PadRight(14)) Not Found ❌"
            $totalFailed++
        }
        else {
            # Attempt to sync the device
            $syncSuccess = Invoke-iOSDeviceSync -DeviceId $deviceId
            
            if ($syncSuccess) {
                Write-Host "$($serial.PadRight(14)) Sync Initiated ✅"
                $totalSynced++
            }
            else {
                Write-Host "$($serial.PadRight(14)) Sync Failed ❌"
                $totalFailed++
            }
        }
        
        Start-Sleep -Milliseconds 500
    }
    
    Write-Host ""
    Write-Host "Summary: $totalSynced / $($totalSynced + $totalFailed) devices sync initiated successfully."
    Write-Host ""
    Write-Host "Sync Summary : $totalSynced Devices ✅ / $totalFailed Devices ❌"
    
} catch {
    Write-Host "`nSCRIPT FAILED: $($_.Exception.Message)"
    Write-Host "Stack Trace: $($_.ScriptStackTrace)"
}

Write-Host "`nScript execution completed"
