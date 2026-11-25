<#
    custom/proxy.ps1
    智能代理分流、国内白名单、物理 IP 地理位置检测及 504 自动回退加速
    底层采用内置 curl-impersonate (真实 Chrome BoringSSL 指纹) 与系统 curl.exe 高速引擎
#>

function Get-CurlProxy($url = 'https://example.com/') {
    try {
        $scoopProxy = get_config PROXY
        if ($scoopProxy -eq 'none') {
            return $null
        }
        if ($scoopProxy -and $scoopProxy -ne 'default') {
            if ($scoopProxy -notmatch '^(https?|socks[45][ah]?)://') {
                $scoopProxy = "http://$scoopProxy"
            }
            return $scoopProxy.TrimEnd('/')
        }

        $testUri = [System.Uri]$url
        foreach ($provider in @([System.Net.WebRequest]::DefaultWebProxy, [System.Net.WebRequest]::GetSystemWebProxy())) {
            if ($null -eq $provider) { continue }
            $proxyUri = $provider.GetProxy($testUri)
            if ($null -ne $proxyUri -and $proxyUri.AbsoluteUri -ne $testUri.AbsoluteUri) {
                return $proxyUri.AbsoluteUri.TrimEnd('/')
            }
        }

        if ($env:ALL_PROXY) { return $env:ALL_PROXY.TrimEnd('/') }
        if ($env:HTTPS_PROXY -and $url -like 'https*') { return $env:HTTPS_PROXY.TrimEnd('/') }
        if ($env:HTTP_PROXY) { return $env:HTTP_PROXY.TrimEnd('/') }
    } catch {}

    return $null
}

function Test-SystemProxy($url = 'https://example.com/') {
    return ($null -ne (Get-CurlProxy $url))
}

function Test-ChinaWhitelistedHost($hostName) {
    if (!$hostName) { return $false }
    if ($hostName -match "^(.*):\d+$") { $hostName = $matches[1] }

    $chinaWhitelist = @(
        'douyin\.com', 'dy\.com', 'dycdn\.com',        # TikTok/抖音
        'quarkcdn\.com', 'quark\.cn',                  # Quark/夸克
        'tencent\.com', 'qq\.com', 'qzone\.qq\.com',   # Tencent/腾讯
        'alibaba\.com', 'aliyun\.com', 'taobao\.com', 'tmall\.com', # Alibaba/阿里
        'baidu\.com', 'baiducdn\.com', 'baidupcs\.com',# Baidu/百度
        'netease\.com', '163\.com', '126\.com', '126\.net', # NetEase/网易
        'jd\.com', 'jingdong\.com',                    # JD/京东
        'bilibili\.com', 'bilicdn\.com', 'hdslb\.com', # Bilibili/B站
        'youku\.com', 'tudou\.com',                    # Youku/优酷
        'weibo\.com', 'sina\.com\.cn',                 # Weibo/微博
        'zhihu\.com',                                  # Zhihu/知乎
        'feishucdn\.com', 'feishu\.cn',                # Feishu/飞书
        'gitcode\.net', 'gitee\.io', 'gitee\.com',     # Chinese Git platforms
        'mozilla\.org',                                # Mozilla
        'visualstudio\.com',                           # Visual Studio
        '\.cn$', '\.com\.cn$', 'net\.cn'               # All .cn domains
    )
    foreach ($pattern in $chinaWhitelist) {
        if ($hostName -match $pattern) {
            return $true
        }
    }
    return $false
}

