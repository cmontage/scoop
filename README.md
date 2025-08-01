<h1 align="center">Scoop</h1>

<!--<img src="scoop.png" alt="Long live Scoop!"/>-->
<p align="center">
        <a href="https://github.com/ScoopInstaller/Scoop#what-does-scoop-do">Features</a>
        |
        <a href="https://github.com/ScoopInstaller/Scoop#installation">Installation</a>
        |
        <a href="https://github.com/ScoopInstaller/Scoop/wiki">Documentation</a>
</p>

---

<!-- <p align="center">
    <a href="https://github.com/ScoopInstaller/Scoop">
        <img src="https://img.shields.io/github/languages/code-size/ScoopInstaller/Scoop.svg" alt="Code Size" />
    </a>
    <a href="https://github.com/ScoopInstaller/Scoop">
        <img src="https://img.shields.io/github/repo-size/ScoopInstaller/Scoop.svg" alt="Repository size" />
    </a>
    <a href="https://github.com/ScoopInstaller/Scoop/actions/workflows/ci.yml">
        <img src="https://github.com/ScoopInstaller/Scoop/actions/workflows/ci.yml/badge.svg" alt="Scoop Core CI Tests" />
    </a>
    <a href="https://discord.gg/s9yRQHt">
        <img src="https://img.shields.io/badge/chat-on%20discord-7289DA.svg" alt="Discord Chat" />
    </a>
    <a href="https://gitter.im/lukesampson/scoop">
        <img src="https://badges.gitter.im/lukesampson/scoop.png" alt="Gitter Chat" />
    </a>
    <a href="./LICENSE">
        <img src="https://img.shields.io/badge/license-UNLICENSE%20or%20MIT-blue" alt="License" />
    </a>
</p> -->

该 Scoop 基于 [官方Scoop](https://github.com/ScoopInstaller/Scoop) 修改. 

## 修改的内容

- 自动代理加速国外应用资源下载链接。
- 移除官方 main 桶，将我自建的官方集合 [official](https://github.com/cmontage/scoopbucket) 作为默认的 Bucket，并且移除默认 Bucket 是否存在的检测机制。
- 内置 Bucket 添加 [official](https://github.com/cmontage/scoopbucket) 、[third](https://github.com/cmontage/scoopbucket-third) 。

## 如何使用？

### 推荐安装方式

```powershell
# 设置 PowerShell 执行策略（非管理员启动）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 下载安装脚本到本地
irm https://gitee.com/cmontage/scoop/raw/main/install.ps1 -outfile 'install.ps1'

# 自定义 Scoop 安装目录，以下是我的路径例子，你可以自己根据情况修改
# 可以不设全局文件夹ScoopGlobalDir，全局文件夹里的应用需要管理员权限
.\install.ps1 -ScoopDir 'D:\Apps\Scoop\ScoopApps' -ScoopGlobalDir 'D:\Apps\Scoop\ScoopApps-G' -NoProxy

# 下载 7zip git，因为我们之后如果要添加别的 Bucket，必须有 git、7zip
scoop install 7zip git
```

### 官方安装方式

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
```

**Note**: 它会将 Scoop 安装到其默认位置：`C:\Users\<YOUR USERNAME>\scoop`

您可以在 [ScoopInstaller/Install](https://github.com/ScoopInstaller/Install) 中找到有关安装程序的完整文档，包括高级安装配置。如果您对安装有任何疑问，请在那里创建新问题。

## 常用命令
```powershell
scoop update                     # 更新 scoop 及软件包列表
scoop update *                   # 更新 app 目录所有应用
scoop status                     # 检查哪些软件有更新
scoop bucket list                # 列出所有已安装的 bucket
scoop bucket add <name>          # 添加已知的内置 bucket
scoop bucket add <name> <url>    # 添加第三方 bucket
scoop bucket rm <name>           # 删除 bucket
scoop cleanup *                  # 清理所有已安装的旧版本软件
scoop cache rm *                 # 清除下载缓存

scoop search <app>               # 搜索应用
scoop-search <app>               # 高效率搜索应用，需要安装 scoop-search
scoop install <app>              # 非全局安装应用
scoop install <app> -g           # 全局安装应用 (需要管理员权限/添加前缀sudo)
scoop uninstall <app>            # 非全局卸载应用
scoop uninstall <app> -g         # 全局卸载应用 (需要管理员权限/添加前缀sudo)

```