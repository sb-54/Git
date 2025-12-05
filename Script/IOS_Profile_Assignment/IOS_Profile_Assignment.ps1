<#
.SYNOPSIS
    Bulk-assigns iOS/iPadOS ADE enrollment profiles to devices using serial numbers from a CSV file.

.DESCRIPTION
    This script reads a CSV that maps each device serial number to an ADE enrollment profile name,
    resolves the corresponding enrollment profiles for your connected ADE (DEP) token, and then
    calls the Microsoft Graph (beta) updateDeviceProfileAssignment endpoint to apply those assignments.
    The implementation is aligned with Microsoft Graph changes effective October 2025 and uses the
    current, supported API path for ADE device profile assignment.

    Expected CSV columns:
      - Serial           : Device serial number as shown in Apple Business Manager / Intune.
      - EnrolmentProfile : Display name of the ADE enrollment profile in Intune.

.REQUIREMENTS
    - PowerShell 7+ (macOS / cross-platform)
    - Microsoft.Graph PowerShell module
    - Intune Graph delegated permissions:
        DeviceManagementConfiguration.ReadWrite.All
        DeviceManagementServiceConfig.ReadWrite.All
    - An active ADE (DEP) connection between Intune and Apple Business Manager

.NOTES
    Author:  L3mon
#>

# Check if already connected to Microsoft Graph
$context = Get-MgContext -ErrorAction SilentlyContinue

if (-not $context -or $context.Scopes -notcontains 'DeviceManagementConfiguration.ReadWrite.All') {
    Connect-MgGraph -Scopes 'DeviceManagementConfiguration.ReadWrite.All', 'DeviceManagementServiceConfig.ReadWrite.All' -NoWelcome
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

# Function to assign ADE devices - CORRECTED VERSION
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
            $Body = @{ deviceIds = @($serial) } | ConvertTo-Json -Depth 3
            Invoke-MgGraphRequest -Uri $uri -Method Post -Body $Body -ContentType 'application/json' -ErrorAction Stop
            Write-Host "Assigning $serial ✅"
            return $true
        }
        catch {
            Write-Host "Assigning $serial ❌"
            Write-Host "  Error: $($_.Exception.Message)"
            return $false
        }
    }
}

try {
    $CSVPath = "/Users/hea2eq/Downloads/devices.csv"
    
    if (-not (Test-Path $CSVPath)) {
        throw "CSV file not found at: $CSVPath"
    }
    
    $Devices = Import-Csv -Path $CSVPath
    
    if (-not $Devices -or $Devices.Count -eq 0) {
        throw "CSV is empty or unreadable"
    }

    if (-not ($Devices | Get-Member -Name 'Serial') -or -not ($Devices | Get-Member -Name 'EnrolmentProfile')) {
        throw "CSV must contain 'Serial' and 'EnrolmentProfile' columns."
    }
    
    # Clean up data and remove empty entries
    $Devices = $Devices | ForEach-Object {
        if ($_.Serial) { $_.Serial = $_.Serial.Trim() }
        if ($_.EnrolmentProfile) { $_.EnrolmentProfile = $_.EnrolmentProfile.Trim() }
        $_
    } | Where-Object { $_.Serial -and $_.EnrolmentProfile }
    
    if (-not $Devices) {
        throw "No valid device entries found with both Serial and EnrolmentProfile"
    }
    
    $Assignments = $Devices | Group-Object -Property EnrolmentProfile
    
    $TokenList = @((Get-ADEEnrolmentToken) | Where-Object { $_ })
    
    if (-not $TokenList) {
        throw "No ADE enrollment tokens found. Ensure Apple Business Manager is connected."
    }
    
    if ($TokenList.Count -gt 1) {
        Write-Warning "Multiple ADE tokens found. Using first token: $($TokenList[0].tokenName)"
    }
    
    $Token = $TokenList[0]
    
    $AllProfiles = Get-ADEEnrolmentProfile -Id $Token.id
    
    if (-not $AllProfiles) {
        throw "No enrollment profiles were returned for token '$($Token.tokenName)'."
    }
    
    $totalAssigned = 0
    $totalFailed = 0
    
    foreach ($Assignment in $Assignments) {
        $ProfileName = $Assignment.Name
        $DeviceSerials = $Assignment.Group.Serial | Where-Object { $_ } | Sort-Object -Unique

        if (-not $DeviceSerials) {
            Write-Warning "Skipping profile '$ProfileName' because no valid serial numbers were found."
            continue
        }

        $EnrolmentProfile = $AllProfiles | Where-Object { $_.displayName -eq $ProfileName }

        if (-not $EnrolmentProfile) {
            Write-Warning "Profile '$ProfileName' not found"
            $totalFailed += $DeviceSerials.Count
            continue
        }

        Write-Host ""
        Write-Host $ProfileName

        foreach ($serial in $DeviceSerials) {
            $result = Add-ADEEnrolmentProfileAssignment -Id $Token.id -ProfileID $EnrolmentProfile.id -DeviceSerials @($serial)
            if ($result) {
                $totalAssigned++
            }
            else {
                $totalFailed++
            }
        }
    }
    
    Write-Host "`n========================================"
    Write-Host "Assignment Summary:"
    Write-Host "========================================"
    Write-Host "Successfully assigned: $totalAssigned devices"
    if ($totalFailed -gt 0) {
        Write-Host "Failed assignments: $totalFailed devices"
    }
    Write-Host "Total processed: $($totalAssigned + $totalFailed) devices"
    Write-Host "========================================"
    
} catch {
    Write-Host "`nSCRIPT FAILED: $($_.Exception.Message)"
    Write-Host "Stack Trace: $($_.ScriptStackTrace)"
}

Write-Host "`nScript execution completed"