function Url_Proxy($url) {
    try {
        # Check self-hosted domain
        if ($url -match "1122330\.xyz") {
            success "direct: $url (whitelisted domain)"
            return $url
        }

        $isSimpleUrl = ($url -match "^https?://([^/]+)")
        $hostName = if ($isSimpleUrl) { $matches[1] } else { $null }

        if ($hostName) {
            if (Test-ChinaWhitelistedHost $hostName) {
                success "direct: $url (whitelisted domain: $hostName)"
                return $url
            }
        }

        if (Test-SystemProxy $url) {
            success "direct: $url (system proxy detected)"
            return $url
        }

        if ($isSimpleUrl) {
            if ($hostName) {
                if ($hostName -match "^\d+\.\d+\.\d+\.\d+$") {
                    $ip = $hostName
                } else {
                    $ip = $null
                    if (Get-Command "Resolve-DnsName" -ErrorAction SilentlyContinue) {
                        try {
                            $dnsResults = Resolve-DnsName -Name $hostName -Server "223.5.5.5" -ErrorAction SilentlyContinue
                            $ip = ($dnsResults | Where-Object { $_.QueryType -eq 'A' -and $_.IPAddress } | Select-Object -ExpandProperty IPAddress -First 1)
                            if (!$ip) {
                                $ip = ($dnsResults | Where-Object { $_.QueryType -eq 'AAAA' -and $_.IPAddress } | Select-Object -ExpandProperty IPAddress -First 1)
                            }
                        } catch {}
                    }
                    if (!$ip) {
                        try {
                            $ip = [System.Net.Dns]::GetHostAddresses($hostName) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1 -ExpandProperty IPAddressToString
                        } catch {}
                    }
                }

                if ($ip) {
                    if ($ip -match "^(127\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|100\.64\.|198\.1[89]\.)") {
                        success "direct: $url (internal/fake: $ip)"
                        return $url
                    }

                    $isChina = $null
                    try {
                        $ipInfoRaw = (curl.exe -s --noproxy '*' --connect-timeout 1 --max-time 2 "https://ip9.com.cn/get?ip=$ip") -join ''
                        $ipInfo = $ipInfoRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($ipInfo -and $ipInfo.ret -eq 200 -and $ipInfo.data -and $ipInfo.data.country_code) {
                            $isChina = ($ipInfo.data.country_code -eq "cn")
                        }
                    } catch {}

                    if ($null -eq $isChina) {
                        try {
                            $ipInfo = Invoke-RestMethod -Uri "https://whois.pconline.com.cn/ipJson.jsp?ip=$ip&json=true" -Method Get -UseBasicParsing -ErrorAction SilentlyContinue
                            if ($ipInfo -and $null -ne $ipInfo.proCode) {
                                $isChina = ($ipInfo.proCode -ne "999999")
                            }
                        } catch {}
                    }

                    if ($isChina -eq $true) {
                        success "direct: $url (China)"
                        return $url
                    }
                    if ($isChina -eq $false) {
                        return uProxy($url)
                    }
                    info "geo-lookup failed for $ip, using proxy: $url"
                    return uProxy($url)
                }
            }
            warn "dns resolution failed for $hostName, using proxy: $url"
            return uProxy($url)
        }
    } catch {
        warn "exception in Url_Proxy, using proxy: $_"
        return uProxy($url)
    }
    return uProxy($url)
}

function uProxy($url) {
    $Proxy = get_config URL_PROXY -default 'https://cfproxy.1122330.xyz'
    success "proxy: $url"
    return "$Proxy/$(strip_fragment $url)"
}

