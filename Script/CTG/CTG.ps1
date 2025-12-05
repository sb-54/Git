# =========================
# HP Warranty – Enhanced Scraper with Current HP Page Support
# Updated for HP's 2025 page structure changes - SYNTAX CORRECTED
# =========================

# -------- Settings --------
$ReportsLocation       = "/Users/hea2eq/Logs"
$CsvOutputPath         = "/Users/hea2eq/Logs/HP_Warranty_All.csv"
$FailedSerialsPath     = "/Users/hea2eq/Logs/HP_Failed_Serials.csv"
$DebugHtmlPath         = "/Users/hea2eq/Logs/HP_Debug_Pages"
$ClientName            = "HP-Fleet"
$CountryDefault        = "US"
$LangDefault           = "EN"
$DebugMode             = $true    # Enable debug mode for troubleshooting

$MinDelaySec           = 3.0
$MaxDelaySec           = 7.0
$MaxBootstrapRetries   = 6
$MaxWarrantyRetries    = 4
$BaseBackoffSec        = 5
$SessionTimeout        = 180
$MaxSessionReuse       = 15

# User agents
$UserAgents = @(
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:127.0) Gecko/20100101 Firefox/127.0'
)

# -------- Enhanced Initialization --------
$ErrorActionPreference = 'Stop'
try { 
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
} catch {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

# Create directories
New-Item -ItemType Directory -Force -Path $ReportsLocation | Out-Null
New-Item -ItemType Directory -Force -Path $DebugHtmlPath | Out-Null

$LogPath = Join-Path $ReportsLocation ("HP_Warranty_Debug_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogPath -Force -ErrorAction SilentlyContinue

# -------- Logging Functions --------
function Write-WarrantyLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$SerialNumber = ""
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $(if($SerialNumber){"[$SerialNumber] "})$Message"
    
    switch($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        "DEBUG" { Write-Host $logMessage -ForegroundColor Cyan }
        default { Write-Host $logMessage -ForegroundColor White }
    }
    
    Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
}

function Save-DebugHtml {
    param(
        [string]$Content,
        [string]$Filename
    )
    try {
        $debugFile = Join-Path $DebugHtmlPath "$Filename.html"
        $Content | Out-File -FilePath $debugFile -Encoding UTF8
        Write-WarrantyLog -Message "Debug HTML saved: $debugFile" -Level "DEBUG"
    } catch {
        Write-WarrantyLog -Message "Failed to save debug HTML: $($_.Exception.Message)" -Level "WARNING"
    }
}

# -------- Session Bootstrap --------
function Get-HPWarrantySession {
    Write-WarrantyLog -Message "Starting enhanced session bootstrap" -Level "INFO"
    
    # Fixed regex patterns
    $patterns = @(
        'window\.sessionId\s*=\s*["\u0027]([^"\u0027]+)["\u0027]',
        'sessionId["\u0027]?\s*:\s*["\u0027]([^"\u0027]+)["\u0027]',
        'mwsid["\u0027]?\s*:\s*["\u0027]([^"\u0027]+)["\u0027]',
        'ssid["\u0027]?\s*:\s*["\u0027]([^"\u0027]+)["\u0027]',
        '"sessionToken"\s*:\s*"([^"]+)"',
        '"authToken"\s*:\s*"([^"]+)"',
        '"mwsid"\s*:\s*"([^"]+)"',
        '"ssid"\s*:\s*"([^"]+)"',
        'var\s+sessionId\s*=\s*["\u0027]([^"\u0027]+)["\u0027]',
        'var\s+ssid\s*=\s*["\u0027]([^"\u0027]+)["\u0027]'
    )

    $cookiePatterns = @(
        'sessionId=([^;\s]+)',
        'ssid=([^;\s]+)',
        'HP_SSID=([^;\s]+)',
        'mwsid=([^;\s]+)'
    )

    # URLs to try
    $urlsToTry = @(
        "https://support.hp.com/us-en/checkwarranty/multipleproducts",
        "https://support.hp.com/us-en/checkwarranty", 
        "https://support.hp.com/checkwarranty",
        "https://support.hp.com/ca-en/checkwarranty"
    )

    foreach ($url in $urlsToTry) {
        try {
            Write-WarrantyLog -Message "Trying URL: $url" -Level "DEBUG"
            
            $headers = @{
                'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                'Accept-Language' = 'en-US,en;q=0.5'
                'User-Agent' = (Get-Random -InputObject $UserAgents)
                'Connection' = 'keep-alive'
                'Cache-Control' = 'max-age=0'
            }

            $response = Invoke-WebRequest -Uri $url -Headers $headers -SessionVariable 'session' -TimeoutSec 30 -MaximumRedirection 5
            
            Write-WarrantyLog -Message "Response: $($response.StatusCode) - Content Length: $($response.Content.Length)" -Level "DEBUG"
            
            # Save debug HTML
            $timestamp = Get-Date -Format 'HHmmss'
            $urlPart = $url.Split('/')[-1]
            if ([string]::IsNullOrEmpty($urlPart)) { $urlPart = "root" }
            Save-DebugHtml -Content $response.Content -Filename "debug_${timestamp}_${urlPart}"
            
            # Check cookies
            $sessionId = $null
            if ($response.Headers.ContainsKey('Set-Cookie')) {
                foreach ($cookie in $response.Headers['Set-Cookie']) {
                    Write-WarrantyLog -Message "Cookie found: $($cookie.Substring(0, [Math]::Min(80, $cookie.Length)))" -Level "DEBUG"
                    
                    foreach ($pattern in $cookiePatterns) {
                        if ($cookie -match $pattern) {
                            $sessionId = $Matches[1]
                            Write-WarrantyLog -Message "Session ID found in cookie: $sessionId" -Level "SUCCESS"
                            break
                        }
                    }
                    if ($sessionId) { break }
                }
            }

            # Check session cookies
            if (-not $sessionId -and $session -and $session.Cookies) {
                try {
                    $uriObject = [System.Uri]$url
                    $cookiesForDomain = $session.Cookies.GetCookies($uriObject)
                    foreach ($cookie in $cookiesForDomain) {
                        Write-WarrantyLog -Message "Session cookie: $($cookie.Name)=$($cookie.Value)" -Level "DEBUG"
                        if ($cookie.Name -match '^(sessionId|ssid|mwsid|HP_SSID)$' -and $cookie.Value) {
                            $sessionId = $cookie.Value
                            Write-WarrantyLog -Message "Session ID found in session cookies: $sessionId" -Level "SUCCESS"
                            break
                        }
                    }
                } catch {
                    Write-WarrantyLog -Message "Error checking session cookies: $($_.Exception.Message)" -Level "DEBUG"
                }
            }

            # Check HTML content
            if (-not $sessionId) {
                Write-WarrantyLog -Message "Checking HTML content for session patterns..." -Level "DEBUG"
                
                foreach ($pattern in $patterns) {
                    try {
                        if ($response.Content -match $pattern) {
                            $sessionId = $Matches[1]
                            Write-WarrantyLog -Message "Session ID found in HTML: $sessionId" -Level "SUCCESS"
                            break
                        }
                    } catch {
                        continue
                    }
                }
            }

            # If session found, return it
            if ($sessionId -and $sessionId.Length -gt 5) {
                return [pscustomobject]@{
                    Ssid = $sessionId
                    WebSession = $session
                    SourceUrl = $url
                    CreatedAt = Get-Date
                }
            } else {
                Write-WarrantyLog -Message "No valid session ID found on this page" -Level "WARNING"
                $sample = $response.Content.Substring(0, [Math]::Min(300, $response.Content.Length))
                Write-WarrantyLog -Message "Content sample: $sample" -Level "DEBUG"
            }

        } catch {
            Write-WarrantyLog -Message "Failed to access $url : $($_.Exception.Message)" -Level "WARNING"
        }
        
        Start-Sleep -Seconds 3
    }

    throw "Could not establish HP warranty session after trying all URLs"
}

# -------- Test Session --------
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " HP WARRANTY SESSION DEBUG TEST" -ForegroundColor Cyan  
Write-Host "=====================================" -ForegroundColor Cyan

Write-WarrantyLog -Message "Debug files: $DebugHtmlPath" -Level "INFO"
Write-WarrantyLog -Message "Log file: $LogPath" -Level "INFO"

try {
    $testSession = Get-HPWarrantySession
    if ($testSession) {
        Write-Host ""
        Write-Host "✅ SUCCESS: Session created!" -ForegroundColor Green
        Write-Host "Session ID: $($testSession.Ssid.Substring(0, [Math]::Min(15, $testSession.Ssid.Length)))..." -ForegroundColor Yellow
        Write-Host "Source URL: $($testSession.SourceUrl)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "🎉 Your HP warranty session is working!" -ForegroundColor Green
    }
} catch {
    Write-Host ""
    Write-Host "❌ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "🔍 Check these files:" -ForegroundColor Yellow
    Write-Host "- Log: $LogPath" -ForegroundColor Cyan
    Write-Host "- Debug HTML: $DebugHtmlPath" -ForegroundColor Cyan
}

Stop-Transcript
