<#
.SYNOPSIS
Identify all iPads removed from Apple Business Manager (ABM) in Microsoft Intune

.DESCRIPTION
Queries Microsoft Graph API to find all imported Apple device identities that have been
marked as deleted from ABM. Exports results to CSV for further analysis.

.REQUIREMENTS
- PowerShell 7+ (for macOS)
- Microsoft.Graph module
- DeviceManagementServiceConfig.Read.All permission
- Active Intune license
#>

# Check if already connected to Microsoft Graph
$context = Get-MgContext -ErrorAction SilentlyContinue

if (-not $context -or $context.Scopes -notcontains 'DeviceManagementServiceConfig.Read.All') {
    Write-Host "🔐 Connecting to Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes @(
        'DeviceManagementServiceConfig.Read.All',
        'DeviceManagementConfiguration.Read.All',
        'DeviceManagementManagedDevices.Read.All'
    ) -NoWelcome
    Write-Host "✅ Connected to Microsoft Graph" -ForegroundColor Green
} else {
    Write-Host "✅ Already connected to Microsoft Graph" -ForegroundColor Green
}

# Function: Get ADE Token with better property detection
Function Get-ADEToken {
    try {
        Write-Host "   🔍 Querying ADE tokens..." -ForegroundColor Gray
        $uri = "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings"
        $response = Invoke-MsgGraphRequest -Uri $uri -Method Get -ErrorAction Stop
        
        Write-Host "   📊 API Response received" -ForegroundColor Gray
        
        if (-not $response -or -not $response.Value -or $response.Value.Count -eq 0) {
            Write-Warning "   ⚠️  No ADE tokens found"
            return $null
        }
        
        Write-Host "   ✅ Found $($response.Value.Count) ADE token(s)" -ForegroundColor Green
        
        # Debug: Show all token properties
        $firstToken = $response.Value[0]
        Write-Host "   🏷️  Token: $($firstToken.tokenName)" -ForegroundColor Gray
        
        # Check what ID property exists
        $tokenProperties = $firstToken | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        Write-Host "   🔍 Available properties: $($tokenProperties -join ', ')" -ForegroundColor Gray
        
        # Try different possible ID properties
        $tokenId = $null
        if ($firstToken.id) {
            $tokenId = $firstToken.id
            Write-Host "   ✅ Using 'id' property: $tokenId" -ForegroundColor Green
        } elseif ($firstToken.Id) {
            $tokenId = $firstToken.Id
            Write-Host "   ✅ Using 'Id' property: $tokenId" -ForegroundColor Green
        } elseif ($firstToken.tokenId) {
            $tokenId = $firstToken.tokenId
            Write-Host "   ✅ Using 'tokenId' property: $tokenId" -ForegroundColor Green
        } elseif ($firstToken.depTokenId) {
            $tokenId = $firstToken.depTokenId
            Write-Host "   ✅ Using 'depTokenId' property: $tokenId" -ForegroundColor Green
        } else {
            Write-Warning "   ⚠️  No recognizable ID property found"
            Write-Host "   📋 Token object: $($firstToken | ConvertTo-Json -Depth 2)" -ForegroundColor Gray
        }
        
        # Add the ID to the token object for consistency
        if ($tokenId) {
            $firstToken | Add-Member -MemberType NoteProperty -Name "TokenId" -Value $tokenId -Force
        }
        
        return $response.Value
    }
    catch {
        Write-Error "   ❌ Failed to retrieve ADE tokens: $($_.Exception.Message)"
        return $null
    }
}

# Function: Get All Imported Apple Device Identities
Function Get-ImportedAppleDevices {
    Param([Parameter(Mandatory = $true)] $Token)
    
    # Try to get the correct ID from the token
    $tokenId = $null
    if ($Token.TokenId) {
        $tokenId = $Token.TokenId
    } elseif ($Token.id) {
        $tokenId = $Token.id  
    } elseif ($Token.Id) {
        $tokenId = $Token.Id
    } else {
        Write-Error "Cannot determine token ID from token object"
        return @()
    }
    
    try {
        Write-Host "   🔍 Querying imported devices for token: $tokenId" -ForegroundColor Gray
        $uri = "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings('$tokenId')/importedAppleDeviceIdentities"
        $allDevices = @()
        
        Write-Host "   📡 Making first API call..." -ForegroundColor Gray
        
        do {
            $response = Invoke-MgGraphRequest -Uri $uri -Method Get -ErrorAction Stop
            
            if ($response.value) {
                $allDevices += $response.value
                Write-Host "   📱 Retrieved $($response.value.Count) devices (Total: $($allDevices.Count))" -ForegroundColor Gray
            }
            
            $uri = $response.'@odata.nextLink'
            if ($uri) {
                Write-Host "   🔄 Getting next page..." -ForegroundColor Gray
            }
            
        } while ($uri)
        
        Write-Host "   ✅ Total devices retrieved: $($allDevices.Count)" -ForegroundColor Green
        return $allDevices
    }
    catch {
        Write-Error "   ❌ Failed to retrieve imported Apple devices: $($_.Exception.Message)"
        Write-Host "   🔍 URI used: $uri" -ForegroundColor Red
        return @()
    }
}

