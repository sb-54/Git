<#
.SYNOPSIS
    Complete diagnostic analysis of INT-ArbourHeights-Care-iOS dynamic group

.DESCRIPTION
    Single script to understand everything about your current group structure.
    All your ~100 groups follow the same pattern, so this analysis applies to all.

.NOTES
    Required Permissions: Group.Read.All, Device.Read.All, DeviceManagementManagedDevices.Read.All
    
.EXAMPLE
    .\Diagnose-CurrentGroupStructure.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$GroupName = "INT-ArbourHeights-Care-iOS"
)

# ============================================================================
# SETUP
# ============================================================================

Clear-Host
Write-Host @"

╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║     INTUNE DYNAMIC GROUP DIAGNOSTIC ANALYSIS                     ║
║     Understanding Your Current Structure                         ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$ErrorActionPreference = "Stop"

# Install required modules (FIXED)
$modules = @('Microsoft.Graph.Identity.DirectoryManagement', 'Microsoft.Graph.DeviceManagement')
foreach ($module in $modules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing $module..." -ForegroundColor Yellow
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
    }
}

Import-Module Microsoft.Graph.Identity.DirectoryManagement
Import-Module Microsoft.Graph.DeviceManagement

# Connect
Write-Host "`n[1/7] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Group.Read.All", "Device.Read.All", "DeviceManagementManagedDevices.Read.All" -NoWelcome
Write-Host "      ✓ Connected`n" -ForegroundColor Green

# ============================================================================
# SECTION 1: GROUP INFORMATION
# ============================================================================

Write-Host "[2/7] Retrieving Group Information..." -ForegroundColor Cyan

try {
    $group = Get-MgGroup -Filter "displayName eq '$GroupName'" `
        -Property "Id,DisplayName,GroupTypes,MembershipRule,MembershipRuleProcessingState,CreatedDateTime"
    
    if (-not $group) {
        Write-Host "      ✗ Group '$GroupName' not found" -ForegroundColor Red
        exit 1
    }
    
    if ($group.GroupTypes -notcontains "DynamicMembership") {
        Write-Host "      ✗ This is not a dynamic group!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "      ✓ Group found`n" -ForegroundColor Green
    
} catch {
    Write-Host "      ✗ Error: $_" -ForegroundColor Red
    exit 1
}

# ============================================================================
# SECTION 2: DISPLAY GROUP DETAILS
# ============================================================================

Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "GROUP DETAILS" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White

Write-Host "`nBasic Information:" -ForegroundColor White
Write-Host "  Name:              $($group.DisplayName)"
Write-Host "  Azure AD ID:       $($group.Id)"
Write-Host "  Type:              Dynamic Membership"
Write-Host "  Processing State:  $($group.MembershipRuleProcessingState)"
Write-Host "  Created:           $($group.CreatedDateTime)"

Write-Host "`nCurrent Dynamic Membership Rule:" -ForegroundColor White
Write-Host "  $($group.MembershipRule)" -ForegroundColor Yellow

# ============================================================================
# SECTION 3: ANALYZE THE RULE
# ============================================================================

Write-Host "`n`n═══════════════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "RULE ANALYSIS" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White

$rule = $group.MembershipRule

Write-Host "`nWhat Properties Does This Rule Use?" -ForegroundColor White

$properties = @{
    "device.displayName" = $rule -match 'device\.displayName'
    "device.deviceOSType" = $rule -match 'device\.deviceOSType'
    "device.deviceOSVersion" = $rule -match 'device\.deviceOSVersion'
    "device.deviceModel" = $rule -match 'device\.deviceModel'
    "device.deviceCategory" = $rule -match 'device\.deviceCategory'
    "device.deviceOwnership" = $rule -match 'device\.deviceOwnership'
    "device.enrollmentProfileName" = $rule -match 'device\.enrollmentProfileName'
    "device.extensionAttribute1" = $rule -match 'device\.extensionAttribute1'
    "device.extensionAttribute2" = $rule -match 'device\.extensionAttribute2'
}

