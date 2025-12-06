param(
    [Parameter(Mandatory = $true)]
    [string[]]$Emails,

    # Optional: export results to CSV (e.g., "/Users/hea2eq/Downloads/LastActiveReport.csv")
    [string]$OutputFile
)

# ----------------------------
# Helpers
# ----------------------------
function Ensure-Graph {
    try {
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
            Install-Module Microsoft.Graph -Scope CurrentUser -Force -ErrorAction Stop
        }
        if (-not (Get-MgContext)) {
            # Scopes: read users + directory + audit logs
            Connect-MgGraph -Scopes "User.Read.All","Directory.Read.All","AuditLog.Read.All"
        }
    }
    catch {
        throw "Failed to prepare Microsoft Graph SDK or connect: $($_.Exception.Message)"
    }
}

function Get-LastActive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Email,
        [int]$RetryCount = 3
    )

    $attempt = 0
    while ($attempt -lt $RetryCount) {
        try {
            # 1) Prefer signInActivity (simpler and faster)
            # Note: signInActivity is not in the default projection; request it explicitly.
            $user = Get-MgUser -UserId $Email -Property "signInActivity,userPrincipalName" -ErrorAction Stop
            $sia  = $user.SignInActivity
            if ($sia -and $sia.LastSignInDateTime) {
                return [datetime]$sia.LastSignInDateTime
            }

            # 2) Fallback to audit sign-in logs (most recent)
            # Use OrderBy for Graph v1.0; then take the first record.
            $logs = Get-MgAuditLogSignIn `
                -Filter "userPrincipalName eq '$Email'" `
                -OrderBy "createdDateTime desc" `
                -Top 1 `
                -ConsistencyLevel eventual `
                -ErrorAction Stop

            if ($logs) {
                $last = $logs | Select-Object -First 1
                if ($last -and $last.CreatedDateTime) {
                    return [datetime]$last.CreatedDateTime
                }
            }

            # No activity found
            return $null
        }
        catch {
            $attempt++
            $msg = $_.Exception.Message

            # Retry on throttling (429) or transient 5xx (e.g., InternalServerError 500)
            if ($msg -match '429' -or $msg -match 'TooManyRequests' -or $msg -match 'Status:\s*5\d\d') {
                $sleep = [Math]::Min(60, [int][Math]::Pow(2, $attempt))
                Start-Sleep -Seconds $sleep
                continue
            }

            # Explicit "not found"
            if ($msg -match 'Request_ResourceNotFound' -or $msg -match 'ResourceNotFound' -or $msg -match 'User not found') {
                throw "User not found: $Email"
            }

            # Generic short retry
            Start-Sleep -Seconds 2
        }
    }

    throw "Failed to retrieve last active date for $Email after $RetryCount attempts."
}

# ----------------------------
# Main
# ----------------------------
Ensure-Graph

$rows = @()

foreach ($e in $Emails) {
    $e = $e.Trim()
    if ([string]::IsNullOrWhiteSpace($e)) { continue }

    try {
        $dt = Get-LastActive -Email $e
        $lastActiveOut = if ($dt) { (Get-Date $dt -Format "dd-MMM-yyyy HH:mm") } else { "Never Logged In" }

        # Console output
        Write-Output "$e : $lastActiveOut"

        # Collect for optional CSV
        $rows += [pscustomobject]@{
            Email      = $e
            LastActive = $lastActiveOut
        }
    }
    catch {
        $err = $_.Exception.Message
        Write-Warning "$e : $err"
        $rows += [pscustomobject]@{
            Email      = $e
            LastActive = "Error: $err"
        }
    }
}

if ($PSBoundParameters.ContainsKey('OutputFile') -and -not [string]::IsNullOrWhiteSpace($OutputFile)) {
    $rows | Export-Csv -Path $OutputFile -NoTypeInformation
    Write-Host "Report saved to $OutputFile"
}