<#
    custom/aria2.ps1
    Aria2 智能分流引擎与现代化进度条渲染器（不修改 aria2 本身）
    - 国内白名单 / 国内 IP 强制直连（剥离代理环境变量 + --no-proxy=*），绝不走代理
    - GitHub / 自建加速镜像 / SOCKS 代理自动分流至内置 curl-impersonate 浏览器指纹引擎
    - 其余海外源经 HTTP 代理多线程下载，遇 WAF/403/504 失败时无缝降级回退至 curl-impersonate
    - 统一复用 Write-CurlProgressLine 彩色进度条与连接数角标（如 16x）
#>

function Test-Aria2BypassHost([string] $HostName) {
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }
    if ($HostName -match '^(.*):\d+$') { $HostName = $matches[1] }

    # GitHub 302 临时鉴权直链并发 Range 易触发 403/504/重置；自建 cfproxy 不宜多连接并发
    $bypassPatterns = @(
        '(^|\.)github\.com$',
        '(^|\.)githubusercontent\.com$',
        '(^|\.)githubassets\.com$',
        '(^|\.)1122330\.xyz$'
    )
    foreach ($pattern in $bypassPatterns) {
        if ($HostName -match $pattern) {
            return $true
        }
    }
    return $false
}

function ConvertFrom-Aria2Size([string] $Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0.0 }
    if ($Text.Trim() -match '^([0-9]+(?:\.[0-9]+)?)\s*([kKmMgGtT]i?)?[bB]?$') {
        $val = [double]$matches[1]
        $unit = if ($matches[2]) { $matches[2].ToLower() } else { '' }
        switch ($unit) {
            'k'  { return $val * 1024 }
            'ki' { return $val * 1024 }
            'm'  { return $val * 1048576 }
            'mi' { return $val * 1048576 }
            'g'  { return $val * 1073741824 }
            'gi' { return $val * 1073741824 }
            't'  { return $val * 1099511627776 }
            'ti' { return $val * 1099511627776 }
            default { return $val }
        }
    }
    return 0.0
}

function ConvertFrom-Aria2Eta([string] $Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '--:--' }
    $sec = 0.0
    if ($Text -match '(\d+)d') { $sec += [double]$matches[1] * 86400 }
    if ($Text -match '(\d+)h') { $sec += [double]$matches[1] * 3600 }
    if ($Text -match '(\d+)m') { $sec += [double]$matches[1] * 60 }
    if ($Text -match '(\d+)s') { $sec += [double]$matches[1] }
    if ($sec -gt 0) {
        return Format-Duration $sec
    }
    return '--:--'
}

