<#
.SYNOPSIS
    Create new scalable dynamic groups for Intune iOS device management

.DESCRIPTION
    Creates 6 new dynamic device groups:
    - INT-iOS-Oak-All (parent)
    - INT-iOS-Oak-Care (child)
    - INT-iOS-Oak-Rec (child)
    - INT-iOS-Spruce-All (parent)
    - INT-iOS-Spruce-Care (child)
    - INT-iOS-Spruce-Rec (child)

.NOTES
    Required Permissions: Group.ReadWrite.All, Device.Read.All
    This script CREATES groups - it makes changes
#>

[CmdletBinding(SupportsShouldProcess)]
param()

Clear-Host
Write-Host @"

╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║     CREATE NEW SCALABLE DYNAMIC GROUPS                           ║
║     6 Groups: 2 Parent + 4 Child                                 ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# ============================================================================
# CONNECT
# ============================================================================

Write-Host "`n[1/3] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Write-Host "      This requires WRITE permissions (Group.ReadWrite.All)" -ForegroundColor Yellow

Connect-MgGraph -Scopes "Group.ReadWrite.All", "Device.Read.All" -NoWelcome
Write-Host "      ✓ Connected`n" -ForegroundColor Green

# ============================================================================
# DEFINE NEW GROUPS
# ============================================================================

Write-Host "[2/3] Preparing Group Definitions..." -ForegroundColor Cyan

$groupsToCreate = @(
    # PARENT GROUPS
    @{
        Name = "INT-iOS-Oak-All"
        Description = "All Oak business line iOS devices (Care + Rec)"
        Rule = '(device.deviceOSType -eq "iPad" -or device.deviceOSType -eq "iPhone") -and (device.extensionAttribute1 -eq "Oak")'
        Type = "Parent"
    },
    @{
        Name = "INT-iOS-Spruce-All"
        Description = "All Spruce business line iOS devices (Care + Rec)"
        Rule = '(device.deviceOSType -eq "iPad" -or device.deviceOSType -eq "iPhone") -and (device.extensionAttribute1 -eq "Spruce")'
        Type = "Parent"
    },
    
    # CHILD GROUPS - OAK
    @{
        Name = "INT-iOS-Oak-Care"
        Description = "Oak business line Care type iOS devices"
        Rule = '(device.deviceOSType -eq "iPad" -or device.deviceOSType -eq "iPhone") -and (device.extensionAttribute1 -eq "Oak") -and (device.extensionAttribute2 -eq "Care")'
        Type = "Child"
    },
    @{
        Name = "INT-iOS-Oak-Rec"
        Description = "Oak business line Recreation type iOS devices"
        Rule = '(device.deviceOSType -eq "iPad" -or device.deviceOSType -eq "iPhone") -and (device.extensionAttribute1 -eq "Oak") -and (device.extensionAttribute2 -eq "Rec")'
        Type = "Child"
    },
    
    # CHILD GROUPS - SPRUCE
    @{
        Name = "INT-iOS-Spruce-Care"
        Description = "Spruce business line Care type iOS devices"
        Rule = '(device.deviceOSType -eq "iPad" -or device.deviceOSType -eq "iPhone") -and (device.extensionAttribute1 -eq "Spruce") -and (device.extensionAttribute2 -eq "Care")'
        Type = "Child"
    },
    @{
        Name = "INT-iOS-Spruce-Rec"
        Description = "Spruce business line Recreation type iOS devices"
        Rule = '(device.deviceOSType -eq "iPad" -or device.deviceOSType -eq "iPhone") -and (device.extensionAttribute1 -eq "Spruce") -and (device.extensionAttribute2 -eq "Rec")'
        Type = "Child"
    }
)

Write-Host "      ✓ Defined $($groupsToCreate.Count) groups`n" -ForegroundColor Green

# ============================================================================
# PREVIEW
# ============================================================================

