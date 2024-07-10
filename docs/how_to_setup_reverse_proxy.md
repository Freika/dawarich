## Setting up reverse proxy

### Environment Variable
To make Dawarich work with a reverse proxy, you need to ensure the APPLICATION_HOSTS environment variable is set to include the domain name that the reverse proxy will use.
For example, if your Dawarich instance is supposed to be on the domain name timeline.mydomain.com, then include "timeline.mydomain.com" in this environment variable.
Make sure to exclude "http://" or "https://" from the environment variable. ⚠️ The webpage will not work if you do include http:// or https:// in the variable. ⚠️

At the time of writing this, the way to set the environment variable is to edit the docker-compose.yml file. Find all APPLICATION_HOSTS entries in the docker-compose.yml file and make sure to include your domain name. Example:

```yaml
  dawarich_app:
    image: freikin/dawarich:latest
    container_name: dawarich_app
    environment:
      APPLICATION_HOSTS: "yourhost.com,www.yourhost.com,127.0.0.1"
```

For a Synology install, refer to **[Synology Install Tutorial](How_to_install_Dawarich_on_Synology.md)**. In this page, it is explained how to set the APPLICATION_HOSTS environment variable.

### Virtual Host

Now that the app works with a domain name, the server needs to be set up to use a reverse proxy. Usually, this is done by setting it up in the virtual host configuration.

Below are examples of reverse proxy configurations.

### Nginx
```
server {

	listen 80;
	listen [::]:80;
	server_name example.com;

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
```

With the above commands entered, the configuration below should work properly.

```
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

Adjust your Dawarich docker-compose.yaml so that the web app is exposed to your new network and the backend Dawarich network:
```
version: '3'
networks:
  dawarich:
  frontend:
    external: true
services:
  dawarich_redis:
    image: redis:7.0-alpine
    command: redis-server
    networks:
      - dawarich
    volumes:
      - ./dawarich/redis:/var/shared/redis
  dawarich_db:
    image: postgres:14.2-alpine
    container_name: dawarich_db
    volumes:
      - ./dawarich/db:/var/lib/postgresql/data
      - ./dawarich/shared:/var/shared
    networks:
      - dawarich
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
  dawarich_app:
    image: freikin/dawarich:latest
    container_name: dawarich_app
    volumes:
      - ./dawarich/gems:/usr/local/bundle/gems
      - ./dawarich/public:/var/app/public
    networks:
      - dawarich
      - frontend
    stdin_open: true
    tty: true
    entrypoint: dev-entrypoint.sh
    command: ['bin/dev']
    restart: on-failure
    environment:
      RAILS_ENV: development
      REDIS_URL: redis://dawarich_redis:6379/0
      DATABASE_HOST: dawarich_db
      DATABASE_USERNAME: postgres
      DATABASE_PASSWORD: password
      DATABASE_NAME: dawarich_development
      MIN_MINUTES_SPENT_IN_CITY: 60
      APPLICATION_HOST: <YOUR FQDN HERE (ex. dawarich.example.com)>
      TIME_ZONE: America/New_York
    depends_on:
      - dawarich_db
      - dawarich_redis
  dawarich_sidekiq:
    image: freikin/dawarich:latest
    container_name: dawarich_sidekiq
    volumes:
      - ./dawarich/gems:/usr/local/bundle/gems
      - ./dawarich/public:/var/app/public
    networks:
      - dawarich
    stdin_open: true
    tty: true
    entrypoint: dev-entrypoint.sh
    command: ['sidekiq']
    restart: on-failure
    environment:
      RAILS_ENV: development
      REDIS_URL: redis://dawarich_redis:6379/0
      DATABASE_HOST: dawarich_db
      DATABASE_USERNAME: postgres
      DATABASE_PASSWORD: password
      DATABASE_NAME: dawarich_development
      APPLICATION_HOST: <YOUR FQDN HERE (ex. dawarich.example.com)>
    depends_on:
      - dawarich_db
      - dawarich_redis
      - dawarich_app
```

Lastly, edit your Caddy config as needed:
```
{
	http_port 80
	https_port 443
}

<YOUR FQDN HERE (ex. dawarich.example.com)> {
	reverse_proxy dawarich_app:3000
}
```

---

Please note that the above configurations are just examples and that they contain the minimum configuration needed to make the reverse proxy work properly. Feel free to adjust the configuration to your own needs.
