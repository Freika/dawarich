# 如何使用 Docker 安装 Dawarich

> [English](../How_to_install_Dawarich_using_Docker.md)

> 在开始之前，你需要先在系统上安装 [Docker](https://docs.docker.com/get-docker/)。

要快速安装 Dawarich，把项目根目录下的 `docker-compose.yml` 文件内容复制到服务器上一个专用文件夹中，然后在该文件夹内运行 `docker compose up`。

这条命令会使用 [docker-compose.yml](../../docker-compose.yml) 来构建你的本地环境。

命令执行成功、容器中的所有服务都启动后，你就可以通过 [http://127.0.0.1:3000](http://127.0.0.1:3000) 打开 Dawarich 的 Web 界面了。

首次登录的默认账号是 `demo@dawarich.app`，密码是 `safepassword`。
