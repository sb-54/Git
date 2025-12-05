# Relaunch the script as Administrator if not already
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {

    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop

    # Pre-register NuGet silently
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Register-PackageSource -Name "Nuget" `
            -Location "https://www.nuget.org/api/v2" `
            -ProviderName "NuGet" `
            -Trusted `
            -Force `
            -ErrorAction SilentlyContinue

        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop
    }

    Import-PackageProvider -Name NuGet -Force -ErrorAction Stop

    $repo = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
    if ($repo.InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop
    }

    if (-not (Get-Command Get-WindowsAutopilotInfo -ErrorAction SilentlyContinue)) {
        Install-Script -Name Get-WindowsAutopilotInfo -Force -ErrorAction Stop
    }

    $ScriptPath = "$env:ProgramFiles\WindowsPowerShell\Scripts\Get-WindowsAutopilotInfo.ps1"
    if (Test-Path $ScriptPath) {
        Unblock-File -Path $ScriptPath
    } else {
        throw "Get-WindowsAutopilotInfo.ps1 not found at expected path: $ScriptPath"
    }

    # Determine output directory and file
    $outputDir = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Get-Location }
    $outputFile = Join-Path $outputDir "Hash.csv"

    & $ScriptPath -OutputFile $outputFile

    # Final output message (2 lines)
    Write-Host "Hash is done, eh!" -ForegroundColor Green
    Write-Host "$outputFile" -ForegroundColor Green

    # Open the folder containing the file
    Start-Process "explorer.exe" $outputDir
}
catch {
    Write-Host " An error occurred: $_" -ForegroundColor Red
}