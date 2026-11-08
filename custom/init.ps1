<#
    custom/init.ps1
    Scoop 自定义扩展总入口
    负责加载所有自改模块并完成函数覆盖（确保自改优先）
#>

$customDir = $PSScriptRoot

# 1. 加载代理与网络加速模块
if (Test-Path "$customDir\proxy.ps1") {
    . "$customDir\proxy.ps1"
    # 强制覆盖官方下载函数，注入代理分流与 504 自动回退
    function script:Invoke-Download ($url, $to, $cookies, $progress) {
        Custom-Invoke-Download $url $to $cookies $progress
    }
    function global:Invoke-Download ($url, $to, $cookies, $progress) {
        Custom-Invoke-Download $url $to $cookies $progress
    }
    function Invoke-Download ($url, $to, $cookies, $progress) {
        Custom-Invoke-Download $url $to $cookies $progress
    }
}

# 2. 加载进程/服务运行检测与提权控制模块
if (Test-Path "$customDir\process.ps1") {
    . "$customDir\process.ps1"
    # 强制覆盖官方进程检测函数，注入交互式询问与管理员提权强制关闭
    function script:test_running_process ($app, $global) {
        Custom-Test-Running-Process $app $global
    }
    function global:test_running_process ($app, $global) {
        Custom-Test-Running-Process $app $global
    }
    function test_running_process ($app, $global) {
        Custom-Test-Running-Process $app $global
    }
}

# 3. 加载自定义 Buckets 模块
if (Test-Path "$customDir\buckets.ps1") {
    . "$customDir\buckets.ps1"
    # 强制覆盖官方默认 bucket 路径查找与自建源列表
    function script:Find-BucketDirectory {
        param([string] $Name = 'official', [switch] $Root)
        Custom-Find-BucketDirectory -Name $Name -Root:$Root
    }
    function global:Find-BucketDirectory {
        param([string] $Name = 'official', [switch] $Root)
        Custom-Find-BucketDirectory -Name $Name -Root:$Root
    }
    function Find-BucketDirectory {
        param([string] $Name = 'official', [switch] $Root)
        Custom-Find-BucketDirectory -Name $Name -Root:$Root
    }

    function script:known_bucket_repos {
        Custom-Known-Bucket-Repos
    }
    function global:known_bucket_repos {
        Custom-Known-Bucket-Repos
    }
    function known_bucket_repos {
        Custom-Known-Bucket-Repos
    }

    function script:check_main_bucket {
        Custom-Check-Main-Bucket
    }
    function global:check_main_bucket {
        Custom-Check-Main-Bucket
    }
    function check_main_bucket {
        Custom-Check-Main-Bucket
    }
}

# 4. 初始化默认 Scoop 仓库配置
if (Get-Command get_config -ErrorAction SilentlyContinue) {
    $configRepo = get_config SCOOP_REPO
    if (!$configRepo) {
        set_config SCOOP_REPO 'https://gitee.com/cmontage/scoop' | Out-Null
    }
}