Write-Host "[3/3] Preview - Groups to Be Created..." -ForegroundColor Cyan
Write-Host ""

Write-Host "PARENT GROUPS (2):" -ForegroundColor Yellow
Write-Host "  1. INT-iOS-Oak-All" -ForegroundColor Cyan
Write-Host "  2. INT-iOS-Spruce-All" -ForegroundColor Cyan

Write-Host "`nCHILD GROUPS (4):" -ForegroundColor Yellow
Write-Host "  3. INT-iOS-Oak-Care" -ForegroundColor Green
Write-Host "  4. INT-iOS-Oak-Rec" -ForegroundColor Green
Write-Host "  5. INT-iOS-Spruce-Care" -ForegroundColor Green
Write-Host "  6. INT-iOS-Spruce-Rec" -ForegroundColor Green

Write-Host "`n  Sample Rules:" -ForegroundColor Gray
Write-Host "    Oak-All: (device.deviceOSType -eq `"iPad`" -or device.deviceOSType -eq `"iPhone`") -and (device.extensionAttribute1 -eq `"Oak`")" -ForegroundColor Gray
Write-Host "    Oak-Care: (device.deviceOSType -eq `"iPad`" -or device.deviceOSType -eq `"iPhone`") -and (device.extensionAttribute1 -eq `"Oak`") -and (device.extensionAttribute2 -eq `"Care`")" -ForegroundColor Gray

Write-Host "`n" -ForegroundColor White

# ============================================================================
# CONFIRMATION
# ============================================================================

Write-Host "⚠ WARNING: This will create 6 NEW dynamic device groups!" -ForegroundColor Yellow
Write-Host "Press Ctrl+C to cancel, or Enter to continue..." -ForegroundColor Yellow
Read-Host

# ============================================================================
# CREATE GROUPS
# ============================================================================

Write-Host "`n`n═══════════════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "CREATING GROUPS" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host ""

$successCount = 0
$errorCount = 0
$skippedCount = 0
$errors = @()

foreach ($groupDef in $groupsToCreate) {
    Write-Host "Creating: $($groupDef.Name)" -ForegroundColor Cyan
    
    try {
        # Check if group already exists
        $existing = Get-MgGroup -Filter "displayName eq '$($groupDef.Name)'" -ErrorAction SilentlyContinue
        
        if ($existing) {
            Write-Host "  ⚠ Group already exists - skipping" -ForegroundColor Yellow
            $skippedCount++
            continue
        }
        
        # Create group
        $mailNickname = $groupDef.Name.Replace("-", "").Replace(" ", "")
        
        $newGroup = New-MgGroup `
            -DisplayName $groupDef.Name `
            -Description $groupDef.Description `
            -MailEnabled:$false `
            -SecurityEnabled:$true `
            -MailNickname $mailNickname `
            -GroupTypes @("DynamicMembership") `
            -MembershipRule $groupDef.Rule `
            -MembershipRuleProcessingState "On" `
            -ErrorAction Stop
        
        Write-Host "  ✓ Created successfully" -ForegroundColor Green
        Write-Host "    ID: $($newGroup.Id)" -ForegroundColor Gray
        Write-Host "    Type: $($groupDef.Type) Group" -ForegroundColor Gray
        Write-Host "    Rule: $($groupDef.Rule)" -ForegroundColor Gray
        Write-Host ""
        
        $successCount++
        
    } catch {
        $errorCount++
        $errorMsg = $_.Exception.Message
        Write-Host "  ✗ Failed: $errorMsg" -ForegroundColor Red
        Write-Host ""
        
        $errors += [PSCustomObject]@{
            GroupName = $groupDef.Name
            Error = $errorMsg
        }
    }
    
    # Rate limiting
    Start-Sleep -Milliseconds 500
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "OPERATION COMPLETE" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White

Write-Host "`nResults:" -ForegroundColor White
Write-Host "  Created: $successCount / 6" -ForegroundColor $(if ($successCount -eq 6) { "Green" } else { "Yellow" })
Write-Host "  Skipped (already exist): $skippedCount / 6" -ForegroundColor Gray
Write-Host "  Errors: $errorCount / 6" -ForegroundColor $(if ($errorCount -eq 0) { "Green" } else { "Red" })

if ($errors.Count -gt 0) {
    Write-Host "`nErrors:" -ForegroundColor Red
    $errors | Format-Table -Property GroupName, Error -AutoSize
}

Write-Host "`n" -ForegroundColor White

Write-Host "✓ Group Summary:" -ForegroundColor Green
Write-Host ""
Write-Host "  PARENT GROUPS:" -ForegroundColor Yellow
Write-Host "    • INT-iOS-Oak-All" -ForegroundColor Cyan
Write-Host "      └─ Will contain: All Oak devices (Care + Rec)" -ForegroundColor Gray
Write-Host ""
Write-Host "    • INT-iOS-Spruce-All" -ForegroundColor Cyan
Write-Host "      └─ Will contain: All Spruce devices (Care + Rec)" -ForegroundColor Gray
Write-Host ""
Write-Host "  CHILD GROUPS - OAK:" -ForegroundColor Yellow
Write-Host "    • INT-iOS-Oak-Care" -ForegroundColor Green
Write-Host "      └─ Will contain: All Oak-Care devices" -ForegroundColor Gray
Write-Host ""
Write-Host "    • INT-iOS-Oak-Rec" -ForegroundColor Green
Write-Host "      └─ Will contain: All Oak-Rec devices" -ForegroundColor Gray
Write-Host ""
Write-Host "  CHILD GROUPS - SPRUCE:" -ForegroundColor Yellow
Write-Host "    • INT-iOS-Spruce-Care" -ForegroundColor Green
Write-Host "      └─ Will contain: All Spruce-Care devices" -ForegroundColor Gray
Write-Host ""
Write-Host "    • INT-iOS-Spruce-Rec" -ForegroundColor Green
Write-Host "      └─ Will contain: All Spruce-Rec devices" -ForegroundColor Gray

Write-Host "`n" -ForegroundColor White

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. ✓ New groups created" -ForegroundColor Green
Write-Host "  2. → Wait 24-48 hours for Azure AD to populate group memberships" -ForegroundColor White
Write-Host "     (Device extension attributes must be set first via population script)" -ForegroundColor Gray
Write-Host "  3. → Verify member counts in new groups match old groups" -ForegroundColor White
Write-Host "  4. → Migrate Intune assignments to new groups" -ForegroundColor White
Write-Host "  5. → Delete old location-specific groups" -ForegroundColor White

Write-Host "`n" -ForegroundColor White

Write-Host "Important Reminders:" -ForegroundColor Yellow
Write-Host "  • Groups are created but will be EMPTY until extension attributes are populated" -ForegroundColor Cyan
Write-Host "  • You must run the attribute population script FIRST for devices to appear in groups" -ForegroundColor Cyan
Write-Host "  • Dynamic membership syncs every 24 hours - be patient" -ForegroundColor Cyan
Write-Host "  • Monitor: Azure AD > Groups > [Group Name] > Members (to see population progress)" -ForegroundColor Cyan

Write-Host "`n═══════════════════════════════════════════════════════════════════`n" -ForegroundColor White

# Export results
$report = [PSCustomObject]@{
    TotalGroupsCreated = $successCount
    TotalGroupsSkipped = $skippedCount
    TotalErrors = $errorCount
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Groups = $groupsToCreate | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Name
            Type = $_.Type
            Description = $_.Description
        }
    }
}

$report | Export-Csv -Path "GroupCreation-Report.csv" -NoTypeInformation
Write-Host "Report saved: GroupCreation-Report.csv`n" -ForegroundColor Green

Disconnect-MgGraph
