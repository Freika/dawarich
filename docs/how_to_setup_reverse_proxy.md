## Setting up reverse proxy

> [简体中文](zh-CN/how_to_setup_reverse_proxy.md)

### Environment Variable
To make Dawarich work with a reverse proxy, you need to ensure the APPLICATION_HOSTS environment variable is set to include the domain name that the reverse proxy will use.
For example, if your Dawarich instance is supposed to be on the domain name timeline.mydomain.com, then include "timeline.mydomain.com" in this environment variable.
Make sure to exclude "http://" or "https://" from the environment variable. ⚠️ The webpage will not work if you do include http:// or https:// in the variable. ⚠️

At the time of writing this, the way to set the environment variable is to edit the docker-compose.yml file. Find all APPLICATION_HOSTS entries in the docker-compose.yml file and make sure to include your domain name. Example:

```yaml
dawarich_app:
    image: freikin/dawarich:latest
    container_name: dawarich_app
    ...
    environment:
      ...
      APPLICATION_HOSTS: "yourhost.com,www.yourhost.com,127.0.0.1" <-- Edit this
```

```yaml
dawarich_sidekiq:
    image: freikin/dawarich:latest
    container_name: dawarich_sidekiq
    ...
    environment:
      ...
      APPLICATION_HOSTS: "yourhost.com,www.yourhost.com,127.0.0.1" <-- Edit this
      ...
```

For a Synology install, refer to **[Synology Install Tutorial](How_to_install_Dawarich_on_Synology.md)**. In this page, it is explained how to set the APPLICATION_HOSTS environment variable.

### Virtual Host

Now that the app works with a domain name, the server needs to be set up to use a reverse proxy. Usually, this is done by setting it up in the virtual host configuration.

Below are examples of reverse proxy configurations.

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

For Apache2, you might need to enable some modules. Start by entering the following commands so the example configuration below works without any problems.

```
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod headers
sudo a2enmod brotli
```

With the above commands entered, the configuration below should work properly.

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
Here is the minimum Caddy config you will need to front Dawarich with.  Please keep in mind that if you are running Caddy separately from your Dawarich stack, you'll need to have a network that is shared between them.

First, create the Docker network that will be used between the stacks, if needed:
```
docker network create frontend
```

Second, create a Docker network for Dawarich to use as the backend network:
```
docker network create dawarich
```

Adjust the following part of your Dawarich docker-compose.yaml, so that the web app is exposed to your new network and the backend Dawarich network:
```yaml
networks:
  dawarich:
  frontend:
    external: true
services:
  ...
```

Lastly, edit your Caddy config as needed:
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
timeline.example.com is an example, use your own (sub) domain.

### Serving Dawarich under a subpath

Dawarich can also run under a path of an existing domain, for example `https://example.com/dawarich`, instead of on its own (sub)domain.

Set `RAILS_RELATIVE_URL_ROOT` to the path on **both** the `dawarich_app` and `dawarich_sidekiq` services. The value starts with a slash and has no trailing slash:

```yaml
dawarich_app:
    ...
    environment:
      ...
      RAILS_RELATIVE_URL_ROOT: /dawarich
```

Dawarich then answers only under that path, for example `http://127.0.0.1:3000/dawarich/`, so anything that probes the health endpoint needs the path as well. The healthcheck in the current `docker-compose.yml` follows the variable. If your compose file is older, change the `dawarich_app` healthcheck URL from `http://127.0.0.1:3000/api/v1/health` to `http://127.0.0.1:3000$${RAILS_RELATIVE_URL_ROOT}/api/v1/health`; otherwise Docker marks the app unhealthy and does not start Sidekiq. Kubernetes probes (see [How to install Dawarich in k8s](How_to_install_Dawarich_in_k8s.md)) use `/dawarich/api/v1/health`. Leave the variable unset to serve Dawarich at the domain root.

If you run Dawarich without the Docker image and precompile assets yourself, set the variable for `rails assets:precompile` as well, so that stylesheets load their fonts from under the path.

The reverse proxy must pass the path to Dawarich unchanged. Do not strip it.

Nginx:

```nginx
location /dawarich/ {
	proxy_http_version 1.1;
	proxy_set_header Upgrade $http_upgrade;
	proxy_set_header Connection "upgrade";
	proxy_set_header Host $http_host;
	proxy_set_header X-Real-IP $remote_addr;
	proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	proxy_set_header X-Forwarded-Proto $scheme;

	proxy_pass http://127.0.0.1:3000;
}
```

`proxy_pass` has no path after the port, so nginx forwards `/dawarich/...` as it is. The `Upgrade` and `Connection` headers let the live map connect its WebSocket at `/dawarich/cable`.

Caddy:

```caddy
example.com {
	redir /dawarich /dawarich/
	reverse_proxy /dawarich/* dawarich_app:3000
}
```

Use `reverse_proxy` with a path matcher (or `handle`), not `handle_path`: `handle_path` strips the prefix.

Mobile apps and trackers need URLs that include the path: `https://example.com/dawarich` as the server address in Dawarich for iOS, or `https://example.com/dawarich/api/v1/owntracks/points?api_key=...` in OwnTracks.

If you sign in with OIDC, include the path in `APPLICATION_URL` (or set `OIDC_REDIRECT_URI` directly), so that the callback is `https://example.com/dawarich/users/auth/openid_connect/callback`.

---

Please note that the above configurations are just examples and that they contain the minimum configuration needed to make the reverse proxy work properly. Feel free to adjust the configuration to your own needs.