Write-Host "`n  Properties USED:" -ForegroundColor Green
$usedProps = $properties.GetEnumerator() | Where-Object { $_.Value }
if ($usedProps.Count -eq 0) {
    Write-Host "    (none detected - unusual!)" -ForegroundColor Red
} else {
    foreach ($prop in $usedProps) {
        Write-Host "    ✓ $($prop.Key)" -ForegroundColor Green
        
        # Extract the actual value/pattern
        if ($rule -match "$($prop.Key.Replace('.', '\.'))\s*(-eq|-contains|-startsWith)\s*`"([^`"]+)`"") {
            Write-Host "      Operator: $($Matches[1])" -ForegroundColor Gray
            Write-Host "      Value: $($Matches[2])" -ForegroundColor Gray
        }
    }
}

Write-Host "`n  Properties NOT USED (but available for new architecture):" -ForegroundColor Yellow
$unusedProps = $properties.GetEnumerator() | Where-Object { -not $_.Value }
foreach ($prop in $unusedProps) {
    Write-Host "    - $($prop.Key)" -ForegroundColor Gray
}

# ============================================================================
# SECTION 4: GET GROUP MEMBERS
# ============================================================================

Write-Host "`n`n[3/7] Retrieving Group Members..." -ForegroundColor Cyan

$members = Get-MgGroupMember -GroupId $group.Id -All
$memberCount = $members.Count

Write-Host "      ✓ Found $memberCount devices in group`n" -ForegroundColor Green

# ============================================================================
# SECTION 5: ANALYZE SAMPLE DEVICES
# ============================================================================

Write-Host "[4/7] Analyzing Device Details..." -ForegroundColor Cyan

$deviceSample = @()
$sampleSize = [Math]::Min(5, $memberCount)

for ($i = 0; $i -lt $sampleSize; $i++) {
    Write-Progress -Activity "Analyzing devices" -Status "Device $($i+1) of $sampleSize" -PercentComplete (($i / $sampleSize) * 100)
    
    $member = $members[$i]
    $device = Get-MgDevice -DeviceId $member.Id `
        -Property "Id,DisplayName,DeviceOSType,DeviceOSVersion,DeviceOwnership,DeviceCategory,EnrollmentProfileName,ExtensionAttributes"
    
    $deviceSample += [PSCustomObject]@{
        DeviceName = $device.DisplayName
        OSType = $device.DeviceOSType
        OSVersion = $device.DeviceOSVersion
        Ownership = $device.DeviceOwnership
        Category = $device.DeviceCategory
        EnrollmentProfile = $device.EnrollmentProfileName
        ExtAttr1 = $device.ExtensionAttributes.extensionAttribute1
        ExtAttr2 = $device.ExtensionAttributes.extensionAttribute2
        ExtAttr3 = $device.ExtensionAttributes.extensionAttribute3
    }
}

Write-Progress -Activity "Analyzing devices" -Completed
Write-Host "      ✓ Analyzed $sampleSize sample devices`n" -ForegroundColor Green

# ============================================================================
# SECTION 6: DISPLAY DEVICE DATA
# ============================================================================

Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "DEVICE ANALYSIS (Sample of $sampleSize devices)" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White

Write-Host "`nSample Devices:" -ForegroundColor White
$deviceSample | Format-Table -Property DeviceName, OSType, OSVersion, Ownership, Category -AutoSize

Write-Host "`nExtension Attribute Status:" -ForegroundColor White
Write-Host "  Device Name                    ExtAttr1    ExtAttr2    ExtAttr3" -ForegroundColor Gray
Write-Host "  -----------                    --------    --------    --------" -ForegroundColor Gray
foreach ($dev in $deviceSample) {
    $attr1 = if ($dev.ExtAttr1) { $dev.ExtAttr1 } else { "(empty)" }
    $attr2 = if ($dev.ExtAttr2) { $dev.ExtAttr2 } else { "(empty)" }
    $attr3 = if ($dev.ExtAttr3) { $dev.ExtAttr3 } else { "(empty)" }
    
    $color = if ($dev.ExtAttr1 -and $dev.ExtAttr2) { "Green" } else { "Yellow" }
    Write-Host ("  {0,-30} {1,-11} {2,-11} {3,-11}" -f $dev.DeviceName.Substring(0, [Math]::Min(30, $dev.DeviceName.Length)), $attr1, $attr2, $attr3) -ForegroundColor $color
}

# ============================================================================
# SECTION 7: EXTENSION ATTRIBUTE READINESS
# ============================================================================

Write-Host "`n`n[5/7] Checking Extension Attribute Readiness..." -ForegroundColor Cyan

$withExt1 = ($deviceSample | Where-Object { $_.ExtAttr1 }).Count
$withExt2 = ($deviceSample | Where-Object { $_.ExtAttr2 }).Count  
$withBoth = ($deviceSample | Where-Object { $_.ExtAttr1 -and $_.ExtAttr2 }).Count
$withNeither = ($deviceSample | Where-Object { -not $_.ExtAttr1 -and -not $_.ExtAttr2 }).Count

Write-Host "      ✓ Analysis complete`n" -ForegroundColor Green

Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "EXTENSION ATTRIBUTE READINESS" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White

Write-Host "`nSample Statistics (from $sampleSize devices):" -ForegroundColor White
Write-Host "  Devices with extensionAttribute1: $withExt1 / $sampleSize"
Write-Host "  Devices with extensionAttribute2: $withExt2 / $sampleSize"
Write-Host "  Devices with BOTH attributes:     $withBoth / $sampleSize" -ForegroundColor $(if ($withBoth -eq $sampleSize) { "Green" } else { "Yellow" })
Write-Host "  Devices with NEITHER attribute:   $withNeither / $sampleSize" -ForegroundColor $(if ($withNeither -eq 0) { "Green" } else { "Red" })

if ($withBoth -eq $sampleSize) {
    Write-Host "`n  ✓ All sampled devices have required extension attributes!" -ForegroundColor Green
    Write-Host "    Your devices are READY for the new architecture." -ForegroundColor Green
} elseif ($withNeither -eq $sampleSize) {
    Write-Host "`n  ✗ No devices have extension attributes populated." -ForegroundColor Red
    Write-Host "    You MUST populate attributes before creating new groups." -ForegroundColor Red
} else {
    Write-Host "`n  ⚠ Partial attribute population detected." -ForegroundColor Yellow
    Write-Host "    Some devices ready, others need attributes populated." -ForegroundColor Yellow
}

# ============================================================================
# SECTION 8: PARSE GROUP NAME AND MAKE RECOMMENDATIONS
# ============================================================================

Write-Host "`n`n[6/7] Generating Migration Recommendations..." -ForegroundColor Cyan

if ($GroupName -match "^INT-([^-]+)-([^-]+)-([^-]+)$") {
    $location = $Matches[1]
    $type = $Matches[2]
    $platform = $Matches[3]
    
    Write-Host "      ✓ Group name parsed successfully`n" -ForegroundColor Green
    
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White
    Write-Host "MIGRATION RECOMMENDATIONS" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White
    
    Write-Host "`nCurrent Group Structure:" -ForegroundColor White
    Write-Host "  Pattern: INT-{Location}-{Type}-{Platform}"
    Write-Host "  Your Location: $location" -ForegroundColor Cyan
    Write-Host "  Your Type: $type" -ForegroundColor Cyan
    Write-Host "  Your Platform: $platform" -ForegroundColor Cyan
    
    Write-Host "`nNew Architecture Mapping:" -ForegroundColor White
    Write-Host "  You need to map '$location' to either 'Oak' or 'Spruce'" -ForegroundColor Yellow
    Write-Host "  Let's assume: $location → Oak (example)" -ForegroundColor Gray
    
    Write-Host "`nRecommended New Groups:" -ForegroundColor White
    Write-Host "  Parent Group: INT-iOS-Oak-All" -ForegroundColor Green
    Write-Host "    → Contains ALL Oak devices (Care + Rec)"
    Write-Host "    → Rule: (device.deviceOSType -eq `"iPad`" -or device.deviceOSType -eq `"iPhone`") -and (device.extensionAttribute1 -eq `"Oak`")"
    
    Write-Host "`n  Child Group: INT-iOS-Oak-$type" -ForegroundColor Green
    Write-Host "    → Contains only Oak $type devices"
    Write-Host "    → Rule: (device.deviceOSType -eq `"iPad`" -or device.deviceOSType -eq `"iPhone`") -and (device.extensionAttribute1 -eq `"Oak`") -and (device.extensionAttribute2 -eq `"$type`")"
    
    Write-Host "`nRequired Extension Attribute Values:" -ForegroundColor White
    Write-Host "  extensionAttribute1 = `"Oak`"" -ForegroundColor Cyan
    Write-Host "  extensionAttribute2 = `"$type`"" -ForegroundColor Cyan
    
} else {
    Write-Host "      ⚠ Could not parse group name pattern`n" -ForegroundColor Yellow
}

# ============================================================================
# SECTION 9: SUMMARY AND NEXT STEPS
# ============================================================================

Write-Host "`n`n[7/7] Generating Summary..." -ForegroundColor Cyan

Write-Host @"

═══════════════════════════════════════════════════════════════════
SUMMARY & NEXT STEPS
═══════════════════════════════════════════════════════════════════

"@ -ForegroundColor White

Write-Host "What We Found:" -ForegroundColor Yellow
Write-Host "  • Group: $GroupName"
Write-Host "  • Total Devices: $memberCount"
Write-Host "  • Current Rule: Uses " -NoNewline
$usedCount = ($properties.GetEnumerator() | Where-Object { $_.Value }).Count
Write-Host "$usedCount device properties" -ForegroundColor Cyan
Write-Host "  • Extension Attributes: " -NoNewline
if ($withBoth -eq $sampleSize) {
    Write-Host "POPULATED ✓" -ForegroundColor Green
} elseif ($withNeither -eq $sampleSize) {
    Write-Host "NOT POPULATED ✗" -ForegroundColor Red
} else {
    Write-Host "PARTIALLY POPULATED ⚠" -ForegroundColor Yellow
}

Write-Host "`nWhat This Means for Your ~100 Groups:" -ForegroundColor Yellow
Write-Host "  • All groups likely use the SAME rule pattern" -ForegroundColor White
Write-Host "  • All groups likely use the SAME device properties" -ForegroundColor White
Write-Host "  • Only the location/site name differs (e.g., ArbourHeights)" -ForegroundColor White

Write-Host "`nYour Migration Path:" -ForegroundColor Yellow

if ($withBoth -eq $sampleSize) {
    Write-Host "  STATUS: Ready to create new groups!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  1. ✓ Extension attributes already populated"
    Write-Host "  2. → Wait 24-48 hours for Azure AD sync (if just populated)"
    Write-Host "  3. → Create new dynamic groups with recommended rules"
    Write-Host "  4. → Validate member counts match between old/new groups"
    Write-Host "  5. → Migrate Intune assignments in portal"
    Write-Host "  6. → After validation, delete old groups"
} else {
    Write-Host "  STATUS: Need to populate extension attributes first" -ForegroundColor Red
    Write-Host ""
    Write-Host "  1. → Create business line mapping (Location → Oak/Spruce)"
    Write-Host "  2. → Run bulk population script to set extension attributes"
    Write-Host "  3. → Wait 24-48 hours for Azure AD sync"
    Write-Host "  4. → Create new dynamic groups with recommended rules"
    Write-Host "  5. → Validate member counts match between old/new groups"
    Write-Host "  6. → Migrate Intune assignments in portal"
    Write-Host "  7. → After validation, delete old groups"
}

Write-Host "`nKey Decision Needed:" -ForegroundColor Yellow
Write-Host "  Map all your locations to business lines:" -ForegroundColor White
Write-Host @"
  
  `$BusinessLineMapping = @{
      "ArbourHeights" = "Oak"        # ← Your decision
      "AnotherSite" = "Spruce"       # ← Your decision
      "ThirdSite" = "Oak"            # ← Your decision
      # ... for all ~100 locations
  }
  
"@ -ForegroundColor Gray

Write-Host "═══════════════════════════════════════════════════════════════════`n" -ForegroundColor White

# Export detailed report
$report = [PSCustomObject]@{
    GroupName = $group.DisplayName
    GroupId = $group.Id
    MembershipRule = $group.MembershipRule
    TotalMembers = $memberCount
    ProcessingState = $group.MembershipRuleProcessingState
    PropertiesUsedInRule = ($usedProps | ForEach-Object { $_.Key }) -join ', '
    ExtensionAttribute1Populated = "$withExt1 / $sampleSize"
    ExtensionAttribute2Populated = "$withExt2 / $sampleSize"
    ReadyForMigration = if ($withBoth -eq $sampleSize) { "Yes" } else { "No - Populate attributes first" }
}

$report | Export-Csv -Path "GroupDiagnosticReport.csv" -NoTypeInformation
$deviceSample | Export-Csv -Path "DeviceSampleData.csv" -NoTypeInformation

Write-Host "Reports Exported:" -ForegroundColor Green
Write-Host "  • GroupDiagnosticReport.csv - Summary of analysis"
Write-Host "  • DeviceSampleData.csv - Sample device details"

Write-Host "`nDone! Disconnecting...`n" -ForegroundColor Cyan
Disconnect-MgGraph