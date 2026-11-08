<#
    custom/proxy.ps1
    智能代理分流、国内白名单、物理 IP 地理位置检测及 504 自动回退加速
    底层采用内置 curl-impersonate (真实 Chrome BoringSSL 指纹) 与系统 curl.exe 高速引擎
#>

function Test-SystemProxy {
    try {
        $scoopProxy = get_config PROXY
        if ($scoopProxy -and $scoopProxy -ne 'none' -and $scoopProxy -ne 'default') {
            return $true
        }

        $proxy = [System.Net.WebRequest]::DefaultWebProxy
        if ($null -ne $proxy) {
            $testUri = [System.Uri]'http://example.com/'
            $proxyUri = $proxy.GetProxy($testUri)
            if ($null -ne $proxyUri -and $proxyUri -ne $testUri) {
                return $true
            }
        }

        $sysProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        if ($null -eq $sysProxy) {
            return $false
        }
        $testUri = [System.Uri]'http://example.com/'
        $proxyUri = $sysProxy.GetProxy($testUri)
        return ($null -ne $proxyUri -and $proxyUri -ne $testUri)
    } catch {
        return $false
    }
}

function Get-CurlProxy($url) {
    try {
        $scoopProxy = get_config PROXY
        if ($scoopProxy -and $scoopProxy -ne 'none' -and $scoopProxy -ne 'default') {
            if ($scoopProxy -notmatch '^https?://|^socks5://') {
                $scoopProxy = "http://$scoopProxy"
            }
            return $scoopProxy
        }

        $testUri = [System.Uri]$url
        $proxy = [System.Net.WebRequest]::DefaultWebProxy
        if ($null -ne $proxy) {
            $proxyUri = $proxy.GetProxy($testUri)
            if ($null -ne $proxyUri -and $proxyUri.AbsoluteUri -ne $testUri.AbsoluteUri) {
                return $proxyUri.AbsoluteUri
            }
        }

        $sysProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        if ($null -ne $sysProxy) {
            $proxyUri = $sysProxy.GetProxy($testUri)
            if ($null -ne $proxyUri -and $proxyUri.AbsoluteUri -ne $testUri.AbsoluteUri) {
                return $proxyUri.AbsoluteUri
            }
        }

        if ($env:ALL_PROXY) { return $env:ALL_PROXY }
        if ($env:HTTPS_PROXY -and $url -like 'https*') { return $env:HTTPS_PROXY }
        if ($env:HTTP_PROXY) { return $env:HTTP_PROXY }
    } catch {}

    return $null
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

        if (Test-SystemProxy) {
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
                        $ipInfoRaw = (curl.exe -s --connect-timeout 1 --max-time 2 "https://ip9.com.cn/get?ip=$ip") -join ''
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

function Custom-Invoke-Download ($url, $to, $cookies, $progress, [switch] $NoProxy) {
    $downloadUrl = ($url -split '#')[0]
    $reqUrl = if ($NoProxy) { $downloadUrl } else { Url_Proxy($downloadUrl) }
    $isAccelerated = ($reqUrl -match "1122330\.xyz")

    # 代理参数解析：如果为国内白名单或已走加速节点，直连下载；否则走代理
    $proxyArg = $null
    if (!$NoProxy -and !$isAccelerated) {
        $hostName = if ($downloadUrl -match "^https?://([^/]+)") { $matches[1] } else { $null }
        if (!(Test-ChinaWhitelistedHost $hostName)) {
            $proxyArg = Get-CurlProxy $downloadUrl
        }
    }

    # 确保目标文件夹存在
    $parent = Split-Path -Parent $to
    if ($parent -and !(Test-Path $parent)) {
        ensure $parent | Out-Null
    }
    # 清理残留的 0 字节损坏文件
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

    $progArg = if ($progress) { @('--progress-bar') } else { @('-sS') }
    $proxyParams = if ($proxyArg) { @('-x', $proxyArg) } else { @() }

    # =========================================================================
    # Level 1 (最高优先级): 内置 curl-impersonate (BoringSSL 真实 Chrome 131 指纹)
    # =========================================================================
    $binDir = "$PSScriptRoot\bin"
    $impersonateExe = "$binDir\curl-impersonate.exe"
    if (!(Test-Path $impersonateExe)) {
        $cmdCheck = Get-Command 'curl-impersonate' -ErrorAction SilentlyContinue
        if ($cmdCheck) { $impersonateExe = $cmdCheck.Source }
    }

    $impersonateSuccess = $false
    if (Test-Path $impersonateExe) {
        $impersonateArgs = @(
            '--impersonate', 'chrome131',
            '-f', '-L',
            '--connect-timeout', '15',
            '--retry', '2',
            '--retry-delay', '1',
            '--retry-connrefused'
        ) + $proxyParams + $headers + $progArg + @('-o', $to, $reqUrl)

        try {
            & $impersonateExe @impersonateArgs
            if ($LASTEXITCODE -eq 0 -and (Test-Path $to) -and (Get-Item $to).Length -gt 0) {
                $impersonateSuccess = $true
                return
            }
        } catch {
            warn "curl-impersonate execution exception: $_"
        }

        if (!$impersonateSuccess) {
            warn "curl-impersonate download failed (exit code $LASTEXITCODE), falling back to system curl.exe..."
            if ((Test-Path $to) -and (Get-Item $to).Length -eq 0) {
                Remove-Item -Force $to -ErrorAction SilentlyContinue
            }
        }
    }

    # =========================================================================
    # Level 2: 降级回退至 Windows 自带的 C:\Windows\System32\curl.exe (原生 HTTP/2)
    # =========================================================================
    $sysCurl = "C:\Windows\System32\curl.exe"
    if (!(Test-Path $sysCurl)) {
        $cmdCheck = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
        if ($cmdCheck) { $sysCurl = $cmdCheck.Source }
    }

    $sysCurlSuccess = $false
    if (Test-Path $sysCurl) {
        $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
        $sysCurlArgs = @(
            '-f', '-L',
            '-A', $ua,
            '--connect-timeout', '15',
            '--retry', '2',
            '--retry-delay', '1',
            '--retry-connrefused'
        ) + $proxyParams + $headers + $progArg + @('-o', $to, $reqUrl)

        try {
            & $sysCurl @sysCurlArgs
            if ($LASTEXITCODE -eq 0 -and (Test-Path $to) -and (Get-Item $to).Length -gt 0) {
                $sysCurlSuccess = $true
                return
            }
        } catch {
            warn "system curl.exe execution exception: $_"
        }

        if (!$sysCurlSuccess) {
            warn "system curl.exe download failed (exit code $LASTEXITCODE)."
            if ((Test-Path $to) -and (Get-Item $to).Length -eq 0) {
                Remove-Item -Force $to -ErrorAction SilentlyContinue
            }
        }
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