function Format-Win32Arg([string] $Arg) {
    if ($null -eq $Arg) { return '""' }
    if ($Arg.Length -gt 0 -and $Arg -notmatch '[\s"]') { return $Arg }
    $escaped = $Arg -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return "`"$escaped`""
}

function ConvertFrom-CurlSize([string] $Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0.0 }
    if ($Text -match '^([0-9]+(?:\.[0-9]+)?)([kKmMgGtT])?$') {
        $val = [double]$matches[1]
        switch ($matches[2]) {
            'k' { return $val * 1024 }
            'm' { return $val * 1048576 }
            'g' { return $val * 1073741824 }
            't' { return $val * 1099511627776 }
            default { return $val }
        }
    }
    return 0.0
}

function Format-HumanBytes([double] $Bytes) {
    if ($Bytes -ge 1073741824) { return '{0:N2} GB' -f ($Bytes / 1073741824) }
    if ($Bytes -ge 1048576)    { return '{0:N1} MB' -f ($Bytes / 1048576) }
    if ($Bytes -ge 1024)       { return '{0:N1} KB' -f ($Bytes / 1024) }
    return '{0:N0} B' -f $Bytes
}

function Format-SizePair([double] $Done, [double] $Total) {
    if ($Total -ge 1073741824) { return '{0:N2}/{1:N2} GB' -f ($Done / 1073741824), ($Total / 1073741824) }
    if ($Total -ge 1048576)    { return '{0:N1}/{1:N1} MB' -f ($Done / 1048576), ($Total / 1048576) }
    if ($Total -ge 1024)       { return '{0:N1}/{1:N1} KB' -f ($Done / 1024), ($Total / 1024) }
    return '{0:N0}/{1:N0} B' -f $Done, $Total
}

function Format-Duration([double] $Seconds) {
    if ($Seconds -lt 0 -or [double]::IsNaN($Seconds) -or [double]::IsInfinity($Seconds)) { return '--:--' }
    $ts = [TimeSpan]::FromSeconds([math]::Floor($Seconds))
    if ($ts.TotalHours -ge 1) {
        return '{0}:{1:D2}:{2:D2}' -f [int][math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds
    }
    return '{0:D2}:{1:D2}' -f $ts.Minutes, $ts.Seconds
}

function Test-ConsoleGlyph([string] $Text) {
    try {
        $enc = [Console]::OutputEncoding
        if ($null -eq $enc -or [string]::IsNullOrEmpty($Text)) { return $false }
        return ($enc.GetString($enc.GetBytes($Text)) -eq $Text)
    } catch {
        return $false
    }
}

function Write-CurlProgressLine {
    param(
        [string] $DisplayName,
        [double] $DoneBytes,
        [double] $TotalBytes,
        [double] $SpeedBytes,
        [string] $EtaText,
        [double] $ElapsedSec,
        [int]    $SpinnerIdx = 0,
        [switch] $Completed
    )

    $esc = [char]0x1b
    $cReset = "$esc[0m"
    $cCyan  = "$esc[36m"
    $cGreen = "$esc[32m"
    $cYel   = "$esc[33m"
    $cDim   = "$esc[90m"

    $winWidth = 100
    try {
        if ([Console]::WindowWidth -gt 20) { $winWidth = [Console]::WindowWidth }
    } catch {}
    $maxCols = [math]::Max(40, $winWidth - 1)

    # Probe [Console]::OutputEncoding per glyph rather than $env:WT_SESSION, because
    # PS 5.1 inside Windows Terminal still defaults OutputEncoding to CP936 (GBK) where ✓/⠋ become '?'.
    if (Test-ConsoleGlyph ([string][char]0x280B)) {
        $spinFrames = @([char]0x280B, [char]0x2819, [char]0x2839, [char]0x2838, [char]0x283C, [char]0x2834, [char]0x2826, [char]0x2827, [char]0x2807, [char]0x280F)
    } else {
        $spinFrames = @('|', '/', '-', '\')
    }

    if ((Test-ConsoleGlyph ([string][char]0x2501)) -and (Test-ConsoleGlyph ([string][char]0x2500))) {
        $chFill = [char]0x2501
        $chEmpty = [char]0x2500
    } else {
        $chFill = '='
        $chEmpty = '-'
    }

    if (Test-ConsoleGlyph ([string][char]0x2713)) {
        $chDone = [char]0x2713
    } elseif (Test-ConsoleGlyph ([string][char]0x221A)) {
        $chDone = [char]0x221A
    } else {
        $chDone = '+'
    }

    $maxNameLen = if ($maxCols -lt 75) { 18 } else { 26 }
    $nameText = $DisplayName
    if ($nameText.Length -gt $maxNameLen) {
        $nameText = $nameText.Substring(0, $maxNameLen - 3) + '...'
    }

    $spin = $spinFrames[$SpinnerIdx % $spinFrames.Count]

    # Phase 1: Connecting / waiting for headers or redirect
    if (-not $Completed -and $TotalBytes -le 0 -and $DoneBytes -le 0) {
        $elapsed = Format-Duration $ElapsedSec
        $line = "$cCyan$spin$cReset $cCyan$nameText$cReset  ${cDim}Connecting... $elapsed$cReset"
        [Console]::Write("`r$line$esc[K")
        return
    }

    # Phase 2b: Streaming with unknown total size
    if (-not $Completed -and $TotalBytes -le 0) {
        $sizeStr = Format-HumanBytes $DoneBytes
        $spdStr  = "$(Format-HumanBytes $SpeedBytes)/s"
        $elapsed = Format-Duration $ElapsedSec
        $line = "$cCyan$spin$cReset $cCyan$nameText$cReset  $sizeStr  $cYel$spdStr$cReset  $cDim$elapsed$cReset"
        [Console]::Write("`r$line$esc[K")
        return
    }

    # Phase 2 & 3: Determinate progress bar (or 100% completed)
    $pct = if ($Completed) { 100.0 } else { [math]::Min(100.0, [math]::Max(0.0, ($DoneBytes / $TotalBytes) * 100.0)) }
    $pctStr = '{0,5:N1}%' -f $pct
    $sizeStr = if ($Completed) { Format-HumanBytes $TotalBytes } else { Format-SizePair $DoneBytes $TotalBytes }
    $spdStr  = "$(Format-HumanBytes $SpeedBytes)/s"
    $timeStr = if ($Completed) { Format-Duration $ElapsedSec } else { "ETA $EtaText" }

    $prefixChar = if ($Completed) { "$cGreen$chDone$cReset" } else { "$cCyan$spin$cReset" }
    $leftVisibleLen = 2 + $nameText.Length + 2

    $includeTime = $true
    $rightVisibleLen = $pctStr.Length + 2 + $sizeStr.Length + 2 + $spdStr.Length + 2 + $timeStr.Length
    $availBar = $maxCols - $leftVisibleLen - $rightVisibleLen - 2
    if ($availBar -lt 10) {
        $includeTime = $false
        $rightVisibleLen = $pctStr.Length + 2 + $sizeStr.Length + 2 + $spdStr.Length
        $availBar = $maxCols - $leftVisibleLen - $rightVisibleLen - 2
    }
    $barWidth = [math]::Max(8, [math]::Min(34, $availBar))

    $filled = [int][math]::Round(($pct / 100.0) * $barWidth)
    $filled = [math]::Min($barWidth, [math]::Max(0, $filled))
    if (-not $Completed -and $filled -ge $barWidth) { $filled = $barWidth - 1 }
    $empty  = $barWidth - $filled

    $barColor = if ($Completed) { $cGreen } else { $cCyan }
    $filledStr = if ($filled -gt 0) { New-Object string($chFill, $filled) } else { '' }
    $emptyStr  = if ($empty -gt 0)  { New-Object string($chEmpty, $empty) } else { '' }
    $barRender = "$barColor$filledStr$cDim$emptyStr$cReset"

    $timeSeg = if ($includeTime) { "  $cDim$timeStr$cReset" } else { '' }
    $pctRender = if ($Completed) { "$cGreen$pctStr$cReset" } else { $pctStr }

    $line = "$prefixChar $cCyan$nameText$cReset  $barRender $pctRender  $sizeStr  $cYel$spdStr$cReset$timeSeg"
    [Console]::Write("`r$line$esc[K")
    if ($Completed) {
        [Console]::WriteLine()
    }
}

