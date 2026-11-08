# Scoop 自定义分支开发与维护规范手册

本文档记录了 `cmontage/scoop` 项目的核心开发准则、架构设计方案、技术踩坑经验以及后续长期维护的注意事项。

---

## 一、开发与生产环境隔离准则（铁律）

在进行任何功能迭代、代码修改或 Bug 修复时，必须严格执行**开发环境与生产环境物理隔离**：

### 1. 开发环境（唯一的源码编辑与提交源）
* **路径**：`E:\Dev\ProjectFiles\GitProject\myGithub\cmontage\scoop`
* **规范**：
  * **所有的代码修改、功能新增、参数调优及 Git Commit 只能在开发目录进行**。
  * 开发完成后，由开发目录统一执行 `git push` 推送至远程仓库（GitHub: `cmontage/scoop` / Gitee: `cmontage/scoop`）。

### 2. 生产环境（只读消费者，绝不直接碰触）
* **路径**：`D:\Apps\Scoop\ScoopApps\apps\scoop`（包含 `current` 软链接目录）
* **规范**：
  * **严禁直接修改、拷贝文件到生产环境，严禁在生产目录执行任何 `git commit`**！
  * 生产环境仅作为下游普通用户，只通过执行标准的 `scoop update` 命令从远程仓库拉取更新。
  * 保持生产环境始终是远程分支的只读快进副本（Fast-Forward），彻底避免任何分支分叉（Divergent branches）和合并挂起（`MERGE_HEAD`）故障。

---

## 二、架构设计：自改功能与官方原版隔离解耦

为了确保后续官方（`ScoopInstaller/Scoop`）发布新版本（如 v0.6.1、v0.7.0 等）时，可以通过 `git merge upstream/master` **无冲突无缝合并**，代码架构采用全隔离设计：

```
Scoop Root
├── bin/
│   └── scoop.ps1            # 仅保留一行条件钩子（分发子命令前调用 init.ps1）
├── lib/
│   ├── core.ps1             # 保持官方纯净，尾部预留钩子
│   ├── download.ps1         # 保持官方纯净，尾部预留钩子
│   └── install.ps1          # 保持官方纯净，尾部预留钩子
├── libexec/                 # 保持 100% 官方纯净，不改动任何官方脚本
└── custom/                  # ★ 所有自改业务逻辑必须集中在此目录 ★
    ├── init.ps1             # 核心扩展加载入口与多作用域函数覆写
    ├── proxy.ps1            # 智能代理分流、国内白名单与多级下载引擎
    ├── process.ps1          # 进程检测、管理员提权强制终止与服务控制
    ├── buckets.ps1          # 默认仓库 official、自建源注入与 main 检测绕过
    └── bin/
        └── curl-impersonate.exe # 内置真实 Chrome BoringSSL 浏览器指纹下载器
```

### 极小侵入钩子标准
官方原版文件中仅允许出现如下三行钩子代码，不得随意添加内联业务逻辑：
```powershell
# ==========================================
# Scoop Custom Extension Hook (cmontage)
# ==========================================
if (Test-Path "$PSScriptRoot\..\custom\init.ps1") { . "$PSScriptRoot\..\custom\init.ps1" }
```

---

## 三、PowerShell 与 Windows 关键技术踩坑与避坑指南

### 1. PowerShell 5.1 中文编码必须保存为 UTF-8 BOM
* **踩坑现象**：Windows PowerShell 5.1 解析**无 BOM 的 UTF-8** 文件且包含中文注释时，会发生字节偏移，将代码中的换行和括号吞掉，抛出 `ParseException: UnexpectedToken '}'` 语法致命错误。
* **准则**：`custom/` 下所有的 `.ps1` 脚本，以及含有中文的文档与脚本，**必须保存为 UTF-8 with BOM 格式**（在 .NET 中使用 `New-Object System.Text.UTF8Encoding($true)` 写入）。

