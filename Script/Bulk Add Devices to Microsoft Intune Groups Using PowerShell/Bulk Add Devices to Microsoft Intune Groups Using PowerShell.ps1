﻿
#.SYNOPSIS
#<Bulk add device in Inutne group Using PowerShell>
#>
<# 
.DESCRIPTION
<Bulk add device in Inutne group Using PowerShell>
Demo
<YouTube video link--> https://youtu.be/lJGiGXPTwZo
INPUTS
<Provide all required inforamtion in User Input Section-line No 43 & 44 >

OUTPUTS
<You will get repsort in text file like this if you input file is in c:\temp\ >
example 📄 Added Devices File:      C:\Temp\DeviceList-AddedDevices.txt
        📄 Already Present File:    C:\Temp\DeviceList-AlreadyPresentDevices.txt
        📄 Failed Devices File:     C:\Temp\DeviceList-FailedDevices.txt
<# 

NOTES
Version:         1.1
Author:          Chander Mani Pandey
Creation Date:   1 July 2025
Update Date :    
Find Author on 
Youtube:-        https://www.youtube.com/@chandermanipandey8763
Twitter:-        https://twitter.com/Mani_CMPandey
LinkedIn:-       https://www.linkedin.com/in/chandermanipandey
#>
# 
#============================= User Input Section Start  ==============================

# Enter the Intune group name and path to device list

$targetGroupName = "CMP_Test"                                             # Replace with your actual group name
$deviceListPath  = "C:\Temp\Bulk_Add_Device_List.txt"                               # Replace with your actual device list path

#============================= Module Setup ===========================================
Clear-Host
Write-Host "====================================================================================================================================" -ForegroundColor  Magenta
Write-Host "======================================== Bulk add device in Inutne group Using PowerShell ==========================================" -ForegroundColor  Magenta
Write-Host "====================================================================================================================================" -ForegroundColor  Magenta
Write-Host ""


$error.clear() ## this is the clear error history 
Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' 
$ErrorActionPreference = 'SilentlyContinue';

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host "📦 Microsoft.Graph module not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
}

# Check if the device list file exists
if (-not (Test-Path $deviceListPath)) {
    Write-Host "❌ Device list file not found: $deviceListPath" -ForegroundColor Red
    break
}

#============================= Connect to Graph ==============================

Connect-Graph -Scopes "GroupMember.ReadWrite.All", "Device.ReadWrite.All"

# Dynamically generate log file paths in the same folder as the device list
$deviceListDir  = Split-Path -Path $deviceListPath
$deviceListBase = [System.IO.Path]::GetFileNameWithoutExtension($deviceListPath)

$addedLogPath   = Join-Path -Path $deviceListDir -ChildPath "$deviceListBase-AddedDevices.txt"
$failedLogPath  = Join-Path -Path $deviceListDir -ChildPath "$deviceListBase-FailedDevices.txt"
$alreadyLogPath = Join-Path -Path $deviceListDir -ChildPath "$deviceListBase-AlreadyPresentDevices.txt"

# Remove old logs if they exist
Remove-Item -Path $addedLogPath, $failedLogPath, $alreadyLogPath -ErrorAction SilentlyContinue

# Read device list
$deviceList = Get-Content -Path $deviceListPath

# Retrieve group ID from Graph
$groupResponse = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$targetGroupName'" -Method GET
$targetGroupId = $groupResponse.value[0].id

if (-not $targetGroupId) {
    Write-Host "❌ Group '$targetGroupName' not found. Exiting." -ForegroundColor Red
    break
}

if (-not $deviceList) {
    Write-Host "❌ Device list is empty. Exiting." -ForegroundColor Red
    break
}

#============================= Device Processing ==============================

$successCount = 0
$alreadyCount = 0
$failureCount = 0

foreach ($currentDeviceName in $deviceList) {
    $trimmedDeviceName = $currentDeviceName.Trim()
    Write-Host "`n➡️  Processing: $trimmedDeviceName"

    $deviceLookupResponse = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$trimmedDeviceName'" -Method GET
    $currentDeviceId = $deviceLookupResponse.value[0].id

    if (-not $currentDeviceId) {
        Write-Host "⚠️  Device '$trimmedDeviceName' not found." -ForegroundColor Yellow
        Add-Content -Path $failedLogPath -Value $trimmedDeviceName
        $failureCount++
        continue
    }

    $addToGroupUrl = "https://graph.microsoft.com/v1.0/groups/$targetGroupId/members/`$ref"
    $jsonPayload = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$currentDeviceId" } | ConvertTo-Json -Depth 3

    try {
        Invoke-MgGraphRequest -Uri $addToGroupUrl -Method POST -Body $jsonPayload -ContentType "application/json"
        Write-Host "✅ Added: $trimmedDeviceName" -ForegroundColor Green
        Add-Content -Path $addedLogPath -Value $trimmedDeviceName
        $successCount++
    } catch {
        $fullErrorText = $_ | Out-String
        if ($fullErrorText -like '*added object references already exist*') {
            Write-Host "ℹ️  Already in group: $trimmedDeviceName" -ForegroundColor Cyan
            Add-Content -Path $alreadyLogPath -Value $trimmedDeviceName
            $alreadyCount++
        } else {
            Write-Host "❌ Failed to add '$trimmedDeviceName'. Error: $($_.Exception.Message)" -ForegroundColor Red
            Add-Content -Path $failedLogPath -Value $trimmedDeviceName
            $failureCount++
        }
    }
}

#============================= Summary =============================================

$totalProcessed = $successCount + $alreadyCount + $failureCount

Write-Host "`n==================== Summary ==========================================" -ForegroundColor Cyan
Write-Host "📦 Total Devices Processed: $totalProcessed"
Write-Host "✅ Devices Added:           $successCount"
Write-Host "ℹ️ Already in Group:        $alreadyCount"
Write-Host "❌ Devices Failed:          $failureCount"
Write-Host "`n📄 Added Devices File:      $addedLogPath"
Write-Host "📄 Already Present File:    $alreadyLogPath"
Write-Host "📄 Failed Devices File:     $failedLogPath"
Write-Host "=========================================================================" -ForegroundColor Cyan

Disconnect-Graph