function Invoke-CurlTransfer {
    <#
        Executes a curl binary with targeted retries for transient TLS handshake
        drops (exit code 35) and socket/HTTP2 resets, cleaning up partial files,
        and renders a clean modern progress bar when interactive.
    #>
    param(
        [string] $ExePath,
        [string] $EngineName,
        [string[]] $BaseArgs,
        [string[]] $FallbackExtraArgs = @(),
        [string] $To,
        [string] $DisplayName = '',
        [bool]   $ShowProgress = $false,
        [int]    $MaxAttempts = 4,
        [hashtable] $Status = @{}
    )

    # 7: connect fail, 18: partial file, 35: TLS handshake drop (SSL_ERROR_SYSCALL/schannel),
    # 52: empty reply, 55/56: send/recv reset, 92: HTTP/2 stream framing error over proxy
    $recoverableExitCodes = @(7, 18, 35, 52, 55, 56, 92)
    $lastCode = 0
    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = Split-Path -Leaf $To
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if (Test-Path $To) {
            Remove-Item -Force $To -ErrorAction SilentlyContinue
        }

        $runArgs = $BaseArgs
        # Switch to HTTP/1.1 on final retry in case the upstream proxy/CDN chokes on HTTP/2
        if ($attempt -eq $MaxAttempts -and $FallbackExtraArgs.Count -gt 0) {
            $runArgs = $FallbackExtraArgs + $BaseArgs
        }

        if (-not $ShowProgress) {
            try {
                $global:LASTEXITCODE = 0
                & $ExePath @runArgs
                $lastCode = $LASTEXITCODE
                if ($lastCode -eq 0 -and (Test-Path $To) -and (Get-Item $To).Length -gt 0) {
                    $Status.ExitCode = 0
                    return $true
                }
            } catch {
                warn "$EngineName execution exception: $_"
                $lastCode = if ($LASTEXITCODE -ne 0) { $LASTEXITCODE } else { -1 }
            }
        } else {
            $esc = [char]0x1b
            $proc = $null
            $errLines = New-Object System.Collections.Generic.List[string]
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $lastDrawMs = -1000L
            $spinIdx = 0
            $totalBytes = 0.0
            $recvBytes = 0.0
            $speedBytes = 0.0
            $etaText = '--:--'
            $cursorHidden = $false

            try {
                try {
                    [Console]::CursorVisible = $false
                    $cursorHidden = $true
                } catch {}

                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $ExePath
                $psi.Arguments = (($runArgs | ForEach-Object { Format-Win32Arg $_ }) -join ' ')
                $psi.UseShellExecute = $false
                $psi.RedirectStandardError = $true
                $psi.RedirectStandardOutput = $true
                $psi.CreateNoWindow = $true

                $proc = New-Object System.Diagnostics.Process
                $proc.StartInfo = $psi
                [void]$proc.Start()
                $proc.BeginOutputReadLine()

                $errTask = $proc.StandardError.ReadLineAsync()
                while ($true) {
                    $gotLine = $false
                    try {
                        $gotLine = $errTask.Wait(80)
                    } catch {
                        break
                    }

                    if ($gotLine) {
                        $line = $null
                        try { $line = $errTask.Result } catch { break }
                        if ($null -eq $line) { break }

                        if ($line -match '^\s*(\d+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*)$') {
                            $parsedTotal = ConvertFrom-CurlSize $matches[2]
                            $parsedRecv  = ConvertFrom-CurlSize $matches[4]
                            $parsedAvg   = ConvertFrom-CurlSize $matches[7]
                            $tail        = ($matches[9].Trim() -split '\s+') | Where-Object { $_ -ne '' }
                            $parsedCur   = if ($tail.Count -ge 1) { ConvertFrom-CurlSize $tail[-1] } else { 0.0 }

                            if ($parsedTotal -gt 0) { $totalBytes = $parsedTotal }
                            if ($parsedRecv -gt 0)  { $recvBytes = $parsedRecv }
                            $speedBytes = if ($parsedCur -gt 0) { $parsedCur } else { $parsedAvg }

                            if ([int]$matches[1] -ge 100) {
                                $etaText = '00:00'
                            } elseif ($tail.Count -ge 4 -and $tail[2] -ne '--:--:--') {
                                $etaText = $tail[2]
                            } elseif ($totalBytes -gt 0 -and $speedBytes -gt 0) {
                                $etaText = Format-Duration (($totalBytes - $recvBytes) / $speedBytes)
                            }
                        } elseif (-not [string]::IsNullOrWhiteSpace($line) -and $line -notmatch '^\s*%\s+Total\b' -and $line -notmatch '^\s*Dload\s+Upload\b') {
                            [void]$errLines.Add($line.Trim())
                        }

                        $errTask = $proc.StandardError.ReadLineAsync()
                    }

                    if (($sw.ElapsedMilliseconds - $lastDrawMs) -ge 80) {
                        $diskBytes = 0.0
                        if (Test-Path $To) {
                            try { $diskBytes = [double](Get-Item $To -ErrorAction SilentlyContinue).Length } catch {}
                        }
                        $shownDone = [math]::Max($recvBytes, $diskBytes)
                        if ($totalBytes -gt 0 -and $shownDone -gt $totalBytes) { $shownDone = $totalBytes }
                        if ($speedBytes -le 0 -and $shownDone -gt 0 -and $sw.Elapsed.TotalSeconds -gt 0.2) {
                            $speedBytes = $shownDone / $sw.Elapsed.TotalSeconds
                        }
                        $liveEta = if ($totalBytes -gt 0 -and $speedBytes -gt 0) {
                            Format-Duration ([math]::Max(0.0, ($totalBytes - $shownDone) / $speedBytes))
                        } else {
                            $etaText
                        }
                        Write-CurlProgressLine -DisplayName $DisplayName -DoneBytes $shownDone -TotalBytes $totalBytes -SpeedBytes $speedBytes -EtaText $liveEta -ElapsedSec $sw.Elapsed.TotalSeconds -SpinnerIdx $spinIdx
                        $spinIdx++
                        $lastDrawMs = $sw.ElapsedMilliseconds
                    }
                }

                $proc.WaitForExit()
                $lastCode = $proc.ExitCode
                $sw.Stop()

                if ($lastCode -eq 0 -and (Test-Path $To) -and (Get-Item $To).Length -gt 0) {
                    $finalBytes = [double](Get-Item $To).Length
                    $elapsedSec = [math]::Max($sw.Elapsed.TotalSeconds, 0.01)
                    $avgSpeed = $finalBytes / $elapsedSec
                    Write-CurlProgressLine -DisplayName $DisplayName -DoneBytes $finalBytes -TotalBytes $finalBytes -SpeedBytes $avgSpeed -EtaText '00:00' -ElapsedSec $sw.Elapsed.TotalSeconds -Completed
                    $Status.ExitCode = 0
                    return $true
                }

                # Clear progress bar before showing error diagnostics
                [Console]::Write("`r$esc[K")
                foreach ($errLine in $errLines) {
                    Write-Host $errLine -ForegroundColor DarkRed
                }
            } catch {
                [Console]::Write("`r$esc[K")
                warn "$EngineName execution exception: $_"
                $lastCode = -1
            } finally {
                if ($null -ne $proc) {
                    try {
                        if (-not $proc.HasExited) { $proc.Kill() }
                    } catch {}
                    try { $proc.Dispose() } catch {}
                }
                if ($cursorHidden) {
                    try { [Console]::CursorVisible = $true } catch {}
                }
            }
        }

        if (Test-Path $To) {
            Remove-Item -Force $To -ErrorAction SilentlyContinue
        }

        if ($attempt -lt $MaxAttempts -and ($recoverableExitCodes -contains $lastCode)) {
            warn "$EngineName connection/TLS error (exit code $lastCode), retrying ($attempt/$($MaxAttempts - 1))..."
            Start-Sleep -Milliseconds 400
            continue
        }

        break
    }

    $Status.ExitCode = $lastCode
    return $false
}

