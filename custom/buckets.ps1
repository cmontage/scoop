<#
    custom/buckets.ps1
    默认仓库自定为 official，支持 soup / third 等自建源，动态注入自建 buckets
#>

function Custom-Find-BucketDirectory {
    param(
        [string] $Name = 'official',
        [switch] $Root
    )

    # Handle info passing empty string as bucket ($install.bucket)
    if (($null -eq $Name) -or ($Name -eq '')) {
        $Name = 'official'
    }

    # 当 Sync-Bucket 执行远古 'main' bucket 转 git 检测时，如果本地没有安装 main 且安装了 official，
    # 将其重定向至 official，让 Test-Path .git 判定通过，彻底消除 "Converting 'main' bucket to git repo" 的报错
    $callers = (Get-PSCallStack).FunctionName
    if ($Name -eq 'main' -and $callers -contains 'Sync-Bucket' -and (Get-LocalBucket) -notcontains 'main') {
        $Name = 'official'
    }

    $bucket = "$bucketsdir\$Name"

    if ((Test-Path "$bucket\bucket") -and !$Root) {
        $bucket = "$bucket\bucket"
    }

    return $bucket
}

function check_main_bucket {
    if ((Get-LocalBucket) -contains 'official' -or (Get-LocalBucket) -contains 'main') {
        return $true
    }
    warn "Neither 'official' nor 'main' bucket is added."
    Write-Host "  run 'scoop bucket add official'"
    return $false
}

function Custom-Known-Bucket-Repos {
    $json = "$PSScriptRoot\..\buckets.json"
    $repos = $null
    if (Test-Path $json) {
        try {
            $repos = Get-Content $json -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        } catch {}
    }
    if ($null -eq $repos) {
        $repos = [PSCustomObject]@{}
    }

    # 优先注入自建源与镜像源，即使官方 buckets.json 更新也无需修改官方文件
    $customBuckets = [ordered]@{
        'official'     = 'https://gitee.com/cmontage/scoopbucket'
        'third'        = 'https://gitee.com/cmontage/scoopbucket-third'
        'soup'         = 'https://gitee.com/cmontage/scoopbucket-soup'
        'main'         = 'https://gitee.com/scoop-installer/Main'
        'extras'       = 'https://gitee.com/scoop-installer/Extras'
        'versions'     = 'https://gitee.com/scoop-installer/Versions'
        'nirsoft'      = 'https://gitee.com/scoop-installer/Nirsoft'
        'sysinternals' = 'https://gitee.com/scoop-installer/scoop-sysinternals'
        'php'          = 'https://gitee.com/scoop-installer/PHP'
        'nerd-fonts'   = 'https://gitee.com/scoop-installer/scoop-nerd-fonts'
        'nonportable'  = 'https://gitee.com/scoop-installer/Nonportable'
        'java'         = 'https://gitee.com/scoop-installer/Java'
        'games'        = 'https://gitee.com/scoop-installer/scoop-games'
    }

    foreach ($k in $customBuckets.Keys) {
        $repos | Add-Member -MemberType NoteProperty -Name $k -Value $customBuckets[$k] -Force
    }

    return $repos
}
