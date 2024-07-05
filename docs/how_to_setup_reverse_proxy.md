## Setting up reverse proxy
To make Darawich work with a reverse proxy, you need to ensure the APPLICATION_HOST environment variable is set to the domain name that the reverse proxy will use.
For example, if your Darawich instance is supposed to be on the domain name timeline.mydomain.com, then set the environment variable to "timeline.mydomain.com".
Make sure to exclude "http://" or "https://" from the environment variable. The webpage will not work if you do include http:// or https:// in the variable.

At the time of writing this, the way to set the environment variable is to edit the docker-compose.yml file. Find all APPLICATION_HOST entries in the docker-compose.yml file and change them from "localhost" to your domain name.
For a synology install, refer to **[Synology Install Tutorial](docs/How_to_install_Dawarich_on_Synology.md)**. In this page it is explained how to set the APPLICATION_HOST environment variable.

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
