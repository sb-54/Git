<#
.SYNOPSIS
    Convert 6 parent groups to Assigned (static) and add location groups as members

.DESCRIPTION
    Steps:
    1. Delete the 6 dynamic groups (can't convert dynamic to assigned)
    2. Recreate them as Assigned groups
    3. Add all location groups as members
    
    This allows groups to be members (unlike dynamic device groups)
#>

[CmdletBinding(SupportsShouldProcess)]
param()

Clear-Host
Write-Host @"

╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║     CONVERT TO ASSIGNED GROUPS + ADD MEMBERS                     ║
║     Delete Dynamic → Recreate as Assigned → Add Members          ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# ============================================================================
# CONNECT
# ============================================================================

Write-Host "`n[1/5] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Group.ReadWrite.All" -NoWelcome
Write-Host "      ✓ Connected`n" -ForegroundColor Green

# ============================================================================
# DEFINE LOCATION MAPPING
# ============================================================================

Write-Host "[2/5] Building Location Mapping..." -ForegroundColor Cyan

$oakLocations = @(
    "Athabasca", "Bayview", "Bonnyville", "Brampton", "CedarsVilla", "Centennial",
    "Cobourg", "Countryside", "CrossingBridge", "EauxClaires", "FairmontPark",
    "FJDavey", "FortMacleod", "Guildwood", "Haliburton", "HaltonHills", "Hamilton",
    "Hillcrest", "HillcrestPlace", "Holyrood", "IreneBaron", "Kapuskasing",
    "KawarthaLakes", "Kirkland", "Lakefield", "LakelandVillage", "Lakeside",
    "Landmark", "Laurier", "Leduc", "Limestone", "London", "Mapleview",
    "Mayerthorpe", "Medex", "MichenerHill", "Mississauga", "OakviewPlace",
    "Oshawa", "Peterborough", "PineMeadow", "PortHope", "PortStanley",
    "RedRiver", "RiverEast", "RougeValley", "Scarborough", "Southlake",
    "Southwood", "Starwood", "StCatharines", "StPaul", "Tecumseh", "Tendercare",
    "Timmins", "TriTown", "Tuxedo", "VanDaele", "Viking", "VillaColombo",
    "VistaPark", "Vulcan", "WestPark", "Wyndham", "York", "NewOrchardLodge"
)

$spruceLocations = @(
    "ArbourHeights", "BayRidges", "BeaconHill", "BlenheimVillage", "Brierwood",
    "Burloak", "Carlingview", "Charleswood", "ColumbiaForest", "Elginwood",
    "Elmwood", "FenelonCourt", "Haroldandgrace", "HeritageLodge", "IlerLodge",
    "Kildonan", "Longfields", "Maples", "McGarrell", "Meadows", "Montfort",
    "Northridge", "Poseidon", "Ridgeview", "Riverbend", "Riverside", "Sherwood",
    "StirlingHeights", "Stoneridge", "Summit", "Telfer", "Trillium", "Valleyview",
    "VillageRidge", "WestOak", "Winbourne"
)

Write-Host "      ✓ Oak locations: $($oakLocations.Count)" -ForegroundColor Green
Write-Host "      ✓ Spruce locations: $($spruceLocations.Count)" -ForegroundColor Green
Write-Host ""

# ============================================================================
# RETRIEVE ALL LOCATION GROUPS
# ============================================================================

Write-Host "[3/5] Retrieving Location Groups..." -ForegroundColor Cyan

$allLocationGroups = Get-MgGroup -Filter "startswith(displayName, 'INT-')" -All `
    -Property "Id,DisplayName" | Where-Object { $_.DisplayName -match "INT-.*-(Care|Rec)-iOS$" }

Write-Host "      ✓ Found $($allLocationGroups.Count) location groups`n" -ForegroundColor Green

# Map groups
$oakCareGroups = @()
$oakRecGroups = @()
$spruceCareGroups = @()
$spruceRecGroups = @()

foreach ($group in $allLocationGroups) {
    if ($group.DisplayName -match "^INT-([^-]+)-(Care|Rec)-iOS$") {
        $location = $Matches[1]
        $type = $Matches[2]
        
        if ($oakLocations -contains $location) {
            if ($type -eq "Care") { $oakCareGroups += $group }
            else { $oakRecGroups += $group }
        } elseif ($spruceLocations -contains $location) {
            if ($type -eq "Care") { $spruceCareGroups += $group }
            else { $spruceRecGroups += $group }
        }
    }
}

Write-Host "Organized groups:" -ForegroundColor Yellow
Write-Host "  Oak-Care: $($oakCareGroups.Count) groups" -ForegroundColor Cyan
Write-Host "  Oak-Rec: $($oakRecGroups.Count) groups" -ForegroundColor Cyan
Write-Host "  Spruce-Care: $($spruceCareGroups.Count) groups" -ForegroundColor Cyan
Write-Host "  Spruce-Rec: $($spruceRecGroups.Count) groups" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# DELETE OLD DYNAMIC GROUPS
# ============================================================================

Write-Host "[4/5] Deleting Old Dynamic Groups..." -ForegroundColor Cyan
Write-Host ""

$groupNamesToDelete = @(
    "INT-iOS-Oak-All",
    "INT-iOS-Oak-Care",
    "INT-iOS-Oak-Rec",
    "INT-iOS-Spruce-All",
    "INT-iOS-Spruce-Care",
    "INT-iOS-Spruce-Rec"
)

foreach ($groupName in $groupNamesToDelete) {
    try {
        $existingGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -Property "Id,DisplayName"
        
        if ($existingGroup) {
            Write-Host "  Deleting: $groupName" -ForegroundColor Yellow
            Remove-MgGroup -GroupId $existingGroup.Id -ErrorAction Stop
            Write-Host "    ✓ Deleted" -ForegroundColor Green
        } else {
            Write-Host "  Skipping: $groupName (not found)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "    ✗ Failed to delete: $_" -ForegroundColor Red
    }
    
    Start-Sleep -Milliseconds 500
}

Write-Host ""

# ============================================================================
# CREATE NEW ASSIGNED GROUPS AND ADD MEMBERS
# ============================================================================

Write-Host "[5/5] Creating Assigned Groups and Adding Members..." -ForegroundColor Cyan
Write-Host ""

$groupConfigs = @(
    @{
        Name = "INT-iOS-Oak-All"
        Description = "All Oak business line iOS devices (Assigned group with location groups as members)"
        MemberGroups = $oakCareGroups + $oakRecGroups
    },
    @{
        Name = "INT-iOS-Oak-Care"
        Description = "All Oak business line Care type iOS devices (Assigned group)"
        MemberGroups = $oakCareGroups
    },
    @{
        Name = "INT-iOS-Oak-Rec"
        Description = "All Oak business line Recreation type iOS devices (Assigned group)"
        MemberGroups = $oakRecGroups
    },
    @{
        Name = "INT-iOS-Spruce-All"
        Description = "All Spruce business line iOS devices (Assigned group)"
        MemberGroups = $spruceCareGroups + $spruceRecGroups
    },
    @{
        Name = "INT-iOS-Spruce-Care"
        Description = "All Spruce business line Care type iOS devices (Assigned group)"
        MemberGroups = $spruceCareGroups
    },
    @{
        Name = "INT-iOS-Spruce-Rec"
        Description = "All Spruce business line Recreation type iOS devices (Assigned group)"
        MemberGroups = $spruceRecGroups
    }
)

$results = @()

foreach ($config in $groupConfigs) {
    Write-Host "Creating: $($config.Name)" -ForegroundColor Cyan
    
    try {
        # Create ASSIGNED (static) security group
        $mailNickname = $config.Name.Replace("-", "").Replace(" ", "")
        
        $newGroup = New-MgGroup `
            -DisplayName $config.Name `
            -Description $config.Description `
            -MailEnabled:$false `
            -SecurityEnabled:$true `
            -MailNickname $mailNickname `
            -ErrorAction Stop
        
        Write-Host "  ✓ Created: $($newGroup.Id)" -ForegroundColor Green
        
        # Add location groups as members
        Write-Host "  Adding $($config.MemberGroups.Count) location groups as members..." -ForegroundColor Gray
        
        $addedCount = 0
        
        foreach ($memberGroup in $config.MemberGroups) {
            try {
                New-MgGroupMember -GroupId $newGroup.Id `
                                 -DirectoryObjectId $memberGroup.Id `
                                 -ErrorAction Stop
                
                $addedCount++
                
            } catch {
                if ($_.Exception.Message -notlike "*already exists*") {
                    Write-Host "    ⚠ Failed to add $($memberGroup.DisplayName)" -ForegroundColor Yellow
                }
            }
            
            Start-Sleep -Milliseconds 50
        }
        
        Write-Host "  ✓ Added $addedCount members" -ForegroundColor Green
        Write-Host ""
        
        $results += [PSCustomObject]@{
            GroupName = $config.Name
            GroupId = $newGroup.Id
            MembersAdded = $addedCount
            TotalMembers = $config.MemberGroups.Count
            Status = "Success"
        }
        
    } catch {
        Write-Host "  ✗ Failed: $_" -ForegroundColor Red
        Write-Host ""
        
        $results += [PSCustomObject]@{
            GroupName = $config.Name
            GroupId = "N/A"
            MembersAdded = 0
            TotalMembers = $config.MemberGroups.Count
            Status = "Failed"
        }
    }
    
    Start-Sleep -Milliseconds 500
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "OPERATION COMPLETE" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor White

Write-Host "`nResults:" -ForegroundColor White
Write-Host ""
$results | Format-Table -Property GroupName, MembersAdded, TotalMembers, Status -AutoSize

Write-Host ""
Write-Host "✓ New Assigned Groups Created:" -ForegroundColor Green
Write-Host ""
Write-Host "  INT-iOS-Oak-All" -ForegroundColor Cyan
Write-Host "    └─ Type: Assigned (Static)" -ForegroundColor Gray
Write-Host "    └─ Members: $($oakCareGroups.Count + $oakRecGroups.Count) location groups" -ForegroundColor Gray
Write-Host ""
Write-Host "  INT-iOS-Oak-Care" -ForegroundColor Cyan
Write-Host "    └─ Type: Assigned (Static)" -ForegroundColor Gray
Write-Host "    └─ Members: $($oakCareGroups.Count) Oak-Care location groups" -ForegroundColor Gray
Write-Host ""
Write-Host "  INT-iOS-Oak-Rec" -ForegroundColor Cyan
Write-Host "    └─ Type: Assigned (Static)" -ForegroundColor Gray
Write-Host "    └─ Members: $($oakRecGroups.Count) Oak-Rec location groups" -ForegroundColor Gray
Write-Host ""
Write-Host "  INT-iOS-Spruce-All" -ForegroundColor Cyan
Write-Host "    └─ Type: Assigned (Static)" -ForegroundColor Gray
Write-Host "    └─ Members: $($spruceCareGroups.Count + $spruceRecGroups.Count) location groups" -ForegroundColor Gray
Write-Host ""
Write-Host "  INT-iOS-Spruce-Care" -ForegroundColor Cyan
Write-Host "    └─ Type: Assigned (Static)" -ForegroundColor Gray
Write-Host "    └─ Members: $($spruceCareGroups.Count) Spruce-Care location groups" -ForegroundColor Gray
Write-Host ""
Write-Host "  INT-iOS-Spruce-Rec" -ForegroundColor Cyan
Write-Host "    └─ Type: Assigned (Static)" -ForegroundColor Gray
Write-Host "    └─ Members: $($spruceRecGroups.Count) Spruce-Rec location groups" -ForegroundColor Gray

Write-Host "`n" -ForegroundColor White

Write-Host "How It Works:" -ForegroundColor Yellow
Write-Host "  • Assigned groups CAN contain other groups (unlike dynamic)" -ForegroundColor White
Write-Host "  • Location groups are members → their devices inherit assignments" -ForegroundColor White
Write-Host "  • Membership is IMMEDIATE (no 24-48 hour wait)" -ForegroundColor White
Write-Host "  • Assign Intune policies to these 6 groups" -ForegroundColor White
Write-Host "  • All devices in member groups automatically get the policies" -ForegroundColor White

Write-Host "`n" -ForegroundColor White

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. ✓ 6 Assigned groups created with location groups as members" -ForegroundColor Green
Write-Host "  2. → Verify in Azure AD: Groups > [Group Name] > Members" -ForegroundColor White
Write-Host "  3. → Test: Assign a web link to INT-iOS-Oak-Care" -ForegroundColor White
Write-Host "  4. → Verify it deploys to all Oak-Care location devices" -ForegroundColor White
Write-Host "  5. → Migrate other assignments to these 6 groups" -ForegroundColor White

Write-Host "`n═══════════════════════════════════════════════════════════════════`n" -ForegroundColor White

# Export results
$results | Export-Csv -Path "AssignedGroups-Report.csv" -NoTypeInformation
Write-Host "Report saved: AssignedGroups-Report.csv`n" -ForegroundColor Green

Disconnect-MgGraph
