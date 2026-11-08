<#
    custom/proxy.ps1
    智能代理分流、国内白名单、物理 IP 地理位置检测及 504 自动回退加速
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
            # Strip port
            if ($hostName -match "^(.*):\d+$") {
                $hostName = $matches[1]
            }

            # Domain whitelist: directly return for whitelisted services
            $chinaWhitelist = @(
                'douyin\.com', 'dy\.com', 'dycdn\.com',  # TikTok/抖音
                'quarkcdn\.com', 'quark\.cn',            # Quark/夸克
                'tencent\.com', 'qq\.com', 'qzone\.qq\.com',  # Tencent/腾讯
                'alibaba\.com', 'aliyun\.com', 'taobao\.com', 'tmall\.com',  # Alibaba/阿里
                'baidu\.com', 'baiducdn\.com', 'baidupcs\.com', # Baidu/百度
                'netease\.com', '163\.com', '126\.com', '126\.net', # NetEase/网易
                'jd\.com', 'jingdong\.com',              # JD/京东
                'bilibili\.com', 'bilicdn\.com', 'hdslb\.com',  # Bilibili/B站
                'youku\.com', 'tudou\.com',              # Youku/优酷
                'weibo\.com', 'sina\.com\.cn',           # Weibo/微博
                'zhihu\.com',                            # Zhihu/知乎
                'feishucdn\.com', 'feishu\.cn',          # Feishu/飞书
                'gitcode\.net', 'gitee\.io',             # Chinese Git platforms
                'mozilla\.org',                          # Mozilla
                'visualstudio\.com',                     # Visual Studio
                '\.cn$', '\.com\.cn$', 'net\.cn'         # All .cn domains
            )
            $isDomainWhitelisted = $false
            foreach ($pattern in $chinaWhitelist) {
                if ($hostName -match $pattern) {
                    $isDomainWhitelisted = $true
                    break
                }
            }
            if ($isDomainWhitelisted) {
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
                # Check for IP literal
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
                    # Filter internal or fake-IP ranges
                    if ($ip -match "^(127\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|100\.64\.|198\.1[89]\.)") {
                        success "direct: $url (internal/fake: $ip)"
                        return $url
                    }

                    # Determine physical location via geolocation APIs
                    $isChina = $null

                    # Primary: IP9 geolocation API
                    try {
                        $ipInfoRaw = (curl.exe -s --connect-timeout 1 --max-time 2 "https://ip9.com.cn/get?ip=$ip") -join ''
                        $ipInfo = $ipInfoRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($ipInfo -and $ipInfo.ret -eq 200 -and $ipInfo.data -and $ipInfo.data.country_code) {
                            $isChina = ($ipInfo.data.country_code -eq "cn")
                        }
                    } catch {}

                    if ($null -eq $isChina) {
                        # Secondary: PConline API
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
                        # Confirmed foreign IP, use proxy
                        return uProxy($url)
                    }
                    # All APIs failed, default to proxy
                    info "geo-lookup failed for $ip, using proxy: $url"
                    return uProxy($url)
                }
            }
            # DNS resolution failed, use proxy
            warn "dns resolution failed for $hostName, using proxy: $url"
            return uProxy($url)
        }
    } catch {
        # Catch-all fallback to proxy
        warn "exception in Url_Proxy, using proxy: $_"
        return uProxy($url)
    }
    # Final fallback to proxy
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
            [System.Net.HttpStatusCode]::MovedPermanently, # HTTP 301
            [System.Net.HttpStatusCode]::Found,            # HTTP 302
            [System.Net.HttpStatusCode]::SeeOther,         # HTTP 303
            [System.Net.HttpStatusCode]::TemporaryRedirect # HTTP 307
        )

        # Only handle redirection codes
        $redirectRes = $exc.Response
        if ($handledCodes -notcontains $redirectRes.StatusCode) {
            # Proxy failed, retry direct
            if (-not $NoProxy -and $reqUrl -ne $downloadUrl) {
                warn "Proxy download failed for $downloadUrl, retrying direct."
                Custom-Invoke-Download $downloadUrl $to $cookies $progress -NoProxy
                return
            }
            # Direct connection returned 504 / 503 (e.g. GitHub WAF rate-limiting proxy IP), fallback to accelerator proxy
            if (-not $NoProxy -and $reqUrl -eq $downloadUrl -and $redirectRes.StatusCode -in @(504, 503)) {
                $fallbackUrl = uProxy($downloadUrl)
                warn "Direct connection returned $($redirectRes.StatusCode), automatically retrying via accelerator proxy: $fallbackUrl"
                Custom-Invoke-Download $fallbackUrl $to $cookies $progress -NoProxy
                return
            }
            throw $exc
        }

        # Get the new location of the file
        if ((-not $redirectRes.Headers) -or ($redirectRes.Headers -notcontains 'Location')) {
            throw $exc
        }

        $newUrl = $redirectRes.Headers['Location']
        info "Following redirect to $newUrl..."

        # Handle manual file rename
        if ($url -like '*#/*') {
            $null, $postfix = $url -split '#/'
            $newUrl = "$newUrl`#/$postfix"
        }

        Custom-Invoke-Download $newUrl $to $cookies $progress -NoProxy:$NoProxy
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
        function Trace-DownloadProgress {
            #no op
        }
    }

    try {
        $s = $wres.getresponsestream()
        $fs = [io.file]::openwrite($to)
        $buffer = New-Object byte[] 2048
        $totalRead = 0

        while (($read = $s.read($buffer, 0, $buffer.length)) -gt 0) {
            $fs.Write($buffer, 0, $read)
            $totalRead += $read
            Trace-DownloadProgress $totalRead
        }
    } finally {
        if ($fs) { $fs.close() }
        if ($s) { $s.close() }
        if ($wres) { $wres.close() }
        if ($progress) { [console]::CursorVisible = $true }
    }
}