function Invoke-Aria2Transfer {
    param(
        [string]   $ExePath,
        [string[]] $Aria2Args,
        [string]   $TargetPath,
        [string]   $DisplayName = '',
        [bool]     $ShowProgress = $false,
        [bool]     $BypassProxyEnv = $false,
        [hashtable] $Status = @{}
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = Split-Path -Leaf $TargetPath
    }

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
    $connCount = 0
    $peakConn = 0
    $lastCode = -1
    $cursorHidden = $false

    try {
        if ($ShowProgress) {
            try {
                [Console]::CursorVisible = $false
                $cursorHidden = $true
            } catch {}
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ExePath
        $psi.Arguments = (($Aria2Args | ForEach-Object { Format-Win32Arg $_ }) -join ' ')
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        # 直连模式彻底清除子进程代理环境变量，确保 aria2c 绝不回落到系统 HTTP_PROXY/HTTPS_PROXY
        if ($BypassProxyEnv) {
            foreach ($envKey in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy')) {
                if ($psi.EnvironmentVariables.ContainsKey($envKey)) {
                    $psi.EnvironmentVariables.Remove($envKey)
                }
            }
        }

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()

        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $outTask = $proc.StandardOutput.ReadLineAsync()

        while ($true) {
            $gotLine = $false
            try {
                $gotLine = $outTask.Wait(80)
            } catch {
                break
            }

            if ($gotLine) {
                $line = $null
                try { $line = $outTask.Result } catch { break }
                if ($null -eq $line) { break }

                $trimmed = $line.Trim()
                if ($trimmed -match '^\[#[0-9a-fA-F]+\s+([0-9.]+[a-zA-Z]*)/([0-9.]+[a-zA-Z]*)(?:\((\d+)%\))?(?:\s+CN:(\d+))?(?:\s+DL:([0-9.]+[a-zA-Z]*))?(?:\s+ETA:([^\]]+))?.*\]$') {
                    $parsedDone  = ConvertFrom-Aria2Size $matches[1]
                    $parsedTotal = ConvertFrom-Aria2Size $matches[2]
                    if ($parsedTotal -gt 0) { $totalBytes = $parsedTotal }
                    if ($parsedDone -gt 0)  { $recvBytes = $parsedDone }

                    if ($matches[4]) {
                        $connCount = [int]$matches[4]
                        if ($connCount -gt $peakConn) { $peakConn = $connCount }
                    }

                    if ($matches[5]) {
                        $speedBytes = ConvertFrom-Aria2Size $matches[5]
                    }

                    if ($totalBytes -gt 0 -and $speedBytes -gt 0) {
                        $etaText = Format-Duration ([math]::Max(0.0, ($totalBytes - $recvBytes) / $speedBytes))
                    } elseif ($matches[6]) {
                        $etaText = ConvertFrom-Aria2Eta $matches[6]
                    }
                } elseif ($trimmed -match '\[ERROR\]|Exception:|errorCode=') {
                    $safeErr = $trimmed -replace '(?i)(Cookie:\s*)[^\r\n]+', '$1***' -replace '(?i)(passwd=)[^\s&]+', '$1***'
                    if ($errLines.Count -lt 6) {
                        [void]$errLines.Add($safeErr)
                    }
                }

                $outTask = $proc.StandardOutput.ReadLineAsync()
            }

            if ($ShowProgress -and (($sw.ElapsedMilliseconds - $lastDrawMs) -ge 80)) {
                $liveTag = if ($connCount -gt 0) { "${connCount}x" } else { 'aria2' }
                $liveEta = if ($totalBytes -gt 0 -and $speedBytes -gt 0) {
                    Format-Duration ([math]::Max(0.0, ($totalBytes - $recvBytes) / $speedBytes))
                } else {
                    $etaText
                }
                Write-CurlProgressLine -DisplayName $DisplayName -DoneBytes $recvBytes -TotalBytes $totalBytes -SpeedBytes $speedBytes -EtaText $liveEta -ElapsedSec $sw.Elapsed.TotalSeconds -SpinnerIdx $spinIdx -Tag $liveTag
                $spinIdx++
                $lastDrawMs = $sw.ElapsedMilliseconds
            }
        }

        $proc.WaitForExit()
        $lastCode = $proc.ExitCode
        $sw.Stop()

        try {
            if ($stderrTask.Wait(500)) {
                $stderrText = $stderrTask.Result
                if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
                    foreach ($sLine in ($stderrText -split "`r?`n")) {
                        $st = $sLine.Trim()
                        if (-not [string]::IsNullOrWhiteSpace($st) -and $errLines.Count -lt 6) {
                            $safeErr = $st -replace '(?i)(Cookie:\s*)[^\r\n]+', '$1***' -replace '(?i)(passwd=)[^\s&]+', '$1***'
                            [void]$errLines.Add($safeErr)
                        }
                    }
                }
            }
        } catch {}

        if ($lastCode -eq 0 -and (Test-Path $TargetPath) -and (Get-Item $TargetPath).Length -gt 0) {
            $finalBytes = [double](Get-Item $TargetPath).Length
            $elapsedSec = [math]::Max($sw.Elapsed.TotalSeconds, 0.01)
            $avgSpeed = $finalBytes / $elapsedSec
            $doneTag = if ($peakConn -gt 0) { "${peakConn}x" } else { 'aria2' }
            if ($ShowProgress) {
                Write-CurlProgressLine -DisplayName $DisplayName -DoneBytes $finalBytes -TotalBytes $finalBytes -SpeedBytes $avgSpeed -EtaText '00:00' -ElapsedSec $sw.Elapsed.TotalSeconds -Tag $doneTag -Completed
            }
            $Status.ExitCode = 0
            return $true
        }

        if ($ShowProgress) {
            [Console]::Write("`r$esc[K")
        }
        foreach ($errLine in ($errLines | Select-Object -First 3)) {
            Write-Host $errLine -ForegroundColor DarkRed
        }
    } catch {
        if ($ShowProgress) {
            [Console]::Write("`r$esc[K")
        }
        warn "aria2 execution exception: $_"
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

    $Status.ExitCode = $lastCode
    return $false
}

function Invoke-CustomCurlFallbackDownload {
    param(
        [string] $Url,
        [string] $Destination,
        $Cookies,
        [bool]   $ShowProgress,
        [switch] $NoProxy,
        [switch] $SkipUrlProxy
    )

    $tempPath = "$Destination.download"
    if (Test-Path $tempPath) {
        Remove-Item -Force $tempPath -ErrorAction SilentlyContinue
    }

    try {
        Custom-Invoke-Download $Url $tempPath $Cookies $ShowProgress -NoProxy:$NoProxy -SkipUrlProxy:$SkipUrlProxy
        if (-not (Test-Path $tempPath) -or (Get-Item $tempPath).Length -le 0) {
            throw "Downloaded file is missing or empty: $tempPath"
        }
        Move-Item $tempPath $Destination -Force
    } catch {
        if (Test-Path $tempPath) {
            Remove-Item -Force $tempPath -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Custom-Invoke-CachedAria2Download ($app, $version, $manifest, $architecture, $dir, $cookies = $null, $use_cache = $true, $check_hash = $true) {
    $data = @{}
    $urls = @(url $manifest $architecture)
    $aria2Exe = Get-HelperPath -Helper Aria2
    $showProgress = ([Console]::IsOutputRedirected -eq $false) -and ($host.Name -ne 'Windows PowerShell ISE Host')
    $chromeUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'

    foreach ($url in $urls) {
        $source = cache_path $app $version $url
        $target = Join-Path $dir (url_filename $url)
        $cachename = fname $source
        $displayName = try { url_remote_filename $url } catch { url_filename $url }

        $data.$url = @{
            'target'    = $target
            'cachename' = $cachename
            'source'    = $source
        }

        if ((Test-Path $source) -and -not (Test-Path "$source.aria2") -and $use_cache) {
            Write-Host "Loading $([char]0x1b)[36m$(url_remote_filename $url)$([char]0x1b)[0m from cache."
        } else {
            ensure $cachedir | Out-Null

            $try_url = $url
            try {
                $try_url = handle_special_urls $url
            } catch {
                if ($_.Exception.Response.StatusCode -eq 'Unauthorized') {
                    warn 'Token might be misconfigured.'
                }
            }

            $downloadUrl = ($try_url -split '#')[0]
            $hostName = if ($downloadUrl -match '^https?://([^/]+)') { $matches[1] } else { $null }
            $isHttp = ($downloadUrl -match '^https?://')
            $hasAria2 = ($aria2Exe -and (Test-Path $aria2Exe))

            # 1) GitHub / 自建代理域名 / 非 HTTP(S) / 无 aria2c -> 直接交给内置 curl-impersonate 引擎
            if (-not $hasAria2 -or -not $isHttp -or (Test-Aria2BypassHost $hostName)) {
                Remove-Item "$source.aria2*" -Force -ErrorAction SilentlyContinue
                try {
                    Invoke-CustomCurlFallbackDownload -Url $try_url -Destination $source -Cookies $cookies -ShowProgress $showProgress
                } catch {
                    Write-Host $_ -ForegroundColor DarkRed
                    error "URL $url is not valid"
                    abort $(new_issue_msg $app $bucket 'download failed')
                }
            } else {
                # 2) 调用智能路由（仅解析并打印一次分流日志）
                $reqUrl = Url_Proxy($downloadUrl)
                $isAccelerated = ($reqUrl -match '1122330\.xyz')

                if ($isAccelerated) {
                    # 无系统代理时经 cfproxy 加速，避免 16 并发冲击 Worker，直接走 curl-impersonate
                    Remove-Item "$source.aria2*" -Force -ErrorAction SilentlyContinue
                    try {
                        Invoke-CustomCurlFallbackDownload -Url $reqUrl -Destination $source -Cookies $cookies -ShowProgress $showProgress -NoProxy
                    } catch {
                        Write-Host $_ -ForegroundColor DarkRed
                        error "URL $url is not valid"
                        abort $(new_issue_msg $app $bucket 'download failed')
                    }
                } else {
                    # 3) 仅对非国内白名单域名解析系统代理；国内白名单或纯国内 IP 强制直连
                    $proxyArg = $null
                    if (-not (Test-ChinaWhitelistedHost $hostName)) {
                        $proxyArg = Get-CurlProxy $downloadUrl
                    }

                    # aria2c 不支持 SOCKS4/SOCKS5 代理，自动交由 curl-impersonate 处理
                    if ($proxyArg -and $proxyArg -match '^socks') {
                        Remove-Item "$source.aria2*" -Force -ErrorAction SilentlyContinue
                        try {
                            Invoke-CustomCurlFallbackDownload -Url $try_url -Destination $source -Cookies $cookies -ShowProgress $showProgress -SkipUrlProxy
                        } catch {
                            Write-Host $_ -ForegroundColor DarkRed
                            error "URL $url is not valid"
                            abort $(new_issue_msg $app $bucket 'download failed')
                        }
                    } else {
                        $aria2Args = @(
                            '--no-conf=true',
                            '--allow-overwrite=true',
                            '--auto-file-renaming=false',
                            '--file-allocation=none',
                            "--user-agent=$chromeUA",
                            "--retry-wait=$(get_config 'aria2-retry-wait' 2)",
                            '--max-tries=3',
                            '--connect-timeout=15',
                            '--timeout=30',
                            "--split=$(get_config 'aria2-split' 5)",
                            "--max-connection-per-server=$(get_config 'aria2-max-connection-per-server' 5)",
                            "--min-split-size=$(get_config 'aria2-min-split-size' '5M')",
                            '--console-log-level=warn',
                            '--enable-color=false',
                            '--summary-interval=0',
                            '--show-console-readout=true',
                            '--truncate-console-readout=false',
                            '--human-readable=false',
                            '--follow-metalink=true',
                            '--metalink-preferred-protocol=https',
                            '--min-tls-version=TLSv1.2',
                            "--stop-with-process=$PID",
                            '--continue=true',
                            '--auto-save-interval=1'
                        )

                        if ($proxyArg) {
                            $aria2Args += "--all-proxy=$proxyArg"
                            try {
                                $cred = [Net.WebRequest]::DefaultWebProxy.Credentials
                                if ($cred -and $cred.UserName) {
                                    $aria2Args += "--all-proxy-user=$($cred.UserName)"
                                }
                                if ($cred -and $cred.Password) {
                                    $aria2Args += "--all-proxy-passwd=$($cred.Password)"
                                }
                            } catch {}
                        } else {
                            $aria2Args += '--no-proxy=*'
                        }

                        if (-not ($downloadUrl -match 'sourceforge\.net' -or $downloadUrl -match 'portableapps\.com')) {
                            $ref = strip_filename $downloadUrl
                            if ($ref) {
                                $aria2Args += "--referer=$ref"
                            }
                        }

                        if ($cookies) {
                            $aria2Args += "--header=Cookie: $(cookie_header $cookies)"
                        }

                        get_config PRIVATE_HOSTS | Where-Object { $_ -ne $null -and $downloadUrl -match $_.match } | ForEach-Object {
                            (ConvertFrom-StringData -StringData $_.Headers).GetEnumerator() | ForEach-Object {
                                $aria2Args += "--header=$($_.Key): $($_.Value)"
                            }
                        }

                        $more_options = get_config 'aria2-options'
                        if ($more_options) {
                            foreach ($opt in @($more_options)) {
                                if (-not [string]::IsNullOrWhiteSpace($opt)) {
                                    $aria2Args += [string]$opt
                                }
                            }
                        }

                        $aria2Args += @(
                            "--dir=$cachedir",
                            "--out=$cachename",
                            $reqUrl
                        )

                        $status = @{ ExitCode = 0 }
                        $okAria2 = Invoke-Aria2Transfer -ExePath $aria2Exe -Aria2Args $aria2Args -TargetPath $source -DisplayName $displayName -ShowProgress $showProgress -BypassProxyEnv ($null -eq $proxyArg) -Status $status

                        if (-not $okAria2) {
                            if (-not (get_config ARIA2-FALLBACK-ENABLED $true)) {
                                error "Download failed! (Error $($status.ExitCode)) $(aria_exit_code $status.ExitCode)"
                                abort $(new_issue_msg $app $bucket 'download via aria2 failed')
                            }

                            warn "aria2 download failed (Error $($status.ExitCode): $(aria_exit_code $status.ExitCode)), falling back to curl-impersonate..."
                            Remove-Item "$source.aria2*" -Force -ErrorAction SilentlyContinue
                            if (Test-Path $source) {
                                Remove-Item $source -Force -ErrorAction SilentlyContinue
                            }

                            try {
                                Invoke-CustomCurlFallbackDownload -Url $try_url -Destination $source -Cookies $cookies -ShowProgress $showProgress -SkipUrlProxy
                            } catch {
                                Write-Host $_ -ForegroundColor DarkRed
                                error "URL $url is not valid"
                                abort $(new_issue_msg $app $bucket 'download failed')
                            }
                        } else {
                            Remove-Item "$source.aria2*" -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
        }

        # Metalink 处理（与官方保持一致）
        $metalink_filename = get_filename_from_metalink $source
        if ($metalink_filename) {
            Remove-Item $source -Force
            Rename-Item -Force (Join-Path -Path $cachedir -ChildPath $metalink_filename) $source
        }

        # 哈希校验（保持 $url 变量名以兼容官方 check_hash 的动态作用域引用）
        if ($check_hash) {
            $manifest_hash = hash_for_url $manifest $url $architecture
            $ok, $err = check_hash $source $manifest_hash $(show_app $app $bucket)
            if (!$ok) {
                error $err
                if (Test-Path $source) {
                    Remove-Item $source -Force -ErrorAction SilentlyContinue
                    Remove-Item "$source.aria2*" -Force -ErrorAction SilentlyContinue
                }
                if ($url.Contains('sourceforge.net')) {
                    Write-Host -ForegroundColor Yellow 'SourceForge.net is known for causing hash validation fails. Please try again before opening a ticket.'
                }
                abort $(new_issue_msg $app $bucket 'hash check failed')
            }
        }

        # 复制或移动到目标安装目录
        if (!(Test-Path $source)) {
            abort $(new_issue_msg $app $bucket 'cached file not found')
        }

        if (!($dir -eq $cachedir)) {
            if ($use_cache) {
                Copy-Item $source $target
            } else {
                Move-Item $source $target -Force
            }
        }
    }
}