# Function: Get Device Details from Managed Devices (if enrolled)
Function Get-ManagedDeviceDetails {
    Param([Parameter(Mandatory = $true)] $SerialNumber)
    
    try {
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=serialNumber eq '$SerialNumber'"
        $response = Invoke-MgGraphRequest -Uri $uri -Method Get -ErrorAction Stop
        
        if ($response.value -and $response.value.Count -gt 0) {
            $device = $response.value[0]
            return @{
                DeviceName = $device.deviceName
                UserName = $device.userDisplayName
                LastSyncDateTime = $device.lastSyncDateTime
                ComplianceState = $device.complianceState
                EnrollmentType = $device.deviceEnrollmentType
                IsManaged = $true
            }
        }
        return @{ IsManaged = $false }
    }
    catch {
        return @{ IsManaged = $false }
    }
}

# Main Script
try {
    Write-Host "🚀 Finding iPads Removed from Apple Business Manager" -ForegroundColor Magenta
    Write-Host "📅 Compatible with October 2025 Graph API" -ForegroundColor Magenta
    Write-Host "=" * 70 -ForegroundColor Gray
    
    # Get ADE token with better property detection
    Write-Host "`n🔑 Retrieving ADE enrollment tokens..." -ForegroundColor Blue
    $tokens = Get-ADEToken
    
    if (-not $tokens -or $tokens.Count -eq 0) {
        throw "No ADE enrollment tokens found"
    }
    
    $token = $tokens[0]
    Write-Host "✅ Using token: $($token.tokenName)" -ForegroundColor Green
    
    # Get all imported Apple devices - pass the whole token object
    Write-Host "`n📱 Retrieving all imported Apple devices..." -ForegroundColor Blue
    $allDevices = Get-ImportedAppleDevices -Token $token
    
    if (-not $allDevices -or $allDevices.Count -eq 0) {
        Write-Host "⚠️  No imported Apple devices found for this token" -ForegroundColor Yellow
        Write-Host "💡 This could mean:" -ForegroundColor Yellow
        Write-Host "   - No devices have been synced from Apple Business Manager" -ForegroundColor White
        Write-Host "   - ADE token needs to be synced" -ForegroundColor White
        Write-Host "   - Devices are managed through a different token" -ForegroundColor White
        return
    }
    
    Write-Host "✅ Retrieved $($allDevices.Count) total imported Apple devices" -ForegroundColor Green
    
    # Filter for iPads removed from ABM
    Write-Host "`n🔍 Filtering for devices removed from ABM..." -ForegroundColor Blue
    
    # Show sample device for debugging
    if ($allDevices.Count -gt 0) {
        $sampleDevice = $allDevices[0]
        Write-Host "   📋 Sample device properties:" -ForegroundColor Gray
        Write-Host "      - isDeleted: $($sampleDevice.isDeleted)" -ForegroundColor Gray
        Write-Host "      - platform: $($sampleDevice.platform)" -ForegroundColor Gray
        Write-Host "      - description: $($sampleDevice.description)" -ForegroundColor Gray
    }
    
    $removedFromABM = $allDevices | Where-Object { 
        $_.isDeleted -eq $true -and 
        ($_.platform -eq 'iOS' -or $_.platform -eq 'iPadOS' -or $_.description -like '*iPad*')
    }
    
    if (-not $removedFromABM -or $removedFromABM.Count -eq 0) {
        Write-Host "✅ No iPads found that have been removed from ABM" -ForegroundColor Green
        Write-Host "`n📊 Summary:" -ForegroundColor Cyan
        Write-Host "   Total Apple devices: $($allDevices.Count)" -ForegroundColor White
        Write-Host "   iPads removed from ABM: 0" -ForegroundColor White
        
        # Show breakdown by platform and isDeleted status
        $platformBreakdown = $allDevices | Group-Object -Property platform
        Write-Host "   Platform breakdown:" -ForegroundColor White
        foreach ($group in $platformBreakdown) {
            Write-Host "      - $($group.Name): $($group.Count)" -ForegroundColor White
        }
        
        $deletedBreakdown = $allDevices | Group-Object -Property isDeleted
        Write-Host "   Deletion status:" -ForegroundColor White
        foreach ($group in $deletedBreakdown) {
            $status = if ($group.Name -eq 'True') { 'Removed from ABM' } else { 'Active in ABM' }
            Write-Host "      - $status: $($group.Count)" -ForegroundColor White
        }
        
        return
    }
    
    Write-Host "⚠️  Found $($removedFromABM.Count) iPads removed from ABM" -ForegroundColor Yellow
    
    # Prepare detailed report
    Write-Host "`n📋 Gathering detailed information..." -ForegroundColor Blue
    $detailedReport = @()
    
    foreach ($device in $removedFromABM) {
        Write-Host "   🔍 Processing: $($device.serialNumber)" -ForegroundColor Gray
        
        # Get managed device details if still enrolled
        $managedDetails = Get-ManagedDeviceDetails -SerialNumber $device.serialNumber
        
        $deviceInfo = [PSCustomObject]@{
            SerialNumber = $device.serialNumber
            Description = $device.description
            Platform = $device.platform
            IsSupervised = $device.isSupervised
            DiscoverySource = $device.discoverySource
            EnrollmentState = $device.enrollmentState
            CreatedDateTime = $device.createdDateTime
            LastContactedDateTime = $device.lastContactedDateTime
            RemovedFromABM = $device.isDeleted
            # Managed device info (if still enrolled)
            IsStillManaged = $managedDetails.IsManaged
            CurrentDeviceName = if ($managedDetails.IsManaged) { $managedDetails.DeviceName } else { "Not Managed" }
            CurrentUser = if ($managedDetails.IsManaged) { $managedDetails.UserName } else { "N/A" }
            LastSyncDateTime = if ($managedDetails.IsManaged) { $managedDetails.LastSyncDateTime } else { "N/A" }
            ComplianceState = if ($managedDetails.IsManaged) { $managedDetails.ComplianceState } else { "N/A" }
            EnrollmentType = if ($managedDetails.IsManaged) { $managedDetails.EnrollmentType } else { "N/A" }
        }
        
        $detailedReport += $deviceInfo
    }
    
    # Display summary
    Write-Host "`n📊 SUMMARY REPORT:" -ForegroundColor Green
    Write-Host "=" * 70 -ForegroundColor Gray
    Write-Host "📱 Total Apple devices in ADE: $($allDevices.Count)" -ForegroundColor White
    Write-Host "❌ iPads removed from ABM: $($removedFromABM.Count)" -ForegroundColor Red
    
    $stillManaged = ($detailedReport | Where-Object { $_.IsStillManaged -eq $true }).Count
    $notManaged = ($detailedReport | Where-Object { $_.IsStillManaged -eq $false }).Count
    
    Write-Host "🔒 Still managed in Intune: $stillManaged" -ForegroundColor Yellow
    Write-Host "🔓 No longer managed: $notManaged" -ForegroundColor Cyan
    
    # Show devices
    Write-Host "`n📋 DEVICES REMOVED FROM ABM:" -ForegroundColor Yellow
    Write-Host "=" * 70 -ForegroundColor Gray
    
    foreach ($device in $detailedReport) {
        $status = if ($device.IsStillManaged) { "Still Managed" } else { "Not Managed" }
        $statusColor = if ($device.IsStillManaged) { "Yellow" } else { "Red" }
        
        Write-Host "📱 $($device.SerialNumber)" -ForegroundColor White
        Write-Host "   Description: $($device.Description)" -ForegroundColor Gray
        Write-Host "   Platform: $($device.Platform)" -ForegroundColor Gray
        Write-Host "   Status: $status" -ForegroundColor $statusColor
        Write-Host "   Current Name: $($device.CurrentDeviceName)" -ForegroundColor Gray
        Write-Host "   Current User: $($device.CurrentUser)" -ForegroundColor Gray
        Write-Host "   Last Contact: $($device.LastContactedDateTime)" -ForegroundColor Gray
        Write-Host ""
    }
    
    # Export to CSV
    $csvPath = "/Users/hea2eq/Downloads/ipads_removed_from_abm.csv"
    $detailedReport | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "📄 Detailed report exported to: $csvPath" -ForegroundColor Green
    
} catch {
    Write-Host "`n❌ SCRIPT FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n✅ Script completed successfully" -ForegroundColor Green
