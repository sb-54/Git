<#
.SYNOPSIS
Bulk wipe iOS devices in Microsoft Intune based on serial numbers from CSV

.DESCRIPTION
Reads CSV with Serial column, finds devices in Intune, and performs remote wipe
Uses Microsoft Graph API with proper error handling

.REQUIREMENTS
- PowerShell 7+ (for macOS)
- Microsoft.Graph module
- CSV format: Serial column
- DeviceManagementManagedDevices.PrivilegedOperations.All permission
#>

# Check if already connected to Microsoft Graph
$context = Get-MgContext -ErrorAction SilentlyContinue

if (-not $context -or $context.Scopes -notcontains 'DeviceManagementManagedDevices.PrivilegedOperations.All') {
    Write-Host "🔐 Connecting to Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes @(
        'DeviceManagementManagedDevices.ReadWrite.All',
        'DeviceManagementManagedDevices.PrivilegedOperations.All'
    ) -NoWelcome
    Write-Host "✅ Connected to Microsoft Graph" -ForegroundColor Green
} else {
    Write-Host "✅ Already connected to Microsoft Graph" -ForegroundColor Green
}

# Function: Find Device by Serial Number
Function Find-DeviceBySerial {
    Param([Parameter(Mandatory = $true)] $SerialNumber)
    
    try {
        # Search managed devices by serial number
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=serialNumber eq '$SerialNumber'"
        $response = Invoke-MgGraphRequest -Uri $uri -Method Get -ErrorAction Stop
        
        if ($response.value -and $response.value.Count -gt 0) {
            $device = $response.value[0]
            return @{
                Found = $true
                Id = $device.id
                DeviceName = $device.deviceName
                SerialNumber = $device.serialNumber
                Platform = $device.operatingSystem
                UserName = $device.userDisplayName
                LastSyncDateTime = $device.lastSyncDateTime
                ComplianceState = $device.complianceState
                EnrollmentType = $device.deviceEnrollmentType
            }
        }
        else {
            return @{ Found = $false }
        }
    }
    catch {
        Write-Warning "❌ Error searching for device $SerialNumber : $($_.Exception.Message)"
        return @{ Found = $false }
    }
}

# Function: Wipe Device
Function Invoke-DeviceWipe {
    Param(
        [Parameter(Mandatory = $true)] $DeviceId,
        [Parameter(Mandatory = $true)] $SerialNumber,
        [Parameter(Mandatory = $false)] $KeepEnrollmentData = $false,
        [Parameter(Mandatory = $false)] $KeepUserData = $false
    )
    
    try {
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices('$DeviceId')/wipe"
        
        # Wipe parameters for iOS
        $body = @{
            keepEnrollmentData = $KeepEnrollmentData
            keepUserData = $KeepUserData
        } | ConvertTo-Json -Depth 3
        
        Write-Host "🔄 Wiping device $SerialNumber..." -ForegroundColor Yellow
        Invoke-MgGraphRequest -Uri $uri -Method Post -Body $body -ContentType 'application/json' -ErrorAction Stop
        Write-Host "✅ Wipe command sent to $SerialNumber" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "❌ Failed to wipe device $SerialNumber : $($_.Exception.Message)"
        return $false
    }
}

# Main Script
try {
    # CSV Configuration
    $CSVPath = "/Users/hea2eq/Downloads/devices_to_wipe.csv"
    
    Write-Host "🚀 Starting iOS Device Wipe Script" -ForegroundColor Magenta
    Write-Host "=" * 60 -ForegroundColor Gray
    
    # Verify CSV file exists
    if (-not (Test-Path $CSVPath)) {
        throw "CSV file not found at: $CSVPath"
    }
    
    # Read CSV
    $devices = Import-Csv -Path $CSVPath | Where-Object {
        $_.Serial -and $_.Serial.Trim() -ne ""
    } | ForEach-Object {
        $_.Serial = $_.Serial.Trim()
        $_
    }
    
    if (-not $devices) {
        throw "No valid serial numbers found in CSV"
    }
    
    Write-Host "📋 Found $($devices.Count) devices to process" -ForegroundColor Cyan
    
    # Process each device
    $totalWiped = 0
    $totalFailed = 0
    $notFound = 0
    
    foreach ($device in $devices) {
        $serial = $device.Serial
        
        Write-Host "`n🔍 Processing device: $serial" -ForegroundColor Cyan
        
        # Find device in Intune
        $deviceInfo = Find-DeviceBySerial -SerialNumber $serial
        
        if (-not $deviceInfo.Found) {
            Write-Warning "❌ Device $serial not found in Intune"
            $notFound++
            continue
        }
        
        # Display device information
        Write-Host "✅ Device found:" -ForegroundColor Green
        Write-Host "   📱 Name: $($deviceInfo.DeviceName)" -ForegroundColor White
        Write-Host "   📊 Platform: $($deviceInfo.Platform)" -ForegroundColor White
        Write-Host "   👤 User: $($deviceInfo.UserName)" -ForegroundColor White
        
        # Confirm iOS device
        if ($deviceInfo.Platform -ne 'iOS') {
            Write-Warning "⚠️  Device $serial is not iOS ($($deviceInfo.Platform)). Skipping."
            $totalFailed++
            continue
        }
        
        # Perform wipe
        $wipeSuccess = Invoke-DeviceWipe -DeviceId $deviceInfo.Id -SerialNumber $serial
        
        if ($wipeSuccess) {
            $totalWiped++
        } else {
            $totalFailed++
        }
        
        # Brief delay between operations
        Start-Sleep -Seconds 1
    }
    
    # Final Summary
    Write-Host "`n🎯 WIPE SUMMARY:" -ForegroundColor Green
    Write-Host "✅ Successfully wiped: $totalWiped devices" -ForegroundColor Green
    
    if ($totalFailed -gt 0) {
        Write-Host "❌ Failed/Skipped: $totalFailed devices" -ForegroundColor Red
    }
    
    if ($notFound -gt 0) {
        Write-Host "🔍 Not found: $notFound devices" -ForegroundColor Yellow
    }
    
    Write-Host "📊 Total processed: $($totalWiped + $totalFailed + $notFound) devices" -ForegroundColor Blue
    
} catch {
    Write-Host "❌ SCRIPT FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Script completed" -ForegroundColor Green
