## 配置反向代理

> [English](../how_to_setup_reverse_proxy.md)

### 环境变量
要让 Dawarich 配合反向代理正常工作，需要确保 `APPLICATION_HOSTS` 环境变量中包含了反向代理将要使用的域名。
例如，如果你的 Dawarich 实例打算部署在域名 timeline.mydomain.com 下，就需要在这个环境变量中包含 "timeline.mydomain.com"。
注意：环境变量中不要包含 "http://" 或 "https://"。⚠️ 如果变量中包含了 http:// 或 https://，网页将无法正常工作。⚠️

在编写本文档时，设置该环境变量的方式是编辑 docker-compose.yml 文件。找到文件中所有 APPLICATION_HOSTS 条目，确保其中包含了你的域名。示例：

```yaml
dawarich_app:
    image: freikin/dawarich:latest
    container_name: dawarich_app
    ...
    environment:
      ...
      APPLICATION_HOSTS: "yourhost.com,www.yourhost.com,127.0.0.1" <-- 在这里修改
```

```yaml
dawarich_sidekiq:
    image: freikin/dawarich:latest
    container_name: dawarich_sidekiq
    ...
    environment:
      ...
      APPLICATION_HOSTS: "yourhost.com,www.yourhost.com,127.0.0.1" <-- 在这里修改
      ...
```

如果是在群晖上安装，请参考**[群晖安装教程](How_to_install_Dawarich_on_Synology.md)**，里面说明了如何设置 APPLICATION_HOSTS 环境变量。

### 虚拟主机

让应用支持域名访问之后，还需要在服务器上配置反向代理，通常是在虚拟主机配置中完成的。

下面是一些反向代理配置示例。

### Nginx
```nginx
server {

	listen 80;
	listen [::]:80;
	server_name example.com;

	brotli on;
	brotli_comp_level 6;
	brotli_types
		text/css
		text/plain
		text/xml
		text/x-component
		text/javascript
		application/x-javascript
		application/javascript
		application/json
		application/manifest+json
		application/vnd.api+json
		application/xml
		application/xhtml+xml
		application/rss+xml
		application/atom+xml
		application/vnd.ms-fontobject
		application/x-font-ttf
		application/x-font-opentype
		application/x-font-truetype
		image/svg+xml
		image/x-icon
		image/vnd.microsoft.icon
		font/ttf
		font/eot
		font/otf
		font/opentype;

	location / {
		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Proto https;
		proxy_set_header X-Forwarded-Server $host;
		proxy_set_header Host $http_host;
		proxy_redirect off;

		proxy_pass http://127.0.0.1:3000/;
	}

}

```

### Apache2

使用 Apache2 时，你可能需要启用一些模块。请先执行以下命令，这样下面的示例配置才能正常工作。

```
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod headers
sudo a2enmod brotli
```

执行完上面的命令后，下面的配置就可以正常工作了。

```apache
<VirtualHost *:80>
	ServerName example.com

	ProxyRequests Off
	ProxyPreserveHost On

	<Proxy *>
		Require all granted
	</Proxy>

	Header always set X-Real-IP %{REMOTE_ADDR}s
	Header always set X-Forwarded-For %{REMOTE_ADDR}s
	Header always set X-Forwarded-Proto https
	Header always set X-Forwarded-Server %{SERVER_NAME}s
	Header always set Host %{HTTP_HOST}s

	SetOutputFilter BROTLI
	AddOutputFilterByType BROTLI_COMPRESS text/css text/plain text/xml text/javascript application/javascript application/json application/manifest+json application/vnd.api+json application/xml application/xhtml+xml application/rss+xml application/atom+xml application/vnd.ms-fontobject application/x-font-ttf application/x-font-opentype application/x-font-truetype image/svg+xml image/x-icon image/vnd.microsoft.icon font/ttf font/eot font/otf font/opentype
	BrotliCompressionQuality 6

	ProxyPass / http://127.0.0.1:3000/
	ProxyPassReverse / http://127.0.0.1:3000/

</VirtualHost>
```

### Caddy
下面是让 Caddy 作为 Dawarich 前置代理所需的最小配置。请注意，如果你的 Caddy 和 Dawarich 服务栈是分开运行的，需要为它们配置一个共享网络。

首先，如果需要的话，创建服务栈之间要用到的 Docker 网络：
```
docker network create frontend
```

然后，为 Dawarich 创建一个作为后端网络使用的 Docker 网络：
```
docker network create dawarich
```

按如下方式调整你的 Dawarich docker-compose.yaml，让 web 应用同时暴露在新建的网络和 Dawarich 后端网络中：
```yaml
networks:
  dawarich:
  frontend:
    external: true
services:
  ...
```

最后，按需编辑你的 Caddy 配置：
```caddy
{
	http_port 80
	https_port 443
}

timeline.example.com {
	reverse_proxy dawarich_app:3000

	encode brotli {
		match {
			content_type text/css text/plain text/xml text/x-component text/javascript application/x-javascript application/javascript application/json application/manifest+json application/vnd.api+json application/xml application/xhtml+xml application/rss+xml application/atom+xml application/vnd.ms-fontobject application/x-font-ttf application/x-font-opentype application/x-font-truetype image/svg+xml image/x-icon image/vnd.microsoft.icon font/ttf font/eot font/otf font/opentype
		}
	}
}

```
timeline.example.com 只是示例，请替换成你自己的（子）域名。

---

请注意，以上配置仅为示例，只包含让反向代理正常工作所需的最小配置。请根据自己的实际需求自行调整。
