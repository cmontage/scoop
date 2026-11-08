<#
    custom/process.ps1
    进程与服务运行检测、交互式停止及管理员权限提权强杀
#>

function Custom-Test-Running-Process($app, $global) {
    $processdir = appdir $app $global | Convert-Path
    $running_processes = Get-Process | Where-Object { $_.Path -like "$processdir\*" }
    $running_processes_str = $running_processes | Out-String

    if ($running_processes) {
        if (get_config 'IGNORE_RUNNING_PROCESSES') {
            warn "The following instances of `"$app`" are still running. Scoop is configured to ignore this condition."
            Write-Host $running_processes_str
            return $false
        }
        else {
            error "The following instances of `"$app`" are still running. Close them and try again."
            Write-Host $running_processes_str
            $answer = Read-Host 'Stop all processes for this program and continue? (y/n) [Default: y]'
            if ($answer -eq '' -or $answer -eq 'y' -or $answer -eq 'Y') {
                $stop_failed = $false
                try {
                    if (is_admin) {
                        $services = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.PathName -like "*$processdir*" -and $_.State -eq 'Running' }
                        if ($null -eq $services -and (Get-Command Get-WmiObject -ErrorAction SilentlyContinue)) {
                            $services = Get-WmiObject Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.PathName -like "*$processdir*" -and $_.State -eq 'Running' }
                        }
                        if ($services) {
                            $services | ForEach-Object {
                                Write-Host "Stopping service: $($_.DisplayName) ($($_.Name))..."
                                Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
                            }
                        }
                    }

                    $running_processes | ForEach-Object {
                        Write-Host "Stopping process: $($_.ProcessName) (PID: $($_.Id))..."
                        Stop-Process -Id $_.Id -Force -ErrorAction Stop
                    }
                }
                catch {
                    $stop_failed = $true
                    warn 'Stopping processes failed with current privileges. Trying as administrator...'
                }

                if ($stop_failed -and -not (is_admin)) {
                    $pids = @($running_processes | Where-Object { $_ -and $_.Id } | Select-Object -ExpandProperty Id -Unique)
                    if ($pids.Count -gt 0) {
                        $host_exe = (Get-Process -Id $PID).Path
                        $safe_dir = $processdir -replace "'", "''"
                        $svc_script = "`$services = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { `$_.PathName -like '*$safe_dir*' -and `$_.State -eq 'Running' }; if (`$null -eq `$services -and (Get-Command Get-WmiObject -ErrorAction SilentlyContinue)) { `$services = Get-WmiObject Win32_Service -ErrorAction SilentlyContinue | Where-Object { `$_.PathName -like '*$safe_dir*' -and `$_.State -eq 'Running' } }; if (`$services) { `$services | ForEach-Object { Stop-Service -Name `$_.Name -Force -ErrorAction SilentlyContinue } };"
                        $stop_script = "$ErrorActionPreference = 'Stop'; $svc_script Stop-Process -Id $($pids -join ',') -Force"
                        $elevated_ok = Invoke-ExternalCommand -FilePath $host_exe -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $stop_script) -Activity 'Retrying process stop as administrator...' -RunAs
                        if (!$elevated_ok) {
                            warn 'Stopping processes as administrator failed.'
                        }
                    }
                }

                # Wait briefly for processes to fully terminate
                Start-Sleep -Milliseconds 500
                # Verify all processes have stopped
                $still_running = Get-Process | Where-Object { $_.Path -like "$processdir\*" }
                if ($still_running) {
                    error 'Some processes could not be stopped. Please close them manually and try again.'
                    $still_running | Out-String | Write-Host
                    return $true
                }
                Write-Host 'All processes have been stopped.' -ForegroundColor Green
                return $false
            }
            else {
                return $true
            }
        }
    }
    else {
        return $false
    }
}
