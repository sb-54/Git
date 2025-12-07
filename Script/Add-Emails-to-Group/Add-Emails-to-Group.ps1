# List of emails
$userEmails = @"
junilaine.ponsones@paramed.com
felixmathew.kokkatabraham@paramed.com
merlice.david@paramed.com
"@ -split "`n"

# Trim whitespace
$userEmails = $userEmails | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

# Group name
$GroupName = "Intune_Salesfore"

# Retrieve group once
$group = Get-MgGroup -Filter "displayName eq '$GroupName'"
if (-not $group) {
    Write-Host "Group '$GroupName' NOT FOUND." -ForegroundColor Red
    return
}
Write-Host "Group Found: $($group.DisplayName)" -ForegroundColor Green

# Results array
$results = @()

foreach ($UserEmail in $userEmails) {
    $entry = [ordered]@{
        Email = $UserEmail
        UserFound = $false
        AddedToGroup = $false
        AlreadyMember = $false
        DisplayName = ""
        Error = ""
    }
    try {
        $user = Get-MgUser -Filter "userPrincipalName eq '$UserEmail' or mail eq '$UserEmail'"
        if (-not $user) {
            $entry.Error = "User not found"
            Write-Host "User with email '$UserEmail' NOT FOUND." -ForegroundColor Red
        } else {
            $entry.UserFound = $true
            $entry.DisplayName = $user.DisplayName
            # Check membership
            $member = Get-MgGroupMember -GroupId $group.Id -All | Where-Object { $_.Id -eq $user.Id }
            if ($member) {
                $entry.AlreadyMember = $true
                Write-Host "User $($user.DisplayName) ($UserEmail) is already a member." -ForegroundColor Yellow
            } else {
                # Add user to group (correctly, using REST API)
                $uri = "https://graph.microsoft.com/v1.0/groups/$($group.Id)/members/`$ref"
                $body = @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
                } | ConvertTo-Json -Depth 5
                Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType "application/json" -ErrorAction Stop
                $entry.AddedToGroup = $true
                Write-Host "User $($user.DisplayName) ($UserEmail) ADDED to group." -ForegroundColor Green
            }
        }
    } catch {
        $entry.Error = $_.Exception.Message
        Write-Host "Error for $UserEmail : $($entry.Error)" -ForegroundColor Red
    }
    $results += [pscustomobject]$entry
}

# Export/report
$results | Export-Csv -NoTypeInformation -Path .\IntuneSalesfore_Group_Assignment_Results.csv
Write-Host "Summary exported to IntuneSalesfore_Group_Assignment_Results.csv" -ForegroundColor Cyan
