**特别强调:**
- 此仓库仅用来解决资源无法拉取的问题，使用此仓库出现问题后切换原版scoop后资源能正常拉取，可提交Issue处理；
- 其他功能性问题请直接找[github scoop](https://github.com/ScoopInstaller/Scoop/)处理，官方库更新后本仓库会自动同步；
- `scoop.201704.xyz`预计于2025年8月27日移除加速国外软件部分，建议个人自行搭建，搭建方法参考章节[3.1.2 自建url代理](https://gitee.com/scoop-installer/scoop#312-%E8%87%AA%E5%BB%BAurl%E4%BB%A3%E7%90%86)，可开Issue贡献你的自建加速网站。



## 0. 项目实现功能
国内github访问不通畅，且多数开源软件托管在github，导致scoop体验极差。为改善使用体验，将scoop主程序库托管在gitee，增加分流逻辑处理安装与更新所涉及的资源，提示见附图所示。

**直连场景**
套娃代理、域名解析为内网IP和fakeIP。

![直连](https://foruda.gitee.com/images/1740363881023287607/49caf4c5_5328893.png "屏幕截图")

**代理场景**
除直连场景外的其他形式，包括域名解析失败、域名为外网IP和程序运行失败。

![代理](https://foruda.gitee.com/images/1740364010065116519/dca2d69e_5328893.png "屏幕截图")

**注意事项：**
- 请勿提取并滥用加速链接，如有发现滥用则取消公开；
- **退出360后再使用（如有解决办法可提issue）；**
- 源代码镜像纯属用爱发电，**有用请点star**；

## 1. 安装scoop主程序

### 1.1 初次安装
（第一次在电脑安装时，执行完本节内容，可跳过1.2节内容。）

打开`Windows Powershell`界面（开始菜单右键）
```powershell
# 脚本执行策略更改，默认自动同意
Set-ExecutionPolicy RemoteSigned -scope CurrentUser -Force

# 执行安装命令（默认安装在用户目录下，如需更改请执行“自定义安装目录”命令）
iwr -useb scoop.201704.xyz | iex


## 自定义安装目录（注意将目录修改为合适位置)
irm scoop.201704.xyz -outfile 'install.ps1'
.\install.ps1 -ScoopDir 'D:\Scoop' -ScoopGlobalDir 'D:\GlobalScoopApps'
```


### 1.2 已安装scoop,更换镜像
（适用于`已安装官方源或其他镜像地址`的人使用)
```powershell
# 更换scoop的repo地址
scoop config SCOOP_REPO "https://gitee.com/scoop-installer/scoop"
# 拉取新库地址
scoop update
```

### 1.3 切换scoop分支
本库包含如下分支。
| 分支| 含义|基于原版分支|
|-|-|-|
|master| 代理分流,根据电脑网络环境自动判断|master|
|develop|代理分流，同上|develop|
|archive|原版，无任何修改|master|

安装默认选择`master`分支，想要切换到其他分支，可执行如下命令
```powershell
# 切换分支到develop
scoop config scoop_branch develop
# 重新拉取git
scoop update
```

## 2. 添加bucket
2.1 安装git程序
```powershell
#必装git，scoop及bucket更新均依赖此软件
scoop install git
```

2.2 添加已知bucket
```powershell
#查询已知bucket
scoop bucket known
#添加bucket
scoop bucket add extras
```
目前已知bucket已镜像至gitee，当前使用本仓库的用户，可通过如下命令进行重新添加仓库。其他用户可直接访问`https://scoop.201704.xyz`获取对应bucket库连接，然后按照下节内容添加即可。
```
# 查看当前buckt
scoop bucket list

# 删除已安装的bucket
scoop bucket rm extras

# 重新添加bucket
scoop bucket add extras

# 重新查看bucket镜像
scoop bucket list

## 正常切换后，bucket列表均应从gitee.com拉取，例如：
Name     Source                                       Updated            Manifests
----     ------                                       -------            ---------
main     https://gitee.com/scoop-installer/Main       2025/2/24 8:37:11       1382
extras   https://gitee.com/scoop-installer/Extras     2025/2/24 8:41:05       2130
dorado   https://gitee.com/scoop-installer/dorado     2025/2/24 8:16:22        257
echo     https://gitee.com/scoop-installer/echo-scoop 2025/2/23 22:14:08       102
scoopcn  https://gitee.com/scoop-installer/scoopcn    2025/2/19 16:37:21        30
scoopet  https://gitee.com/scoop-installer/scoopet    2025/2/24 2:01:44         81
siku     https://gitee.com/scoop-installer/siku       2025/2/24 0:33:43         89
Versions https://gitee.com/scoop-installer/Versions   2025/2/24 4:34:25        477

```

2.3 添加第三方bucket
```powershell
# 基本语法
scoop bucket add <别名> <git地址>

# 举例添加scoopcn（[Mostly Chinese applications / 大多是国内应用程序](https://github.com/scoopcn/scoopcn)）
scoop bucket add scoopcn https://gitee.com/scoop-installer/scoopcn

```
其他较为优秀的bucket，可访问[scoop-installer](https://scoop.201704.xyz)，有选择性地添加

删除bucket
```powershell
scoop bucket rm <别名>
```

### 3. 安装软件

#### 3.1 代理(可选)

##### 3.1.1 默认http代理
```powershell
# 添加代理 根据实际填写http代理
scoop config proxy 127.0.0.1:4412

# 删除代理
scoop config rm proxy
```

##### 3.1.2 自建url代理
- 仅限于本仓库使用（默认启用），其中archive分支和原版scoop设置无效。
- 推荐自建代理，自建代理参考教程：[文件加速代下载服务,github 项目加速服务](https://zwc365.com/2020/09/24/file-proxy-download)。
- 此节提供的加速站均可使用（后续会移除域名`scoop.201704.xyz`的代理加速功能，专用于scoop程序本体安装，避免域名被干掉导致无法正常安装软件）。
- **其他类型加速站因跨域限制或仅限于加速指定网站的原因，可能会出现拉取资源失败的问题**。
```powershell
# 添加代理
## 使用本仓库已默认使用该代理，无需重复添加。只有切换至其他代理站时才需要设置。
scoop config URL_PROXY "https://jiashu.1win.eu.org"

# 删除代理
scoop config rm URL_PROXY


### 可供设置的代理站
转发服务域名1：https://jiashu.1win.eu.org
转发服务域名2：https://j.1lin.dpdns.org
转发服务域名3：https://j.1win.ddns-ip.net
转发服务域名4：https://j.1win.ggff.net(一年制,2026年5月3日到期)
转发服务域名5：https://j.1win.ip-ddns.com
转发服务域名6：https://j.n1win.dpdns.org


```



### 3.2 软件安装
```powershell
# 基本语法
scoop install <库名/软件名>

# 例如安装 qq 微信(wechat) 
scoop install qq
# 指定bucket库的软件（如需要）
scoop install scoopcn/wechat

# 一条命令安装多个软件
scoop install qq wechat aria2

```

### 3.3 软件卸载
```powershell
scoop uninstall qq wechat
```

### 3.4 软件更新
```powershell
scoop update *
```

### 3.5 其他命令
```powershell
# 软件暂停更新
scoop hold <软件名>
# 切换到指定版本
scoop reset <软件名@版本号>
# 重置所有软件链接及图标
scoop reset *

# 删除缓存软件包
scoop cache rm *

# 删除软件老版本
scoop cleanup rm *

```
### 4. 常见问题
#### 问题1：**Scoop is running the installer as administrator is disabled.**

原因：scoop禁止在管理员权限下安装

解决办法：开始菜单右键，选择`Windows PowerShell`，然后重新执行安装命令

#### 问题2：**无法正确下载软件资源，导致软件安装失败**

原因：可能存在多重套娃代理，例如（https://<代理A>/https://<代理B>/<资源链接>），尤其是国内镜像bucket或者针对中国优化的bucket库，其中json资源多数已硬编码了代理链接。
以scoop-proxy-cn为例，git资源的下载链接为：<https://mirror.ghproxy.com/https://github.com/git-for-windows/git/releases/download/v2.45.0.windows.1/PortableGit-2.45.0-64-bit.7z.exe#/dl.7z>，其已经存在了`代理B`，由于此类链接的IP多为外网IP，默认走程序代理，增加了`代理B`，也即出现上面的代理套娃，跨域失败，资源拉取失败，软件安装失败。

解决办法（3种方法可选）：
1. 执行`scoop update`将程序更新至最新版本，然后再执行下载（推荐）；
2. 使用本页面推荐的几个bucket，或切换spc仓库至sync分支；
3. 切换至`archive`分支，放弃本镜像的代理优化。

#### 问题3：**远程主机强迫关闭了一个现有的连接**

原因：重复多次请求同一个资源，后端关闭了此链接。

解决办法：关闭aria2

#### 问题4：**fatal: protocol ''https' is not supported**

原因：软件未正确识别内容，详细内容见[官方问答区](https://proxy.201704.xyz/https://github.com/ScoopInstaller/Scoop/discussions/5414)。

解决办法: 将命令中的链接使用双引号包裹起来（命令中存在链接，都可以解决），重新执行一遍命令。

```powershell
C:\Users\用户名>scoop config SCOOP_REPO 'https://gitee.com/glsnames/scoop-installer'
'SCOOP_REPO' has been set to ''https://gitee.com/glsnames/scoop-installer''

C:\Users\用户名>scoop update *
Updating Scoop...
fatal: protocol ''https' is not supported
Update failed.

C:\Users\用户名>scoop config SCOOP_REPO "https://gitee.com/glsnames/scoop-installer"
'SCOOP_REPO' has been set to 'https://gitee.com/glsnames/scoop-installer'

C:\Users\用户名>scoop update *
Latest versions for all apps are installed! For more information try 'scoop status'
```

若依旧不能更新，请用记事本打开config文件(`scoop安装目录\apps\scoop\current\.git\config`)，手动去掉其中url行中的引号，修改保存后再重新执行更新命令。
显示为如下内容为正常。
```
***省略
[remote "origin"]
	url = https://gitee.com/glsnames/scoop-installer
	fetch = +refs/heads/*:refs/remotes/origin/*
***省略
```



### 5. 常用命令
```powershell
Usage: scoop <command> [<args>]  
  
Some useful commands are:  
  
alias       Manage scoop aliases # 管理指令的替身  
bucket      Manage Scoop buckets # 管理软件仓库  
cache       Show or clear the download cache # 查看与管理缓存  
checkup     Check for potential problems # 做个体检  
cleanup     Cleanup apps by removing old versions # 清理缓存与旧版本软件包  
config      Get or set configuration values # 配置Scoop  
create      Create a custom app manifest # 创建自定义软件包  
depends     List dependencies for an app # 查看依赖  
export      Exports (an importable) list of installed apps # 导出软件包列表  
help        Show help for a command # 显示帮助指令  
hold        Hold an app to disable updates # 禁止软件包更新  
home        Opens the app homepage # 打开软件包主页  
info        Display information about an app # 显示软件包信息  
install     Install apps # 安装软件包的指令  
list        List installed apps # 列出所有已安装软件包  
prefix      Returns the path to the specified app # 查看软件包路径  
reset       Reset an app to resolve conflicts # 恢复软件包版本  
search      Search available apps # 搜索软件包  
status      Show status and check for new app versions # 查看软件包更新状态  
unhold      Unhold an app to enable updates # 启动软件包更新  
uninstall   Uninstall an app # 卸载软件包的指令  
update      Update apps, or Scoop itself # 更新软件包  
virustotal  Look for app hash on virustotal.com # 查看哈希值  
which       Locate a shim/executable (similar to 'which' on Linux) # 查看可执行程序路径
```