function Custom-Invoke-Download ($url, $to, $cookies, $progress, [switch] $NoProxy) {
    $downloadUrl = ($url -split '#')[0]
    $reqUrl = if ($NoProxy) { $downloadUrl } else { Url_Proxy($downloadUrl) }
    $isAccelerated = ($reqUrl -match "1122330\.xyz")

    # 代理参数解析：如果为国内白名单、-NoProxy 或已走加速节点，直连下载；否则走代理
    $proxyArg = $null
    if (!$NoProxy -and !$isAccelerated) {
        $hostName = if ($downloadUrl -match "^https?://([^/]+)") { $matches[1] } else { $null }
        if (!(Test-ChinaWhitelistedHost $hostName)) {
            $proxyArg = Get-CurlProxy $downloadUrl
        }
    }

    # 确保目标文件夹存在并清理残留文件
    $parent = Split-Path -Parent $to
    if ($parent -and !(Test-Path $parent)) {
        ensure $parent | Out-Null
    }
    if ((Test-Path $to) -and (Get-Item $to).Length -eq 0) {
        Remove-Item -Force $to -ErrorAction SilentlyContinue
    }

    # 构造标头与鉴权参数
    $headers = @()
    if (-not ($downloadUrl -match 'sourceforge\.net' -or $downloadUrl -match 'portableapps\.com')) {
        $ref = strip_filename $downloadUrl
        if ($ref) { $headers += @('-e', $ref) }
    }
    if ($downloadUrl -match '^https://api\.github\.com/repos') {
        $headers += @(
            '-H', 'Accept: application/octet-stream',
            '-H', "Authorization: Bearer $(Get-GitHubToken)",
            '-H', 'X-GitHub-Api-Version: 2022-11-28'
        )
    }
    if ($cookies) {
        $headers += @('-b', (cookie_header $cookies))
    }
    get_config PRIVATE_HOSTS | Where-Object { $_ -ne $null -and $downloadUrl -match $_.match } | ForEach-Object {
        (ConvertFrom-StringData -StringData $_.Headers).GetEnumerator() | ForEach-Object {
            $headers += @('-H', "$($_.Key): $($_.Value)")
        }
    }

    $displayName = try { url_remote_filename $url } catch { Split-Path -Leaf $downloadUrl }
    $showProgress = [bool]$progress
    # Interactive mode parses curl's native stderr progress meter to render a custom progress bar
    $progArg = if ($showProgress) { @() } else { @('-sS') }
    # Pass --noproxy * explicitly when direct so env HTTP_PROXY/HTTPS_PROXY does not hijack direct/whitelist downloads
    $proxyParams = if ($proxyArg) { @('-x', $proxyArg) } else { @('--noproxy', '*') }
    $commonCurlArgs = @(
        '-f', '-L',
        '--connect-timeout', '15',
        '--retry', '2',
        '--retry-delay', '1',
        '--retry-connrefused'
    ) + $proxyParams + $headers + $progArg + @('-o', $to, $reqUrl)

    # 解析并执行下载引擎流水线：Level 1 (curl-impersonate) -> Level 2 (系统 curl.exe)
    $engines = @(
        @{
            Name              = 'curl-impersonate'
            DefaultPath       = "$PSScriptRoot\bin\curl-impersonate.exe"
            CommandName       = 'curl-impersonate'
            PrefixArgs        = @('--impersonate', 'chrome131')
            FallbackExtraArgs = @('--http1.1')
            MaxAttempts       = 5
            FailSuffix        = ', falling back to system curl.exe...'
        },
        @{
            Name              = 'system curl.exe'
            DefaultPath       = 'C:\Windows\System32\curl.exe'
            CommandName       = 'curl.exe'
            PrefixArgs        = @('-A', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36')
            FallbackExtraArgs = @()
            MaxAttempts       = 3
            FailSuffix        = '.'
        }
    )

    foreach ($engine in $engines) {
        $exePath = $engine.DefaultPath
        if (!(Test-Path $exePath)) {
            $cmdCheck = Get-Command $engine.CommandName -ErrorAction SilentlyContinue
            $exePath = if ($cmdCheck) { $cmdCheck.Source } else { $null }
        }
        if (-not ($exePath -and (Test-Path $exePath))) { continue }
        $status = @{ ExitCode = 0 }
        $fullArgs = $engine.PrefixArgs + $commonCurlArgs
        if (Invoke-CurlTransfer -ExePath $exePath -EngineName $engine.Name -BaseArgs $fullArgs -FallbackExtraArgs $engine.FallbackExtraArgs -To $to -DisplayName $displayName -ShowProgress $showProgress -MaxAttempts $engine.MaxAttempts -Status $status) {
            return
        }
        warn "$($engine.Name) download failed (exit code $($status.ExitCode))$($engine.FailSuffix)"
    }

    # =========================================================================
    # Level 3: 降级回退至自建加速代理镜像节点 (cfproxy.1122330.xyz)
    # =========================================================================
    if (!$NoProxy -and !$isAccelerated) {
        $fallbackUrl = uProxy($downloadUrl)
        warn "Direct/proxy download failed, automatically retrying via accelerator proxy: $fallbackUrl"
        Custom-Invoke-Download $fallbackUrl $to $cookies $progress -NoProxy
        return
    }

    # =========================================================================
    # Level 4 (终极保底): 原版 .NET WebRequest (64KB 增强缓冲区)
    # =========================================================================
    warn "All curl engines failed, falling back to .NET WebRequest..."
    Custom-Invoke-WebDownload $reqUrl $to $cookies $progress -NoProxy:$NoProxy
}

function Custom-Invoke-WebDownload ($url, $to, $cookies, $progress, [switch] $NoProxy) {
    $downloadUrl = ($url -split '#')[0]
    $reqUrl = if ($NoProxy) { $downloadUrl } else { Url_Proxy($downloadUrl) }
    $wreq = [Net.WebRequest]::Create($reqUrl)
    $bypassProxy = $NoProxy -or ($reqUrl -match "1122330\.xyz")
    if (!$bypassProxy -and $reqUrl -match "^https?://([^/]+)") {
        $bypassProxy = Test-ChinaWhitelistedHost $matches[1]
    }
    if ($bypassProxy) {
        $wreq.Proxy = $null
    }
    if ($wreq -is [Net.HttpWebRequest]) {
        $wreq.UserAgent = Get-UserAgent
        if (-not ($downloadUrl -match 'sourceforge\.net' -or $downloadUrl -match 'portableapps\.com')) {
            $wreq.Referer = strip_filename $downloadUrl
        }
        if ($downloadUrl -match '^https://api\.github\.com/repos') {
            $wreq.Accept = 'application/octet-stream'
            $wreq.Headers['Authorization'] = "Bearer $(Get-GitHubToken)"
            $wreq.Headers['X-GitHub-Api-Version'] = '2022-11-28'
        }
        if ($cookies) {
            $wreq.Headers.Add('Cookie', (cookie_header $cookies))
        }

        get_config PRIVATE_HOSTS | Where-Object { $_ -ne $null -and $downloadUrl -match $_.match } | ForEach-Object {
            (ConvertFrom-StringData -StringData $_.Headers).GetEnumerator() | ForEach-Object {
                $wreq.Headers[$_.Key] = $_.Value
            }
        }
    }

    try {
        $wres = $wreq.GetResponse()
    }
    catch [System.Net.WebException] {
        $exc = $_.Exception
        $handledCodes = @(
            [System.Net.HttpStatusCode]::MovedPermanently,
            [System.Net.HttpStatusCode]::Found,
            [System.Net.HttpStatusCode]::SeeOther,
            [System.Net.HttpStatusCode]::TemporaryRedirect
        )
        $redirectRes = $exc.Response
        if ($handledCodes -notcontains $redirectRes.StatusCode) {
            if (-not $NoProxy -and $reqUrl -ne $downloadUrl) {
                warn "Proxy download failed for $downloadUrl, retrying direct."
                Custom-Invoke-WebDownload $downloadUrl $to $cookies $progress -NoProxy
                return
            }
            if (-not $NoProxy -and $reqUrl -eq $downloadUrl -and $redirectRes.StatusCode -in @(504, 503)) {
                $fallbackUrl = uProxy($downloadUrl)
                warn "Direct connection returned $($redirectRes.StatusCode), retrying via accelerator proxy: $fallbackUrl"
                Custom-Invoke-WebDownload $fallbackUrl $to $cookies $progress -NoProxy
                return
            }
            throw $exc
        }

        if ((-not $redirectRes.Headers) -or ($redirectRes.Headers -notcontains 'Location')) {
            throw $exc
        }
        $newUrl = $redirectRes.Headers['Location']
        info "Following redirect to $newUrl..."
        if ($url -like '*#/*') {
            $null, $postfix = $url -split '#/'
            $newUrl = "$newUrl`#/$postfix"
        }
        Custom-Invoke-WebDownload $newUrl $to $cookies $progress -NoProxy:$NoProxy
        return
    }

    $total = $wres.ContentLength
    if ($total -eq -1 -and $wreq -is [net.ftpwebrequest]) {
        $total = ftp_file_size($url)
    }

    if ($progress -and ($total -gt 0)) {
        [console]::CursorVisible = $false
        function Trace-DownloadProgress ($read) {
            Write-DownloadProgress $read $total $url
        }
    } else {
        Write-Host "Downloading $url ($(filesize $total))..."
        function Trace-DownloadProgress {}
    }

    try {
        $s = $wres.getresponsestream()
        $fs = [io.file]::openwrite($to)
        $buffer = New-Object byte[] 65536
        $totalRead = 0
        $sw = [diagnostics.stopwatch]::StartNew()

        while (($read = $s.read($buffer, 0, $buffer.length)) -gt 0) {
            $fs.Write($buffer, 0, $read)
            $totalRead += $read
            if ($sw.ElapsedMilliseconds -gt 150) {
                $sw.Restart()
                Trace-DownloadProgress $totalRead
            }
        }
        $sw.Stop()
        Trace-DownloadProgress $totalRead
    } finally {
        if ($fs) { $fs.close() }
        if ($s) { $s.close() }
        if ($wres) { $wres.close() }
        if ($progress) { [console]::CursorVisible = $true; Write-Host }
    }
}
