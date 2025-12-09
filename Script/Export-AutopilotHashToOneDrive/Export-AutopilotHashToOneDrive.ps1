# ==========================
# Autopilot Hash to OneDrive
# ==========================

# CONFIG - UPDATE THESE 3 VALUES FOR YOUR ENVIRONMENT
$ClientId_OneDrive   = "887e3ea1-7f5c-485c-8fe4-a4bb44e24bda"
$ClientSecret_OneDrive = $env:ONEDRIVE_APP_SECRET   # <-- NO literal secret here
$TenantId            = "f182f527-abdc-4051-8ac6-7d483c7dab0b"
$UserUPN             = "Testhash@closingthegap.ca"

$GraphBaseUrl = "https://graph.microsoft.com/v1.0"

# --------------------------
# Logging / transcript setup
# --------------------------
try {
    $logPath = Join-Path $env:SystemRoot ("Temp\hash-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Start-Transcript -Path $logPath -Force | Out-Null
} catch { }

Write-Host "===== Autopilot hash collection and OneDrive upload started ====="

# ---------------------------------
# 1. Ensure Get-WindowsAutopilotInfo
# ---------------------------------
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Host "Installing NuGet provider (if needed)..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

    Write-Host "Installing Get-WindowsAutopilotInfo script (if needed)..."
    Install-Script -Name Get-WindowsAutopilotInfo -Force -Confirm:$false -ErrorAction Stop | Out-Null
    Write-Host "Get-WindowsAutopilotInfo is ready."
}
catch {
    Write-Host "ERROR: Failed to install Get-WindowsAutopilotInfo. $_" -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}

# --------------------------
# 2. Export hardware hash CSV
# --------------------------
try {
    $sn = (Get-WmiObject -Class Win32_BIOS).SerialNumber
    if ([string]::IsNullOrWhiteSpace($sn)) {
        Write-Host "ERROR: Could not read BIOS serial number." -ForegroundColor Red
        Stop-Transcript | Out-Null
        exit 1
    }

    Write-Host "Device serial number: $sn"

    $outputPath = Join-Path $env:SystemRoot ("Temp\{0}.csv" -f $sn)
    Write-Host "Exporting Autopilot hash to: $outputPath"

    Get-WindowsAutopilotInfo -OutputFile $outputPath -ErrorAction Stop

    if (-not (Test-Path $outputPath)) {
        Write-Host "ERROR: Hash export failed, file not found: $outputPath" -ForegroundColor Red
        Stop-Transcript | Out-Null
        exit 1
    }

    $csv = Import-Csv -Path $outputPath
    $hashLength = $csv.'Hardware Hash'.Length
    Write-Host "Hash exported successfully. Length: $hashLength (expected ~4096)."
}
catch {
    Write-Host "ERROR during hash export: $_" -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}

# --------------------------
# 3. Authenticate to Graph
# --------------------------
Write-Host "Authenticating to Microsoft Graph (client credentials)..."

try {
    $tokenBody = @{
        grant_type    = "client_credentials"
        scope         = "https://graph.microsoft.com/.default"
        client_id     = $ClientId_OneDrive
        client_secret = $ClientSecret_OneDrive
    }

    $tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                                       -Method POST `
                                       -Body $tokenBody `
                                       -ErrorAction Stop

    if (-not $tokenResponse.access_token) {
        Write-Host "ERROR: No access token returned from AAD." -ForegroundColor Red
        Stop-Transcript | Out-Null
        exit 1
    }

    $headers = @{
        "Authorization" = "Bearer $($tokenResponse.access_token)"
        "Content-Type"  = "application/json"
    }
    Write-Host "Graph authentication successful."
}
catch {
    Write-Host "ERROR: Graph authentication failed. $_" -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}

# --------------------------
# 4. Get OneDrive drive & folder
# --------------------------
try {
    Write-Host "Getting OneDrive drive for user: $UserUPN"
    $drive = Invoke-RestMethod -Uri "$GraphBaseUrl/users/$UserUPN/drive" `
                               -Method GET `
                               -Headers $headers `
                               -ErrorAction Stop

    if (-not $drive.id) {
        Write-Host "ERROR: Could not retrieve drive ID." -ForegroundColor Red
        Stop-Transcript | Out-Null
        exit 1
    }

    Write-Host "Drive ID: $($drive.id)"

    # Get existing 'hash' folder in root
    Write-Host "Locating 'hash' folder in OneDrive root..."
    $destFolder = Invoke-RestMethod -Uri "$GraphBaseUrl/users/$UserUPN/drives/$($drive.id)/root:/hash" `
                                    -Method GET `
                                    -Headers $headers `
                                    -ErrorAction Stop

    if (-not $destFolder.id) {
        Write-Host "ERROR: 'hash' folder not found in OneDrive." -ForegroundColor Red
        Stop-Transcript | Out-Null
        exit 1
    }

    Write-Host "'hash' folder ID: $($destFolder.id)"
}
catch {
    Write-Host "ERROR: Failed to get OneDrive drive or 'hash' folder. $_" -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}

# --------------------------
# 5. Upload CSV to OneDrive
# --------------------------
try {
    $file = $outputPath
    if (-not (Test-Path $file)) {
        Write-Host "ERROR: CSV file not found at upload time: $file" -ForegroundColor Red
        Stop-Transcript | Out-Null
        exit 1
    }

    $fileName = [System.IO.Path]::GetFileName($file)
    Write-Host "Uploading $fileName to OneDrive /hash/ ..."

    # Upload small file as simple PUT
    $uploadUri = "$GraphBaseUrl/users/$UserUPN/drives/$($drive.id)/items/$($destFolder.id):/${fileName}:/content"

    Invoke-RestMethod -Uri $uploadUri `
                      -Method PUT `
                      -Headers @{ "Authorization" = "Bearer $($tokenResponse.access_token)" } `
                      -InFile $file `
                      -ContentType "text/csv" `
                      -ErrorAction Stop

    Write-Host "File uploaded successfully to OneDrive /hash/$fileName"
}
catch {
    Write-Host "ERROR: File upload to OneDrive failed. $_" -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}

Write-Host "===== Script completed successfully ====="

try { Stop-Transcript | Out-Null } catch { }
exit 0
