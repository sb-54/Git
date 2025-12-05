<#
.SYNOPSIS
Bulk assign iOS/iPadOS devices to ADE enrollment profiles using serial numbers from CSV
Fixed for October 2025 Microsoft Graph API changes

.DESCRIPTION
Uses the correct API parameter for ADE device assignment after October 2025 API changes

.REQUIREMENTS
- PowerShell 7+ (for macOS)
- Microsoft.Graph module
- CSV format: Serial,EnrolmentProfile
- DeviceManagementConfiguration.ReadWrite.All permission
- DeviceManagementServiceConfig.ReadWrite.All permission
#>

# Check if already connected to Microsoft Graph
$context = Get-MgContext -ErrorAction SilentlyContinue

if (-not $context -or $context.Scopes -notcontains 'DeviceManagementConfiguration.ReadWrite.All') {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes 'DeviceManagementConfiguration.ReadWrite.All', 'DeviceManagementServiceConfig.ReadWrite.All' -NoWelcome
    Write-Host "Connected to Microsoft Graph" -ForegroundColor Green
}
else {
    Write-Host "Already connected to Microsoft Graph" -ForegroundColor Green
}

# Function to get ADE Enrollment Token
Function Get-ADEEnrolmentToken() {
    $graphApiVersion = 'Beta'
    $Resource = 'deviceManagement/depOnboardingSettings'
    try {
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
        (Invoke-MgGraphRequest -Uri $uri -Method Get -ErrorAction Stop).Value
    }
    catch {
        Write-Error "Failed to retrieve ADE tokens: $($_.Exception.Message)"
        return
    }
}

# Function to get Enrollment Profiles for a token
Function Get-ADEEnrolmentProfile() {
    Param(
        [Parameter(Mandatory = $true)]
        $Id
    )
    $graphApiVersion = 'Beta'
    $Resource = "deviceManagement/depOnboardingSettings/$Id/enrollmentProfiles"
    try {
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
        (Invoke-MgGraphRequest -Uri $uri -Method Get -ErrorAction Stop).Value
    }
    catch {
        Write-Error "Failed to retrieve ADE enrollment profiles: $($_.Exception.Message)"
        return
    }
}

# Function to assign ADE devices - FINAL OCTOBER 2025 VERSION
Function Add-ADEEnrolmentProfileAssignment() {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Id,
        [Parameter(Mandatory = $true)]
        [string] $ProfileID,
        [Parameter(Mandatory = $true)]
        [string[]] $DeviceSerials
    )
    
    $graphApiVersion = 'Beta'
    $Resource = "deviceManagement/depOnboardingSettings('$Id')/enrollmentProfiles('$ProfileID')/updateDeviceProfileAssignment"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
    
    foreach ($serial in $DeviceSerials) {
        try {
            Write-Host -NoNewline "Assigning $serial " -ForegroundColor White
            
            # CRITICAL FIX: Use deviceIds parameter (not deviceSerialNumbers) but still pass serial numbers as values
            $Body = @{ deviceIds = @($serial) } | ConvertTo-Json -Depth 3
            Invoke-MgGraphRequest -Uri $uri -Method Post -Body $Body -ContentType 'application/json' -ErrorAction Stop
            
            Write-Host "✅" -ForegroundColor Green
        }
        catch {
            Write-Host "❌" -ForegroundColor Red
        }
    }
}

