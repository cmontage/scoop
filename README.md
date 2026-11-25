<h1 align="center">Scoop</h1>

<p align="center"><img src="https://gcore.jsdelivr.net/gh/cmontage/scoopbucket@main/scoop.png" width="100" alt="Scoop Logo"></p>


<p align="center">
    <a href="https://github.com/cmontage/scoop"><img src="https://img.shields.io/badge/code%20size-536%20KB-blue.svg" alt="Code Size" /></a>
    <a href="https://github.com/cmontage/scoop"><img src="https://img.shields.io/badge/repo%20size-14%20MB-blue.svg" alt="Repository size" /></a>
    <a href="./LICENSE"><img src="https://img.shields.io/badge/license-UNLICENSE%20or%20MIT-green.svg" alt="License" /></a>
    <a href="https://github.com/cmontage/scoop/releases"><img src="https://img.shields.io/badge/base-v0.6.0-blue.svg" alt="Base Version" /></a>
</p>

该 Scoop 基于 [官方 Scoop (v0.6.0+)](https://github.com/ScoopInstaller/Scoop) 修改，针对**中国大陆网络环境**与日常使用痛点进行了深度重构与优化。内置真实浏览器指纹引擎、智能代理分流、提权守护，并采用**完全解耦的架构隔离设计**，确保未来能无缝同步官方上游最新特性。

## 如何安装与使用？

### 推荐安装方式（国内极速）

以**非管理员身份**打开 PowerShell：

```powershell
# 1. 允许脚本执行策略
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 2. 下载安装脚本到本地
irm https://gitee.com/cmontage/scoop/raw/master/install.ps1 -outfile 'install.ps1'

# 3. 执行安装（可自定义应用安装路径 ScoopDir 与全局路径 ScoopGlobalDir）
.\install.ps1 -ScoopDir 'D:\Apps\Scoop\ScoopApps' -ScoopGlobalDir 'D:\Apps\Scoop\ScoopApps-G' -NoProxy

# 4. 安装基础解压与版本管理组件
scoop install 7zip git

# 5. （可选）安装 aria2 开启智能多线程加速，突破部分国内 CDN 单连接限速
# 未安装 aria2 时会静默使用内置 curl-impersonate，无任何报错或额外提示
scoop install aria2
scoop config aria2-split 16
scoop config aria2-max-connection-per-server 16
scoop config aria2-warning-enabled false
```

## 核心特性与改进

### ⚡ 内置 `curl-impersonate` 真实浏览器指纹极速下载

原版 Scoop 使用 .NET 的单流 HTTP/1.1，内置硬编码的 2KB 读缓冲区，速度极其缓慢；且在代理环境下经常遭遇 GitHub Releases / Cloudflare WAF 对机房代理 IP 的人机校验，抛出 `504 Gateway Timeout`。此外，原版 Scoop 在开启 `aria2` 时会无差别注入 `--all-proxy`，既破坏国内直连，又容易因 GitHub 302 临时鉴权链接并发 Range 切片触发 403 封锁或连接重置。

本项目内置了开箱即用的**四级自愈下载流水线**，并为 `aria2` 构建了完全解耦的**智能分流调度与统一进度条引擎**：

1. **Level 1（内置首选 · 真实 Chrome 浏览器指纹）**：
   - 仓库独立内置静态编译的 `curl-impersonate.exe`（BoringSSL + HTTP/2/HTTP/3）。
   - 自动模拟 **Chrome 131 真实浏览器 TLS 1.3 指纹（JA3/JA4）**与请求头顺序，彻底穿透 GitHub Releases / CDN WAF 防爬风控，**告别 504 网关超时**。
   - C 语言底层大窗口零开销写盘，轻松跑满千兆带宽，体验与 Chrome 浏览器下载完全一致。
2. **Level 2（第一级容灾 · 系统自带 curl.exe）**：
   - 若内置组件异常，自动无缝降级为 Windows 10/11 原生的 `C:\Windows\System32\curl.exe`。
3. **Level 3（第二级容灾 · 代理镜像加速通道）**：
   - 若遇代理节点宕机或物理断网，自动无缝重定向到自建加速镜像继续下载。
4. **Level 4（终极保底 · 增强 .NET WebRequest）**：
   - 极端环境下降级回退至优化后的 64KB 增强缓冲区 WebRequest。

### 🚀 Aria2 智能多线程调度与现代化统一进度条

针对部分国内 CDN（如夸克 `umcdn.quark.cn`）对**单条 TCP 连接限速（约 200 KB/s）**的场景，开启 `aria2`（`scoop config aria2-enabled true`）即可通过多线程叠加突破单连接瓶颈，同时不修改 `aria2` 程序本体（全部逻辑位于 [`custom/aria2.ps1`](./custom/aria2.ps1)）：

- **不破坏国内直连与 GitHub 下载的智能路由**：
  - **国内白名单 / 国内 IP**：强制直连多线程下载（传入 `--no-proxy=*` 并在子进程环境中彻底剥离 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`），绝不走系统代理，不浪费代理流量。
  - **GitHub / 自建加速镜像 / SOCKS 代理**：自动识别 `github.com`、`githubusercontent.com`、`githubassets.com`、`1122330.xyz` 及 SOCKS 代理场景，自动绕过 `aria2` 并交由内置 `curl-impersonate` 引擎下载，彻底规避 GitHub 并发 Range 403/504 与 `aria2` 不支持 SOCKS 的问题。
  - **其他海外源**：通过 HTTP 代理多线程加速；若遇 WAF 拦截或异常退出，自动清理残留 `.aria2` 控制文件并无缝回退至 `curl-impersonate` 四级流水线。
- **现代化统一彩色进度条**：
  - 接管 `aria2c` 实时输出并复用 [`custom/proxy.ps1`](./custom/proxy.ps1) 的 `Write-CurlProgressLine` 渲染器，告别原版杂乱刷屏日志，统一展示旋转指示器、彩色进度条、百分比、已下载/总大小、实时速率、**并发连接数角标（如 `16x`）** 与剩余时间（ETA）。
  - 自动探测终端 `OutputEncoding` 字形支持情况，在 GBK（CP936）老旧控制台下自动回退 ASCII 字符，避免出现 `?` 乱码。
- **未安装静默兜底**：未安装 `aria2` 或关闭 `aria2-enabled` 时无任何报错或多余提示，自动静默使用内置 `curl-impersonate` 引擎。

### 🌐 智能分流与国内白名单直连

- **国内大厂与 `.cn` 域名白名单全速直连**：
针对微信、QQ、抖音、夸克、阿里、百度、网易、B站、京东、知乎等国内常用软件及所有 `.cn` 域名，自动识别并**强行绕过代理，走本地物理宽带直连**，既省代理流量又保证国内软件满速下载。
- **地理位置动态解析**：
通过阿里云公共 DNS（`223.5.5.5`）解析真实物理 IP，结合 IP 归属地库智能判断物理位置，自动分流。
- **本地代理无缝兼容**：
完美兼容 Clash、Sing-box、V2Ray 等本地代理的 TUN / System Proxy 模式。可通过 `scoop config PROXY <url>` 自定义代理端口。

### 🔄 交互式自动停止运行中进程与提权

原版 Scoop 在更新或卸载时，若应用进程正在运行会直接抛错中止。本版本提供了智能进程守护：

- **交互式询问**：检测到进程占用时，提示 `Stop all processes for this program and continue? (y/n)`（回车默认 `y`）。
- **进程树优雅退出 / 强制终止**：选择 `y` 后自动清退相关进程及后台常驻服务。
- **管理员权限自动提权**：针对全局安装（`-g`）或受保护的系统级进程，自动以 Administrator 提权强制清理。
- **跳过配置**：支持通过 `scoop config IGNORE_RUNNING_PROCESSES true` 静默忽略进程检测直接覆盖。

### 📦 自建 Bucket 体系与远古 Bug 静默修复

| 对比项 | 官方 Scoop | 本版本 |
| :--- | :--- | :--- |
| **默认 Bucket** | `main`（GitHub 托管） | `official`（Gitee 镜像，自建聚合桶） |
| **Bucket 仓库源** | GitHub（国内易连不上） | **Gitee 镜像源**（国内极速拉取） |
| **远古 `main` 桶转换检测** | 强制检测 `main`，不存在则报错中止 | **Custom 拦截重定向**，静默绕过检测 |
| **内置已知 Bucket 列表** | 仅官方桶 | 扩展内置 `official`、`soup`、`third` |

- **[official](https://gitee.com/cmontage/scoopbucket)**：自建官方集合桶，聚合维护各类常用官方软件清单。
- **[soup](https://gitee.com/cmontage/scoopbucket-soup)**：个人深度调优桶，定制安装/卸载逻辑，收录自用高频软件。
- **[third](https://gitee.com/cmontage/scoopbucket-third)**：精选第三方优质软件集合桶。
- **彻底消除 `main` 桶报错**：针对未添加 `main` 的自建源用户，在 `custom/` 拦截将 `main` 重定向至本地已存在的 `official`，彻底解决官方旧代码抛出 `ERROR 'main' bucket not found. Failed to remove local 'main' bucket` 的问题。

### 🛡️ 架构全隔离设计（零冲突升级上游）

所有自改逻辑均封装于独立的 [`custom/`](./custom/) 目录中，官方原有核心文件仅保留 3 行极简钩子。未来当官方 Scoop 发布新版本时，可以直接执行 `git merge upstream/master` **零冲突同步官方所有新特性**。

### 📋 特性对比汇总

| 特性 | 官方 Scoop | 本版本 |
| :--- | :--- | :--- |
| **下载引擎** | .NET 2KB 读循环 / 原生 aria2（无分流） | **内置 `curl-impersonate` (Chrome 131 指纹) + `aria2` 智能分流调度** |
| **下载速度** | 通常 1~5 MB/s | **单连接跑满千兆宽带，限速 CDN 可由 aria2 16 并发叠加加速** |
| **进度条体验** | 简易文本或原版 aria2 杂乱表格 | **统一现代彩色进度条（实时速率 / ETA / 并发角标 `16x` / 编码自适应）** |
| **代理 504 / WAF 拦截** | 频繁报错超时 | **真实浏览器 TLS 指纹，GitHub 自动绕过 aria2 彻底规避** |
| **国内软件下载** | 若开代理常被减速或走代理 | **国内白名单强制直连分流（含 aria2 剥离代理环境变量）** |
| **运行中进程占用** | 报错中止 | **交互式确认 + 自动终止 + 提权清理** |
| **未添加 main 桶更新** | 报错中止更新 | **底层动态重定向，无感静默更新** |
| **更新及安装源** | GitHub 官方 | **Gitee 国内镜像链路** |


# 常用命令速查

### Scoop 核心管理
```powershell
scoop update                     # 更新 Scoop 自身及所有软件源列表
scoop update *                   # 一键升级所有已安装的软件
scoop status                     # 检查当前有哪些软件发布了新版本
scoop cleanup *                  # 清理所有已安装软件的历史旧版本，释放磁盘
scoop cache rm *                 # 清理本地安装包下载缓存
scoop checkup                    # 检查当前系统环境与潜在配置问题
```

### 软件源（Bucket）管理
```powershell
scoop bucket list                # 查看当前已启用的软件源
scoop bucket known               # 查看内置支持的所有镜像源
scoop bucket add <name>          # 添加内置已知源（如 soup, third 等）
scoop bucket add <name> <url>    # 添加自定义第三方 Git 仓库源
scoop bucket rm <name>           # 移除软件源
```

### 应用安装与管理
```powershell
scoop search <app>               # 搜索应用
scoop-search <app>               # 高效率索引秒搜（需先执行 scoop install scoop-search）
scoop install <app>              # 普通用户权限安装应用
scoop install <app> -g           # 全局安装应用（软链接到系统级目录）
scoop install <bucket>/<app>     # 指定特定软件源安装应用
scoop uninstall <app>            # 卸载应用
scoop update <app1> <app2>...    # 单独更新指定应用
scoop reset <app>@<version>      # 切换指定程序的不同版本
```
