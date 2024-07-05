## Setting up reverse proxy

### Environment Variable
To make Darawich work with a reverse proxy, you need to ensure the APPLICATION_HOST environment variable is set to the domain name that the reverse proxy will use.
For example, if your Darawich instance is supposed to be on the domain name timeline.mydomain.com, then set the environment variable to "timeline.mydomain.com".
Make sure to exclude "http://" or "https://" from the environment variable. The webpage will not work if you do include http:// or https:// in the variable.

At the time of writing this, the way to set the environment variable is to edit the docker-compose.yml file. Find all APPLICATION_HOST entries in the docker-compose.yml file and change them from "localhost" to your domain name.
For a synology install, refer to **[Synology Install Tutorial](How_to_install_Dawarich_on_Synology.md)**. In this page it is explained how to set the APPLICATION_HOST environment variable.

### Virtual Host

Now that the app works with a domain name, the server needs to be setup to use a reverse proxy. Usually this is done by setting it up in the virtual host configuration.

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

Please note that the above configurations are just examples and that they contain the minimum configuration needed to make the reverse proxy work properly. Feel free to adjust the configuration to your own needs.
