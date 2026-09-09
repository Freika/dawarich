# 如何用 Docker 在群晖 Synology 上安装 Dawarich

> [English](../How_to_install_Dawarich_on_Synology.md)

# 准备工作

## Container Manager（容器管理器）
首先你需要在 DSM 中安装 [Container Manager](https://www.synology.com/en-global/dsm/feature/container-manager)。

- 打开 Synology DSM 网页管理界面。
- 在主菜单中打开**套件中心**。
- 在"开源"分类下搜索 **Container Manager**。
- 安装它。

## Web Station（网站服务器）
按同样的方式安装 [Web Station](https://www.synology.com/en-global/dsm/packages/WebStation) 套件。

## 项目文件夹准备

### Docker 根共享文件夹
如果你还没有专门用来存放 Docker 项目的共享文件夹，建议先创建一个。

如果你不想为 Docker 安装的项目单独使用共享文件夹，可以跳过本节，直接进入下一章。

- 打开**控制面板** -> **共享文件夹** -> **创建** -> **创建共享文件夹**
- 设置名称（比如 **docker**）和位置。
- 勾选**在"网上邻居"中隐藏此共享文件夹**。这样可以避免该文件夹被 smb、afp、ftp 等共享方式列出。
- 多次点击**下一步**，直到看到**配置用户权限**窗口。
- 为你自己的账户勾选**读/写**权限，其他账户设为**无权限**。

### Dawarich 根目录
1. 在**文件站**中打开你的 [Docker 根共享文件夹](#docker-根共享文件夹)。
2. 新建 **dawarich** 文件夹并进入。
3. 在 **dawarich** 文件夹中创建 **redis**、**db_data**、**db_shared** 和 **public** 四个子文件夹。
4. 把仓库 **synology** 文件夹中的 [docker compose](../synology/docker-compose.yml) 和 [.env](../synology/.env) 文件复制到群晖上的 **dawarich** 文件夹中。

# 安装

## 创建项目
1. 打开 **Container Manager** -> **项目** -> **创建**
2. 在**创建项目**窗口中：
   1. 按你的喜好设置**项目名称**。
   2. 将**路径**设置为 [Dawarich 根目录](#dawarich-根目录)。
      1. DSM 会询问是否使用已存在的 docker-compose 文件，选择**使用现有的 docker-compose.yml 来创建项目**。
   3. 点击**下一步**。
   4. 勾选**通过 Web Station 设置网页门户**。
      1. 选择容器名称、端口，协议选择 **http**（不是 https）。
   5. 点击"下一步"。
   6. 取消勾选**创建后立即启动项目**。
   7. 点击"完成"。
3. 弹出提示"dawarich 已创建，请前往 Web Station 配置该容器的网页门户"，点击"确定"，**Web Station** 门户创建向导会随即打开。
4. 将**门户类型**设置为**基于名称**。
5. 按你的喜好设置**主机名**。例如，如果你的 DSM 主机名是 **my-syno.com**，可以使用 **dawarich.my-syno.com**。
6. 勾选 **HTTPS 设置 - HSTS**
   >这一步假定你已经在 DSM 中配置好了证书（参见**控制面板** -> **安全性** -> **证书**），比如之前已经配置过 **QuickConnect** 或 **DynDNS**（DDNS），见**控制面板** -> **外部访问**。
7. 点击**创建**。

## 配置
### DNS
在你的本地 DNS 服务器上，需要新增一条记录，把 `dawarich.my-syno.com` 解析到群晖的 IP 地址（可在 DSM 的**控制面板** -> **网络** -> **网络接口**中查看），以确保能正确访问 Dawarich；或者也可以直接用通配符 `*.my-syno.com` 记录，把 `my-syno.com` 的所有子域名都解析到群晖的 IP。

具体操作方法请参考你所使用 DNS 服务器的相关文档。

如果你还没有 DNS 服务器，可以安装 [Synology DNS](https://www.synology.com/en-global/dsm/packages/DNSServer)。
>别忘了重新配置你的 DHCP 服务器，或本地网络中所有设备的设置，让它们使用这台 DNS 服务器。

### Dawarich
1. 用任意文本编辑器打开 /[Docker 根共享文件夹](#docker-根共享文件夹)/[Dawarich 根目录](#dawarich-根目录)/.env 文件。例如，你可以使用 [Text Editor](https://www.synology.com/en-global/dsm/packages/TextEditor) 套件，或者从**文件站**下载后本地编辑再上传回去，或者通过文件共享方式访问。
2. 更新 `APPLICATION_HOSTS` 的值，加入你在 **Web Station** 中设置的 **Dawarich 主机名**。按上面的例子就是 **dawarich.my-syno.com**。如果要设置多个主机名，用逗号分隔：`dawarich.my-syno.com,dawarich2.my-syno.com`。
3. 设置你当前所在的 `TIME_ZONE`。完整列表见[这里](https://github.com/Freika/dawarich/issues/27#issuecomment-2094721396)。
4. 可选：修改 `DATABASE_USERNAME`、`DATABASE_USERNAME`、`DATABASE_NAME`。

5. 点击你的项目名称。
6. 打开 **YAML 配置**标签页。

# 运行
1. 打开 **Container Manager** -> **项目** -> **dawarich**
2. 点击右上角的**操作** -> **构建**
3. 等待弹窗提示全部完成，再多等几分钟让容器里的所有应用启动完成。
4. 通过你设置的主机名打开它，本例中是 https://dawarich.my-syno.com

# 添加到主菜单链接
有两种方式可选：
1. 使用 **Web Station**。但这样只会有默认的 Web Station 图标。
2. 通过**套件中心**的自定义应用。
## Web Station 方式
- 打开 **Web Station** -> **网页门户** -> **dawarich（项目）**。
- 勾选**在主菜单创建快捷方式**并设置链接名称。

## 自定义应用方式
群晖允许你创建自定义应用，并通过**套件中心**安装。
[这里](https://github.com/vletroye/Mods)有一个工具，可以创建仅带图标、显示在主菜单中的空壳应用。
你可以使用这个工具自己创建一个应用，也可以直接用本仓库已经准备好的方案，但需要修改其中指向 Dawarich 的 url。

- 编辑 `synology` 文件夹中的 `update.sh`，在开头几行设置正确的 `author` 和 `URL` 值。
- 运行 `update.sh`。脚本执行完成后，你会在同一文件夹中看到 `spk` 和 `Dawarich.spk`。

如果你没有 Linux 终端环境，也可以创建一个临时的 Docker 项目来生成 spk 安装包。
- 在 [Docker 根共享文件夹](#docker-根共享文件夹)中新建一个文件夹。
- 创建子文件夹 `app`，并把 `update.sh` 和 `spk.tgz` 复制到这个子文件夹中。
- 打开 **Container Manager** -> **项目** -> **创建**。
- 设置任意名称，选择刚创建的文件夹，并选择**创建 docker-compose.yml**。
- 把下面的文本复制到文本框中。
```yaml
name: spk-template

services:
  spk-template:
    container_name: spk-template
    image: alpine
    restart: unless-stopped
    working_dir: /app
    volumes:
      - ./app:/app
    command:
      - /app/update.sh
```
- 依次点击**下一步**、**下一步**、**完成**
容器会自动运行并完成任务。
- 完成后，你可以在 `app` 文件夹中看到 `spk` 和 `Dawarich.spk`。


- 检查 `spk/package/ui/config` 文件中的 `url`，以及 `spk/INFO` 文件中的 `maintainer` 和 `distributor`。
- 打开**套件中心**，点击**手动安装**，选择 `Dawarich.spk`，同意安全提示后完成安装。