# Main execution
try {
    # Your CSV path
    $CSVPath = "/Users/s/Downloads/devices.csv"
    
    Write-Host "Starting ADE Profile Assignment Script" -ForegroundColor Magenta
    Write-Host "Fixed for October 2025 Microsoft Graph API changes" -ForegroundColor Magenta
    
    # Verify CSV exists
    if (-not (Test-Path $CSVPath)) {
        throw "CSV file not found at: $CSVPath"
    }
    
    Write-Host "Reading devices from: $CSVPath" -ForegroundColor Blue
    $Devices = Import-Csv -Path $CSVPath
    
    if (-not $Devices -or $Devices.Count -eq 0) {
        throw "CSV is empty or unreadable"
    }

    if (-not ($Devices | Get-Member -Name 'Serial') -or -not ($Devices | Get-Member -Name 'EnrolmentProfile')) {
        throw "CSV must contain 'Serial' and 'EnrolmentProfile' columns."
    }

    Write-Host "Found $($Devices.Count) devices in CSV" -ForegroundColor Blue
    
    # Clean up data and remove empty entries
    $Devices = $Devices | ForEach-Object {
        if ($_.Serial) { $_.Serial = $_.Serial.Trim() }
        if ($_.EnrolmentProfile) { $_.EnrolmentProfile = $_.EnrolmentProfile.Trim() }
        $_
    } | Where-Object { $_.Serial -and $_.EnrolmentProfile }
    
    if (-not $Devices) {
        throw "No valid device entries found with both Serial and EnrolmentProfile"
    }
    
    Write-Host "Found $($Devices.Count) valid device entries" -ForegroundColor Green
    
    $UniqueDeviceProfiles = $Devices |
    Select-Object -ExpandProperty EnrolmentProfile -Unique
    
    Write-Host "Target profiles: $($UniqueDeviceProfiles -join ', ')" -ForegroundColor Cyan
    
    # Build assignments grouped by enrollment profile
    $Assignments = $Devices | Group-Object -Property EnrolmentProfile
    
    Write-Host "Getting ADE enrollment token..." -ForegroundColor Blue
    $TokenList = @((Get-ADEEnrolmentToken) | Where-Object { $_ })
    
    if (-not $TokenList) {
        throw "No ADE enrollment tokens found. Ensure Apple Business Manager is connected."
    }
    
    if ($TokenList.Count -gt 1) {
        Write-Warning "Multiple ADE tokens found. Using first token: $($TokenList[0].tokenName)"
    }
    
    $Token = $TokenList[0]
    Write-Host "Using token: $($Token.tokenName)" -ForegroundColor Green
    
    # Get all available enrollment profiles
    Write-Host "Getting enrollment profiles..." -ForegroundColor Blue
    $AllProfiles = Get-ADEEnrolmentProfile -Id $Token.id
    
    if (-not $AllProfiles) {
        throw "No enrollment profiles were returned for token '$($Token.tokenName)'."
    }
    
    Write-Host "Found $($AllProfiles.Count) available profiles" -ForegroundColor Blue
    
    # Process assignments
    Write-Host "Starting ADE profile assignments..." -ForegroundColor Magenta
    
    $totalAssigned = 0
    $totalFailed = 0
    
    foreach ($Assignment in $Assignments) {
        $ProfileName = $Assignment.Name
        $DeviceSerials = $Assignment.Group.Serial |
        Where-Object { $_ } |
        Sort-Object -Unique
        
        if (-not $DeviceSerials) {
            Write-Warning "Skipping profile '$ProfileName' because no valid serial numbers were found."
            continue
        }
        
        Write-Host "`nProcessing profile: '$ProfileName'" -ForegroundColor Cyan
        
        $EnrolmentProfile = $AllProfiles | Where-Object { $_.displayName -eq $ProfileName }
        
        if (-not $EnrolmentProfile) {
            Write-Warning "Profile '$ProfileName' not found"
            $totalFailed += $DeviceSerials.Count
            continue
        }
        
        Write-Host "Found profile: $($EnrolmentProfile.displayName)" -ForegroundColor Green
        
        # Track success/failure for each device
        foreach ($serial in $DeviceSerials) {
            try {
                Add-ADEEnrolmentProfileAssignment -Id $Token.id -ProfileID $EnrolmentProfile.id -DeviceSerials @($serial)
                $totalAssigned++
            }
            catch {
                $totalFailed++
            }
        }
    }
    
    # Summary
    Write-Host "`nAssignment Summary:" -ForegroundColor Green
    Write-Host "Successfully assigned: $totalAssigned devices" -ForegroundColor Green
    
    # Only show failed assignments if there are failures
    if ($totalFailed -gt 0) {
        Write-Host "Failed assignments: $totalFailed devices" -ForegroundColor Red
    }
    
    Write-Host "Total processed: $($totalAssigned + $totalFailed) devices" -ForegroundColor Green
    
}
catch {
    Write-Host "`nSCRIPT FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Script execution completed" -ForegroundColor Green