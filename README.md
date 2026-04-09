<h1 align="center">Scoop</h1>

<p align="center"><img src="https://gcore.jsdelivr.net/gh/cmontage/scoopbucket@main/scoop.png" width="100" alt="Scoop Logo"></p>

<!--<img src="scoop.png" alt="Long live Scoop!"/>-->
<p align="center">
        <a href="https://github.com/ScoopInstaller/Scoop#what-does-scoop-do">Features</a>
        |
        <a href="https://github.com/ScoopInstaller/Scoop#installation">Installation</a>
        |
        <a href="https://github.com/ScoopInstaller/Scoop/wiki">Documentation</a>
</p>

---

<p align="center">
    <a href="https://github.com/cmontage/scoop">
        <img src="https://img.shields.io/github/languages/code-size/cmontage/scoop.svg" alt="Code Size" />
    </a>
    <a href="https://github.com/cmontage/scoop">
        <img src="https://img.shields.io/github/repo-size/cmontage/scoop.svg" alt="Repository size" />
    </a>
    <a href="./LICENSE">
        <img src="https://img.shields.io/badge/license-UNLICENSE%20or%20MIT-green" alt="License" />
    </a>
</p>

该 Scoop 基于 [官方 Scoop](https://github.com/ScoopInstaller/Scoop) 修改，针对**中国大陆网络环境**进行了深度优化，并新增了多项实用特性。

---

## 与官方 Scoop 的区别

### 🚀 智能代理加速

原版 Scoop 下载国外资源时经常因为网络问题失败或者速度极慢。本版本通过**基于 IP 地理位置的智能代理**自动加速下载：

- **基于真实 IP 判断**：通过阿里云 DNS（`223.5.5.5`）解析域名的真实 IP 地址，再通过国内 IP 归属地查询（太平洋电脑网 whois）判断服务器物理位置。
- **自动路由**：
  - 国内 IP → **直连下载**（无需代理，保证速度）
  - 国外 IP → **自动走 Cloudflare 代理加速**
  - 内网 / Fake-IP 地址 → **自动直连**（兼容本地代理环境如 Clash 等）
- **自定义白名单**：自建域名自动跳过代理。
- **可配置代理地址**：通过 `scoop config URL_PROXY <url>` 自定义代理服务器。

> 相比原版手动配置代理或完全无加速的方式，本方案免维护、零配置，开箱即用。

### 🔄 自动停止运行中的进程

原版 Scoop 在更新/卸载应用时，如果检测到应用进程仍在运行，会直接报错并中止操作，需要用户手动关闭进程后重试。

该版本改进了这一流程：

- **交互式提示**：检测到运行中的进程时，提示用户 `Stop all processes for this program and continue? (y/n)`，回车默认 `y`。
- **自动停止进程**：选择 `y` 后自动停止所有相关进程。
- **自动提权重试**：如果当前权限不足以停止进程（如全局安装的应用），自动以管理员权限重试停止。
- **完整性验证**：停止后自动验证进程是否全部退出，确保更新流程安全。
- **可配置跳过**：通过 `scoop config IGNORE_RUNNING_PROCESSES true` 配置忽略运行中进程的检测，直接覆盖更新。

### 📦 自定义 Bucket（软件源）体系

| 对比项 | 官方 Scoop | 本版本 |
|--------|-----------|--------|
| 默认 Bucket | `main`（GitHub 托管） | `official`（Gitee 镜像，自建聚合桶） |
| Bucket 仓库源 | GitHub | **Gitee 镜像**（国内访问快） |
| 默认 Bucket 检测 | 检测 `main` 桶是否存在 | **移除检测**，避免不必要的报错 |
| 内置已知 Bucket | 仅官方桶 | 额外添加 `official`、`third` 和 `soup` |

- **[official](https://github.com/cmontage/scoopbucket)**：自建官方集合桶，聚合多个官方桶并聚合。
- **[third](https://github.com/cmontage/scoopbucket-third)**：第三方应用集合桶，收录其他人自建的桶。
- **[soup](https://github.com/cmontage/scoopbucket-soup)**：我自建的应用桶，优化安装/卸载逻辑，提供一些自己用得到的应用（持续更新中）。
- 所有内置已知桶的 URL 均改为 **Gitee 镜像**，确保 `scoop bucket add <name>` 快速可用。

### 🔧 Bucket 自动 Git 初始化

原版 Scoop 通过 zip 包安装时，默认 Bucket 目录没有 `.git` 元数据，导致后续 `scoop update` 无法正常拉取更新。

本版本在执行 `scoop update` 时自动检测：

- 如果 `official` 桶不是 Git 仓库，自动删除旧目录并以 `git clone` 重新初始化。
- 确保后续所有更新操作正常运行，无需用户手动干预。

### 🇨🇳 全面国内源优化

- **Scoop 自身更新源**：默认从 Gitee（`gitee.com/cmontage/scoop`）拉取更新，代替 GitHub。
- **安装脚本源**：安装脚本（`install.ps1`）使用 Gitee + Cloudflare Proxy 双链路下载，兼顾有无 Git 环境。
- **默认 Bucket 更新源**：所有已知 Bucket 均使用 Gitee 镜像地址。

### 📋 改动汇总

| 特性 | 官方 Scoop | 本版本 |
|------|-----------|--------|
| 国外资源下载 | 直连（可能超时） | 智能代理加速 |
| 运行中进程处理 | 报错中止 | 交互式自动停止 + 提权重试 |
| 默认 Bucket | `main`（GitHub） | `official`（Gitee 镜像） |
| Bucket 源 | GitHub | Gitee 镜像 |
| Scoop 更新源 | GitHub | Gitee |
| Bucket Git 初始化 | 需手动处理 | 自动转换 |
| 安装脚本 | GitHub 官方 | Gitee + CF Proxy 双链路 |

## 如何使用？

### 推荐安装方式

```powershell
# 设置 PowerShell 执行策略（非管理员启动）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 下载安装脚本到本地
irm https://gitee.com/cmontage/scoop/raw/master/install.ps1 -outfile 'install.ps1'

# 自定义 Scoop 安装目录，以下是我的路径例子，你可以自己根据情况修改
# 可以不设全局文件夹ScoopGlobalDir，全局文件夹里的应用需要管理员权限
.\install.ps1 -ScoopDir 'D:\Apps\Scoop\ScoopApps' -ScoopGlobalDir 'D:\Apps\Scoop\ScoopApps-G' -NoProxy

# 已内置 'official' 桶 ，下载 7zip git，如果要添加别的 Bucket，必须有 git、7zip
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

Scoop 常用命令
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
```
应用相关
```powershell
scoop search <app>               # 搜索应用
scoop-search <app>               # 高效率搜索应用，需要安装 scoop-search
scoop install <app>              # 非全局安装应用
scoop install <app> -g           # 全局安装应用 (需要管理员权限/添加前缀sudo)
scoop install <bucket>/<app>     # 指定 bucket (软件源) 安装程序
scoop uninstall <app>            # 非全局卸载应用
scoop uninstall <app> -g         # 全局卸载应用 (需要管理员权限/添加前缀sudo)
scoop update <app1> <app2>...    # 更新非全局应用
scoop update <app1> <app2>... -g # 更新全局应用
scoop reset <app>@<version>      # 同一程序不同版本之间切换
```