### 2. 多作用域覆写原则（Scope Shadowing 陷阱）
* **踩坑现象**：PowerShell 的函数调用遵循 `Local -> Enclosing/Script -> Global` 作用域查找顺序。如果仅通过 `function global:Func` 定义覆写，当外层脚本（如 `scoop.ps1`）在脚本级别已有同名函数时，`global:` 会被父级作用域的同名函数彻底遮蔽，导致自改代码失效。
* **准则**：在 [`custom/init.ps1`](file:///e:/Dev/ProjectFiles/GitProject/myGithub/cmontage/scoop/custom/init.ps1) 中覆盖官方函数时，必须同时在当前作用域、`script:` 和 `global:` 三层注册：
  ```powershell
  function script:Find-BucketDirectory { ... }
  function global:Find-BucketDirectory { ... }
  function Find-BucketDirectory { ... }
  ```

### 3. 钩子执行时机（Hook Placement）
* **踩坑现象**：若在 `bin/scoop.ps1` 文件末尾加载 `init.ps1`，由于分发执行子命令 `exec $subCommand` 在中间行就会通过 `& $cmd_path` 唤起子脚本，文件末尾的代码在子命令执行前根本没有运行。
* **准则**：`bin/scoop.ps1` 中的钩子必须放在**核心库加载完成之后、`$subCommand = $Args[0]` 分发执行之前**，确保任何子命令启动前自定义函数已被覆写。

---

## 四、历史 Bug 与业务定制逻辑设计

### 1. 彻底绕过官方远古 `main` Bucket 转换检测
* **背景**：官方 `libexec/scoop-update.ps1:161` 存在一段 2017 年遗留的 `Converting 'main' bucket to git repo...` 转换代码。由于本机使用 `official` 与 `soup` 仓库，未安装 `main`，导致每次 `scoop update` 均报 `ERROR 'main' bucket not found. Failed to remove local 'main' bucket.`。
* **解决方案**：在 [`custom/buckets.ps1`](file:///e:/Dev/ProjectFiles/GitProject/myGithub/cmontage/scoop/custom/buckets.ps1) 中，重写 `Custom-Find-BucketDirectory`：当请求 `'main'` 且本地不存在 `main` 仓库时，自动将路径重定向至本地已存在的 `official`（或首个有效 git bucket），使得 `Test-Path .git` 恒为真，无感跳过转换检测，且零修改官方 `scoop-update.ps1`。

### 2. 高性能下载与浏览器指纹引擎（解决 504、限速与 aria2 代理缺陷）
* **痛点根因**：
  * 原版 `Invoke-Download` 使用 .NET `HttpWebRequest`，硬编码 2KB 读缓冲区，数十万次脚本解释器循环，单流速度被锁死。
  * 代理环境下下载 GitHub Releases 频发 `504 Gateway Timeout`，系 Cloudflare / GitHub WAF 针对数据中心代理 IP 下非浏览器 JA3/JA4 TLS 指纹的限速与拦截。
  * aria2 使用 `--all-proxy` 时会破坏国内直连，且对 GitHub 302 临时鉴权跳转并发 Range 切片极易导致 403 封锁或连接重置。
* **落地架构（四级自愈下载流水线）**：
  1. **Level 1（内置首选）**：内置 `custom/bin/curl-impersonate.exe`（4.3 MB，BoringSSL + HTTP/2/HTTP/3），采用 `--impersonate chrome131` 真实浏览器指纹发包，直连或经代理均无视 504 拦截，跑满物理带宽。
  2. **Level 2（系统级回退）**：若 `curl-impersonate` 异常，自动降级至 `C:\Windows\System32\curl.exe`（原生 C 语言写盘；**注意：不得添加 `--http2` 参数**，因系统自带 curl 未编译 nghttp2 特性，加该参数会报错退出）。
  3. **Level 3（加速镜像回退）**：若遇到直连节点超时或严重波动，自动改由自建加速镜像通道（`https://cfproxy.1122330.xyz/`）下载兜底。
  4. **Level 4（终极保底）**：原版 .NET WebRequest（升级为 64KB 增强缓冲区）。
* **智能分流机制**：
  * 国内大厂（微信、QQ、抖音、夸克、阿里、百度、B站等）与 `.cn` 域名命中白名单，自动绕过本地代理直接全速下载；海外源自动挂接本地代理（`127.0.0.1:7890`）。

---

## 五、日常维护速查清单

| 场景 | 推荐操作步骤 |
| :--- | :--- |
| **修改功能 / 修复 Bug** | 1. 在 `E:\Dev\...` 源码目录修改并测试。<br>2. 提交并推送：`git commit -am "..."` & `git push`。<br>3. 生产环境执行 `scoop update` 自动同步。 |
| **同步官方最新版本** | 1. 在开发目录：`git fetch upstream`<br>2. 合并官方分支：`git merge upstream/master`<br>3. 检查钩子完好性并推送。 |
| **排查生产环境分叉** | 若生产环境意外出现 `MERGE_HEAD` 或分支分叉：<br>`cd D:\Apps\Scoop\ScoopApps\apps\scoop\current`<br>`git merge --abort`<br>`git reset --hard origin/master` |
